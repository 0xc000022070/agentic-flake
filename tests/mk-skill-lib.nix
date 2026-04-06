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
      "nested/group/child"
    ];
  };
in
  pkgs.runCommand "mk-skill-lib-test" {} ''
    set -e

    test "${toString (builtins.length skillPkg.availablePlugins)}" = "2" || {
      echo "Expected 2 discovered plugins, got ${toString (builtins.length skillPkg.availablePlugins)}"
      exit 1
    }

    ${if builtins.elem "root-skill" skillPkg.availablePlugins then ''
      :
    '' else ''
      echo "root-skill was not discovered"
      exit 1
    ''}

    ${if builtins.elem "nested/group/child" skillPkg.availablePlugins then ''
      :
    '' else ''
      echo "nested/group/child was not discovered"
      exit 1
    ''}

    ${if builtins.elem "templates/example-template" skillPkg.availablePlugins then ''
      echo "Template paths should not be exposed as plugins"
      exit 1
    '' else ''
      :
    ''}

    test "${configured.prefix}" = "" || {
      echo "Expected default prefix to be empty"
      exit 1
    }

    mkdir -p "$out"
    touch "$out/ok"
  ''
