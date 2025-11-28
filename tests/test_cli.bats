#!/usr/bin/env bats

# Tests for command-line interface of gh-commit-ai

load test_helper

setup() {
    setup
}

teardown() {
    teardown
}

@test "CLI: --help shows usage information" {
    run "$ORIGINAL_DIR/gh-commit-ai" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: gh commit-ai"* ]]
    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--preview"* ]]
    [[ "$output" == *"--amend"* ]]
}

@test "CLI: -h shows usage information" {
    run "$ORIGINAL_DIR/gh-commit-ai" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: gh commit-ai"* ]]
}

@test "CLI: unknown option shows error" {
    run "$ORIGINAL_DIR/gh-commit-ai" --unknown-option
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Unknown option"* ]]
}

@test "CLI: fails when not in git repository" {
    cd "$TEST_TEMP_DIR" || exit 1
    run "$ORIGINAL_DIR/gh-commit-ai"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Not a git repository"* ]]
}

@test "CLI: shows no changes message in empty repo" {
    create_test_repo
    run "$ORIGINAL_DIR/gh-commit-ai"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No changes to commit"* ]]
}

@test "CLI: --amend fails with no commits" {
    create_test_repo
    run "$ORIGINAL_DIR/gh-commit-ai" --amend
    [ "$status" -eq 1 ]
    [[ "$output" == *"No commits to amend"* ]]
}
