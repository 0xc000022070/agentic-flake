{
  agentic-flake,
  pkgs,
  ...
}: let
  pkgLib = import ../lib/packages.nix {
    inherit pkgs;
    lib = pkgs.lib;
  };
  skillApi = import ../lib/skill-api.nix {lib = pkgs.lib;};

  # Inline skills with null scopes (not specified by caller)
  inlineSkills = skillApi.mkInlineSkill {
    "null-scope-test" = {
      name = "null-scope-test";
      content = "Test skill for null scopes";
    };
  };

  # Call without scopes — should have scopes = null
  configuredSkill = inlineSkills {
    plugins = ["null-scope-test"];
    # Note: no scopes specified
  };

  # project-factory with null scopes should default to ["global"]
  factory = agentic-flake.lib.project-factory {
    inherit pkgs;
    skills = [configuredSkill];
  };
in
  pkgs.runCommand "project-factory-null-scopes-test" {} ''
    set -e

    # Verify that configuredSkill has null scopes
    ${
      if configuredSkill.scopes == null
      then ''
        :
      ''
      else ''
        echo "Expected configuredSkill.scopes to be null, got ${builtins.toString configuredSkill.scopes}"
        exit 1
      ''
    }

    # Verify factory generated symlinks for global scope
    symlinks='${builtins.toJSON factory.allSymlinks}'
    echo "Generated symlinks: $symlinks"

    # Check that a symlink to .agents/skills (global scope) was created
    echo "$symlinks" | grep -q "agents/skills/null-scope-test" || {
      echo "Expected symlink to .agents/skills/null-scope-test"
      exit 1
    }

    mkdir -p "$out"
    touch "$out/ok"
    echo "project-factory null scopes test passed"
  ''
