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
    "all-skill-types-integration" = ./all-skill-types-integration.nix;
    "default-scopes" = ./default-scopes.nix;
    "encoredev-skills-installation" = ./encoredev-skills.nix;
    "mk-skill-integration" = ./mk-skill-integration.nix;
    "mk-inline-skill-integration" = ./mk-inline-skill-integration.nix;
    "mk-inline-skill-mixed" = ./mk-inline-skill-mixed.nix;
    "openfang-fetch-skill" = ./openfang-fetch-skill.nix;
    "prefix-and-scopes" = ./prefix-and-scopes.nix;
    "hm-conflict-detection" = ./hm-conflict-detection.nix;
    "workspaces" = ./workspaces.nix;
  };

  exampleChecks = {
    "example-1-minimal-devshell-shell" = (
      let
        flake = import (self + "/examples/1-minimal-devshell/flake.nix");
        outputs = flake.outputs {
          self = self;
          nixpkgs = nixpkgs;
          agentic-flake = self;
        };
      in
        outputs.devShells."x86_64-linux".default
    );
    "example-2-multi-source-shell" = (
      let
        flake = import (self + "/examples/2-multi-source/flake.nix");
        outputs = flake.outputs {
          self = self;
          nixpkgs = nixpkgs;
          agentic-flake = self;
        };
      in
        outputs.devShells."x86_64-linux".default
    );
    "example-3-home-manager-config" = (
      let
        flake = import (self + "/examples/3-home-manager/flake.nix");
        outputs = flake.outputs {
          self = self;
          nixpkgs = nixpkgs;
          home-manager = home-manager;
          agentic-flake = self;
        };
      in
        outputs.homeConfigurations.yourname.activationPackage
    );
  };
in
  (pkgs.lib.mapAttrs (name: path: mkTestSuite name path) suites)
  // exampleChecks
  // {
    "mk-skill-lib" = import ./mk-skill-lib.nix {
      inherit pkgs;
      agentic-flake = self;
    };
    "mk-inline-skill-lib" = import ./mk-inline-skill-lib.nix {
      inherit pkgs;
      agentic-flake = self;
    };
    "project-factory-null-scopes" = import ./project-factory-null-scopes.nix {
      inherit pkgs;
      agentic-flake = self;
    };
    "project-factory-conflict-detection" = import ./project-factory-conflict-detection.nix {
      inherit pkgs;
      agentic-flake = self;
    };
    "project-factory-context" = import ./project-factory-context.nix {
      inherit pkgs;
      agentic-flake = self;
    };
  }
