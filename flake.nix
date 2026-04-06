{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];

    forAllSystems = f:
      nixpkgs.lib.genAttrs supportedSystems (
        system: f nixpkgs.legacyPackages.${system}
      );
  in {
    packages = forAllSystems (
      pkgs: let
        lib = nixpkgs.lib;

        sourcesFile = builtins.fromJSON (builtins.readFile ./sources.json);
        pkgLib = import ./lib/packages.nix {inherit pkgs lib;};

        skillPackages = pkgLib.buildPackageTree pkgLib.mkSkillPackage sourcesFile.providers;
        flattenedPackages =
          lib.mapAttrs (
            providerName: providerData:
              lib.mapAttrs (
                org: orgRepos:
                  lib.mapAttrs (repoName: package: package) orgRepos
              )
              providerData
          )
          skillPackages;
      in {
        skills-sh = flattenedPackages;
        skills-sh-official = pkgLib.mkOfficialAlias pkgs lib flattenedPackages;
      }
    );

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        buildInputs = with pkgs; [
          bun
          htmlq
          curl
          git
        ];
      };
    });
  };
}
