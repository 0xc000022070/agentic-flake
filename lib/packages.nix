{
  pkgs,
  lib,
}: let
  skillApi = import ./skill-api.nix {inherit lib;};
  inherit (skillApi) normalizeSrc assertKnownPlugins mkSkill;

  mkSkillDerivation = {
    src,
    skillMap,
    pname ? "agent-skills",
    version ? "dev",
    meta ? {},
  }: let
    normalizedSrc = normalizeSrc src;
  in
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname version meta;
      src = normalizedSrc;

      dontBuild = true;
      dontConfigure = true;

      installPhase = ''
        mkdir -p "$out"
        ${lib.concatMapStringsSep "\n" (plugin: let
          relPath = skillMap.${plugin};
          srcPath =
            if relPath == "."
            then "$src"
            else "$src/${relPath}";
        in ''
          mkdir -p "$out/$(dirname '${plugin}')"
          cp -rL "${srcPath}" "$out/${plugin}"
        '') (builtins.attrNames skillMap)}

        for f in AGENTS.md CLAUDE.md; do
          [ -f "$src/$f" ] && cp "$src/$f" "$out/" || true
        done
      '';
    };
in {
  inherit mkSkill;

  mkMaterializedSkill = {
    src,
    skillMap,
    pname ? "agent-skills",
    version ? "dev",
    meta ? {},
  }: let
    drv = mkSkillDerivation {
      inherit src skillMap pname version meta;
    };
  in
    drv
    // {
      availablePlugins = builtins.attrNames skillMap;
      inherit src skillMap;

      __functor = self: {
        plugins,
        scopes ? ["global"],
        prefix ? "",
      }:
        builtins.seq (assertKnownPlugins self.availablePlugins plugins) {
          inherit plugins scopes prefix;
          drv = self;
        };
    };

  materializeConfiguredSkill = entry:
    if entry ? drv
    then entry
    else if entry ? __agenticSkill && entry ? src && entry ? skillMap
    then
      entry
      // {
        drv = mkSkillDerivation {
          inherit (entry) src skillMap;
          pname = "agent-skill-bundle";
        };
      }
    else entry;

  mkSkillPackage = {
    owner,
    repo,
    rev,
    sha256,
  }: let
    src =
      if sha256 != ""
      then pkgs.fetchFromGitHub {inherit owner repo rev sha256;}
      else
        pkgs.fetchGit {
          url = "https://github.com/${owner}/${repo}";
          inherit rev;
        };
    drv = pkgs.stdenvNoCC.mkDerivation {
      pname = "${owner}-${repo}";
      version = rev;
      inherit src;

      dontBuild = true;
      dontConfigure = true;

      installPhase = ''
        mkdir -p "$out"

        for skill_file in $(find -L . -name SKILL.md -type f); do
          skill_dir=$(dirname "$skill_file")

          [ "$skill_dir" = "." ] && continue
          if echo "$skill_dir" | grep -qi "template"; then continue; fi

          skill_name=$(sed -n '/^---$/,/^---$/{/^name: */{ s/^name: *//; s/ *$//; p; q; }}' "$skill_file")

          if [ -z "$skill_name" ]; then
            skill_name=$(basename "$skill_dir")
          fi

          if [ -d "$out/$skill_name" ]; then
            continue
          fi

          cp -rL "$skill_dir" "$out/$skill_name" || true
        done

        for f in AGENTS.md CLAUDE.md; do
          [ -f "$f" ] && cp "$f" "$out/" || true
        done
      '';
    };
  in
    drv
    // {
      __functor = self: {
        plugins,
        scopes ? ["global"],
        prefix ? "",
      }: {
        inherit plugins scopes prefix;
        drv = self;
      };
    };

  buildPackageTree = mkSkill: providers:
    lib.mapAttrs (
      providerName: providerData:
        lib.mapAttrs (
          org: orgRepos:
            lib.mapAttrs (
              repoName: repoData:
                mkSkill repoData
            )
            orgRepos
        )
        providerData
    )
    providers;
}
