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
    else lib.last parts;

  isTemplate = relParts: lib.any (part: builtins.match ".*[Tt]emplate.*" part != null) relParts;

  discoverSkills = src: let
    normalizedSrc = normalizeSrc src;

    # Recursively scan directory tree for SKILL.md files, building (skillId -> relPath) map.
    # Skips directories matching template patterns and respects symlinks.
    scan = path: relParts: let
      entries = builtins.readDir path;
      relPath = lib.concatStringsSep "/" relParts;
      hasSkill = entries ? "SKILL.md";
      isTemplatePath = isTemplate relParts;

      current =
        if hasSkill && !isTemplatePath
        then let
          skillId =
            if relParts == []
            then rootSkillName normalizedSrc
            else lib.last relParts;
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

      dirs = builtins.attrNames (lib.filterAttrs (name: kind: kind == "directory" || kind == "symlink") entries);

      deeper = lib.flatten (map (name: scan (path + "/${name}") (relParts ++ [name])) dirs);
    in
      current ++ deeper;

    scanned = scan normalizedSrc [];

    nameCount = lib.foldl' (acc: e: acc // {${e.name} = (acc.${e.name} or 0) + 1;}) {} scanned;
    duplicates = builtins.attrNames (lib.filterAttrs (_: count: count > 1) nameCount);

    discovered = lib.listToAttrs scanned;
  in
    if scanned == []
    then throw "mkSkill found no SKILL.md files under ${toString normalizedSrc}. Ensure skill directories contain SKILL.md and are not in 'template' directories."
    else if duplicates != []
    then throw "mkSkill found duplicate skill names under ${toString normalizedSrc}: ${lib.concatStringsSep ", " duplicates}. Rename the conflicting directories."
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
  buildFrontmatter = {
    name,
    description ? null,
    tags ? null,
  }: let
    lines =
      ["name: ${name}"]
      ++ (
        if description != null
        then ["description: ${description}"]
        else []
      )
      ++ (
        if tags != null
        then ["tags: ${builtins.toJSON tags}"]
        else []
      );
  in
    "---\n" + lib.concatStringsSep "\n" lines + "\n---\n\n";

  mkInlineSkill = skillDefs: let
    validateSkill = id: def:
      if !def ? content
      then throw "mkInlineSkill: skill '${id}' missing required 'content' field"
      else true;

    skillMap =
      lib.mapAttrs (
        id: def:
          if validateSkill id def
          then "."
          else null
      )
      skillDefs;

    skillContent =
      lib.mapAttrs (
        id: def: let
          name = def.name or id;
          frontmatter = buildFrontmatter {
            inherit name;
            description = def.description or null;
            tags = def.tags or null;
          };
        in
          frontmatter + def.content
      )
      skillDefs;
  in let
    baseEntry = mkConfiguredSkillEntry {
      src = "inline";
      inherit skillMap;
    };
  in
    baseEntry
    // {
      __inlineSkillContent = skillContent;
      __functor = _self: {
        plugins,
        scopes ? ["global"],
        prefix ? "",
      }:
        builtins.seq (assertKnownPlugins baseEntry.availablePlugins plugins) {
          inherit plugins scopes prefix;
          src = "inline";
          inherit skillMap;
          availablePlugins = baseEntry.availablePlugins;
          __agenticSkill = true;
          __inlineSkillContent = skillContent;
        };
    };
in {
  inherit normalizeSrc discoverSkills assertKnownPlugins;

  # Scans a local `src` path for SKILL.md files at eval-time and returns a
  # configured skill descriptor. No derivation is created — materialization
  # is deferred until project-factory time via `materializeConfiguredSkill`.
  #
  # Skill IDs are the immediate parent directory name of each SKILL.md.
  # Duplicate names across different depths are a hard error.
  #
  # Does not require `pkgs`. Incompatible with remote sources (use
  # `mkSkillPackage` for GitHub repos).
  mkSkill = {src}:
    mkConfiguredSkillEntry {
      inherit src;
      skillMap = discoverSkills src;
    };

  # Defines skills inline from Nix strings, without any on-disk source.
  # Each entry requires at least a `content` field (the SKILL.md body).
  # Optional fields: `name`, `description`, `tags`.
  #
  # Like `mkSkill`, returns a descriptor — no derivation until project-factory.
  inherit mkInlineSkill;
}
