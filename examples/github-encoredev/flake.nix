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

    encoreSkills = agentic-flake.lib.mkSkill {
      src = builtins.fetchGit {
        url = "https://github.com/encoredev/skills";
        rev = "91fda02311c65b57c0f56d793c1aa01420083002";
      };
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
            skills = [
              (encoreSkills {
                plugins = [
                  "encore-api"
                  "encore-service"
                  "encore-testing"
                ];
                scopes = ["global" "claude"];
              })
            ];
          };
        }
      ];
    };
  };
}
