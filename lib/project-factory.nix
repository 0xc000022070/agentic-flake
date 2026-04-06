{lib}: {
  project-factory = {
    pkgs,
    workspaces ? {},
    plugins ? [],
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
      scopes = entry.scopes or ["global"];
      prefix = entry.prefix or "";
      dirs = scopesToDirs scopes;
    in
      lib.flatten (
        map (plugin:
          map (dir: {
            source = "${drv}/${plugin}";
            target = "${dir}/${prefix}${plugin}";
          })
          dirs)
        pluginList
      );

    allSymlinks = lib.flatten (map mkSkillSymlinks plugins);

    # Generate shell hook that creates directories and symlinks
    setupHook = pkgs.writeScript "agentic-setup" ''
      #!${pkgs.runtimeShell}
      set -e

      ${lib.concatMapStringsSep "\n" (
          symlink: "mkdir -p \"$(dirname \"$PWD/${symlink.target}\")\" 2>/dev/null || true"
        )
        allSymlinks}

      ${lib.concatMapStringsSep "\n" (
          symlink: ''
            if [ -e "$PWD/${symlink.target}" ]; then
              rm -rf "$PWD/${symlink.target}"
            fi
            ln -sf "${symlink.source}" "$PWD/${symlink.target}"
          ''
        )
        allSymlinks}
    '';
  in {
    shellHook = ''
      export AGENTIC_SETUP_DONE=1
      ${pkgs.runtimeShell} ${setupHook}
    '';

    inherit allSymlinks;
  };
}
