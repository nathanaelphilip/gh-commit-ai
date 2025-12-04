#!/usr/bin/env bats

# Integration tests for OpenAI provider
# These tests require OPENAI_API_KEY to be set

load test_helper

setup() {
    # Create a temporary directory for test
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"

    # Check if OpenAI API key is available
    if [ -z "$OPENAI_API_KEY" ]; then
        skip "OPENAI_API_KEY not set"
    fi
}

teardown() {
    # Clean up
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

@test "openai: generate commit message for simple feature" {
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

    # Generate commit message using OpenAI
    export AI_PROVIDER="openai"
    export OPENAI_MODEL="gpt-4o-mini"  # Use cheaper model for testing

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    [ "$status" -eq 0 ]

    # Check format
    [[ "$output" == *":"* ]]  # Should have type prefix
    [[ "$output" == *"- "* ]]  # Should have bullet points
}

@test "openai: shows token usage and cost" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial commit"

    echo "change" > file.txt
    git add file.txt

    export AI_PROVIDER="openai"
    export OPENAI_MODEL="gpt-4o-mini"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    [ "$status" -eq 0 ]
    [[ "$output" == *":"* ]]
}

@test "openai: handles API errors gracefully" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial commit"

    echo "change" > file.txt
    git add file.txt

    # Use invalid API key to trigger error
    export AI_PROVIDER="openai"
    export OPENAI_API_KEY="sk-invalid-key-12345"
    export OPENAI_MODEL="gpt-4o-mini"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    # Should fail gracefully
    [ "$status" -ne 0 ]
    [[ "$output" == *"Error"* ]] || [[ "$output" == *"error"* ]] || [[ "$output" == *"failed"* ]]
}

@test "openai: works with different models" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial commit"

    echo "feature" > feature.js
    git add feature.js

    export AI_PROVIDER="openai"
    # Test with gpt-4o-mini (cheapest)
    export OPENAI_MODEL="gpt-4o-mini"

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    [ "$status" -eq 0 ]
    [[ "$output" == *":"* ]]
}

@test "openai: respects max lines configuration" {
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial commit"

    # Create a large file
    for i in {1..300}; do
        echo "line $i" >> large.txt
    done
    git add large.txt

    export AI_PROVIDER="openai"
    export OPENAI_MODEL="gpt-4o-mini"
    export DIFF_MAX_LINES=100

    run "$BATS_TEST_DIRNAME/../gh-commit-ai" --preview

    [ "$status" -eq 0 ]
    [[ "$output" == *":"* ]]
}
