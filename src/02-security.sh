# ============================================================================
# Security Functions
# ============================================================================

# Create a secure temporary file with restricted permissions (600)
# Returns the path to the created file
create_secure_temp_file() {
    local prefix="${1:-gh-commit-ai}"
    local temp_file

    # Use mktemp for secure temp file creation
    temp_file=$(mktemp "/tmp/${prefix}.XXXXXXXXXX") || {
        echo -e "${RED}Error: Failed to create secure temporary file${NC}" >&2
        return 1
    }

    # Ensure restrictive permissions (owner read/write only)
    chmod 600 "$temp_file" 2>/dev/null || {
        echo -e "${RED}Error: Failed to set secure permissions on temporary file${NC}" >&2
        rm -f "$temp_file"
        return 1
    }

    echo "$temp_file"
}

# Validate that a parameter is a positive integer
# Usage: validate_positive_integer <value> <param_name>
# Returns: 0 if valid, 1 if invalid
validate_positive_integer() {
    local value="$1"
    local param_name="$2"

    # Check if value is empty
    if [ -z "$value" ]; then
        echo -e "${RED}Error: ${param_name} cannot be empty${NC}" >&2
        return 1
    fi

    # Check if value is a positive integer
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: ${param_name} must be a positive integer, got: $value${NC}" >&2
        return 1
    fi

    # Check if value is zero
    if [ "$value" -eq 0 ]; then
        echo -e "${RED}Error: ${param_name} must be greater than zero${NC}" >&2
        return 1
    fi

    return 0
}

# Validate that a parameter is within a set of allowed values
# Usage: validate_allowed_values <value> <param_name> <allowed1> <allowed2> ...
# Returns: 0 if valid, 1 if invalid
validate_allowed_values() {
    local value="$1"
    local param_name="$2"
    shift 2
    local allowed_values=("$@")

    # Check if value is empty
    if [ -z "$value" ]; then
        echo -e "${RED}Error: ${param_name} cannot be empty${NC}" >&2
        return 1
    fi

    # Check if value is in allowed list
    for allowed in "${allowed_values[@]}"; do
        if [ "$value" = "$allowed" ]; then
            return 0
        fi
    done

    # Value not found in allowed list
    echo -e "${RED}Error: ${param_name} must be one of: ${allowed_values[*]}, got: $value${NC}" >&2
    return 1
}

# Sanitize a string to prevent command injection
# Removes or escapes potentially dangerous characters
# Usage: sanitize_string <string>
sanitize_string() {
    local input="$1"

    # Remove null bytes, control characters, and backticks
    # Keep only printable ASCII + common unicode
    echo "$input" | tr -d '\000-\010\013-\037\177`$(){}[]<>|;&'
}

# Detect secrets/PII in diff before sending to cloud AI providers
# Args: diff_content
# Returns: 0 if no secrets found, 1 if secrets found (sets DETECTED_SECRETS)
# Side effect: sets DETECTED_SECRETS array and REDACTED_DIFF
detect_secrets_in_diff() {
    local diff_content="$1"
    DETECTED_SECRETS=()
    REDACTED_DIFF=""

    # Only scan added lines (lines starting with +, excluding +++ headers)
    local added_lines
    added_lines=$(echo "$diff_content" | grep '^+' | grep -v '^+++')

    if [ -z "$added_lines" ]; then
        return 0
    fi

    local found=false

    # AWS Access Key
    if echo "$added_lines" | grep -qE 'AKIA[0-9A-Z]{16}'; then
        DETECTED_SECRETS+=("AWS Access Key (AKIA...)")
        found=true
    fi

    # OpenAI/Stripe API key (sk-...)
    if echo "$added_lines" | grep -qE 'sk-[a-zA-Z0-9]{20,}'; then
        DETECTED_SECRETS+=("API key (sk-...)")
        found=true
    fi

    # Anthropic API key
    if echo "$added_lines" | grep -qE 'sk-ant-[a-zA-Z0-9-]{20,}'; then
        DETECTED_SECRETS+=("Anthropic API key (sk-ant-...)")
        found=true
    fi

    # GitHub Personal Access Token
    if echo "$added_lines" | grep -qE 'ghp_[a-zA-Z0-9]{36}'; then
        DETECTED_SECRETS+=("GitHub Personal Access Token (ghp_...)")
        found=true
    fi

    # GitLab Personal Access Token
    if echo "$added_lines" | grep -qE 'glpat-[a-zA-Z0-9-]{20}'; then
        DETECTED_SECRETS+=("GitLab Personal Access Token (glpat-...)")
        found=true
    fi

    # Private keys
    if echo "$added_lines" | grep -qE '-----BEGIN (RSA|EC|OPENSSH) PRIVATE KEY-----'; then
        DETECTED_SECRETS+=("Private key")
        found=true
    fi

    # Hardcoded passwords
    if echo "$added_lines" | grep -qiE 'password[[:space:]]*[:=][[:space:]]*["\x27][^"\x27]+["\x27]'; then
        DETECTED_SECRETS+=("Hardcoded password")
        found=true
    fi

    # Hardcoded secrets
    if echo "$added_lines" | grep -qiE 'secret[[:space:]]*[:=][[:space:]]*["\x27][^"\x27]+["\x27]'; then
        DETECTED_SECRETS+=("Hardcoded secret")
        found=true
    fi

    # Hardcoded tokens (but not "token" as a variable name reference)
    if echo "$added_lines" | grep -qiE '(api_token|auth_token|access_token)[[:space:]]*[:=][[:space:]]*["\x27][^"\x27]+["\x27]'; then
        DETECTED_SECRETS+=("Hardcoded token")
        found=true
    fi

    if [ "$found" = true ]; then
        # Build redacted version of the diff
        REDACTED_DIFF=$(echo "$diff_content" | sed \
            -e 's/AKIA[0-9A-Z]\{16\}/[REDACTED_AWS_KEY]/g' \
            -e 's/sk-ant-[a-zA-Z0-9-]\{20,\}/[REDACTED_ANTHROPIC_KEY]/g' \
            -e 's/sk-[a-zA-Z0-9]\{20,\}/[REDACTED_API_KEY]/g' \
            -e 's/ghp_[a-zA-Z0-9]\{36\}/[REDACTED_GITHUB_TOKEN]/g' \
            -e 's/glpat-[a-zA-Z0-9-]\{20\}/[REDACTED_GITLAB_TOKEN]/g')
        return 1
    fi

    return 0
}

