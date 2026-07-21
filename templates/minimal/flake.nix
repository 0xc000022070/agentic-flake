{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    agentic-flake.url = "github:0xc000022070/agentic-flake";
  };

  outputs = {
    nixpkgs,
    agentic-flake,
    ...
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];

    forAllSystems = f:
      nixpkgs.lib.genAttrs supportedSystems (
        system: f nixpkgs.legacyPackages.${system}
      );
  in {
    devShells = forAllSystems (
      pkgs: let
        catalog = agentic-flake.skills.${pkgs.system};

        agenticSetup = agentic-flake.lib.project-factory {
          inherit pkgs;
          name = "my-project";
          defaultScopes = ["standard" "claude"];

          skills = [
            (catalog.anthropics.skills {
              plugins = ["skill-creator"];
            })
          ];
        };
      in {
        default = pkgs.mkShell {
          inherit (agenticSetup) shellHook;
        };
      }
    );
  };
}
