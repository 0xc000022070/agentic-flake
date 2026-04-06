{
  agentic-flake,
  pkgs,
  ...
}: {
  homeModule = {
    imports = [agentic-flake.homeModules.default];

    programs.agents = {
      enable = true;

      workspaces = {
        "foo" = {
          path = "Projects/foo";
          scopes = ["claude"];
        };
        "bar" = {
          path = "src/myproject";
          scopes = [];
        };
      };

      skills = with pkgs.agent-skills; [
        (official.encoredev.skills {
          scopes = ["global" "claude"];
          plugins = [
            "encore-api"
            "encore-service"
          ];
        })

        (official.anthropics.skills {
          scopes = ["foo"];
          prefix = "my-";
          plugins = [
            "pdf"
            "pptx"
          ];
        })
      ];
    };
  };

  testScript = ''
    # Test encoredev skills in global scope
    global_skills = ["encore-api", "encore-service"]
    for skill in global_skills:
        path = f"/home/testuser/.agents/skills/{skill}"
        machine.succeed(f"test -d {path} && test -f {path}/SKILL.md")

    # Test encoredev skills in claude scope
    claude_skills = ["encore-api", "encore-service"]
    for skill in claude_skills:
        path = f"/home/testuser/.claude/skills/{skill}"
        machine.succeed(f"test -d {path} && test -f {path}/SKILL.md")

    # Test anthropics skills in foo workspace with prefix (foo workspace has scopes = ["claude"])
    workspace_skills = ["my-pdf", "my-pptx"]
    for skill in workspace_skills:
        path = f"/home/testuser/Projects/foo/.claude/skills/{skill}"
        machine.succeed(f"test -d {path} && test -f {path}/SKILL.md")

    # Verify skills are not in .agents/skills of workspace (foo only has claude scope)
    machine.succeed("test ! -d /home/testuser/Projects/foo/.agents/skills/my-pdf")
    machine.succeed("test ! -d /home/testuser/Projects/foo/.agents/skills/my-pptx")

    # Verify prefix isolation in workspace
    machine.succeed("test ! -d /home/testuser/Projects/foo/.claude/skills/pdf")
    machine.succeed("test ! -d /home/testuser/Projects/foo/.claude/skills/pptx")
    machine.succeed("test -d /home/testuser/Projects/foo/.claude/skills/my-pdf")
    machine.succeed("test -d /home/testuser/Projects/foo/.claude/skills/my-pptx")

    # Verify bar workspace is created but empty (no skills assigned to it, and has empty scopes list)
    machine.succeed("test ! -d /home/testuser/src/myproject/.agents/skills")
    machine.succeed("test ! -d /home/testuser/src/myproject/.claude/skills")

    print("Global and claude scopes installed correctly in home root")
    print("Workspace-scoped skills correctly installed in workspace scope directories")
    print("Workspace scope expansion working (foo.scopes=[claude] -> .claude/skills)")
    print("Prefix isolation verified in workspace")
  '';
}
