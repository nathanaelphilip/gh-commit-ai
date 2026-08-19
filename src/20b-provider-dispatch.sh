# ---------------------------------------------------------------------------
# Provider dispatch with automatic local fallback
# ---------------------------------------------------------------------------

# Records the provider that actually produced output (may differ from the
# configured AI_PROVIDER when a fallback kicks in). Read by callers so analytics
# and cost tracking point at the model that ran.
EFFECTIVE_PROVIDER_FILE="/tmp/gh-commit-ai-provider-$$"

# Route a prompt to a named provider.
dispatch_provider() {
    local provider="$1"
    local prompt="$2"
    case "$provider" in
        ollama)    call_ollama "$prompt" ;;
        anthropic) call_anthropic "$prompt" ;;
        openai)    call_openai "$prompt" ;;
        groq)      call_groq "$prompt" ;;
        *)
            echo -e "${RED}Error: Unknown AI provider '$provider'${NC}" >&2
            return 1
            ;;
    esac
}

# Is the local fallback provider ready to serve? (Only Ollama needs a live check;
# other providers gate on their own API keys inside their call_* functions.)
fallback_is_available() {
    [ "$FALLBACK_PROVIDER" = "ollama" ] || return 0
    curl -s --connect-timeout 1 "$OLLAMA_HOST/api/tags" >/dev/null 2>&1 || return 1
    local count
    count=$(curl -s "$OLLAMA_HOST/api/tags" 2>/dev/null | grep -o '"name":"[^"]*"' | wc -l)
    [ "$count" -gt 0 ]
}

# Choose which local model to use for the fallback: honor the configured
# OLLAMA_MODEL if it's actually installed, otherwise auto-pick the best one
# available so the fallback doesn't fail on a missing model.
pick_fallback_ollama_model() {
    local installed
    installed=$(curl -s "$OLLAMA_HOST/api/tags" 2>/dev/null | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//')
    if [ -n "$OLLAMA_MODEL" ] && echo "$installed" | grep -qxF "$OLLAMA_MODEL"; then
        echo "$OLLAMA_MODEL"
        return
    fi
    get_best_ollama_model
}

# Resolve the model name configured for a given provider.
provider_model() {
    case "$1" in
        ollama)    echo "$OLLAMA_MODEL" ;;
        anthropic) echo "$ANTHROPIC_MODEL" ;;
        openai)    echo "$OPENAI_MODEL" ;;
        groq)      echo "$GROQ_MODEL" ;;
        *)         echo "" ;;
    esac
}

# Daily-rotated error log. The full provider error output goes here instead of the
# terminal. The file is reset the first time it is written on a new day, so it
# never grows beyond a single day's worth of failures.
ERROR_LOG="${GH_COMMIT_AI_ERROR_LOG:-/tmp/gh-commit-ai-errors.log}"

log_provider_error() {
    local provider="$1" model="$2" detail_file="$3"
    local today ts label first_date esc
    today=$(date +%Y-%m-%d 2>/dev/null || echo "unknown")
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$today")
    esc=$(printf '\033')   # literal ESC byte, portable across GNU/BSD sed
    label="$provider"
    if [ -n "$model" ]; then label="$provider/$model"; fi

    # Daily rotation: start a fresh log if the existing one isn't from today.
    if [ -f "$ERROR_LOG" ]; then
        first_date=$(head -1 "$ERROR_LOG" 2>/dev/null | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
        if [ "$first_date" != "$today" ]; then
            : > "$ERROR_LOG" 2>/dev/null || true
        fi
    fi

    {
        echo "$ts  [$label]"
        if [ -s "$detail_file" ]; then
            # Strip ANSI color codes and indent for readability.
            sed -E "s/${esc}\[[0-9;]*m//g; s/^/    /" "$detail_file" 2>/dev/null || true
        else
            echo "    (no error detail captured)"
        fi
        echo "------------------------------------------------------------"
    } >> "$ERROR_LOG" 2>/dev/null || true
    return 0
}

# Log the full error quietly and show the user a single concise line.
report_provider_failure() {
    local provider="$1" model="$2" detail_file="$3"
    local label="$provider"
    if [ -n "$model" ]; then label="$provider/$model"; fi
    log_provider_error "$provider" "$model" "$detail_file"
    echo -e "${RED}✗ Model ${label} failed.${NC} See error log: $ERROR_LOG" >&2
    return 0
}

# Call the configured provider; on failure, log the (verbose) error to ERROR_LOG,
# tell the user where to find it in one line, then transparently retry with the
# local fallback provider so a commit message still gets generated. Records the
# provider that produced output in EFFECTIVE_PROVIDER_FILE.
call_provider_with_fallback() {
    local prompt="$1"
    local result="" rc=0
    local errfile="/tmp/gh-commit-ai-provider-err-$$"

    printf '%s' "$AI_PROVIDER" > "$EFFECTIVE_PROVIDER_FILE" 2>/dev/null || true

    # Primary provider. Capture fd 2 (error detail) to a file; the spinner uses
    # fd 3 and still reaches the terminal. '|| rc=$?' keeps set -e from aborting
    # here so we can fall back instead of dying on the first failure.
    : > "$errfile" 2>/dev/null || true
    rc=0
    result=$(dispatch_provider "$AI_PROVIDER" "$prompt" 2>"$errfile") || rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$result" ]; then
        rm -f "$errfile"
        printf '%s\n' "$result"
        return 0
    fi

    report_provider_failure "$AI_PROVIDER" "$(provider_model "$AI_PROVIDER")" "$errfile"
    rm -f "$errfile"

    # Fall back to a local model when enabled, different, and actually available.
    if [ "$ENABLE_FALLBACK" = "true" ] && [ "$AI_PROVIDER" != "$FALLBACK_PROVIDER" ] && fallback_is_available; then
        if [ "$FALLBACK_PROVIDER" = "ollama" ]; then
            OLLAMA_MODEL=$(pick_fallback_ollama_model 2>/dev/null || echo "$OLLAMA_MODEL")
        fi
        echo -e "↪ Falling back to $FALLBACK_PROVIDER ($(provider_model "$FALLBACK_PROVIDER"))" >&2

        : > "$errfile" 2>/dev/null || true
        rc=0
        result=$(dispatch_provider "$FALLBACK_PROVIDER" "$prompt" 2>"$errfile") || rc=$?
        if [ "$rc" -eq 0 ] && [ -n "$result" ]; then
            rm -f "$errfile"
            printf '%s' "$FALLBACK_PROVIDER" > "$EFFECTIVE_PROVIDER_FILE" 2>/dev/null || true
            printf '%s\n' "$result"
            return 0
        fi
        report_provider_failure "$FALLBACK_PROVIDER" "$(provider_model "$FALLBACK_PROVIDER")" "$errfile"
        rm -f "$errfile"
    fi

    return 1
}

