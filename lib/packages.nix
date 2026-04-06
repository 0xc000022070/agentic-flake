{
  pkgs,
  lib,
}: {
  mkSkillPackage = {
    owner,
    repo,
    rev,
    sha256,
  }:
    pkgs.stdenvNoCC.mkDerivation {
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
        mkdir -p $out/plugins

        for f in AGENTS.md CLAUDE.md; do
          [ -f "$f" ] && cp "$f" "$out/"
        done

        cp -rL plugins/* "$out/plugins/"
      '';

      meta = with lib; {
        description = "Agent skill: ${owner}/${repo}";
        homepage = "https://github.com/${owner}/${repo}";
        license = licenses.free;
        platforms = platforms.all;
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

  mkOfficialAlias = pkgs: lib: flattenedPackages:
    pkgs.symlinkJoin {
      name = "skills-sh-official";
      paths = lib.flatten (
        lib.mapAttrsToList (
          org: orgRepos:
            lib.mapAttrsToList (repoName: package: package) orgRepos
        )
        flattenedPackages.official
      );
      postBuild = ''
        mkdir -p $out/share/doc
        echo "Official Agent Skills Collection" > $out/share/doc/README.md
      '';
    };
}
