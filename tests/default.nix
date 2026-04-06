{
  self,
  nixpkgs,
  home-manager,
}: let
  pkgs = (nixpkgs.legacyPackages.x86_64-linux).appendOverlays [self.overlays.default];

  mkTestSuite = name: suitePath: let
    suite = import suitePath {
      inherit pkgs home-manager;
      agentic-flake = self;
    };
  in
    pkgs.testers.nixosTest {
      inherit name;

      nodes.machine = {
        imports = [
          {
            imports = [home-manager.nixosModules.home-manager];

            nixpkgs.overlays = [self.overlays.default];

            users.users.testuser = {
              isNormalUser = true;
              home = "/home/testuser";
              createHome = true;
              group = "users";
              uid = 1000;
            };

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;

              users.testuser = {
                imports = [suite.homeModule];

                home.stateVersion = "26.05";
              };
            };
          }
        ];
      };

      testScript = ''
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_unit("home-manager-testuser.service")
        ${suite.testScript}
      '';
    };

  suites = {
    "encoredev-skills-installation" = ./encoredev-skills.nix;
    "mk-skill-integration" = ./mk-skill-integration.nix;
    "openfang-fetch-skill" = ./openfang-fetch-skill.nix;
    "prefix-and-scopes" = ./prefix-and-scopes.nix;
    "workspaces" = ./workspaces.nix;
  };
in
  (pkgs.lib.mapAttrs (name: path: mkTestSuite name path) suites)
  // {
    "mk-skill-lib" = import ./mk-skill-lib.nix {
      inherit pkgs;
      agentic-flake = self;
    };
  }
