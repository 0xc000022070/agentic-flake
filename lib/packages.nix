{
  pkgs,
  lib,
}: {
  mkSkillPackage = {
    owner,
    repo,
    rev,
    sha256,
  }: let
    drv = pkgs.stdenvNoCC.mkDerivation {
      pname = "${owner}-${repo}";
      version = rev;

      src =
        if sha256 != ""
        then pkgs.fetchFromGitHub {inherit owner repo rev sha256;}
        else
          pkgs.fetchGit {
            url = "https://github.com/${owner}/${repo}";
            inherit rev;
          };

      dontBuild = true;
      dontConfigure = true;

      installPhase = ''
        mkdir -p $out

        # Find and process each skill directory containing a SKILL.md
        # Use explicit loop to avoid pipe issues in nix build environment
        for skill_file in $(find -L . -name SKILL.md -type f); do
          skill_dir=$(dirname "$skill_file")

          # Skip root and template directories
          [ "$skill_dir" = "." ] && continue
          if echo "$skill_dir" | grep -qi "template"; then continue; fi

          # Extract the name from YAML frontmatter: "name: <value>"
          skill_name=$(sed -n '/^---$/,/^---$/{/^name: */{ s/^name: *//; s/ *$//; p; q; }}' "$skill_file")

          # Fallback to directory name if no frontmatter name found
          if [ -z "$skill_name" ]; then
            skill_name=$(basename "$skill_dir")
          fi

          # Skip duplicates (symlinks cause the same skill to appear multiple times)
          if [ -d "$out/$skill_name" ]; then
            continue
          fi

          # Copy skill directory with all assets, dereferencing symlinks
          cp -rL "$skill_dir" "$out/$skill_name" || true
        done

        # Copy repository-level documentation
        for f in AGENTS.md CLAUDE.md; do
          [ -f "$f" ] && cp "$f" "$out/" || true
        done
      '';

      meta = with lib; {
        description = "Agent skill: ${owner}/${repo}";
        homepage = "https://github.com/${owner}/${repo}";
        license = licenses.free;
        platforms = platforms.all;
      };
    };
  in
    drv
    // {
      # Make the package callable for use with the HM module:
      #   official.encoredev.skills {
      #     plugins = ["encore-api" "encore-database"];
      #     scopes = ["global" "claude"];
      #     prefix = "";
      #   }
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
