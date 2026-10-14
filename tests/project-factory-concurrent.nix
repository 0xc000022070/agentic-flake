{
  agentic-flake,
  pkgs,
  ...
}: let
  skillBundle = pkgs.runCommand "concurrent-test-skills" {} ''
    for skill in alpha beta gamma; do
      mkdir -p "$out/$skill"
      touch "$out/$skill/SKILL.md"
    done
  '';

  contextFile = pkgs.writeText "concurrent-context.md" "shared context";

  setup = agentic-flake.lib.project-factory {
    inherit pkgs;
    skills = [
      {
        drv = skillBundle;
        plugins = ["alpha" "beta" "gamma"];
        scopes = ["standard"];
      }
    ];
    context.AGENTS = contextFile;
  };
in
  pkgs.runCommand "project-factory-concurrent-test" {} ''
    set -e

    work="$TMPDIR/work"
    mkdir -p "$work"
    cd "$work"

    ${setup.shellHook}

    for round in $(seq 1 25); do
      pids=""
      for shell in 1 2 3 4; do
        (
          ${setup.shellHook}
        ) >"$TMPDIR/hook-$round-$shell.log" 2>&1 &
        pids="$pids $!"
      done

      for pid in $pids; do
        if ! wait "$pid"; then
          cat "$TMPDIR"/hook-$round-*.log >&2
          echo "concurrent shell hook failed in round $round" >&2
          exit 1
        fi
      done
    done

    for skill in alpha beta gamma; do
      test "$(readlink "$work/.agents/skills/$skill")" = "${skillBundle}/$skill"
    done
    test "$(readlink "$work/AGENTS.md")" = "${contextFile}"
    test -z "$(find "$work" -name '*.agentic-tmp.*')"

    mkdir -p "$out"
    touch "$out/ok"
  ''
