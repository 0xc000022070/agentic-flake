{
  agentic-flake,
  pkgs,
  ...
}: {
  homeModule = {
    imports = [agentic-flake.homeModules.default];

    programs.agents = {
      enable = true;
      defaultScopes = ["global" "claude"];

      skills = with pkgs.agent-skills; [
        # These inherit defaultScopes ["common" "claude"]
        (encoredev.skills {
          plugins = [
            "encore-api"
            "encore-code-review"
          ];
        })

        (anthropics.skills {
          plugins = ["pdf"];
          prefix = "anthropics-";
        })

        # This one overrides defaultScopes with its own
        (anthropics.skills {
          plugins = ["pptx"];
          scopes = ["global"];
        })
      ];
    };
  };

  testScript = ''
    # Test that encoredev skills are in both common (.agents) and claude scopes
    for skill in ["encore-api", "encore-code-review"]:
        global_path = f"/home/testuser/.agents/skills/{skill}"
        claude_path = f"/home/testuser/.claude/skills/{skill}"
        machine.succeed(f"test -d {global_path} && test -f {global_path}/SKILL.md")
        machine.succeed(f"test -d {claude_path} && test -f {claude_path}/SKILL.md")

    # Test that anthropics pdf (inherits defaultScopes) is in both scopes
    pdf_global = "/home/testuser/.agents/skills/anthropics-pdf"
    pdf_claude = "/home/testuser/.claude/skills/anthropics-pdf"
    machine.succeed(f"test -d {pdf_global} && test -f {pdf_global}/SKILL.md")
    machine.succeed(f"test -d {pdf_claude} && test -f {pdf_claude}/SKILL.md")

    # Test that anthropics pptx (with scopes override) is ONLY in global scope
    pptx_global = "/home/testuser/.agents/skills/pptx"
    pptx_claude = "/home/testuser/.claude/skills/pptx"
    machine.succeed(f"test -d {pptx_global} && test -f {pptx_global}/SKILL.md")
    machine.succeed(f"test ! -d {pptx_claude}")

    print("Default scopes feature working correctly:")
    print("- Skills without explicit scopes inherit defaultScopes")
    print("- Skills can override defaultScopes with their own scopes attribute")
  '';
}
