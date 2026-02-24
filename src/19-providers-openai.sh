# Call OpenAI API
call_openai() {
    local prompt="$1"

    if [ -z "$OPENAI_API_KEY" ]; then
        show_api_key_error "OpenAI" "OPENAI_API_KEY"
        exit 1
    fi

    # Check network connectivity before making API call
    if ! check_network_connectivity; then
        show_offline_error "OpenAI"
        exit 1
    fi

    # Check if OpenAI API is reachable
    if ! check_host_reachability "api.openai.com"; then
        echo -e "${RED}Error: Cannot reach OpenAI API${NC}" >&2
        echo "" >&2
        echo "The API endpoint api.openai.com is not reachable." >&2
        echo "Possible causes:" >&2
        echo "  • OpenAI service is down" >&2
        echo "  • Firewall or network filtering" >&2
        echo "  • DNS issues" >&2
        echo "" >&2
        echo "Try:" >&2
        echo "  • Check service status: https://status.openai.com/" >&2
        echo "  • Use a different provider (export AI_PROVIDER=groq or ollama)" >&2
        exit 1
    fi

    local prompt_escaped=$(escape_json "$prompt")

    if [ "$VERBOSE" = "true" ]; then
        echo "[Verbose] API Endpoint:${NC} https://api.openai.com/v1/chat/completions"
        echo "[Verbose] Model:${NC} $OPENAI_MODEL"
    fi

    # Token file for streaming
    local token_file="/tmp/gh-commit-ai-tokens-$$"

    # Try streaming first
    if should_stream; then
        local stream_payload=$(printf '{"model":"%s","messages":[{"role":"user","content":"%s"}],"temperature":0.7,"stream":true,"stream_options":{"include_usage":true}}' "$OPENAI_MODEL" "$prompt_escaped")
        local stream_output
        stream_output=$(create_secure_temp_file "gh-commit-ai-stream") || return 1

        if streaming_api_call \
            "https://api.openai.com/v1/chat/completions" \
            "$stream_payload" \
            "$stream_output" \
            parse_openai_stream \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $OPENAI_API_KEY"; then

            local result=$(cat "$stream_output" 2>/dev/null)
            INPUT_TOKENS=$(cat "${stream_output}.input_tokens" 2>/dev/null || echo "0")
            OUTPUT_TOKENS=$(cat "${stream_output}.output_tokens" 2>/dev/null || echo "0")
            echo "${INPUT_TOKENS:-0}" > "${token_file}.input"
            echo "${OUTPUT_TOKENS:-0}" > "${token_file}.output"
            rm -f "$stream_output" "${stream_output}.input_tokens" "${stream_output}.output_tokens"
            if [ -n "$result" ]; then
                unescape_json "$result"
                return 0
            fi
        fi

        rm -f "$stream_output" "${stream_output}.input_tokens" "${stream_output}.output_tokens"
        printf "\r%-80s\r" " " >&2
        echo "Streaming failed, retrying..." >&2
    fi

    # Non-streaming path
    local json_payload=$(printf '{"model":"%s","messages":[{"role":"user","content":"%s"}],"temperature":0.7}' "$OPENAI_MODEL" "$prompt_escaped")

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
            "https://api.openai.com/v1/chat/completions" \
            "$json_payload" \
            "$temp_response" \
            "$temp_error" \
            "OpenAI" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $OPENAI_API_KEY"
        echo $? > "${temp_response}.exit"
    ) &
    local api_pid=$!

    show_spinner "$api_pid" "Thinking"
    wait "$api_pid"

    # Read exit code
    exit_code=$(cat "${temp_response}.exit" 2>/dev/null || echo "1")

    # Read response from file
    local response=$(cat "$temp_response" 2>/dev/null)

    # Check for final failure after all retries
    if [ "$exit_code" != "0" ] || [ -z "$response" ]; then
        echo -e "${RED}Error: Failed to get response from OpenAI after $MAX_RETRIES attempts${NC}" >&2
        echo "" >&2
        echo "All retry attempts exhausted. Possible causes:" >&2
        echo "  • Network connection issues" >&2
        echo "  • OpenAI API is experiencing downtime" >&2
        echo "  • Request timeout (large diff or slow connection)" >&2
        echo "  • Rate limiting or quota exceeded" >&2
        echo "" >&2
        echo "Suggestions:" >&2
        echo "  • Check your internet: ping api.openai.com" >&2
        echo "  • Verify service status: https://status.openai.com/" >&2
        echo "  • Try reducing diff size: DIFF_MAX_LINES=50 gh commit-ai" >&2
        echo "  • Use a different provider:" >&2
        echo "    - Groq (fast, free tier): export AI_PROVIDER=groq" >&2
        echo "    - Ollama (local, no internet): export AI_PROVIDER=ollama" >&2
        echo "  • Wait a few minutes and try again" >&2
        rm -f "$temp_response" "$temp_error" "${temp_response}.exit"
        return 1
    fi

    # Validate response content
    if ! validate_api_response "$response"; then
        echo -e "${RED}Error: Invalid response from OpenAI${NC}" >&2
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
        local error_code=$(echo "$response" | grep -o '"code":"[^"]*"' | head -1 | sed 's/"code":"//;s/"$//')

        echo -e "${RED}Error from OpenAI" >&2
        [ -n "$error_code" ] && echo -e "${RED}Code: $error_code" >&2
        [ -n "$error_type" ] && echo -e "${RED}Type: $error_type" >&2
        [ -n "$error_msg" ] && echo -e "${RED}Message: $error_msg" >&2

        if [[ "$error_code" == *"invalid_api_key"* ]] || [[ "$error_msg" == *"API key"* ]]; then
            echo "Tip: Check your API key is valid and has credits" >&2
        elif [[ "$error_code" == *"rate_limit"* ]]; then
            echo "Tip: You've hit the rate limit. Wait a moment and try again" >&2
        elif [[ "$error_code" == *"model_not_found"* ]]; then
            echo "Tip: The model '$OPENAI_MODEL' doesn't exist or you don't have access" >&2
        fi
        return 1
    fi

    # Extract token usage (global variables for cost tracking)
    INPUT_TOKENS=$(echo "$response" | grep -o '"prompt_tokens":[0-9]*' | head -1 | grep -o '[0-9]*')
    OUTPUT_TOKENS=$(echo "$response" | grep -o '"completion_tokens":[0-9]*' | head -1 | grep -o '[0-9]*')

    # Write token counts for parent process
    echo "${INPUT_TOKENS:-0}" > "${token_file}.input"
    echo "${OUTPUT_TOKENS:-0}" > "${token_file}.output"

    # Extract commit message from response
    # OpenAI returns: {"choices":[{"message":{"content":"..."},...}],...}
    # Use awk to properly extract JSON string value (handles escaped quotes)
    local raw_message=$(echo "$response" | awk -F'"content":"' '{
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

