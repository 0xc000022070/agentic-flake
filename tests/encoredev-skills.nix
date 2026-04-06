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
        (official.encoredev.skills {
          scopes = ["claude" "global"];
          plugins = [
            "encore-api"
            "encore-code-review"
            "encore-service"
            "encore-auth"
            "encore-database"
            "encore-testing"
          ];
        })
      ];
    };
  };

  testScript = ''
    global_skills = [
        "encore-api",
        "encore-code-review",
        "encore-service",
        "encore-auth",
        "encore-database",
        "encore-testing",
    ]

    for skill in global_skills:
        path = f"/home/testuser/.agents/skills/{skill}"
        machine.succeed(f"test -d {path}")
        machine.succeed(f"test -f {path}/SKILL.md")

    for skill in global_skills:
        path = f"/home/testuser/.claude/skills/{skill}"
        machine.succeed(f"test -d {path}")
        machine.succeed(f"test -f {path}/SKILL.md")

    result = machine.succeed(
        "find /home/testuser/.agents/skills -mindepth 3 -type d | wc -l"
    )
    if int(result.strip()) > 0:
        machine.fail(f"Found nested skill directories: {result}")

    api_name = machine.succeed(
        "grep '^name:' /home/testuser/.agents/skills/encore-api/SKILL.md | head -1 | sed 's/^name: //'"
    ).strip()
    if "encore-api" not in api_name.lower():
        machine.fail(f"encore-api skill name incorrect: {api_name}")

    print("All skills installed correctly")
  '';
}
