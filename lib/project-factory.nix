{lib}: {
  project-factory = {
    pkgs,
    workspaces ? {},
    skills ? [],
    defaultScopes ? ["global"],
  }: let
    pkgLib = import ./packages.nix {inherit pkgs lib;};

    toolDirs = {
      global = ".agents/skills";
      standard = ".agents/skills";
      claude = ".claude/skills";
    };

    scopesToDirs = scopes: let
      normalized =
        if builtins.isList scopes
        then scopes
        else [scopes];
      expandScope = scope:
        if builtins.hasAttr scope toolDirs
        then [toolDirs.${scope}]
        else if builtins.hasAttr scope workspaces
        then let
          workspace = workspaces.${scope};
          workspaceScopes =
            if workspace.scopes == []
            then ["global"]
            else workspace.scopes;
        in
          map (
            s:
              if builtins.hasAttr s toolDirs
              then "${workspace.path}/${toolDirs.${s}}"
              else throw "Unknown tool scope '${s}' in workspace '${scope}'"
          )
          workspaceScopes
        else throw "Unknown scope '${scope}': not a built-in tool or defined workspace";
    in
      lib.flatten (map expandScope normalized);

    # Build skill symlink pairs: {source, target}
    mkSkillSymlinks = rawEntry: let
      entry = pkgLib.materializeConfiguredSkill rawEntry;
      drv = entry.drv;
      pluginList = entry.plugins;
      scopes = let
        s = entry.scopes or null;
      in
        if s != null
        then s
        else defaultScopes;
      prefix = entry.prefix or "";
      dirs = scopesToDirs scopes;
    in
      lib.flatten (
        map (plugin:
          map (dir: {
            source = "${drv}/${plugin}";
            target = "${dir}/${prefix}${plugin}";
            plugin = plugin;
            prefix = prefix;
          })
          dirs)
        pluginList
      );

    allSymlinks = lib.flatten (map mkSkillSymlinks skills);

    # Detect conflicting plugin names across different skills
    pluginTargets =
      lib.foldl' (
        acc: symlink:
          acc
          // {
            ${symlink.target} =
              (acc.${symlink.target} or [])
              ++ [
                {
                  source = symlink.source;
                  plugin = symlink.plugin;
                  prefix = symlink.prefix;
                }
              ];
          }
      ) {}
      allSymlinks;

    conflicts = lib.filterAttrs (_: targets: builtins.length targets > 1) pluginTargets;
    conflictNames = builtins.attrNames conflicts;

    # Validate no conflicts
    validated =
      if conflictNames != []
      then let
        conflictDetails = lib.concatStringsSep "\n" (
          map (
            target: let
              pluginConflicts = conflicts.${target};
            in
              "  ${target}:\n"
              + lib.concatMapStringsSep "\n" (
                conflict: "    - ${conflict.plugin}${lib.optionalString (conflict.prefix != "") " (prefix: ${conflict.prefix})"}"
              )
              pluginConflicts
          )
          conflictNames
        );
      in
        throw ''
          Plugin name conflicts detected in project-factory skills:
          ${conflictDetails}

          Solutions:
          1. Add unique prefixes to conflicting skills:
             (skillA { plugins = [...]; prefix = "skillA-"; })
             (skillB { plugins = [...]; prefix = "skillB-"; })

          2. Select non-conflicting plugins from each skill

          3. Use different scopes for conflicting skills to separate them into different directories
        ''
      else allSymlinks;

    # Generate shell hook that creates directories and symlinks
    setupHook = pkgs.writeScript "agentic-setup" ''
      #!${pkgs.runtimeShell}
      set -e

      ${lib.concatMapStringsSep "\n" (
          symlink: "mkdir -p \"$(dirname \"$PWD/${symlink.target}\")\" 2>/dev/null || true"
        )
        validated}

      ${lib.concatMapStringsSep "\n" (
          symlink: ''
            if [ -e "$PWD/${symlink.target}" ]; then
              rm -rf "$PWD/${symlink.target}"
            fi
            ln -sf "${symlink.source}" "$PWD/${symlink.target}"
          ''
        )
        validated}
    '';
  in {
    shellHook = ''
      export AGENTIC_SETUP_DONE=1
      ${pkgs.runtimeShell} ${setupHook}
    '';

    allSymlinks = validated;
  };
}
