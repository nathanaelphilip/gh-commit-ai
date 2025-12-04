#!/usr/bin/env bats

# Integration tests for Ollama provider
# These tests require Ollama to be running with at least one model installed

load test_helper

setup() {
    # Create a temporary directory for test
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"

    # Check if Ollama is available
    if ! curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        skip "Ollama is not running"
    fi

    # Check if any models are installed
    if ! curl -s http://localhost:11434/api/tags | grep -q "models"; then
        skip "No Ollama models installed"
    fi
}

teardown() {
    # Clean up
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

@test "ollama: generate commit message for simple feature" {
    # Create a git repo with changes
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create initial commit
    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial commit"

    # Apply test fixture
    echo "new feature" > feature.js
    git add feature.js

    # Generate commit message using --preview mode
    export AI_PROVIDER="ollama"
    export OLLAMA_MODEL="gemma3:12b"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    # Check that it succeeded
    [ "$status" -eq 0 ]

    # Check that output contains expected format
    [[ "$output" == *"feat:"* ]] || [[ "$output" == *"chore:"* ]]
    [[ "$output" == *"- "* ]]  # Should have bullet points
}

@test "ollama: generate commit message for bug fix" {
    # Create a git repo with bug fix changes
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create initial commit
    echo "function broken() { return null; }" > api.js
    git add api.js
    git commit -m "initial commit"

    # Fix the bug
    echo "function fixed() { return true; }" > api.js
    git add api.js

    # Generate commit message
    export AI_PROVIDER="ollama"
    export OLLAMA_MODEL="gemma3:12b"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    [ "$status" -eq 0 ]

    # Should detect it's a fix (though not guaranteed with simple test)
    [[ "$output" == *":"* ]]  # Should have type prefix
    [[ "$output" == *"- "* ]]  # Should have bullet points
}

@test "ollama: handle docs-only changes" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create initial commit
    echo "# Project" > README.md
    git add README.md
    git commit -m "initial commit"

    # Update documentation
    echo -e "# Project\n\n## Installation\n\nRun npm install" > README.md
    git add README.md

    export AI_PROVIDER="ollama"
    export OLLAMA_MODEL="gemma3:12b"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    [ "$status" -eq 0 ]

    # Should detect documentation type
    [[ "$output" == *"docs:"* ]] || [[ "$output" == *"doc:"* ]]
}

@test "ollama: amend mode regenerates last commit message" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create a commit
    echo "code" > file.js
    git add file.js
    git commit -m "bad commit message"

    # Run in amend preview mode
    export AI_PROVIDER="ollama"
    export OLLAMA_MODEL="gemma3:12b"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --amend --preview

    [ "$status" -eq 0 ]
    [[ "$output" == *":"* ]]  # Should have type prefix
    [[ "$output" != *"bad commit message"* ]]  # Should be different from original
}

@test "ollama: handles large diffs with intelligent sampling" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create initial commit
    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial commit"

    # Create a large diff (more than DIFF_MAX_LINES)
    for i in {1..500}; do
        echo "function func$i() { return $i; }" >> large.js
    done
    git add large.js

    export AI_PROVIDER="ollama"
    export OLLAMA_MODEL="gemma3:12b"
    export DIFF_MAX_LINES=200

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    [ "$status" -eq 0 ]
    [[ "$output" == *":"* ]]  # Should still generate valid message
}

@test "ollama: respects USE_SCOPE configuration" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial commit"

    echo "new auth feature" > src/auth.js
    mkdir -p src
    mv src/auth.js src/ 2>/dev/null || true
    git add src/auth.js

    export AI_PROVIDER="ollama"
    export OLLAMA_MODEL="gemma3:12b"
    export USE_SCOPE="true"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    [ "$status" -eq 0 ]

    # Should include scope in format: type(scope): message
    # Note: Can't guarantee AI will always add scope, but format should allow it
    [[ "$output" == *":"* ]]
}

@test "ollama: excludes lock files from diff" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial commit"

    # Add code and lock file
    echo "const x = 1;" > code.js
    echo '{"lockfileVersion": 2}' > package-lock.json
    git add code.js package-lock.json

    export AI_PROVIDER="ollama"
    export OLLAMA_MODEL="gemma3:12b"
    export VERBOSE="true"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    [ "$status" -eq 0 ]

    # Output should mention code file but not lock file
    [[ "$output" == *"code"* ]] || [[ "$output" == *"js"* ]]
    # Lock file might still appear in git status, but shouldn't dominate the message
}
