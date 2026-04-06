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

    openfangSkills = agentic-flake.lib.mkSkill {
      src =
        builtins.fetchGit {
          url = "https://github.com/RightNow-AI/openfang";
          rev = "07963779be926d3f501a3fdc9065934668c6cfc8";
        }
        + "/crates/openfang-skills/bundled";
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

            workspaces.ops = {
              path = "Projects/ops";
              scopes = ["claude"];
            };

            skills = [
              (openfangSkills {
                plugins = ["linux-networking"];
                scopes = ["ops"];
              })
            ];
          };
        }
      ];
    };
  };
}
