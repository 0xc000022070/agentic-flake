{
  agentic-flake,
  pkgs,
  ...
}: let
  skillBundle = pkgs.runCommand "warning-test-skills" {} ''
    mkdir -p "$out/valid"
    touch "$out/valid/SKILL.md"
  '';

  setup = agentic-flake.lib.project-factory {
    inherit pkgs;
    skills = [
      {
        drv = skillBundle;
        plugins = ["valid" "missing"];
        scopes = ["standard"];
      }
    ];
  };
in
  pkgs.runCommand "project-factory-missing-source-test" {} ''
    set -e

    work="$TMPDIR/work"
    mkdir -p "$work/.agents/skills"
    cd "$work"

    ln -s "${skillBundle}/missing" "$work/.agents/skills/missing"
    test -L "$work/.agents/skills/missing"

    (
      ${setup.shellHook}
    ) >"$TMPDIR/setup.log" 2>&1

    test -L "$work/.agents/skills/valid"
    test -e "$work/.agents/skills/valid/SKILL.md"
    test ! -L "$work/.agents/skills/missing"
    grep -F "agentic-flake: warning: skill source '${skillBundle}/missing' does not exist; skipping '.agents/skills/missing'" "$TMPDIR/setup.log"

    mkdir -p "$out"
    touch "$out/ok"
  ''
