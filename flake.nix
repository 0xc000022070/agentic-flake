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
        system: f (nixpkgs.legacyPackages.${system}.appendOverlays [self.overlays.default])
      );

    sourcesFile = builtins.fromJSON (builtins.readFile ./sources.json);

    mkProjectFactory = lib:
      (import ./lib/project-factory.nix {inherit lib;}).project-factory;

    skillApi = import ./lib/skill-api.nix {lib = nixpkgs.lib;};

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
    lib = {
      project-factory = mkProjectFactory nixpkgs.lib;
      inherit (skillApi) mkSkill;
    };

    homeModules.default = import ./modules/home-manager/agents.nix;

    overlays.default = final: _prev: {
      agent-skills = mkSkillPackages final;
    };

    devShells = forAllSystems (pkgs: let
      agentic-setup = self.lib.project-factory {
        inherit pkgs;

        plugins = with pkgs.agent-skills; [
          (official.anthropics.skills {
            scopes = ["standard" "claude"];
            plugins = ["skill-creator"];
          })
        ];
      };
    in {
      default = pkgs.mkShell {
        inherit (agentic-setup) shellHook;
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
