# /lib

## `mkSkill` vs `mkSkillPackage`

These two functions serve different source origins and intentionally live at different layers:

| | `mkSkill` (`skill-api.nix`) | `mkSkillPackage` (`packages.nix`) |
|---|---|---|
| Source | Local path | Remote GitHub repo |
| Discovery | `builtins.readDir` at eval-time | `find` + `sed` in build phase |
| Produces | Skill descriptor (pure attrset) | Derivation (store path) |
| Requires `pkgs` | No | Yes |

`mkSkill` is a pure, eval-time function — it only describes what skills exist. No derivation is created until `materializeConfiguredSkill` (in `packages.nix`) is called at project-factory time, when `pkgs` is available and a store path is actually needed.

`mkSkillPackage` must produce a derivation upfront because the remote source does not exist locally and cannot be inspected at eval-time without IFD.

The bridge between the two is `materializeConfiguredSkill`, which converts a `mkSkill` descriptor into a derivation lazily. `mkInlineSkill` follows the same lazy pattern as `mkSkill`.
