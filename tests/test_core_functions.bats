#!/usr/bin/env bats

# Tests for core functions in gh-commit-ai

load test_helper

setup() {
    common_setup
    source_script_functions
}

teardown() {
    common_teardown
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
    [[ "$result" == *'\n'* ]]
}

@test "escape_json: handles tabs" {
    result=$(escape_json $'Column1\tColumn2')
    [[ "$result" == *'\t'* ]]
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

# Tests for unescape_json function
#
# The ampersand cases are the important ones: they used to spin forever rather
# than return a wrong answer, so they run under a deadline.

@test "unescape_json: escaped ampersand does not hang" {
    local rc=0
    run_with_deadline 15 unescape_json 'search \u0026 filter' || rc=$?
    [ "$rc" -ne 124 ]
    [ "$DEADLINE_OUTPUT" = "search & filter" ]
}

@test "unescape_json: several escaped ampersands do not hang" {
    local rc=0
    run_with_deadline 15 unescape_json '\u0026 a \u0026 b \u0026' || rc=$?
    [ "$rc" -ne 124 ]
    [ "$DEADLINE_OUTPUT" = "& a & b &" ]
}

@test "unescape_json: ampersand after a literal backslash does not hang" {
    local rc=0
    run_with_deadline 15 unescape_json 'a \\u0026 b' || rc=$?
    [ "$rc" -ne 124 ]
    [ "$DEADLINE_OUTPUT" = 'a \& b' ]
}

@test "unescape_json: decodes angle brackets" {
    result=$(unescape_json 'x \u003c y \u003e z')
    [ "$result" = "x < y > z" ]
}

@test "unescape_json: decodes ASCII escapes" {
    result=$(unescape_json '\u0041\u0042')
    [ "$result" = "AB" ]
}

@test "unescape_json: decodes an escaped backslash code point" {
    result=$(unescape_json 'p \u005c q')
    [ "$result" = 'p \ q' ]
}

@test "unescape_json: decodes two-byte code points as UTF-8" {
    result=$(unescape_json 'caf\u00e9')
    [ "$result" = "café" ]
}

@test "unescape_json: decodes three-byte code points as UTF-8" {
    result=$(unescape_json '\u4f60\u597d')
    [ "$result" = "你好" ]
}

@test "unescape_json: decodes surrogate pairs as one code point" {
    result=$(unescape_json 'ship \ud83d\ude80')
    [ "$result" = "ship 🚀" ]
}

@test "unescape_json: leaves text without escapes alone" {
    result=$(unescape_json 'feat: add login')
    [ "$result" = "feat: add login" ]
}

@test "unescape_json: collapses escaped backslashes and quotes" {
    result=$(unescape_json 'say \\"hi\\"')
    [ "$result" = 'say "hi"' ]
}

@test "unescape_json: leaves newline escapes for convert_newlines" {
    result=$(unescape_json 'one\\ntwo')
    [ "$result" = 'one\ntwo' ]
}

# Tests for replace_placeholder function

@test "replace_placeholder: an ampersand in the value stays an ampersand" {
    result='X {{message}} Y'
    replace_placeholder result '{{message}}' 'add search & filter'
    [ "$result" = "X add search & filter Y" ]
}

@test "replace_placeholder: substitutes a plain value" {
    result='X {{message}} Y'
    replace_placeholder result '{{message}}' 'add login'
    [ "$result" = "X add login Y" ]
}

@test "replace_placeholder: substitutes every occurrence" {
    result='{{type}}-{{type}}'
    replace_placeholder result '{{type}}' 'feat'
    [ "$result" = "feat-feat" ]
}

@test "replace_placeholder: an empty value removes the placeholder" {
    result='X {{ticket}} Y'
    replace_placeholder result '{{ticket}}' ''
    [ "$result" = "X  Y" ]
}

@test "replace_placeholder: leaves text without the placeholder alone" {
    result='nothing to substitute'
    replace_placeholder result '{{ticket}}' 'ABC-123'
    [ "$result" = "nothing to substitute" ]
}

@test "replace_placeholder: preserves backslashes in the value" {
    result='A {{message}} B'
    replace_placeholder result '{{message}}' 'use C:\path\here'
    [ "$result" = 'A use C:\path\here B' ]
}

@test "replace_placeholder: a value containing the placeholder terminates" {
    probe_placeholder_recursion() {
        local result='A {{type}} B'
        replace_placeholder result '{{type}}' 'x {{type}} y'
        printf '%s' "$result"
    }
    local rc=0
    run_with_deadline 15 probe_placeholder_recursion || rc=$?
    [ "$rc" -ne 124 ]
    [ "$DEADLINE_OUTPUT" = "A x {{type}} y B" ]
}
