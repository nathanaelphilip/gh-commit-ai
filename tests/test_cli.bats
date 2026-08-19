#!/usr/bin/env bats

# Tests for command-line interface of gh-commit-ai

load test_helper

setup() {
    common_setup
}

teardown() {
    common_teardown
}

@test "DIAGNOSTIC: environment" {
    echo "bats version: $(bats --version 2>&1)" >&3
    echo "bash version: $BASH_VERSION" >&3
    echo "pwd:          $(pwd)" >&3
    echo "ORIGINAL_DIR: [$ORIGINAL_DIR]" >&3
    echo "script path:  [$ORIGINAL_DIR/gh-commit-ai]" >&3
    echo "exists:       $([ -f "$ORIGINAL_DIR/gh-commit-ai" ] && echo yes || echo no)" >&3
    echo "executable:   $([ -x "$ORIGINAL_DIR/gh-commit-ai" ] && echo yes || echo no)" >&3
    echo "local config: $([ -f .gh-commit-ai.yml ] && echo yes || echo no)" >&3
}

@test "DIAGNOSTIC: --help" {
    run "$ORIGINAL_DIR/gh-commit-ai" --help
    echo "status=$status" >&3
    echo "--- output start ---" >&3
    echo "$output" >&3
    echo "--- output end ---" >&3
}

@test "DIAGNOSTIC: --unknown-option" {
    run "$ORIGINAL_DIR/gh-commit-ai" --unknown-option
    echo "status=$status" >&3
    echo "--- output start ---" >&3
    echo "$output" >&3
    echo "--- output end ---" >&3
}

@test "DIAGNOSTIC: --help with stderr split" {
    run --separate-stderr "$ORIGINAL_DIR/gh-commit-ai" --help || true
    echo "status=$status" >&3
    echo "stdout=[$output]" >&3
    echo "stderr=[$stderr]" >&3
}

@test "DIAGNOSTIC: outside a git repo" {
    cd "$TEST_TEMP_DIR" || exit 1
    run "$ORIGINAL_DIR/gh-commit-ai"
    echo "status=$status" >&3
    echo "--- output start ---" >&3
    echo "$output" >&3
    echo "--- output end ---" >&3
}
