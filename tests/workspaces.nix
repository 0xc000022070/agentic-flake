{
  agent-skills-flake,
  pkgs,
  ...
}: {
  homeModule = {
    imports = [agent-skills-flake.homeManagerModules.agents];

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

      skills = with pkgs.agent-skills.skills-sh; [
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

    # Test anthropics skills in foo workspace with prefix
    workspace_skills = ["my-pdf", "my-pptx"]
    for skill in workspace_skills:
        path = f"/home/testuser/Projects/foo/.agents/skills/{skill}"
        machine.succeed(f"test -d {path} && test -f {path}/SKILL.md")

    # Verify prefix isolation in workspace
    machine.succeed("test ! -d /home/testuser/Projects/foo/.agents/skills/pdf")
    machine.succeed("test ! -d /home/testuser/Projects/foo/.agents/skills/pptx")
    machine.succeed("test -d /home/testuser/Projects/foo/.agents/skills/my-pdf")
    machine.succeed("test -d /home/testuser/Projects/foo/.agents/skills/my-pptx")

    # Verify myproject workspace is created but empty (no skills assigned to it)
    machine.succeed("test ! -d /home/testuser/src/myproject/.agents/skills")

    print("Global and claude scopes installed correctly")
    print("Workspace-scoped skills with prefix installed correctly")
    print("Workspace creation and isolation verified")
  '';
}
