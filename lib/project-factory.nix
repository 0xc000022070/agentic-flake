{lib}: {
  project-factory = {
    pkgs,
    workspaces ? {},
    skills ? [],
    defaultScopes ? ["global"],
    context ? {},
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

    # Process context files: normalize filenames and separate inline vs filesystem paths
    processContextFiles = let
      normalizeFilename = name: value: let
        hasExtension = lib.hasSuffix ".md" name;
        filename =
          if hasExtension
          then name
          else "${name}.md";
      in {
        filename = filename;
        isInline = builtins.isString value;
        source = value;
      };

      contextEntries =
        lib.mapAttrsToList (
          name: value:
            normalizeFilename name value
        )
        context;
    in
      contextEntries;

    contextFiles = processContextFiles;

    # Detect conflicting context file targets
    contextTargets =
      lib.foldl' (
        acc: entry:
          acc
          // {
            ${entry.filename} =
              (acc.${entry.filename} or [])
              ++ [
                {
                  filename = entry.filename;
                  isInline = entry.isInline;
                }
              ];
          }
      ) {}
      contextFiles;

    contextConflicts = lib.filterAttrs (_: targets: builtins.length targets > 1) contextTargets;
    contextConflictNames = builtins.attrNames contextConflicts;

    # Validate no context conflicts
    validatedContext =
      if contextConflictNames != []
      then let
        conflictDetails = lib.concatStringsSep "\n" (
          map (
            filename: let
              fileConflicts = contextConflicts.${filename};
            in "  ${filename}: defined ${builtins.toString (builtins.length fileConflicts)} times"
          )
          contextConflictNames
        );
      in
        throw ''
          Context file name conflicts detected in project-factory:
          ${conflictDetails}

          Each context file key must map to a unique filename. Use different keys if you need multiple files.
        ''
      else contextFiles;

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

    # Generate shell hook that creates directories, symlinks, and context files
    setupHook = pkgs.writeScript "agentic-setup" ''
      #!${pkgs.runtimeShell}
      set -e

      managed_file="$PWD/.agents/.agentic-flake-managed-links"
      managed_tmp="$(mktemp)"

      cleanup_managed_tmp() {
        if [ -n "$managed_tmp" ]; then
          rm -f "$managed_tmp"
        fi
      }

      trap cleanup_managed_tmp EXIT HUP INT TERM

      ${lib.concatMapStringsSep "\n" (
          symlink: ''
            if [ ! -e "${symlink.source}" ]; then
              echo "agentic-flake: warning: skill source '${symlink.source}' does not exist; skipping '${symlink.target}'" >&2
              if [ -L "$PWD/${symlink.target}" ] && [ ! -e "$PWD/${symlink.target}" ]; then
                rm -f "$PWD/${symlink.target}"
              fi
            else
              printf '%s\t%s\n' '${symlink.target}' '${symlink.source}' >> "$managed_tmp"
            fi
          ''
        )
        validated}

      if [ -f "$managed_file" ]; then
        while IFS="$(printf '\t')" read -r old_target old_source; do
          [ -n "$old_target" ] || continue

          if ! cut -f1 "$managed_tmp" | grep -Fqx -- "$old_target"; then
            target_path="$PWD/$old_target"
            if [ -L "$target_path" ]; then
              current_source="$(readlink "$target_path")"
              if [ "$current_source" = "$old_source" ]; then
                rm -f "$target_path"
                echo "agentic-flake: removed undeclared skill '$old_target'"
              else
                echo "agentic-flake: warning: managed link '$old_target' changed outside agentic-flake; leaving it unchanged" >&2
              fi
            elif [ -e "$target_path" ]; then
              echo "agentic-flake: warning: managed path '$old_target' is no longer a symlink; leaving it unchanged" >&2
            fi
          fi
        done < "$managed_file"
      fi

      ${lib.concatMapStringsSep "\n" (
          symlink: ''
            if [ -e "${symlink.source}" ]; then
              mkdir -p "$(dirname "$PWD/${symlink.target}")"
              if [ -e "$PWD/${symlink.target}" ] || [ -L "$PWD/${symlink.target}" ]; then
                rm -rf "$PWD/${symlink.target}"
              fi
              ln -s "${symlink.source}" "$PWD/${symlink.target}"
            fi
          ''
        )
        validated}

      if [ -s "$managed_tmp" ]; then
        mkdir -p "$(dirname "$managed_file")"
        mv "$managed_tmp" "$managed_file"
        managed_tmp=""
      else
        rm -f "$managed_file"
      fi

      ${lib.concatMapStringsSep "\n" (
          entry:
            if entry.isInline
            then ''
                            cat > "$PWD/${entry.filename}" << 'CONTEXT_EOF'
              ${entry.source}CONTEXT_EOF
            ''
            else ''
              if [ -e "$PWD/${entry.filename}" ]; then
                rm -rf "$PWD/${entry.filename}"
              fi
              ln -sf "${entry.source}" "$PWD/${entry.filename}"
            ''
        )
        validatedContext}
    '';
  in {
    shellHook = ''
      export AGENTIC_SETUP_DONE=1
      ${pkgs.runtimeShell} ${setupHook}
    '';

    allSymlinks = validated;
    allContextFiles = validatedContext;
  };
}
