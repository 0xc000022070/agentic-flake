# agentic-flake

The goal is to keep the API minimal and usable in two common places:

- **Home Manager**, for user-level configuration
- **dev shells**, for project-local configuration

Instead of building a large catalog or registry model first, the approach is simple:

1. choose a source
2. select the plugins you need
3. done

## quick start

```sh
nix flake init -t github:0xc000022070/agentic-flake
nix develop   # or `direnv allow`
```

This scaffolds a minimal dev shell with one catalog skill; edit the `skills` list from there.

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

## skill repos outside the catalog

If a skill repository is not already packaged, add it as a non-flake input and point `mkSkill` at it. No rev, no hash — your lockfile pins it:

```nix
{
  inputs.android-skills = {
    url = "github:new-silvermoon/awesome-android-agent-skills";
    flake = false;
  };
}
```

```nix
(agentic-flake.lib.mkSkill {src = inputs.android-skills;} {
  plugins = ["android-emulator-skill"];
})
```

For umbrella repos (a single `SKILL.md` at the repo root), set `name` to control the skill id — store-path basenames are just `source`, so the derived default is rarely what you want:

```nix
(agentic-flake.lib.mkSkill {
  src = inputs.some-skill-repo;
  name = "my-skill";
} {
  plugins = ["my-skill"];
})
```

`mkSkill` also accepts local paths (`src = ./skills;`) and fetcher results (`pkgs.fetchFromGitHub`, `builtins.fetchGit`) if you prefer explicit pins inside the file. See [examples/4-external-repo](./examples/4-external-repo/) for a complete flake.

## upgrading skills

- **Catalog skills** (`pkgs.agent-skills.*`) are pinned by this flake's `sources.json` and refreshed by CI. Pull the latest pins with `nix flake update agentic-flake`.
- **Skills added as flake inputs** are pinned by your own lockfile. Upgrade one with `nix flake update <input-name>`.
- **Need a catalog repo newer than the current pin?** Add it as your own `flake = false` input and use `mkSkill` — your lockfile wins, no need to wait for a catalog sync.

## pins file (alternative to flake inputs)

If you'd rather not touch your flake inputs for every skill repo, keep pins in a JSON file managed by the bundled helper:

```sh
nix run github:0xc000022070/agentic-flake#add -- new-silvermoon/awesome-android-agent-skills android
nix run github:0xc000022070/agentic-flake#update   # refresh all pins
```

This writes `agentic-skills.json` (override with `AGENTIC_PINS_FILE`) next to your flake — commit it. Load it with `pinnedSkills`:

```nix
devShells = forAllSystems (pkgs: let
  pinned = agentic-flake.lib.pinnedSkills {
    inherit pkgs;
    pinsFile = ./agentic-skills.json;
  };

  agenticSetup = agentic-flake.lib.project-factory {
    inherit pkgs;
    skills = [
      (pinned.android {
        plugins = ["android-emulator-skill"];
      })
    ];
  };
in { ... });
```

The helper only edits the pins file; evaluation stays pure and reproducible.

The same API works for:

- global setup via Home Manager
- project-local setup inside `nix develop` (or *direnv*)

This allows keeping personal skills in dotfiles while defining project-specific skills directly in the repository, without introducing a separate configuration model.

## example (dev shell)

The catalog is reachable directly via the `skills` output — no overlay required:

```nix
{
  outputs = { nixpkgs, agentic-flake, ... }: let
    supportedSystems = ["x86_64-linux"];

    forAllSystems = f:
      nixpkgs.lib.genAttrs supportedSystems (
        system: f nixpkgs.legacyPackages.${system}
      );
  in {
    devShells = forAllSystems (pkgs: let
      catalog = agentic-flake.skills.${pkgs.system};

      agenticSetup = agentic-flake.lib.project-factory {
        inherit pkgs;
        defaultScopes = ["standard" "claude"];

        skills = [
          (catalog.official.anthropics.skills {
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

Alternatively, apply `agentic-flake.overlays.default` (via `appendOverlays` or your nixpkgs config) to get the same catalog as `pkgs.agent-skills` — convenient with `with pkgs.agent-skills;` in Home Manager setups.

More examples can be found in [examples/](./examples/).
