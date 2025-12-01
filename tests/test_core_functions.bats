#!/usr/bin/env bats

# Tests for core functions in gh-commit-ai

load test_helper

setup() {
    setup
    source_script_functions
}

teardown() {
    teardown
}

# Tests for escape_json function

@test "escape_json: handles double quotes" {
    result=$(escape_json 'Hello "World"')
    [[ "$result" == *'Hello \"World\"'* ]]
}

@test "escape_json: handles backslashes" {
    result=$(escape_json 'C:\Users\test')
    [[ "$result" == *'\\'* ]]
}

@test "escape_json: handles newlines" {
    result=$(escape_json $'Line1\nLine2')
    [[ "$result" == *'\\n'* ]]
}

@test "escape_json: handles tabs" {
    result=$(escape_json $'Column1\tColumn2')
    [[ "$result" == *'\\t'* ]]
}

@test "escape_json: handles empty string" {
    result=$(escape_json '')
    [ -z "$result" ]
}

# Tests for enforce_lowercase function

@test "enforce_lowercase: converts simple text to lowercase" {
    result=$(enforce_lowercase "Hello World")
    [ "$result" = "hello world" ]
}

@test "enforce_lowercase: preserves API acronym" {
    result=$(enforce_lowercase "Fix API Connection")
    [ "$result" = "fix API connection" ]
}

@test "enforce_lowercase: preserves HTTP acronym" {
    result=$(enforce_lowercase "Add HTTP Support")
    [ "$result" = "add HTTP support" ]
}

@test "enforce_lowercase: preserves JSON acronym" {
    result=$(enforce_lowercase "Parse JSON Data")
    [ "$result" = "parse JSON data" ]
}

@test "enforce_lowercase: preserves JWT acronym" {
    result=$(enforce_lowercase "Implement JWT Authentication")
    [ "$result" = "implement JWT authentication" ]
}

@test "enforce_lowercase: preserves SQL acronym" {
    result=$(enforce_lowercase "Optimize SQL Queries")
    [ "$result" = "optimize SQL queries" ]
}

@test "enforce_lowercase: preserves ticket number ABC-123" {
    result=$(enforce_lowercase "Fix Login Bug ABC-123")
    [ "$result" = "fix login bug ABC-123" ]
}

@test "enforce_lowercase: preserves ticket number JIRA-456" {
    result=$(enforce_lowercase "Add Feature JIRA-456")
    [ "$result" = "add feature JIRA-456" ]
}

@test "enforce_lowercase: preserves ticket number PROJ-789" {
    result=$(enforce_lowercase "Update Documentation For PROJ-789")
    [ "$result" = "update documentation for PROJ-789" ]
}

@test "enforce_lowercase: preserves multiple acronyms" {
    result=$(enforce_lowercase "Add API Support For JSON And HTTP")
    [ "$result" = "add API support for JSON and HTTP" ]
}

@test "enforce_lowercase: preserves ticket and acronyms together" {
    result=$(enforce_lowercase "Fix API Bug ABC-123 With JWT")
    [ "$result" = "fix API bug ABC-123 with JWT" ]
}

@test "enforce_lowercase: handles conventional commit format" {
    result=$(enforce_lowercase "Feat: Add User Authentication")
    [ "$result" = "feat: add user authentication" ]
}

@test "enforce_lowercase: handles scope in commit message" {
    result=$(enforce_lowercase "Feat(Auth): Add Login")
    [ "$result" = "feat(auth): add login" ]
}

@test "enforce_lowercase: preserves npm acronym" {
    result=$(enforce_lowercase "Update NPM Dependencies")
    [ "$result" = "update NPM dependencies" ]
}

@test "enforce_lowercase: preserves README" {
    result=$(enforce_lowercase "Update README File")
    [ "$result" = "update README file" ]
}

@test "enforce_lowercase: handles empty string" {
    result=$(enforce_lowercase "")
    [ "$result" = "" ]
}

# Tests for convert_newlines function

@test "convert_newlines: converts literal backslash-n to newlines" {
    result=$(convert_newlines 'Line1\nLine2')
    expected=$'Line1\nLine2'
    [ "$result" = "$expected" ]
}

@test "convert_newlines: handles multiple newlines" {
    result=$(convert_newlines 'Line1\n\nLine2\nLine3')
    expected=$'Line1\n\nLine2\nLine3'
    [ "$result" = "$expected" ]
}

@test "convert_newlines: handles commit message format" {
    result=$(convert_newlines 'feat: add feature\n\n- change 1\n- change 2')
    expected=$'feat: add feature\n\n- change 1\n- change 2'
    [ "$result" = "$expected" ]
}

@test "convert_newlines: handles empty string" {
    result=$(convert_newlines '')
    [ "$result" = "" ]
}

@test "convert_newlines: handles string with no newlines" {
    result=$(convert_newlines 'Simple text')
    [ "$result" = "Simple text" ]
}
