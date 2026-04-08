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
    inlineContent ? {},
  }: let
    isInline = src == "inline";
    normalizedSrc =
      if isInline
      then null
      else normalizeSrc src;
  in
    pkgs.stdenvNoCC.mkDerivation (
      {
        inherit pname version meta;
        src = normalizedSrc;

        dontBuild = true;
        dontConfigure = true;

        installPhase = ''
          mkdir -p "$out"
          ${lib.concatMapStringsSep "\n" (
            plugin: let
              relPath = skillMap.${plugin};
            in
              if inlineContent ? ${plugin}
              then ''
                              mkdir -p "$out/${plugin}"
                              cat > "$out/${plugin}/SKILL.md" << 'CONTENT'
                ${inlineContent.${plugin}}
                CONTENT
              ''
              else let
                srcPath =
                  if relPath == "."
                  then "$src"
                  else "$src/${relPath}";
              in ''
                mkdir -p "$out/$(dirname '${plugin}')"
                cp -rL "${srcPath}" "$out/${plugin}"
              ''
          ) (builtins.attrNames skillMap)}

          ${
            if !isInline
            then ''
              for f in AGENTS.md CLAUDE.md; do
                [ -f "$src/$f" ] && cp "$src/$f" "$out/" || true
              done
            ''
            else ""
          }
        '';
      }
      // (
        if isInline
        then {dontUnpack = true;}
        else {}
      )
    );
in {
  inherit mkSkill;

  mkMaterializedSkill = {
    src,
    skillMap,
    pname ? "agent-skills",
    version ? "dev",
    meta ? {},
    inlineContent ? {},
  }: let
    drv = mkSkillDerivation {
      inherit src skillMap pname version meta inlineContent;
    };
  in
    drv
    // {
      availablePlugins = builtins.attrNames skillMap;
      inherit src skillMap;

      __functor = self: {
        plugins,
        scopes ? null,
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
          inlineContent = entry.__inlineSkillContent or {};
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

      # Skill repos come in two flavours:
      #   1. Umbrella — root SKILL.md defines the skill, sub-dirs are
      #      supporting content (e.g. novuhq/skills → "novu").
      #   2. Flat — no root SKILL.md, each sub-dir is an independent
      #      skill (e.g. encoredev/skills → "encore-testing", …).
      # When a root SKILL.md exists, copy the entire source as a
      # single skill whose name comes from frontmatter or the repo.
      installPhase = ''
        mkdir -p "$out"

        if [ -f "./SKILL.md" ]; then
          skill_name=$(sed -n '/^---$/,/^---$/{/^name: */{ s/^name: *//; s/ *$//; p; q; }}' "./SKILL.md")
          if [ -z "$skill_name" ]; then
            skill_name="${repo}"
          fi
          skill_name=$(echo "$skill_name" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | sed 's/--*/-/g; s/^-//; s/-$//')
          cp -rL . "$out/$skill_name"
        else
          for skill_file in $(find -L . -name SKILL.md -type f); do
            skill_dir=$(dirname "$skill_file")

            [ "$skill_dir" = "." ] && continue
            if echo "$skill_dir" | grep -qi "template"; then continue; fi

            skill_name=$(sed -n '/^---$/,/^---$/{/^name: */{ s/^name: *//; s/ *$//; p; q; }}' "$skill_file")

            if [ -z "$skill_name" ]; then
              skill_name=$(basename "$skill_dir")
            fi

            skill_name=$(echo "$skill_name" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | sed 's/--*/-/g; s/^-//; s/-$//')

            if [ -d "$out/$skill_name" ]; then
              continue
            fi

            cp -rL "$skill_dir" "$out/$skill_name" || true
          done
        fi

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
        scopes ? null,
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
