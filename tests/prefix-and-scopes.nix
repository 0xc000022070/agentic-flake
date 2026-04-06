{
  agentic-flake,
  pkgs,
  ...
}: {
  homeModule = {
    imports = [agentic-flake.homeModules.default];

    programs.agents = {
      enable = true;
      skills = with pkgs.agent-skills; [
        (official.anthropics.skills {
          prefix = "anthropics-";
          scopes = ["global"];
          plugins = [
            "pdf"
            "pptx"
          ];
        })

        (official.anthropics.skills {
          scopes = ["claude"];
          plugins = [
            "claude-api"
          ];
        })
      ];
    };
  };

  testScript = ''
    # Test anthropics skills in global scope with prefix
    anthropics_global_skills = [
        "anthropics-pdf",
        "anthropics-pptx",
    ]

    for skill in anthropics_global_skills:
        path = f"/home/testuser/.agents/skills/{skill}"
        machine.succeed(f"test -d {path} && test -f {path}/SKILL.md")

    # Test anthropics skills in claude scope without prefix
    claude_path = "/home/testuser/.claude/skills/claude-api"
    machine.succeed(f"test -d {claude_path} && test -f {claude_path}/SKILL.md")

    # Verify no nested directories (only check directories that exist)
    result = machine.succeed(
        "find /home/testuser/.agents/skills /home/testuser/.claude/skills -mindepth 3 -type d 2>/dev/null | wc -l"
    )
    if int(result.strip()) > 0:
        machine.fail(f"Found nested skill directories: {result}")

    machine.succeed("test ! -d /home/testuser/.agents/skills/pdf")
    machine.succeed("test -d /home/testuser/.agents/skills/anthropics-pdf")

    machine.succeed("test -d /home/testuser/.claude/skills/claude-api")
    machine.succeed("test ! -d /home/testuser/.claude/skills/anthropics-claude-api")

    print("Anthropics skills installed with prefix in global scope")
    print("Anthropics skills installed without prefix in claude scope")
    print("No nested directories detected")
    print("Prefix logic working correctly")
  '';
}
