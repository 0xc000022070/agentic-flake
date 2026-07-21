{
  agentic-flake,
  pkgs,
  ...
}: let
  skillPkg = agentic-flake.lib.mkSkill {
    src = ./fixtures/mk-skill;
  };

  configured = skillPkg {
    plugins = [
      "root-skill"
      "child"
    ];
  };

  # Root SKILL.md sources get their id from the directory name unless
  # `name` overrides it.
  renamedPkg = agentic-flake.lib.mkSkill {
    src = ./fixtures/mk-skill/root-skill;
    name = "renamed-skill";
  };

  fileWithoutName = builtins.tryEval (agentic-flake.lib.mkSkill {
    src = ./fixtures/mk-skill/root-skill/SKILL.md;
  });

  namedFilePkg = agentic-flake.lib.mkSkill {
    src = ./fixtures/mk-skill/root-skill/SKILL.md;
    name = "file-skill";
  };
in
  pkgs.runCommand "mk-skill-lib-test" {} ''
    set -e

    test "${toString (builtins.length skillPkg.availablePlugins)}" = "2" || {
      echo "Expected 2 discovered plugins, got ${toString (builtins.length skillPkg.availablePlugins)}"
      exit 1
    }

    ${
      if builtins.elem "root-skill" skillPkg.availablePlugins
      then ''
        :
      ''
      else ''
        echo "root-skill was not discovered"
        exit 1
      ''
    }

    ${
      if builtins.elem "child" skillPkg.availablePlugins
      then ''
        :
      ''
      else ''
        echo "nested/group/child was not discovered"
        exit 1
      ''
    }

    ${
      if builtins.elem "templates/example-template" skillPkg.availablePlugins
      then ''
        echo "Template paths should not be exposed as plugins"
        exit 1
      ''
      else ''
        :
      ''
    }

    test "${configured.prefix}" = "" || {
      echo "Expected default prefix to be empty"
      exit 1
    }

    ${
      if renamedPkg.availablePlugins == ["renamed-skill"]
      then ''
        :
      ''
      else ''
        echo "name override was not applied to root skill"
        exit 1
      ''
    }

    ${
      if !fileWithoutName.success
      then ''
        :
      ''
      else ''
        echo "single-file src without name should fail"
        exit 1
      ''
    }

    ${
      if namedFilePkg.availablePlugins == ["file-skill"]
      then ''
        :
      ''
      else ''
        echo "name override was not applied to single-file src"
        exit 1
      ''
    }

    ${
      if pkgs.lib.hasInfix "root-skill" namedFilePkg.__inlineSkillContent.file-skill
      then ''
        :
      ''
      else ''
        echo "single-file src content was not read"
        exit 1
      ''
    }

    mkdir -p "$out"
    touch "$out/ok"
  ''
