{agentic-flake, ...}: let
  openfangSkills = agentic-flake.lib.mkSkill {
    src =
      builtins.fetchGit {
        url = "https://github.com/RightNow-AI/openfang";
        rev = "07963779be926d3f501a3fdc9065934668c6cfc8";
      }
      + "/crates/openfang-skills/bundled";
  };
in {
  homeModule = {
    imports = [agentic-flake.homeModules.default];

    programs.agents = {
      enable = true;

      workspaces.ops = {
        path = "Projects/ops";
        scopes = ["claude"];
      };

      skills = [
        (openfangSkills {
          plugins = ["linux-networking"];
          scopes = ["ops"];
        })
      ];
    };
  };

  testScript = ''
    skill_path = "/home/testuser/Projects/ops/.claude/skills/linux-networking"

    machine.succeed(f"test -d {skill_path}")
    machine.succeed(f"test -f {skill_path}/SKILL.md")
    machine.succeed(f"grep -q 'Linux Networking Expert' {skill_path}/SKILL.md")
    machine.succeed("test ! -d /home/testuser/.agents/skills/linux-networking")
  '';
}
