{
  agentic-flake,
  pkgs,
  ...
}: let
  inlineSkills = agentic-flake.lib.mkInlineSkill {
    "simple-skill" = {
      description = "A simple test skill";
      tags = ["test" "simple"];
      content = "# Simple Skill\n\nThis is a test skill.";
    };

    "another-skill" = {
      content = "# Another Skill\n\nNo metadata here.";
    };

    "nested/group/skill" = {
      name = "nested-skill";
      description = "A nested skill";
      content = "# Nested\n\nThis is nested.";
    };
  };

  configured = inlineSkills {
    plugins = ["simple-skill"];
    scopes = ["global"];
    prefix = "test-";
  };

  hasConfiguredAttrs = configured ? plugins && configured ? scopes && configured ? prefix;
in
  pkgs.runCommand "mk-inline-skill-lib-test" {} ''
    set -e

    # Test 1: Check that we discovered the correct number of plugins
    test "${toString (builtins.length inlineSkills.availablePlugins)}" = "3" || {
      echo "Expected 3 discovered plugins, got ${toString (builtins.length inlineSkills.availablePlugins)}"
      exit 1
    }

    # Test 2: Verify all plugins are in availablePlugins list
    ${
      if builtins.elem "simple-skill" inlineSkills.availablePlugins
      then ''
        :
      ''
      else ''
        echo "simple-skill was not discovered"
        exit 1
      ''
    }

    ${
      if builtins.elem "another-skill" inlineSkills.availablePlugins
      then ''
        :
      ''
      else ''
        echo "another-skill was not discovered"
        exit 1
      ''
    }

    ${
      if builtins.elem "nested/group/skill" inlineSkills.availablePlugins
      then ''
        :
      ''
      else ''
        echo "nested/group/skill was not discovered"
        exit 1
      ''
    }

    # Test 3: Verify inline content was captured
    ${
      if inlineSkills ? __inlineSkillContent
      then ''
        :
      ''
      else ''
        echo "__inlineSkillContent attribute missing"
        exit 1
      ''
    }

    # Test 4-8: Check content generation
    ${
      let
        simpleContent = inlineSkills.__inlineSkillContent.simple-skill;
        anotherContent = inlineSkills.__inlineSkillContent.another-skill;
        nestedContent = inlineSkills.__inlineSkillContent."nested/group/skill";
      in
        if
          (builtins.match "^---\nname: simple-skill.*" simpleContent)
          != null
          && (builtins.match ".*description: A simple test skill.*" simpleContent) != null
          && (builtins.match ".*tags:.*" simpleContent) != null
          && (builtins.match ".*# Simple Skill.*" simpleContent) != null
          && (builtins.match "^---\nname: another-skill.*" anotherContent) != null
          && (builtins.match "^---\nname: nested-skill.*" nestedContent) != null
        then ''
          :
        ''
        else ''
          echo "Content generation checks failed"
          exit 1
        ''
    }

    # Test 9: Check that calling the skill works (functor test)
    ${
      if hasConfiguredAttrs
      then ''
        :
      ''
      else ''
        echo "Configured skill missing required attributes"
        exit 1
      ''
    }

    mkdir -p "$out"
    touch "$out/ok"
  ''