# Prompt user about detected secrets and handle their choice
# Args: provider_name
# Returns: 0 to continue, 1 to cancel
# Side effect: may update GIT_DIFF with redacted version
handle_detected_secrets() {
    local provider_name="$1"

    echo "" >&2
    echo -e "${RED}⚠  Potential secrets detected in diff!${NC}" >&2
    echo "" >&2
    echo "The following sensitive patterns were found:" >&2
    for secret in "${DETECTED_SECRETS[@]}"; do
        echo "  • $secret" >&2
    done
    echo "" >&2
    echo "These will be sent to $provider_name's cloud API." >&2
    echo "" >&2
    echo -n "Continue? (y/n/r to redact): " >&2
    read -n 1 -r
    echo >&2

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0  # Continue with original diff
    elif [[ $REPLY =~ ^[Rr]$ ]]; then
        # Replace diff with redacted version
        GIT_DIFF="$REDACTED_DIFF"
        echo "Secrets redacted from diff." >&2
        return 0
    else
        echo "Cancelled." >&2
        return 1
    fi
}

# ============================================================================
# Network and Error Handling
# ============================================================================

# Check if we have basic network connectivity
# Returns 0 if online, 1 if offline
check_network_connectivity() {
    # Try to resolve common DNS names
    if command -v host >/dev/null 2>&1; then
        host google.com >/dev/null 2>&1 && return 0
    elif command -v nslookup >/dev/null 2>&1; then
        nslookup google.com >/dev/null 2>&1 && return 0
    elif command -v ping >/dev/null 2>&1; then
        # Try ping with timeout (works on both macOS and Linux)
        ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && return 0
    fi

    return 1
}

# Check if a specific host is reachable
# Usage: check_host_reachability <hostname>
check_host_reachability() {
    local host="$1"

    if command -v host >/dev/null 2>&1; then
        host "$host" >/dev/null 2>&1 && return 0
    elif command -v nslookup >/dev/null 2>&1; then
        nslookup "$host" >/dev/null 2>&1 && return 0
    fi

    return 1
}

# Display offline mode error with helpful suggestions
show_offline_error() {
    local provider="$1"

    echo -e "${RED}Error: No internet connection detected${NC}" >&2
    echo "" >&2
    echo "Unable to reach $provider API. Possible causes:" >&2
    echo "  • No internet connection" >&2
    echo "  • Firewall blocking access" >&2
    echo "  • VPN or proxy issues" >&2
    echo "  • DNS resolution problems" >&2
    echo "" >&2
    echo "Suggestions:" >&2
    echo "  • Check your internet connection" >&2
    echo "  • Try: ping 8.8.8.8" >&2

    if [ "$provider" = "Ollama" ]; then
        echo "  • Ollama runs locally - check if it's running: ollama ps" >&2
    else
        echo "  • Use Ollama (local, no internet required):" >&2
        echo "    export AI_PROVIDER=ollama" >&2
        echo "    Install from: https://ollama.ai" >&2
    fi
}

# Validate that an API response contains expected content
# Usage: validate_api_response <response>
# Returns 0 if valid, 1 if invalid/incomplete
validate_api_response() {
    local response="$1"

    # Check if response is empty
    if [ -z "$response" ]; then
        return 1
    fi

    # Check if response is valid JSON (rough check)
    if ! echo "$response" | grep -q '{.*}'; then
        return 1
    fi

    return 0
}

# Enhanced error message for API key issues
show_api_key_error() {
    local provider="$1"
    local key_var="$2"

    echo -e "${RED}Error: $key_var is not set${NC}" >&2
    echo "" >&2
    echo "To use $provider, you need to set your API key:" >&2
    echo "  export $key_var=\"your-key-here\"" >&2
    echo "" >&2

    case "$provider" in
        "Anthropic")
            echo "Get your API key from: https://console.anthropic.com/settings/keys" >&2
            echo "Example: export ANTHROPIC_API_KEY=\"sk-ant-...\"" >&2
            ;;
        "OpenAI")
            echo "Get your API key from: https://platform.openai.com/api-keys" >&2
            echo "Example: export OPENAI_API_KEY=\"sk-proj-...\"" >&2
            ;;
        "Groq")
            echo "Get your API key from: https://console.groq.com/keys" >&2
            echo "Example: export GROQ_API_KEY=\"gsk_...\"" >&2
            ;;
    esac

    echo "" >&2
    echo "Alternative: Use Ollama (local, no API key needed):" >&2
    echo "  brew install ollama  # or download from https://ollama.ai" >&2
    echo "  ollama run gemma2:2b" >&2
    echo "  export AI_PROVIDER=ollama" >&2
}

