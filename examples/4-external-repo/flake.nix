{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    agentic-flake.url = "path:../..";

    # Any skill repo works as a non-flake input: no rev, no sha256 —
    # the lockfile pins it, `nix flake update <name>` upgrades it.
    android-skills = {
      url = "github:new-silvermoon/awesome-android-agent-skills";
      flake = false;
    };

    novu-skills = {
      url = "github:novuhq/skills";
      flake = false;
    };
  };

  outputs = {
    nixpkgs,
    agentic-flake,
    android-skills,
    novu-skills,
    ...
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];

    # No overlay needed: skills come from flake inputs, not the catalog.
    forAllSystems = f:
      nixpkgs.lib.genAttrs supportedSystems (
        system: f nixpkgs.legacyPackages.${system}
      );
  in {
    devShells = forAllSystems (
      pkgs: let
        androidSkills = agentic-flake.lib.mkSkill {
          src = android-skills;
        };

        novuSkills = agentic-flake.lib.mkSkill {
          src = novu-skills;
        };

        agenticSetup = agentic-flake.lib.project-factory {
          inherit pkgs;
          defaultScopes = ["standard" "claude"];

          skills = [
            (androidSkills {
              plugins = ["android-gradle-logic" "compose-performance-audit"];
            })

            (novuSkills {
              plugins = ["trigger-notification" "connect-agent"];
              prefix = "novu-";
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
