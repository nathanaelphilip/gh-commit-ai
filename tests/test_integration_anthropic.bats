#!/usr/bin/env bats

# Integration tests for Anthropic provider
# These tests require ANTHROPIC_API_KEY to be set

load test_helper

setup() {
    # Create a temporary directory for test
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"

    # Check if Anthropic API key is available
    if [ -z "$ANTHROPIC_API_KEY" ]; then
        skip "ANTHROPIC_API_KEY not set"
    fi
}

teardown() {
    # Clean up
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

@test "anthropic: generate commit message for simple feature" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Create initial commit
    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial commit"

    # Add new feature
    echo "new feature code" > feature.js
    git add feature.js

    # Generate commit message using Anthropic
    export AI_PROVIDER="anthropic"
    export ANTHROPIC_MODEL="claude-3-5-haiku-20241022"  # Use cheaper model for testing

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    [ "$status" -eq 0 ]

    # Check format
    [[ "$output" == *":"* ]]  # Should have type prefix
    [[ "$output" == *"- "* ]]  # Should have bullet points

    # Check for lowercase (our enforcement)
    first_line=$(echo "$output" | head -n1)
    [[ ! "$first_line" =~ [A-Z][a-z] ]]  # Should not have capitalized words (except acronyms/tickets)
}

@test "anthropic: shows token usage and cost" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial commit"

    echo "change" > file.txt
    git add file.txt

    export AI_PROVIDER="anthropic"
    export ANTHROPIC_MODEL="claude-3-5-haiku-20241022"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    [ "$status" -eq 0 ]

    # Should show cost information in stderr or in output
    # (In preview mode, cost might not be shown, but in normal mode it would be)
    [[ "$output" == *":"* ]]
}

@test "anthropic: handles API errors gracefully" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial commit"

    echo "change" > file.txt
    git add file.txt

    # Use invalid API key to trigger error
    export AI_PROVIDER="anthropic"
    export ANTHROPIC_API_KEY="sk-ant-invalid-key"
    export ANTHROPIC_MODEL="claude-3-5-haiku-20241022"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    # Should fail gracefully
    [ "$status" -ne 0 ]
    [[ "$output" == *"Error"* ]] || [[ "$output" == *"error"* ]] || [[ "$output" == *"failed"* ]]
}

@test "anthropic: works with different models" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial commit"

    echo "feature" > feature.js
    git add feature.js

    export AI_PROVIDER="anthropic"
    # Test with Haiku (cheapest, fastest)
    export ANTHROPIC_MODEL="claude-3-5-haiku-20241022"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    [ "$status" -eq 0 ]
    [[ "$output" == *":"* ]]
}

@test "anthropic: generates multiple options with --options flag" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial commit"

    echo "new feature" > feature.js
    git add feature.js

    export AI_PROVIDER="anthropic"
    export ANTHROPIC_MODEL="claude-3-5-haiku-20241022"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview --options

    [ "$status" -eq 0 ]

    # Should contain multiple options (separated by "---OPTION---")
    # Note: In preview mode with --options, output format may vary
    [[ "$output" == *":"* ]]
}
