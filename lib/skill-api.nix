{lib}: let
  normalizeSrc = src:
    if builtins.typeOf src == "path"
    then src
    else let
      coerced = builtins.tryEval (toString src);
    in
      if coerced.success
      then /. + builtins.unsafeDiscardStringContext coerced.value
      else throw "mkSkill expects `src` to be a path-like value such as `./.` or `builtins.fetchGit { ...; }`";

  rootSkillName = src: let
    parts = lib.filter (part: part != "") (lib.splitString "/" (toString src));
  in
    if parts == []
    then throw "mkSkill could not derive a root skill name from src"
    else builtins.elemAt parts ((builtins.length parts) - 1);

  discoverSkills = src: let
    normalizedSrc = normalizeSrc src;

    scan = path: relParts: let
      entries = builtins.readDir path;
      relPath = lib.concatStringsSep "/" relParts;
      hasSkill = entries ? "SKILL.md";
      isTemplatePath = lib.any (part: builtins.match ".*[Tt]emplate.*" part != null) relParts;

      current =
        if hasSkill && !isTemplatePath
        then let
          skillId =
            if relPath == ""
            then rootSkillName normalizedSrc
            else relPath;
        in [
          {
            name = skillId;
            value =
              if relPath == ""
              then "."
              else relPath;
          }
        ]
        else [];

      dirs =
        lib.filter (
          name: let kind = entries.${name}; in kind == "directory" || kind == "symlink"
        )
        (builtins.attrNames entries);

      deeper = lib.flatten (map (name: scan (path + "/${name}") (relParts ++ [name])) dirs);
    in
      current ++ deeper;

    discovered = lib.listToAttrs (scan normalizedSrc []);
  in
    if discovered == {}
    then throw "mkSkill found no directories containing SKILL.md under ${toString normalizedSrc}"
    else discovered;

  assertKnownPlugins = availablePlugins: requestedPlugins: let
    unknown = lib.filter (plugin: !(builtins.elem plugin availablePlugins)) requestedPlugins;
  in
    if unknown != []
    then
      throw ''
        Unknown skill plugin(s): ${lib.concatStringsSep ", " unknown}
        Available plugins: ${lib.concatStringsSep ", " availablePlugins}
      ''
    else true;

  mkConfiguredSkillEntry = {
    src,
    skillMap,
  }: let
    availablePlugins = builtins.attrNames skillMap;
  in {
    inherit src skillMap availablePlugins;
    __agenticSkill = true;

    __functor = _self: {
      plugins,
      scopes ? ["global"],
      prefix ? "",
    }:
      builtins.seq (assertKnownPlugins availablePlugins plugins) {
        inherit plugins scopes prefix src skillMap availablePlugins;
        __agenticSkill = true;
      };
  };
in {
  inherit normalizeSrc discoverSkills assertKnownPlugins;

  mkSkill = {src}:
    mkConfiguredSkillEntry {
      inherit src;
      skillMap = discoverSkills src;
    };
}
