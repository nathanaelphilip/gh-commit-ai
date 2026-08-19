#!/usr/bin/env bash

# Test helper functions for gh-commit-ai tests

# Shared setup - call from a test file's own setup(). Must NOT be named setup():
# a test file that defines setup() and calls `setup` would recurse into itself.
common_setup() {
    # Create a temporary directory for test fixtures
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Save original directory
    ORIGINAL_DIR="$(pwd)"
    export ORIGINAL_DIR
}

# Shared teardown - call from a test file's own teardown(). See common_setup above.
common_teardown() {
    # Clean up temporary directory
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi

    # Return to original directory
    if [ -n "$ORIGINAL_DIR" ]; then
        cd "$ORIGINAL_DIR" || exit 1
    fi
}

# Create a test git repository
create_test_repo() {
    cd "$TEST_TEMP_DIR" || exit 1
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
}

# Create a test file with content
create_test_file() {
    local filename="$1"
    local content="$2"
    echo "$content" > "$filename"
}

# Source specific functions from the main script for unit testing
# This extracts and sources only the functions we need without executing the script
source_script_functions() {
    # Extract the escape_json function
    local script="${BATS_TEST_DIRNAME}/../gh-commit-ai"

    eval "$(sed -n '/^escape_json() {/,/^}/p' "$script")"

    # Extract the enforce_lowercase function
    eval "$(sed -n '/^enforce_lowercase() {/,/^}$/p' "$script")"

    # Extract the convert_newlines function
    eval "$(sed -n '/^convert_newlines() {/,/^}$/p' "$script")"
}
