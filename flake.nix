{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];

    forAllSystems = f:
      nixpkgs.lib.genAttrs supportedSystems (
        system: f nixpkgs.legacyPackages.${system}
      );

    sourcesFile = builtins.fromJSON (builtins.readFile ./sources.json);

    mkSkillPackages = pkgs: let
      lib = pkgs.lib;
      pkgLib = import ./lib/packages.nix {inherit pkgs lib;};
      skillPackages = pkgLib.buildPackageTree pkgLib.mkSkillPackage sourcesFile.providers;
    in
      lib.mapAttrs (
        _: providerData:
          lib.mapAttrs (
            _: orgRepos:
              lib.mapAttrs (_: package: package) orgRepos
          )
          providerData
      )
      skillPackages;
  in {
    homeManagerModules.agents = import ./modules/home-manager/agents.nix;
    homeManagerModules.default = self.homeManagerModules.agents;
    homeModules.default = self.homeManagerModules.agents;

    overlays.default = final: _prev: {
      agent-skills = {
        skills-sh = mkSkillPackages final;
      };
    };

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

    checks = forAllSystems (
      pkgs:
        import ./tests {
          self = self;
          nixpkgs = nixpkgs;
          inherit home-manager;
        }
    );
  };
}
