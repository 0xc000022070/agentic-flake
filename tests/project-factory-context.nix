{
  agentic-flake,
  pkgs,
  ...
}: let
  # Test 1: Inline context strings
  inlineContextTest = agentic-flake.lib.project-factory {
    inherit pkgs;
    context = {
      CLAUDE = ''
        # Claude Context
        Prefer existing patterns.
      '';
      AGENTS = ''
        # Agents Configuration
        List of custom agents.
      '';
    };
  };

  # Test 2: File path context
  testContextFile = pkgs.writeText "test-context.md" ''
    # Test File
    This is a test context file.
  '';

  fileContextTest = agentic-flake.lib.project-factory {
    inherit pkgs;
    context = {
      TEST = testContextFile;
    };
  };

  # Test 3: Mixed inline and file paths
  mixedContextTest = agentic-flake.lib.project-factory {
    inherit pkgs;
    context = {
      CLAUDE = "Inline CLAUDE content";
      REFERENCE = testContextFile;
    };
  };

  # Test 4: Filename normalization (with .md extension already present)
  extensionTest = agentic-flake.lib.project-factory {
    inherit pkgs;
    context = {
      "CLAUDE.md" = "Already has extension";
      "AGENTS" = "Will get extension added";
    };
  };
in
  pkgs.runCommand "project-factory-context-test" {} ''
    set -e

    # Test 1: Inline context generates correct descriptors
    echo "Test 1: Inline context"
    inline='${builtins.toJSON inlineContextTest.allContextFiles}'
    echo "Inline context files: $inline"
    echo "$inline" | grep -q '"filename":"CLAUDE.md"' || {
      echo "Expected CLAUDE.md in context files"
      exit 1
    }
    echo "$inline" | grep -q '"filename":"AGENTS.md"' || {
      echo "Expected AGENTS.md in context files"
      exit 1
    }
    echo "$inline" | grep -q '"isInline":true' || {
      echo "Expected isInline:true for inline content"
      exit 1
    }

    # Test 2: File path context generates correct descriptors
    echo "Test 2: File path context"
    fileCtx='${builtins.toJSON fileContextTest.allContextFiles}'
    echo "File context files: $fileCtx"
    echo "$fileCtx" | grep -q '"filename":"TEST.md"' || {
      echo "Expected TEST.md in context files"
      exit 1
    }
    echo "$fileCtx" | grep -q '"isInline":false' || {
      echo "Expected isInline:false for file paths"
      exit 1
    }

    # Test 3: Mixed context
    echo "Test 3: Mixed inline and file paths"
    mixed='${builtins.toJSON mixedContextTest.allContextFiles}'
    echo "Mixed context files: $mixed"
    echo "$mixed" | grep -q '"filename":"CLAUDE.md"' || {
      echo "Expected CLAUDE.md in mixed context"
      exit 1
    }
    echo "$mixed" | grep -q '"filename":"REFERENCE.md"' || {
      echo "Expected REFERENCE.md in mixed context"
      exit 1
    }

    # Test 4: Extension normalization
    echo "Test 4: Extension normalization"
    ext='${builtins.toJSON extensionTest.allContextFiles}'
    echo "Extension test context: $ext"
    echo "$ext" | grep -q '"filename":"CLAUDE.md"' || {
      echo "Expected CLAUDE.md (not double-extended)"
      exit 1
    }
    # Verify CLAUDE.md appears only once
    count=$(echo "$ext" | grep -o '"filename":"CLAUDE.md"' | wc -l)
    if [ "$count" -ne 1 ]; then
      echo "Expected exactly one CLAUDE.md, got $count"
      exit 1
    fi
    echo "$ext" | grep -q '"filename":"AGENTS.md"' || {
      echo "Expected AGENTS.md with extension added"
      exit 1
    }

    mkdir -p "$out"
    touch "$out/ok"
    echo "All project-factory context tests passed"
  ''
