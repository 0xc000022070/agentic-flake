{
  agentic-flake,
  pkgs,
  ...
}: let
  skillApi = import ../lib/skill-api.nix {lib = pkgs.lib;};

  # Simulate a repo with duplicate skill names at different depths
  # (like java, nodejs, python appearing in multiple subdirectories)
  repoWithDups = agentic-flake.lib.mkSkill {
    src = ./fixtures/mk-skill-duplicates;
  };

  # Test 1: Selecting a non-ambiguous plugin should work fine
  testUnambiguous = agentic-flake.lib.project-factory {
    inherit pkgs;
    skills = [
      (repoWithDups {plugins = ["utils"];})
    ];
  };

  # Test 2: Selecting an ambiguous plugin should fail
  testAmbiguous = builtins.tryEval (
    let
      result = agentic-flake.lib.project-factory {
        inherit pkgs;
        skills = [
          (repoWithDups {plugins = ["tools"];})
        ];
      };
    in
      builtins.seq result.allSymlinks result
  );

  # Test 3: Ambiguous plugin with prefix should work
  testAmbiguousWithPrefix = agentic-flake.lib.project-factory {
    inherit pkgs;
    skills = [
      (repoWithDups {
        plugins = ["tools"];
        prefix = "suite-";
      })
    ];
  };

  # Test 4: Two inline skills with conflicting plugin names
  skill1 = skillApi.mkInlineSkill {
    "python" = {
      name = "python";
      content = "Python skill from org1";
    };
  };

  skill2 = skillApi.mkInlineSkill {
    "python" = {
      name = "python";
      content = "Python skill from org2";
    };
  };

  testCrossSkillConflict = builtins.tryEval (
    let
      result = agentic-flake.lib.project-factory {
        inherit pkgs;
        skills = [
          (skill1 {plugins = ["python"];})
          (skill2 {plugins = ["python"];})
        ];
      };
    in
      builtins.seq result.allSymlinks result
  );

  # Test 5: Cross-skill conflict resolved with prefix
  testCrossSkillWithPrefix = agentic-flake.lib.project-factory {
    inherit pkgs;
    skills = [
      (skill1 {
        plugins = ["python"];
        prefix = "org1-";
      })
      (skill2 {
        plugins = ["python"];
        prefix = "org2-";
      })
    ];
  };
in
  pkgs.runCommand "project-factory-conflict-detection-test" {} ''
    set -e

    # Test 1: Non-ambiguous plugin from repo with duplicates works
    ${
      if testUnambiguous ? shellHook
      then ''
        echo "Test 1 passed: non-ambiguous plugin works despite duplicates in source"
      ''
      else ''
        echo "Test 1 failed: should have succeeded for non-ambiguous plugin"
        exit 1
      ''
    }

    # Test 2: Ambiguous plugin fails
    ${
      if !testAmbiguous.success
      then ''
        echo "Test 2 passed: ambiguous plugin correctly rejected"
      ''
      else ''
        echo "Test 2 failed: should have rejected ambiguous plugin"
        exit 1
      ''
    }

    # Test 3: Ambiguous plugin with prefix works
    ${
      if testAmbiguousWithPrefix ? shellHook
      then ''
        echo "Test 3 passed: ambiguous plugin with prefix works"
      ''
      else ''
        echo "Test 3 failed: should have succeeded with prefix"
        exit 1
      ''
    }

    # Test 4: Cross-skill conflict detected
    ${
      if !testCrossSkillConflict.success
      then ''
        echo "Test 4 passed: cross-skill plugin conflict detected"
      ''
      else ''
        echo "Test 4 failed: should have detected cross-skill conflict"
        exit 1
      ''
    }

    # Test 5: Cross-skill conflict resolved with prefix
    ${
      if testCrossSkillWithPrefix ? shellHook
      then ''
        echo "Test 5 passed: cross-skill conflict resolved with prefix"
      ''
      else ''
        echo "Test 5 failed: should have resolved conflict with prefix"
        exit 1
      ''
    }

    mkdir -p "$out"
    touch "$out/ok"
    echo ""
    echo "All conflict detection tests passed"
  ''
