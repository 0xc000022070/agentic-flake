{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agentic-flake.url = "path:../..";
  };

  outputs = {
    nixpkgs,
    home-manager,
    agentic-flake,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    localSkills = agentic-flake.lib.mkSkill {
      src = ./skills;
    };
  in {
    homeConfigurations.dev = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      modules = [
        agentic-flake.homeModules.default
        {
          home.username = "dev";
          home.homeDirectory = "/home/dev";
          home.stateVersion = "26.05";

          programs.agents = {
            enable = true;

            workspaces.api = {
              path = "Projects/api";
              scopes = ["claude"];
            };

            skills = [
              (localSkills {
                plugins = ["release"];
                scopes = ["global"];
              })

              (localSkills {
                plugins = ["review-api"];
                scopes = ["api"];
                prefix = "internal-";
              })
            ];
          };
        }
      ];
    };
  };
}
