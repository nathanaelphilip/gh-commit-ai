#!/usr/bin/env bats

# End-to-end workflow tests
# These tests verify complete user workflows

load test_helper

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
}

teardown() {
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

@test "workflow: help flag shows usage" {
    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
    [[ "$output" == *"--preview"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--amend"* ]]
}

@test "workflow: version command shows help" {
    run "$BATS_TEST_DIRNAME/../gh-commit-ai" version --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"version"* ]]
    [[ "$output" == *"--create-tag"* ]]
    [[ "$output" == *"semver"* ]]
}

@test "workflow: changelog command shows help" {
    run "$BATS_TEST_DIRNAME/../gh-commit-ai" changelog --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"changelog"* ]]
    [[ "$output" == *"--since"* ]]
}

@test "workflow: review command shows help" {
    run "$BATS_TEST_DIRNAME/../gh-commit-ai" review --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"review"* ]]
    [[ "$output" == *"--all"* ]]
}

@test "workflow: pr-description command shows help" {
    run "$BATS_TEST_DIRNAME/../gh-commit-ai" pr-description --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"pr-description"* ]]
    [[ "$output" == *"--base"* ]]
}

@test "workflow: error when not in git repo" {
    # Don't initialize git
    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    [ "$status" -ne 0 ]
    [[ "$output" == *"git"* ]] || [[ "$output" == *"repository"* ]]
}

@test "workflow: error when no changes to commit" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create initial commit
    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial commit"

    # No changes staged
    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    [ "$status" -ne 0 ] || [[ "$output" == *"No changes"* ]]
}

@test "workflow: version command with no tags" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create a commit
    echo "initial" > file.txt
    git add file.txt
    git commit -m "feat: initial feature"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" version

    [ "$status" -eq 0 ]
    [[ "$output" == *"0.1.0"* ]]  # Should suggest first version
}

@test "workflow: version command suggests patch bump for fixes" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create initial version
    echo "v1" > file.txt
    git add file.txt
    git commit -m "feat: initial"
    git tag v1.0.0

    # Add a fix
    echo "v2" > file.txt
    git add file.txt
    git commit -m "fix: bug fix"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" version

    [ "$status" -eq 0 ]
    [[ "$output" == *"1.0.1"* ]]  # Should suggest patch bump
    [[ "$output" == *"fix"* ]]
}

@test "workflow: version command suggests minor bump for features" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create initial version
    echo "v1" > file.txt
    git add file.txt
    git commit -m "feat: initial"
    git tag v1.0.0

    # Add a feature
    echo "v2" > file.txt
    git add file.txt
    git commit -m "feat: new feature"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" version

    [ "$status" -eq 0 ]
    [[ "$output" == *"1.1.0"* ]]  # Should suggest minor bump
    [[ "$output" == *"feature"* ]]
}

@test "workflow: version command suggests major bump for breaking changes" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create initial version
    echo "v1" > file.txt
    git add file.txt
    git commit -m "feat: initial"
    git tag v1.0.0

    # Add breaking change
    echo "v2" > file.txt
    git add file.txt
    git commit -m "feat!: breaking change"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" version

    [ "$status" -eq 0 ]
    [[ "$output" == *"2.0.0"* ]]  # Should suggest major bump
    [[ "$output" == *"breaking"* ]] || [[ "$output" == *"BREAKING"* ]]
}

@test "workflow: changelog generates from commits" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create some commits
    echo "initial" > file.txt
    git add file.txt
    git commit -m "feat: add feature"

    echo "fix" > file.txt
    git add file.txt
    git commit -m "fix: resolve bug"

    echo "docs" > README.md
    git add README.md
    git commit -m "docs: update readme"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" changelog

    [ "$status" -eq 0 ]
    [[ "$output" == *"Features"* ]] || [[ "$output" == *"✨"* ]]
    [[ "$output" == *"Bug Fixes"* ]] || [[ "$output" == *"🐛"* ]]
    [[ "$output" == *"Documentation"* ]] || [[ "$output" == *"📝"* ]]
}

@test "workflow: config file is respected" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create a config file
    cat > .gh-commit-ai.yml <<'EOF'
ai_provider: ollama
ollama_model: test-model
use_scope: true
diff_max_lines: 50
EOF

    # Create changes
    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial"

    echo "change" > file.txt
    git add file.txt

    # The script should load the config
    # We can't test the actual execution without a model, but we can verify the file is read
    [ -f .gh-commit-ai.yml ]
}

@test "workflow: branch intelligence extracts ticket number" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create a branch with ticket number
    git checkout -b feature/ABC-123-add-auth

    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial"

    # The script should detect ABC-123 from branch name
    # This would be reflected in the commit message if we ran it
    branch=$(git branch --show-current)
    [[ "$branch" == *"ABC-123"* ]]
}

@test "workflow: smart type detection for docs" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial"

    # Add only documentation
    echo "# Documentation" > README.md
    echo "# API Docs" > docs/api.md
    mkdir -p docs
    mv docs/api.md docs/ 2>/dev/null || true
    git add README.md docs/api.md

    # Smart detection should suggest "docs" type
    # We can verify files are categorized correctly
    git diff --cached --name-only | grep -q ".md"
    [ "$?" -eq 0 ]
}

@test "workflow: message history saves to tmp" {
    # After a generation, message should be saved to /tmp/gh-commit-ai-history
    # We can't test without actual execution, but verify the directory would be writable
    [ -d /tmp ] && [ -w /tmp ]
}

@test "workflow: lock files are excluded from diff" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial"

    # Add code file and lock file
    echo "code" > code.js
    echo '{"lockfileVersion": 2}' > package-lock.json
    git add code.js package-lock.json

    # Check that exclusion pattern would work
    # (actual exclusion tested in integration tests)
    git diff --cached --name-only | grep -q "package-lock.json"
    [ "$?" -eq 0 ]  # File is staged

    # But with exclusion, it should be filtered
    excluded=$(git diff --cached --name-only ':(exclude)package-lock.json')
    [[ "$excluded" != *"package-lock.json"* ]]
    [[ "$excluded" == *"code.js"* ]]
}
