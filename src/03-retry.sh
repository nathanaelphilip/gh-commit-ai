# ============================================================================
# Retry Logic
# ============================================================================

# Retry wrapper with exponential backoff
# Usage: retry_with_backoff <attempt_num> <max_attempts> "<command>"
# Returns: 0 on success, 1 on failure after all retries
retry_api_call() {
    local url="$1"
    local data="$2"
    local output_file="$3"
    local error_file="$4"
    local provider_name="$5"
    shift 5
    # Remaining arguments are header options for curl (e.g., -H "Content-Type: application/json")
    local header_args=("$@")

    local attempt=1
    local delay="$RETRY_DELAY"

    while [ $attempt -le "$MAX_RETRIES" ]; do
        # Make the API call
        local exit_code=0
        curl -s -X POST "$url" \
            "${header_args[@]}" \
            -d "$data" \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            -o "$output_file" 2>"$error_file" || exit_code=$?

        # Check if successful
        if [ $exit_code -eq 0 ] && [ -s "$output_file" ]; then
            # Check if response contains an error
            if ! grep -q '"error"' "$output_file" 2>/dev/null; then
                return 0  # Success!
            fi
        fi

        # If this was the last attempt, fail
        if [ $attempt -eq "$MAX_RETRIES" ]; then
            return 1
        fi

        # Determine error type for better messaging
        local error_msg=""
        case $exit_code in
            0)
                error_msg="API error (rate limit or invalid response)"
                ;;
            6)
                error_msg="Could not resolve host"
                ;;
            7)
                error_msg="Failed to connect"
                ;;
            28)
                error_msg="Timeout"
                ;;
            35)
                error_msg="SSL connection error"
                ;;
            52)
                error_msg="Empty response from server"
                ;;
            56)
                error_msg="Network error (receive failure)"
                ;;
            *)
                error_msg="Network error (code: $exit_code)"
                ;;
        esac

        # Show retry message
        echo -e "${YELLOW}⚠ $error_msg - Retrying in ${delay}s (attempt $attempt/$MAX_RETRIES)${NC}" >&2

        # Wait with exponential backoff
        sleep $delay

        # Double the delay for next time (exponential backoff)
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done

    return 1  # All retries failed
}

# Streaming API call (no retry - on failure, caller falls back to non-streaming)
# Usage: streaming_api_call <url> <data> <output_file> <parser_func> [header_args...]
# Returns: 0 on success, 1 on failure
streaming_api_call() {
    local url="$1"
    local data="$2"
    local output_file="$3"
    local parser_func="$4"
    shift 4
    local header_args=("$@")

    # Use curl with -N (no buffering) for streaming
    curl -sN -X POST "$url" \
        "${header_args[@]}" \
        -d "$data" \
        --connect-timeout "$CONNECT_TIMEOUT" \
        --max-time "$MAX_TIME" \
        2>/dev/null | "$parser_func" "$output_file"

    local exit_code=${PIPESTATUS[0]}

    # Check if we got any output
    if [ $exit_code -ne 0 ] || [ ! -s "$output_file" ]; then
        return 1
    fi

    return 0
}

