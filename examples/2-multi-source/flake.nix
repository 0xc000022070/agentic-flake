{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    agentic-flake.url = "path:../..";
  };

  outputs = {
    nixpkgs,
    agentic-flake,
    ...
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];

    forAllSystems = f:
      nixpkgs.lib.genAttrs supportedSystems (
        system:
          f (nixpkgs.legacyPackages.${system}.appendOverlays [
            agentic-flake.overlays.default
          ])
      );
  in {
    devShells = forAllSystems (
      pkgs: let
        localSkills = agentic-flake.lib.mkSkill {
          src = ./skills;
        };

        inlineSkills = agentic-flake.lib.mkInlineSkill {
          "naming-convention" = {
            description = "Team naming standards and conventions";
            tags = ["reference"];
            content = ''
              # Naming Conventions

              ## Variables
              - camelCase for JS/TS
              - snake_case for Python/Nix
              - SCREAMING_SNAKE_CASE for constants

              ## Functions
              - Verb-first: getUser, formatDate, calculateTotal
            '';
          };

          "code-style" = {
            description = "Code style guide for consistency";
            tags = ["reference"];
            content = ''
              # Code Style Guide

              ## Formatting
              - 2 spaces for indentation
              - Max 80 chars per line

              ## Comments
              - Explain "why", not "what"
              - Keep comments up-to-date
            '';
          };
        };

        agenticSetup = agentic-flake.lib.project-factory {
          inherit pkgs;
          defaultScopes = ["standard" "claude"];

          skills = with pkgs.agent-skills; [
            (localSkills {
              plugins = [];
            })

            (official.anthropics.skills {
              plugins = ["pdf" "pptx"];
              prefix = "anthropics-";
            })

            (inlineSkills {
              plugins = ["naming-convention" "code-style"];
              prefix = "util-";
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
