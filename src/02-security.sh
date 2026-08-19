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

# Create a secure temporary directory with restricted permissions (700)
# Returns the path to the created directory
create_secure_temp_dir() {
    local prefix="${1:-gh-commit-ai}"
    local temp_dir

    temp_dir=$(mktemp -d "/tmp/${prefix}.XXXXXXXXXX") || {
        echo -e "${RED}Error: Failed to create secure temporary directory${NC}" >&2
        return 1
    }

    chmod 700 "$temp_dir" 2>/dev/null || {
        echo -e "${RED}Error: Failed to set secure permissions on temporary directory${NC}" >&2
        rm -rf "$temp_dir"
        return 1
    }

    echo "$temp_dir"
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
    if echo "$added_lines" | grep -qE -e '-----BEGIN (RSA|EC|OPENSSH) PRIVATE KEY-----'; then
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

# List every provider that could receive the diff on this run, excluding the
# local one. The diff does not only go to $AI_PROVIDER: the two-stage pipeline
# can route Stage 1 to $ANALYSIS_PROVIDER, and a primary failure can hand the
# same diff to $FALLBACK_PROVIDER. Gating the secret scan on $AI_PROVIDER alone
# meant `AI_PROVIDER=ollama` skipped the scan while a cloud analysis or fallback
# provider still received the raw diff.
# Output: space-separated provider names, empty if everything stays local.
cloud_providers_in_play() {
    local candidates="$AI_PROVIDER"

    if [ "$PIPELINE_ENABLED" = "true" ] && [ -n "$ANALYSIS_PROVIDER" ]; then
        candidates="$candidates $ANALYSIS_PROVIDER"
    fi

    if [ "$ENABLE_FALLBACK" = "true" ] && [ -n "$FALLBACK_PROVIDER" ]; then
        candidates="$candidates $FALLBACK_PROVIDER"
    fi

    local provider seen="" cloud=""
    for provider in $candidates; do
        [ -n "$provider" ] || continue
        [ "$provider" != "ollama" ] || continue
        case " $seen " in
            *" $provider "*) continue ;;
        esac
        seen="$seen $provider"
        cloud="$cloud $provider"
    done

    # shellcheck disable=SC2086
    echo $cloud
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

# Explain an already-failed API call in network terms.
#
# These two lookups used to run *before* every cloud request, which cost two
# forked processes and up to two DNS round trips (or a 2s ping timeout where
# neither host(1) nor nslookup exists) on every successful call - while telling
# the user nothing that curl's own exit codes, already mapped to friendly text
# in retry_api_call, did not cover. Running them only after a failure keeps the
# better error message and takes the cost off the success path.
#
# Usage: diagnose_network_failure <provider_label> <hostname>
diagnose_network_failure() {
    local provider="$1"
    local host="$2"

    if ! check_network_connectivity; then
        show_offline_error "$provider"
        return 0
    fi

    if ! check_host_reachability "$host"; then
        echo -e "${RED}Error: Cannot reach $provider API${NC}" >&2
        echo "" >&2
        echo "The API endpoint $host is not reachable." >&2
        echo "Possible causes:" >&2
        echo "  • $provider service is down" >&2
        echo "  • Firewall or network filtering" >&2
        echo "  • DNS issues" >&2
        echo "" >&2
        echo "Try:" >&2
        echo "  • Use a different provider (export AI_PROVIDER=groq or ollama)" >&2
        return 0
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
    echo "  ollama run qwen3:8b  # strong instruction following, fast" >&2
    echo "  export AI_PROVIDER=ollama" >&2
}

# Actionable guidance when a request exceeds the model's token/rate limit.
# This is NOT a transient rate limit — the prompt itself is too big to accept,
# so waiting and retrying will never help. The user must send fewer tokens.
show_token_limit_tip() {
    local provider="$1"
    echo "" >&2
    echo -e "${YELLOW}This request is larger than the model's token limit for your tier.${NC}" >&2
    echo "The prompt (diff + analysis context) exceeded what the API will accept" >&2
    echo "in a single request, so retrying the same request will not help." >&2
    echo "" >&2
    echo "To fix:" >&2
    echo "  • Send less of the diff: DIFF_MAX_LINES=50 gh commit-ai (or lower)" >&2
    echo "  • Stage fewer files and commit in smaller batches" >&2
    case "$provider" in
        "Groq")
            echo "  • Groq's free tier caps tokens-per-minute (e.g. 12000 TPM); one large" >&2
            echo "    request can exceed it. Upgrade: https://console.groq.com/settings/billing" >&2
            echo "  • Check your per-model limits: https://console.groq.com/settings/limits" >&2
            ;;
        "OpenAI")
            echo "  • Use a model with a larger context window, or raise your usage tier" >&2
            ;;
        "Anthropic")
            echo "  • Reduce input tokens, or raise your rate limit in the Anthropic console" >&2
            ;;
    esac
    echo "  • Or switch provider: export AI_PROVIDER=ollama (local, no token limits)" >&2
}

# ============================================================================
# Retry Logic
# ============================================================================

