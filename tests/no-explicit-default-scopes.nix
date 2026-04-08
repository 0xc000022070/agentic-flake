{
  agentic-flake,
  pkgs,
  ...
}: {
  homeModule = {
    imports = [agentic-flake.homeModules.default];

    programs.agents = {
      enable = true;
      # No explicit defaultScopes — should use module default ["global"]

      skills = with pkgs.agent-skills; [
        (official.encoredev.skills {
          plugins = ["encore-api"];
          # No scopes specified — should inherit module's default ["global"]
        })

        (official.anthropics.skills {
          plugins = ["pdf"];
          scopes = ["claude"];
          # This one overrides with explicit scopes
        })
      ];
    };
  };

  testScript = ''
    # Test that encore-api (no scopes specified) goes to global (.agents)
    machine.succeed("test -d /home/testuser/.agents/skills/encore-api")
    machine.succeed("test -f /home/testuser/.agents/skills/encore-api/SKILL.md")

    # Verify encore-api is NOT in claude scope
    machine.succeed("test ! -d /home/testuser/.claude/skills/encore-api")

    # Test that anthropics pdf (explicit scopes=["claude"]) only goes to claude
    machine.succeed("test -d /home/testuser/.claude/skills/pdf")
    machine.succeed("test -f /home/testuser/.claude/skills/pdf/SKILL.md")

    # Verify pdf is NOT in global scope
    machine.succeed("test ! -d /home/testuser/.agents/skills/pdf")

    print("No explicit defaultScopes test passed:")
    print("- Skills without scopes default to module default (global)")
    print("- Explicit scopes still override")
  '';
}
