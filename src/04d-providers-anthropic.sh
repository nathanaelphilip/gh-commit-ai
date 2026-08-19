# Call Anthropic API
call_anthropic() {
    local prompt="$1"

    if [ -z "$ANTHROPIC_API_KEY" ]; then
        show_api_key_error "Anthropic" "ANTHROPIC_API_KEY"
        exit 1
    fi

    # Connectivity is not probed up front - curl resolves and connects anyway,
    # and retry_api_call already turns its exit codes into readable errors.
    # diagnose_network_failure runs on the failure path instead.

    local prompt_escaped=$(escape_json "$prompt")

    if [ "$VERBOSE" = "true" ]; then
        echo "[Verbose] API Endpoint:${NC} https://api.anthropic.com/v1/messages"
        echo "[Verbose] Model:${NC} $ANTHROPIC_MODEL"
    fi

    # Token file for streaming (used to pass token counts out of subshell)
    local token_file="/tmp/gh-commit-ai-tokens-$$"

    # Try streaming first
    if should_stream; then
        local stream_payload=$(printf '{"model":"%s","max_tokens":1024,"temperature":%s,"stream":true,"messages":[{"role":"user","content":"%s"}]}' "$ANTHROPIC_MODEL" "$AI_TEMPERATURE" "$prompt_escaped")
        local stream_output
        stream_output=$(create_secure_temp_file "gh-commit-ai-stream") || return 1

        if streaming_api_call \
            "https://api.anthropic.com/v1/messages" \
            "$stream_payload" \
            "$stream_output" \
            parse_anthropic_stream \
            -H "Content-Type: application/json" \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01"; then

            local result=$(cat "$stream_output" 2>/dev/null)
            # Read token counts from sidecar files
            INPUT_TOKENS=$(cat "${stream_output}.input_tokens" 2>/dev/null || echo "0")
            OUTPUT_TOKENS=$(cat "${stream_output}.output_tokens" 2>/dev/null || echo "0")
            # Write token counts for parent process
            echo "${INPUT_TOKENS:-0}" > "${token_file}.input"
            echo "${OUTPUT_TOKENS:-0}" > "${token_file}.output"
            rm -f "$stream_output" "${stream_output}.input_tokens" "${stream_output}.output_tokens"
            if [ -n "$result" ]; then
                unescape_json "$result"
                return 0
            fi
        fi

        # Streaming failed, fall back
        rm -f "$stream_output" "${stream_output}.input_tokens" "${stream_output}.output_tokens"
        printf "\r%-80s\r" " " >&3
        echo "Streaming failed, retrying..." >&2
    fi

    # Non-streaming path (original behavior)
    local json_payload=$(printf '{"model":"%s","max_tokens":1024,"temperature":%s,"messages":[{"role":"user","content":"%s"}]}' "$ANTHROPIC_MODEL" "$AI_TEMPERATURE" "$prompt_escaped")

    if [ "$VERBOSE" = "true" ]; then
        echo "[Verbose] Request payload:"
        echo "$json_payload" | jq '.' 2>/dev/null || echo "$json_payload"
        echo ""
    fi

    # Run API call with retry logic in background with spinner
    local temp_response
    local temp_error
    temp_response=$(create_secure_temp_file "gh-commit-ai-response") || return 1
    temp_error=$(create_secure_temp_file "gh-commit-ai-error") || {
        rm -f "$temp_response"
        return 1
    }
    local exit_code=0
    (
        retry_api_call \
            "https://api.anthropic.com/v1/messages" \
            "$json_payload" \
            "$temp_response" \
            "$temp_error" \
            "Anthropic" \
            -H "Content-Type: application/json" \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01"
        echo $? > "${temp_response}.exit"
    ) &
    local api_pid=$!

    show_spinner "$api_pid" "$SPINNER_MESSAGE"
    wait "$api_pid"

    # Read exit code
    exit_code=$(cat "${temp_response}.exit" 2>/dev/null || echo "1")

    # Read response from file
    local response=$(cat "$temp_response" 2>/dev/null)

    # Check for final failure after all retries
    if [ -z "$response" ]; then
        # Now that the request has actually failed, it is worth spending two DNS
        # lookups to say whether the machine is offline or the host is
        # unreachable. If it reports either, that is the whole story.
        if diagnose_network_failure "Anthropic" "api.anthropic.com"; then
            rm -f "$temp_response" "$temp_error" "${temp_response}.exit"
            return 1
        fi

        echo -e "${RED}Error: Failed to get response from Anthropic after $MAX_RETRIES attempts${NC}" >&2
        echo "" >&2
        echo "All retry attempts exhausted. This could be due to:" >&2
        echo "  • Poor network connection" >&2
        echo "  • API service issues" >&2
        echo "  • Request timeouts" >&2
        echo "" >&2
        echo "Suggestions:" >&2
        echo "  • Check your internet connection" >&2
        echo "  • Check Anthropic status: https://status.anthropic.com/" >&2
        echo "  • Try again in a few minutes" >&2
        echo "  • Use a different provider: export AI_PROVIDER=ollama" >&2
        rm -f "$temp_response" "$temp_error" "${temp_response}.exit"
        return 1
    fi

    # Validate API response
    if ! validate_api_response "$response"; then
        echo -e "${RED}Error: Invalid response from Anthropic${NC}" >&2
        echo "" >&2
        echo "The API returned an unexpected response format." >&2
        echo "This could indicate:" >&2
        echo "  • API version changes" >&2
        echo "  • Service degradation" >&2
        echo "  • Network proxy interference" >&2
        echo "" >&2
        echo "Try:" >&2
        echo "  • Run with verbose mode: gh commit-ai --verbose" >&2
        echo "  • Use a different provider: export AI_PROVIDER=ollama" >&2
        rm -f "$temp_response" "$temp_error" "${temp_response}.exit"
        return 1
    fi

    # Cleanup temp files
    rm -f "$temp_error" "${temp_response}.exit"

    if [ "$VERBOSE" = "true" ]; then
        echo "[Verbose] Response:"
        echo "$response" | jq '.' 2>/dev/null || echo "$response"
        echo ""
    fi

    # Check for errors
    if echo "$response" | grep -q '"error"'; then
        local error_type=$(echo "$response" | grep -o '"type":"[^"]*"' | head -1 | sed 's/"type":"//;s/"$//')
        local error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | head -1 | sed 's/"message":"//;s/"$//')
        echo -e "${RED}Error from Anthropic ($error_type): $error_msg" >&2

        if [[ "$error_msg" == *"too long"* ]] || [[ "$error_msg" == *"too large"* ]] || [[ "$error_msg" == *"maximum"* ]]; then
            show_token_limit_tip "Anthropic"
        elif [[ "$error_type" == *"authentication"* ]] || [[ "$error_msg" == *"API key"* ]]; then
            echo "Tip: Check your API key is valid and has credits" >&2
        elif [[ "$error_type" == *"rate_limit"* ]]; then
            echo "Tip: You've hit the rate limit. Wait a moment and try again" >&2
        fi
        return 1
    fi

    # Extract token usage (global variables for cost tracking)
    INPUT_TOKENS=$(echo "$response" | grep -o '"input_tokens":[0-9]*' | head -1 | grep -o '[0-9]*')
    OUTPUT_TOKENS=$(echo "$response" | grep -o '"output_tokens":[0-9]*' | head -1 | grep -o '[0-9]*')

    # Write token counts for parent process
    echo "${INPUT_TOKENS:-0}" > "${token_file}.input"
    echo "${OUTPUT_TOKENS:-0}" > "${token_file}.output"

    # Extract commit message from response
    # Anthropic returns: {"content":[{"text":"...","type":"text"}],...}
    # Use awk to properly extract JSON string value (handles escaped quotes)
    local raw_message=$(echo "$response" | awk -F'"text":"' '{
        if (NF > 1) {
            str = $2
            result = ""
            escaped = 0
            for (i = 1; i <= length(str); i++) {
                c = substr(str, i, 1)
                if (escaped) {
                    result = result c
                    escaped = 0
                } else if (c == "\\") {
                    result = result c
                    escaped = 1
                } else if (c == "\"") {
                    break
                } else {
                    result = result c
                }
            }
            print result
            exit
        }
    }')

    # Cleanup temp files
    rm -f "$temp_response"

    unescape_json "$raw_message"
}

