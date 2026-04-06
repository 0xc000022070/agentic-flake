{agentic-flake, ...}: let
  localSkills = agentic-flake.lib.mkSkill {
    src = ./fixtures/mk-skill;
  };
in {
  homeModule = {
    imports = [agentic-flake.homeModules.default];

    programs.agents = {
      enable = true;

      workspaces.demo = {
        path = "Projects/demo";
        scopes = ["claude"];
      };

      skills = [
        (localSkills {
          scopes = ["global"];
          plugins = ["root-skill"];
        })

        (localSkills {
          scopes = ["demo"];
          plugins = ["nested/group/child"];
          prefix = "local-";
        })
      ];
    };
  };

  testScript = ''
    machine.succeed("test -d /home/testuser/.agents/skills/root-skill")
    machine.succeed("test -f /home/testuser/.agents/skills/root-skill/SKILL.md")
    machine.succeed("grep -q 'Root Skill' /home/testuser/.agents/skills/root-skill/SKILL.md")

    machine.succeed("test -d /home/testuser/Projects/demo/.claude/skills/local-nested/group/child")
    machine.succeed("test -f /home/testuser/Projects/demo/.claude/skills/local-nested/group/child/SKILL.md")
    machine.succeed("grep -q 'Nested Child Skill' /home/testuser/Projects/demo/.claude/skills/local-nested/group/child/SKILL.md")

    machine.succeed("test ! -d /home/testuser/.agents/skills/templates")
    machine.succeed("test ! -d /home/testuser/Projects/demo/.claude/skills/nested/group/child")
  '';
}
