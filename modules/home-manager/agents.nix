{
  config,
  lib,
  ...
}: let
  inherit (lib) mkIf mkEnableOption mkOption types;

  cfg = config.programs.agents;

  toolDirs = {
    global = ".agents/skills";
    codex = ".codex/skills";
    gemini = ".gemini/skills";
    claude = ".claude/skills";
    opencode = ".config/opencode/skills";
  };

  allTools = lib.attrNames (lib.removeAttrs toolDirs ["global"]);

  scopeToDirs = scopes: let
    normalized =
      if builtins.isList scopes
      then scopes
      else [scopes];
  in
    map (s: toolDirs.${s}) normalized;

  # Convert a scope to a directory, handling both built-in tools and workspaces
  scopeToDir = scope:
    if builtins.hasAttr scope toolDirs
    then toolDirs.${scope}
    else if builtins.hasAttr scope cfg.workspaces
    then "${cfg.workspaces.${scope}.path}/.agents/skills"
    else
      throw "Unknown scope '${scope}': not a built-in tool (${lib.concatStringsSep ", " allTools}) or defined workspace";

  mkConfiguredSkillFiles = entry: let
    drv = entry.drv;
    plugins = entry.plugins;
    scopes = entry.scopes or ["global"];
    prefix = entry.prefix or "";
    normalized =
      if builtins.isList scopes
      then scopes
      else [scopes];
    dirs = map scopeToDir normalized;
  in
    lib.listToAttrs (lib.flatten (
      map (plugin:
        map (dir:
          lib.nameValuePair "${dir}/${prefix}${plugin}" {
            source = "${drv}/${plugin}";
          })
        dirs)
      plugins
    ));

  isConfiguredEntry = x: builtins.isAttrs x && x ? drv && x ? plugins;

  allSkillFiles = lib.foldl' (acc: entry: acc // mkConfiguredSkillFiles entry) {} cfg.skills;
in {
  options.programs.agents = {
    enable = mkEnableOption "Declarative agent skills for AI coding tools";

    workspaces = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          path = mkOption {
            type = types.str;
            description = ''
              Relative path to the workspace directory (relative to home directory).
              Example: "Projects/github.com/myapp"
            '';
          };
          scopes = mkOption {
            type = types.listOf types.str;
            default = [];
            description = ''
              List of tool scopes to use within this workspace.
              When a skill is configured with a scope matching a workspace name,
              its skills will be installed at `<workspace-path>/.agents/skills/`.
            '';
          };
        };
      });
      default = {};
      description = ''
        Declare project-specific workspaces where skills can be scoped.

        Each workspace is a directory with an associated tool scope name.
        You can then use the workspace name as a scope when configuring skills.
      '';
      example = lib.literalExpression ''
        {
          "cc" = {
            path = "Projects/github.com/chanchitaapp";
            scopes = ["claude"];
          };
          "myapi" = {
            path = "src/myapi";
          };
        }
      '';
    };

    skills = mkOption {
      type = types.listOf types.raw;
      default = [];
      description = ''
        List of configured skill entries to install.

        Each entry is created by calling a skill package as a function:

        ```nix
        official.encoredev.skills {
          plugins = ["encore-api" "encore-database"];
          scopes = ["global" "claude"];  # optional, default: ["global"]
          prefix = "";                   # optional, default: ""
        }
        ```

        - `plugins`: list of skill names to install from the package
        - `scopes`: where to install — `"global"` (~/.agents/skills/),
          tool-specific: ${lib.concatStringsSep ", " (map (t: ''"${t}"'') allTools)},
          or a workspace name defined in `workspaces`
        - `prefix`: string prepended to each skill directory name (to avoid conflicts)

        Skills are symlinked at activation time into each scope directory as:
        `<scope-dir>/<prefix><plugin-name>/` → `<store-path>/<plugin-name>/`
      '';
      example = lib.literalExpression ''
        with pkgs.agent-skills.skills-sh; [
          (official.encoredev.skills {
            plugins = [
              "encore-api"
              "encore-auth"
              "encore-database"
              "encore-service"
              "encore-testing"
              "encore-code-review"
            ];
            scopes = ["global" "claude"];
          })

          (official.getsentry.skills {
            plugins = ["find-bugs"];
            scopes = ["cc"];  # uses workspace named "cc"
          })

          (official.anthropics.skills {
            plugins = ["pdf" "pptx"];
            scopes = ["global"];
            prefix = "anthropic-";
          })
        ]
      '';
    };
  };

  config = mkIf (cfg.enable && cfg.skills != []) {
    assertions =
      map (entry: {
        assertion = isConfiguredEntry entry;
        message = ''
          programs.agents.skills expects configured entries.
          Call the skill package as a function:
            official.encoredev.skills { plugins = ["encore-api"]; }
        '';
      })
      cfg.skills;

    home.file = allSkillFiles;
  };
}
