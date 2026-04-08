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
    pkgs = (nixpkgs.legacyPackages.${system}).appendOverlays [
      agentic-flake.overlays.default
    ];

    teamSkills = agentic-flake.lib.mkSkill {
      src = ./skills;
    };

    frameworkGuides = agentic-flake.lib.mkInlineSkill {
      "encore-guide" = {
        description = "Backend framework patterns";
        tags = ["backend"];
        content = ''
          # Backend Framework Guide

          Build type-safe backend services with Encore.

          ## Service Structure
          - Services organize related endpoints
          - Each service is a Go package
        '';
      };

      "react-guide" = {
        description = "React component patterns";
        tags = ["react" "frontend"];
        content = ''
          # React Guide

          ## Component Patterns
          - Functional components with hooks
          - Props for composition
          - Use Context/Redux to avoid prop drilling

          ## Hooks
          - useState for local state
          - useEffect for side effects
          - Custom hooks for reusable logic

          ## State Management
          - Local: useState
          - Shared: Context, Redux, Zustand
          - Server: React Query, SWR
        '';
      };
    };
  in {
    homeConfigurations.yourname = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      modules = [
        agentic-flake.homeModules.default
        {
          home.username = "yourname";
          home.homeDirectory = "/home/yourname";
          home.stateVersion = "26.05";

          programs.agents = {
            enable = true;

            defaultScopes = ["common"];

            workspaces = {
              api = {
                path = "Projects/api";
                scopes = ["claude"];
              };
              web = {
                path = "Projects/web";
                scopes = ["claude"];
              };
            };

            skills = with pkgs.agent-skills; [
              (teamSkills {
                plugins = ["code-review" "api-design"];
                scopes = ["common"];
              })

              (official.anthropics.skills {
                plugins = ["pdf" "pptx"];
                scopes = ["common"];
                prefix = "anthropics-";
              })

              (frameworkGuides {
                plugins = ["encore-guide" "react-guide"];
                scopes = ["common"];
                prefix = "guide-";
              })
            ];
          };
        }
      ];
    };
  };
}
