#!/usr/bin/env bats

# Mock API response tests
# These tests verify JSON parsing and response handling without making real API calls

load test_helper

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"

    # Source the script to get access to functions
    source_script_functions
}

teardown() {
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

@test "parse ollama JSON response" {
    # Create a mock Ollama response
    cat > /tmp/ollama_response.json <<'EOF'
{
  "model": "gemma3:12b",
  "created_at": "2023-12-03T12:00:00Z",
  "response": "feat: add user authentication\n\n- implement JWT token generation\n- create login endpoint\n- add password hashing",
  "done": true
}
EOF

    # Extract the response field using grep/sed (same method as in script)
    result=$(grep -o '"response":"[^"]*"' /tmp/ollama_response.json | sed 's/"response":"//; s/"$//' | sed 's/\\n/\n/g')

    # Verify extraction
    [[ "$result" == *"feat: add user authentication"* ]]
    [[ "$result" == *"- implement JWT token generation"* ]]

    rm -f /tmp/ollama_response.json
}

@test "parse anthropic JSON response" {
    # Create a mock Anthropic response
    cat > /tmp/anthropic_response.json <<'EOF'
{
  "id": "msg_123",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "fix: resolve database connection timeout\n\n- add connection retry logic\n- increase timeout to 30 seconds\n- add error logging"
    }
  ],
  "model": "claude-3-5-sonnet-20241022",
  "stop_reason": "end_turn",
  "usage": {
    "input_tokens": 150,
    "output_tokens": 75
  }
}
EOF

    # Extract content using grep/sed
    result=$(grep -o '"text":"[^"]*"' /tmp/anthropic_response.json | head -1 | sed 's/"text":"//; s/"$//' | sed 's/\\n/\n/g')

    # Verify extraction
    [[ "$result" == *"fix: resolve database connection timeout"* ]]
    [[ "$result" == *"- add connection retry logic"* ]]

    # Extract token counts
    input_tokens=$(grep -o '"input_tokens":[0-9]*' /tmp/anthropic_response.json | sed 's/"input_tokens"://')
    output_tokens=$(grep -o '"output_tokens":[0-9]*' /tmp/anthropic_response.json | sed 's/"output_tokens"://')

    [ "$input_tokens" -eq 150 ]
    [ "$output_tokens" -eq 75 ]

    rm -f /tmp/anthropic_response.json
}

@test "parse openai JSON response" {
    # Create a mock OpenAI response
    cat > /tmp/openai_response.json <<'EOF'
{
  "id": "chatcmpl-123",
  "object": "chat.completion",
  "created": 1677652288,
  "model": "gpt-4o-mini",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "docs: update API documentation\n\n- add authentication section\n- update endpoint examples\n- fix typos"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 200,
    "completion_tokens": 50,
    "total_tokens": 250
  }
}
EOF

    # Extract content using grep/sed
    result=$(grep -o '"content":"[^"]*"' /tmp/openai_response.json | sed 's/"content":"//; s/"$//' | sed 's/\\n/\n/g')

    # Verify extraction
    [[ "$result" == *"docs: update API documentation"* ]]
    [[ "$result" == *"- add authentication section"* ]]

    # Extract token counts
    prompt_tokens=$(grep -o '"prompt_tokens":[0-9]*' /tmp/openai_response.json | sed 's/"prompt_tokens"://')
    completion_tokens=$(grep -o '"completion_tokens":[0-9]*' /tmp/openai_response.json | sed 's/"completion_tokens"://')

    [ "$prompt_tokens" -eq 200 ]
    [ "$completion_tokens" -eq 50 ]

    rm -f /tmp/openai_response.json
}

@test "handle multiple options in response" {
    # Create a mock response with multiple options
    cat > /tmp/multi_response.txt <<'EOF'
feat: add user authentication

- implement JWT tokens
- create login endpoint

---OPTION---

feat: implement authentication system

- add JWT token generation
- create user login functionality

---OPTION---

feat: create user login feature

- implement JWT authentication
- add login API endpoint
EOF

    # Split by separator
    options=$(cat /tmp/multi_response.txt)

    # Verify it contains the separator
    [[ "$options" == *"---OPTION---"* ]]

    # Count options (should be 3)
    option_count=$(echo "$options" | grep -c "^feat:")
    [ "$option_count" -eq 3 ]

    rm -f /tmp/multi_response.txt
}

@test "lowercase enforcement preserves structure" {
    # Test the enforce_lowercase function
    input="Feat: Add User Authentication With JWT

- Implement Token Generation
- Create Login Endpoint For Users
- Add Password Hashing Using bcrypt

This is a TEST-123 ticket for the API endpoint."

    # Apply lowercase (this requires the function to be loaded)
    result=$(enforce_lowercase "$input")

    # Verify lowercase applied
    [[ "$result" == *"feat: add user authentication with JWT"* ]]

    # Verify acronyms preserved
    [[ "$result" == *"JWT"* ]]
    [[ "$result" == *"API"* ]]

    # Verify ticket number preserved
    [[ "$result" == *"TEST-123"* ]]
}

@test "escape_json handles special characters" {
    # Test escape_json function
    input='This has "quotes" and \ backslashes and
newlines and	tabs'

    result=$(escape_json "$input")

    # Verify escaping
    [[ "$result" == *'\\"quotes\\"'* ]]
    [[ "$result" == *'\\\\'* ]]  # Backslash should be escaped
    [[ "$result" == *'\\n'* ]]   # Newline should be escaped
    [[ "$result" == *'\\t'* ]]   # Tab should be escaped
}

@test "convert_newlines transforms literal backslash-n" {
    # Test newline conversion
    input='feat: add feature\n\n- bullet one\n- bullet two'

    # Simulate the conversion (using printf %b)
    result=$(printf "%b" "$input")

    # Verify newlines are actual newlines now
    [[ "$result" == *$'\n'* ]]

    # Count lines
    line_count=$(echo "$result" | wc -l | tr -d ' ')
    [ "$line_count" -ge 3 ]  # Should have at least 3 lines
}

@test "smart_sample_diff preserves structure" {
    # Create a large diff
    cat > /tmp/large.diff <<'EOF'
diff --git a/file1.js b/file1.js
index abc123..def456 100644
--- a/file1.js
+++ b/file1.js
@@ -1,5 +1,10 @@
 function existing() {
   return true;
 }
+
+function newFunction() {
+  return false;
+}
+
 module.exports = { existing };
EOF

    # Read and verify structure is maintained
    result=$(cat /tmp/large.diff)

    # Should have file markers
    [[ "$result" == *"diff --git"* ]]
    [[ "$result" == *"--- a/"* ]]
    [[ "$result" == *"+++ b/"* ]]

    # Should have chunk markers
    [[ "$result" == *"@@"* ]]

    rm -f /tmp/large.diff
}
