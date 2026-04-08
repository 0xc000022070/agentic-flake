{
  agentic-flake,
  pkgs,
  ...
}: let
  inlineSkills = agentic-flake.lib.mkInlineSkill {
    "inline-tool" = {
      name = "inline-tool";
      description = "Defined entirely in Nix";
      content = "# Inline Tool\n\nNo source file needed.";
    };
  };

  localSkills = agentic-flake.lib.mkSkill {
    src = ./fixtures/mk-skill;
  };
in {
  homeModule = {
    imports = [agentic-flake.homeModules.default];

    programs.agents = {
      enable = true;

      skills = [
        (pkgs.agent-skills.official.redis.agent-skills {
          plugins = ["redis-development"];
          scopes = ["global"];
        })
        (pkgs.agent-skills.unofficial.daffy0208.ai-dev-standards {
          plugins = ["mvp-builder"];
          scopes = ["claude"];
        })
        (inlineSkills {
          plugins = ["inline-tool"];
          scopes = ["claude"];
        })

        (localSkills {
          plugins = ["root-skill"];
          scopes = ["global"];
        })
        # Umbrella skill (root SKILL.md)
        (pkgs.agent-skills.official.novuhq.skills {
          plugins = ["novu"];
          scopes = ["claude"];
        })
      ];
    };
  };

  testScript = ''
    machine.succeed("test -d /home/testuser/.agents/skills/redis-development")
    machine.succeed("test -f /home/testuser/.agents/skills/redis-development/SKILL.md")

    machine.succeed("test -d /home/testuser/.claude/skills/inline-tool")
    machine.succeed("test -f /home/testuser/.claude/skills/inline-tool/SKILL.md")
    machine.succeed("grep -q 'name: inline-tool' /home/testuser/.claude/skills/inline-tool/SKILL.md")
    machine.succeed("grep -q 'description: Defined entirely in Nix' /home/testuser/.claude/skills/inline-tool/SKILL.md")
    machine.succeed("grep -q '# Inline Tool' /home/testuser/.claude/skills/inline-tool/SKILL.md")
    machine.succeed("test -d /home/testuser/.claude/skills/mvp-builder")
    machine.succeed("test -f /home/testuser/.claude/skills/mvp-builder/SKILL.md")
    machine.succeed("grep -q 'name: MVP Builder' /home/testuser/.claude/skills/mvp-builder/SKILL.md")

    machine.succeed("test -d /home/testuser/.agents/skills/root-skill")
    machine.succeed("test -f /home/testuser/.agents/skills/root-skill/SKILL.md")
    machine.succeed("grep -q 'Root Skill' /home/testuser/.agents/skills/root-skill/SKILL.md")

    # Umbrella skill: root SKILL.md with nested sub-skills
    machine.succeed("test -d /home/testuser/.claude/skills/novu")
    machine.succeed("test -f /home/testuser/.claude/skills/novu/SKILL.md")
    machine.succeed("test -d /home/testuser/.claude/skills/novu/inbox-integration")
    machine.succeed("test -d /home/testuser/.claude/skills/novu/trigger-notification")

    # Isolation: each skill only present in its assigned scope
    machine.fail("test -d /home/testuser/.claude/skills/redis-development")
    machine.fail("test -d /home/testuser/.agents/skills/inline-tool")
    machine.fail("test -d /home/testuser/.claude/skills/root-skill")
    machine.fail("test -d /home/testuser/.agents/skills/mvp-builder")
    machine.fail("test -d /home/testuser/.agents/skills/novu")
  '';
}
