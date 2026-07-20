{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];

    forAllSystems = f:
      nixpkgs.lib.genAttrs supportedSystems (
        system: f (nixpkgs.legacyPackages.${system}.appendOverlays [self.overlays.default])
      );

    sourcesFile = builtins.fromJSON (builtins.readFile ./sources.json);

    mkProjectFactory = lib:
      (import ./lib/project-factory.nix {inherit lib;}).project-factory;

    skillApi = import ./lib/skill-api.nix {lib = nixpkgs.lib;};

    mkSkillPackages = pkgs: let
      lib = pkgs.lib;
      pkgLib = import ./lib/packages.nix {inherit pkgs lib;};
      skillPackages = pkgLib.buildPackageTree pkgLib.mkSkillPackage sourcesFile.providers;
    in
      lib.mapAttrs (
        _: providerData:
          lib.mapAttrs (
            _: orgRepos:
              lib.mapAttrs (_: package: package) orgRepos
          )
          providerData
      )
      skillPackages;
  in {
    lib = {
      project-factory = mkProjectFactory nixpkgs.lib;
      inherit (skillApi) mkSkill mkInlineSkill;

      # Load a pins file written by `nix run agentic-flake#add` into an
      # attrset of callable skill packages, keyed by pin name.
      pinnedSkills = {
        pkgs,
        pinsFile,
      }: let
        pkgLib = import ./lib/packages.nix {
          inherit pkgs;
          lib = pkgs.lib;
        };
        pinned = builtins.fromJSON (builtins.readFile pinsFile);
      in
        pkgs.lib.mapAttrs (
          _: entry:
            pkgLib.mkSkillPackage {
              inherit (entry) owner repo rev sha256;
            }
        ) (pinned.pins or {});
    };

    # Overlay-free access to the catalog: agentic-flake.skills.${system}.<org>.<repo>
    skills = forAllSystems (pkgs: pkgs.agent-skills);

    templates.default = {
      path = ./templates/minimal;
      description = "Dev shell with declarative agent skills";
    };

    homeModules.default = import ./modules/home-manager/agents.nix;

    overlays.default = final: _prev: {
      agent-skills = mkSkillPackages final;
    };

    devShells = forAllSystems (pkgs: let
      agentic-setup = self.lib.project-factory {
        inherit pkgs;

        skills = with pkgs.agent-skills; [
          (anthropics.skills {
            scopes = ["standard" "claude"];
            plugins = ["skill-creator"];
          })
        ];
      };
    in {
      default = pkgs.mkShell {
        inherit (agentic-setup) shellHook;
        buildInputs = with pkgs; [
          bun
          htmlq
          curl
          git
        ];
      };
    });

    apps = forAllSystems (pkgs: let
      add = pkgs.writeShellApplication {
        name = "agentic-add";
        runtimeInputs = [pkgs.git pkgs.jq];
        text = ''
          repo_arg="''${1:?usage: agentic-add <owner>/<repo> [pin-name]}"
          owner="''${repo_arg%%/*}"
          repo="''${repo_arg##*/}"
          if [ -z "$owner" ] || [ -z "$repo" ] || [ "$owner" = "$repo_arg" ]; then
            echo "expected <owner>/<repo>, got '$repo_arg'" >&2
            exit 1
          fi
          name="''${2:-$repo}"
          pins="''${AGENTIC_PINS_FILE:-agentic-skills.json}"

          echo "resolving $owner/$repo..."
          rev=$(git ls-remote "https://github.com/$owner/$repo.git" HEAD | cut -f1)
          if [ -z "$rev" ]; then
            echo "could not resolve HEAD of $owner/$repo" >&2
            exit 1
          fi

          echo "prefetching..."
          sha256=$(nix-prefetch-url --unpack "https://github.com/$owner/$repo/archive/$rev.tar.gz" 2>/dev/null)
          if [ -z "$sha256" ]; then
            echo "nix-prefetch-url failed for $owner/$repo@$rev" >&2
            exit 1
          fi

          [ -f "$pins" ] || printf '{"version":"1","pins":{}}\n' > "$pins"
          tmp=$(mktemp)
          jq --arg name "$name" --arg owner "$owner" --arg repo "$repo" \
             --arg rev "$rev" --arg sha256 "$sha256" \
             '.pins[$name] = {owner: $owner, repo: $repo, rev: $rev, sha256: $sha256}' \
             "$pins" > "$tmp"
          mv "$tmp" "$pins"
          echo "pinned $owner/$repo@''${rev:0:7} as '$name' in $pins"
        '';
      };

      update = pkgs.writeShellApplication {
        name = "agentic-update";
        runtimeInputs = [pkgs.git pkgs.jq];
        text = ''
          pins="''${AGENTIC_PINS_FILE:-agentic-skills.json}"
          if [ ! -f "$pins" ]; then
            echo "no $pins in $PWD (run the add app first)" >&2
            exit 1
          fi

          updated=0
          while IFS= read -r name; do
            owner=$(jq -r --arg n "$name" '.pins[$n].owner' "$pins")
            repo=$(jq -r --arg n "$name" '.pins[$n].repo' "$pins")
            current=$(jq -r --arg n "$name" '.pins[$n].rev' "$pins")

            rev=$(git ls-remote "https://github.com/$owner/$repo.git" HEAD | cut -f1)
            if [ -z "$rev" ]; then
              echo "skip $name: could not resolve $owner/$repo" >&2
              continue
            fi
            if [ "$rev" = "$current" ]; then
              echo "$name: up to date"
              continue
            fi

            sha256=$(nix-prefetch-url --unpack "https://github.com/$owner/$repo/archive/$rev.tar.gz" 2>/dev/null)
            if [ -z "$sha256" ]; then
              echo "skip $name: prefetch failed for rev $rev" >&2
              continue
            fi

            tmp=$(mktemp)
            jq --arg n "$name" --arg rev "$rev" --arg sha256 "$sha256" \
               '.pins[$n].rev = $rev | .pins[$n].sha256 = $sha256' "$pins" > "$tmp"
            mv "$tmp" "$pins"
            echo "$name: $current -> ''${rev:0:7}"
            updated=$((updated + 1))
          done < <(jq -r '.pins | keys[]' "$pins")

          echo "$updated pin(s) updated"
        '';
      };
    in {
      add = {
        type = "app";
        program = "${add}/bin/agentic-add";
      };
      update = {
        type = "app";
        program = "${update}/bin/agentic-update";
      };
    });

    checks = forAllSystems (
      pkgs:
        import ./tests {
          self = self;
          nixpkgs = nixpkgs;
          inherit home-manager;
        }
    );
  };
}
