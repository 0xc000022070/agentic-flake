# agentic-flake

The goal is to keep the API minimal and usable in two common places:

- **Home Manager**, for user-level configuration
- **dev shells**, for project-local configuration

Instead of building a large catalog or registry model first, the approach is simple:

1. choose a source
2. select the plugins you need
3. done

Example:

```nix
(official.anthropics.skills {
  plugins = [
    "pdf"
    "pptx"
    "frontend-design"
  ];
})
```

If a skill repository is not already packaged, `mkSkill` lets you use the same interface for arbitrary repositories:

```nix
(agentic-flake.lib.mkSkill {
  src = pkgs.fetchFromGitHub {
    owner = "new-silvermoon";
    repo = "awesome-android-agent-skills";
    rev = "e5d0275e9f28f4e5feb5939210d78ef39568c029";
    sha256 = "sha256-m+d1iXr5tfyDQfJfVV6qhZHL1o8WgeMy8raezLcIMEs=";
  };
} {
  plugins = ["android-emulator-skill"];
})
```

The same API works for:

- global setup via Home Manager
- project-local setup inside `nix develop` (or *direnv*)

This allows keeping personal skills in dotfiles while defining project-specific skills directly in the repository, without introducing a separate configuration model.

## example (dev shell)

```nix
{
  outputs = { nixpkgs, agentic-flake, ... }: let
    supportedSystems = ["x86_64-linux"];

    forAllSystems = f:
      nixpkgs.lib.genAttrs supportedSystems (
        system: f (nixpkgs.legacyPackages.${system}.appendOverlays [
          agentic-flake.overlays.default
        ])
      );
  in {
    devShells = forAllSystems (pkgs: let
      agenticSetup = agentic-flake.lib.project-factory {
        inherit pkgs;
        defaultScopes = ["standard" "claude"];

        skills = with pkgs.agent-skills; [
          (official.anthropics.skills {
            plugins = ["skill-creator"];
          })
        ];
      };
    in {
      default = pkgs.mkShell {
        inherit (agenticSetup) shellHook;
      };
    });
  };
}
```

More examples can be found in [examples/](./examples/).
