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

            # The server returned an error body. Some errors are permanent:
            # retrying the identical request cannot fix them (the request exceeds
            # the model's token/rate limit, the API key is invalid, or the model
            # does not exist). Stop now and let the caller surface the real
            # message instead of burning retries. The error body is preserved in
            # "$output_file"; return 2 to signal "API error body available".
            if grep -qiE 'too large|too long|reduce your message size|context.?length|maximum context length|invalid_?api_?key|invalid api key|authentication_error|model_not_found|does not exist|decommissioned' "$output_file" 2>/dev/null; then
                return 2
            fi
        fi

        # If this was the last attempt, fail
        if [ $attempt -eq "$MAX_RETRIES" ]; then
            # Distinguish a real error body from a pure network failure so the
            # caller can show the actual API error rather than a generic message.
            if [ $exit_code -eq 0 ] && [ -s "$output_file" ] && grep -q '"error"' "$output_file" 2>/dev/null; then
                return 2
            fi
            return 1
        fi

        # Determine error type for better messaging
        local error_msg=""
        case $exit_code in
            0)
                # curl succeeded but response contains an error - extract the actual message
                local api_error=$(grep -o '"error":"[^"]*"' "$output_file" 2>/dev/null | head -1 | sed 's/"error":"//;s/"$//')
                if [ -n "$api_error" ]; then
                    error_msg="$provider_name error: $api_error"
                else
                    error_msg="API error (invalid response)"
                fi
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

    # Start background spinner while waiting for first token
    local spinner_pidfile
    spinner_pidfile=$(mktemp /tmp/gh-commit-ai-spinner-pid.XXXXXX 2>/dev/null || echo "/tmp/gh-commit-ai-spinner-pid-$$")
    (
        local delay=0.15
        local arrows=("←" "↖" "↑" "↗" "→" "↘" "↓" "↙")
        local i=0
        while true; do
            printf "\r%s %s" "${arrows[$i]}" "$SPINNER_MESSAGE" >&3
            i=$(( (i + 1) % 8 ))
            sleep $delay
        done
    ) &
    echo $! > "$spinner_pidfile"

    # Export spinner PID so parsers can kill it on first token
    export STREAM_SPINNER_PID=$(cat "$spinner_pidfile")
    rm -f "$spinner_pidfile"

    # Use curl with -N (no buffering) for streaming
    curl -sN -X POST "$url" \
        "${header_args[@]}" \
        -d "$data" \
        --connect-timeout "$CONNECT_TIMEOUT" \
        --max-time "$MAX_TIME" \
        2>/dev/null | "$parser_func" "$output_file"

    local exit_code=${PIPESTATUS[0]}

    # Ensure spinner is stopped
    if [ -n "$STREAM_SPINNER_PID" ] && kill -0 "$STREAM_SPINNER_PID" 2>/dev/null; then
        kill "$STREAM_SPINNER_PID" 2>/dev/null
        wait "$STREAM_SPINNER_PID" 2>/dev/null
    fi

    # Check if we got any output
    if [ $exit_code -ne 0 ] || [ ! -s "$output_file" ]; then
        return 1
    fi

    return 0
}

