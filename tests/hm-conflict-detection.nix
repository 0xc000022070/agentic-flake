{
  agentic-flake,
  pkgs,
  ...
}: let
  skillApi = import ../lib/skill-api.nix {lib = pkgs.lib;};

  # Two inline skills that would conflict on "python"
  orgA = skillApi.mkInlineSkill {
    "python" = {
      name = "python";
      content = "Python skill from orgA";
    };
    "nodejs" = {
      name = "nodejs";
      content = "NodeJS skill from orgA";
    };
  };

  orgB = skillApi.mkInlineSkill {
    "python" = {
      name = "python";
      content = "Python skill from orgB";
    };
    "rust" = {
      name = "rust";
      content = "Rust skill from orgB";
    };
  };

  # Skill from a repo with internal duplicates (only selecting non-ambiguous plugin)
  repoWithDups = agentic-flake.lib.mkSkill {
    src = ./fixtures/mk-skill-duplicates;
  };
in {
  homeModule = {
    imports = [agentic-flake.homeModules.default];

    programs.agents = {
      enable = true;
      defaultScopes = ["global"];

      skills = [
        # Conflict resolved via prefix
        (orgA {
          plugins = ["python" "nodejs"];
          prefix = "orgA-";
        })
        (orgB {
          plugins = ["python" "rust"];
          prefix = "orgB-";
        })

        # Non-ambiguous plugin from repo with duplicates
        (repoWithDups {
          plugins = ["utils"];
        })
      ];
    };
  };

  testScript = ''
    # Prefixed skills from orgA
    machine.succeed("test -L /home/testuser/.agents/skills/orgA-python")
    machine.succeed("test -f /home/testuser/.agents/skills/orgA-python/SKILL.md")
    machine.succeed("grep -q 'orgA' /home/testuser/.agents/skills/orgA-python/SKILL.md")

    machine.succeed("test -L /home/testuser/.agents/skills/orgA-nodejs")
    machine.succeed("test -f /home/testuser/.agents/skills/orgA-nodejs/SKILL.md")

    # Prefixed skills from orgB
    machine.succeed("test -L /home/testuser/.agents/skills/orgB-python")
    machine.succeed("test -f /home/testuser/.agents/skills/orgB-python/SKILL.md")
    machine.succeed("grep -q 'orgB' /home/testuser/.agents/skills/orgB-python/SKILL.md")

    machine.succeed("test -L /home/testuser/.agents/skills/orgB-rust")
    machine.succeed("test -f /home/testuser/.agents/skills/orgB-rust/SKILL.md")

    # No unprefixed "python" should exist
    machine.succeed("test ! -e /home/testuser/.agents/skills/python")

    # Non-ambiguous plugin from repo with duplicates
    machine.succeed("test -L /home/testuser/.agents/skills/utils")
    machine.succeed("test -f /home/testuser/.agents/skills/utils/SKILL.md")

    print("Home-manager conflict detection tests passed")
  '';
}
