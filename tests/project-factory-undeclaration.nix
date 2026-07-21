{
  agentic-flake,
  pkgs,
  ...
}: let
  skillBundle = pkgs.runCommand "undeclaration-test-skills" {} ''
    for skill in kept removed changed; do
      mkdir -p "$out/$skill"
      touch "$out/$skill/SKILL.md"
    done
  '';

  mkSetup = {
    name ? "default",
    plugins,
  }:
    agentic-flake.lib.project-factory {
      inherit pkgs name;
      skills = [
        {
          drv = skillBundle;
          inherit plugins;
          scopes = ["standard"];
        }
      ];
    };

  initialSetup = mkSetup {plugins = ["kept" "removed" "changed"];};
  reducedSetup = mkSetup {plugins = ["kept"];};
  emptySetup = agentic-flake.lib.project-factory {
    inherit pkgs;
    skills = [];
  };
  inheritedSetup = mkSetup {
    name = "inherited";
    plugins = ["kept"];
  };
  localSetup = mkSetup {
    name = "local";
    plugins = ["removed"];
  };
  emptyInheritedSetup = agentic-flake.lib.project-factory {
    inherit pkgs;
    name = "inherited";
    skills = [];
  };
in
  pkgs.runCommand "project-factory-undeclaration-test" {} ''
    set -e

    work="$TMPDIR/work"
    external="$TMPDIR/external"
    mkdir -p "$work" "$external"
    cd "$work"

    ${initialSetup.shellHook}

    manifest="$work/.agents/.agentic-flake-managed-links"
    test -L "$work/.agents/skills/kept"
    test -L "$work/.agents/skills/removed"
    test -L "$work/.agents/skills/changed"
    test -f "$manifest"

    rm "$work/.agents/skills/changed"
    ln -s "$external" "$work/.agents/skills/changed"

    (
      ${reducedSetup.shellHook}
    ) >"$TMPDIR/reduced.log" 2>&1

    test -L "$work/.agents/skills/kept"
    test ! -e "$work/.agents/skills/removed"
    test "$(readlink "$work/.agents/skills/changed")" = "$external"
    grep -F "agentic-flake: removed undeclared skill '.agents/skills/removed'" "$TMPDIR/reduced.log"
    grep -F "agentic-flake: warning: managed link '.agents/skills/changed' changed outside agentic-flake; leaving it unchanged" "$TMPDIR/reduced.log"
    test "$(wc -l < "$manifest")" -eq 1
    grep -Fqx ".agents/skills/kept$(printf '\t')${skillBundle}/kept" "$manifest"

    ${emptySetup.shellHook}

    test ! -e "$work/.agents/skills/kept"
    test ! -e "$manifest"
    test "$(readlink "$work/.agents/skills/changed")" = "$external"

    ${inheritedSetup.shellHook}
    ${localSetup.shellHook}

    test -L "$work/.agents/skills/kept"
    test -L "$work/.agents/skills/removed"
    test -f "$work/.agents/.agentic-flake-managed-links-inherited"
    test -f "$work/.agents/.agentic-flake-managed-links-local"

    ${emptyInheritedSetup.shellHook}

    test ! -e "$work/.agents/skills/kept"
    test -L "$work/.agents/skills/removed"
    test ! -e "$work/.agents/.agentic-flake-managed-links-inherited"
    test -f "$work/.agents/.agentic-flake-managed-links-local"

    mkdir -p "$out"
    touch "$out/ok"
  ''
