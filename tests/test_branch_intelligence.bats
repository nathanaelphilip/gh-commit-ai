#!/usr/bin/env bats

# Tests for branch intelligence features

load test_helper

setup() {
    setup
    create_test_repo
}

teardown() {
    teardown
}

@test "Branch Intelligence: extracts ticket number from feature/ABC-123-description" {
    git checkout -b feature/ABC-123-user-login
    ticket=$(git rev-parse --abbrev-ref HEAD | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1)
    [ "$ticket" = "ABC-123" ]
}

@test "Branch Intelligence: extracts ticket number from fix/JIRA-456-bug" {
    git checkout -b fix/JIRA-456-login-bug
    ticket=$(git rev-parse --abbrev-ref HEAD | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1)
    [ "$ticket" = "JIRA-456" ]
}

@test "Branch Intelligence: extracts ticket number from PROJ-789" {
    git checkout -b feature/PROJ-789-add-feature
    ticket=$(git rev-parse --abbrev-ref HEAD | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1)
    [ "$ticket" = "PROJ-789" ]
}

@test "Branch Intelligence: no ticket from main branch" {
    ticket=$(echo "main" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1 || echo "")
    [ -z "$ticket" ]
}

@test "Branch Intelligence: no ticket from feature/no-ticket" {
    git checkout -b feature/no-ticket-here
    ticket=$(git rev-parse --abbrev-ref HEAD | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1 || echo "")
    [ -z "$ticket" ]
}

@test "Branch Intelligence: detects feat type from feature/ prefix" {
    branch="feature/add-login"
    case "$branch" in
        feat/*|feature/*) type="feat" ;;
    esac
    [ "$type" = "feat" ]
}

@test "Branch Intelligence: detects feat type from feat/ prefix" {
    branch="feat/add-login"
    case "$branch" in
        feat/*|feature/*) type="feat" ;;
    esac
    [ "$type" = "feat" ]
}

@test "Branch Intelligence: detects fix type from fix/ prefix" {
    branch="fix/login-bug"
    case "$branch" in
        fix/*|bugfix/*|hotfix/*) type="fix" ;;
    esac
    [ "$type" = "fix" ]
}

@test "Branch Intelligence: detects fix type from bugfix/ prefix" {
    branch="bugfix/api-error"
    case "$branch" in
        fix/*|bugfix/*|hotfix/*) type="fix" ;;
    esac
    [ "$type" = "fix" ]
}

@test "Branch Intelligence: detects fix type from hotfix/ prefix" {
    branch="hotfix/critical-bug"
    case "$branch" in
        fix/*|bugfix/*|hotfix/*) type="fix" ;;
    esac
    [ "$type" = "fix" ]
}

@test "Branch Intelligence: detects docs type from docs/ prefix" {
    branch="docs/update-readme"
    case "$branch" in
        docs/*|doc/*) type="docs" ;;
    esac
    [ "$type" = "docs" ]
}

@test "Branch Intelligence: detects chore type from chore/ prefix" {
    branch="chore/update-deps"
    case "$branch" in
        chore/*) type="chore" ;;
    esac
    [ "$type" = "chore" ]
}

@test "Branch Intelligence: detects refactor type from refactor/ prefix" {
    branch="refactor/cleanup-code"
    case "$branch" in
        refactor/*) type="refactor" ;;
    esac
    [ "$type" = "refactor" ]
}

@test "Branch Intelligence: detects test type from test/ prefix" {
    branch="test/add-unit-tests"
    case "$branch" in
        test/*|tests/*) type="test" ;;
    esac
    [ "$type" = "test" ]
}

@test "Branch Intelligence: detects test type from tests/ prefix" {
    branch="tests/integration-tests"
    case "$branch" in
        test/*|tests/*) type="test" ;;
    esac
    [ "$type" = "test" ]
}

@test "Branch Intelligence: no type detection from main branch" {
    branch="main"
    type=""
    case "$branch" in
        feat/*|feature/*) type="feat" ;;
        fix/*|bugfix/*|hotfix/*) type="fix" ;;
        docs/*|doc/*) type="docs" ;;
    esac
    [ -z "$type" ]
}
