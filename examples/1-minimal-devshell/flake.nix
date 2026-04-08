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
        inlineSkills = agentic-flake.lib.mkInlineSkill {
          "quick-reference" = {
            description = "Quick reference for common commands and patterns";
            tags = ["reference"];
            content = ''
              # Quick Reference

              Fast lookup for:
              - Shell commands
              - Git workflows
              - Nix syntax
              - Configuration examples

              Ask for what you need.
            '';
          };

          "code-formatter" = {
            description = "Format and beautify code snippets";
            tags = ["formatting"];
            content = ''
              # Code Formatter

              Handles formatting for:
              - JSON, YAML, TOML
              - Markdown
              - Shell scripts
              - Multi-language cleanup

              Paste your code for formatting.
            '';
          };
        };

        agenticSetup = agentic-flake.lib.project-factory {
          inherit pkgs;
          defaultScopes = ["standard" "claude"];

          skills = with pkgs.agent-skills; [
            (official.anthropics.skills {
              plugins = ["pdf" "pptx"];
              prefix = "anthropics-";
            })

            (inlineSkills {
              plugins = ["quick-reference" "code-formatter"];
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
