# Call Ollama API
call_ollama() {
    local prompt="$1"

    # Quick pre-flight check: verify Ollama is reachable
    if ! curl -s --connect-timeout 2 --max-time 5 "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
        echo -e "${RED}Error: Cannot connect to Ollama at $OLLAMA_HOST${NC}" >&2
        echo "" >&2
        echo "Ollama is not responding. Possible causes:" >&2
        echo "  • Ollama service is not running" >&2
        echo "  • Wrong OLLAMA_HOST configuration" >&2
        echo "  • Port conflict or firewall blocking" >&2
        echo "" >&2
        echo "Troubleshooting:" >&2
        echo "  • Start Ollama: ollama serve" >&2
        echo "  • Check if running: ps aux | grep ollama" >&2
        echo "  • Verify host: curl $OLLAMA_HOST/api/tags" >&2
        echo "  • List models: ollama list" >&2
        echo "" >&2
        echo "Don't have Ollama? Install from: https://ollama.ai" >&2
        return 1
    fi

    local model_escaped=$(escape_json "$OLLAMA_MODEL")
    local prompt_escaped=$(escape_json "$prompt")

    if [ "$VERBOSE" = "true" ]; then
        echo "[Verbose] API Endpoint:${NC} $OLLAMA_HOST/api/generate"
        echo "[Verbose] Model:${NC} $OLLAMA_MODEL"
    fi

    # Try streaming first
    if should_stream; then
        local stream_payload=$(printf '{"model":"%s","prompt":"%s","stream":true}' "$model_escaped" "$prompt_escaped")
        local stream_output
        stream_output=$(create_secure_temp_file "gh-commit-ai-stream") || return 1

        if streaming_api_call \
            "$OLLAMA_HOST/api/generate" \
            "$stream_payload" \
            "$stream_output" \
            parse_ollama_stream \
            -H "Content-Type: application/json"; then

            local result=$(cat "$stream_output" 2>/dev/null)
            rm -f "$stream_output" "${stream_output}.input_tokens" "${stream_output}.output_tokens"
            if [ -n "$result" ]; then
                unescape_json "$result"
                return 0
            fi
        fi

        # Streaming failed, fall back to non-streaming
        rm -f "$stream_output" "${stream_output}.input_tokens" "${stream_output}.output_tokens"
        printf "\r%-80s\r" " " >&2
        echo "Streaming failed, retrying..." >&2
    fi

    # Non-streaming path (original behavior)
    local json_payload=$(printf '{"model":"%s","prompt":"%s","stream":false}' "$model_escaped" "$prompt_escaped")

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
            "$OLLAMA_HOST/api/generate" \
            "$json_payload" \
            "$temp_response" \
            "$temp_error" \
            "Ollama" \
            -H "Content-Type: application/json"
        echo $? > "${temp_response}.exit"
    ) &
    local api_pid=$!

    show_spinner "$api_pid" "Thinking"
    wait "$api_pid"

    exit_code=$(cat "${temp_response}.exit" 2>/dev/null || echo "1")

    # Read response from file
    local response=$(cat "$temp_response" 2>/dev/null)

    # Check for final failure after all retries
    if [ "$exit_code" != "0" ] || [ -z "$response" ]; then
        echo -e "${RED}Error: Failed to get response from Ollama after $MAX_RETRIES attempts${NC}" >&2
        echo "" >&2
        echo "All retry attempts exhausted. Possible causes:" >&2
        echo "  • Model '$OLLAMA_MODEL' not found or not loaded" >&2
        echo "  • Ollama service stopped during request" >&2
        echo "  • Out of memory (model too large)" >&2
        echo "  • Request timeout" >&2
        echo "" >&2

        # Show actual error if available
        if [ -s "$temp_error" ]; then
            echo -e "${YELLOW}Error details: $(cat "$temp_error" | head -1)${NC}" >&2
            echo "" >&2
        fi

        echo "Troubleshooting:" >&2
        echo "  • Check if model exists: ollama list" >&2
        echo "  • Pull model if needed: ollama pull $OLLAMA_MODEL" >&2
        echo "  • Verify service: curl $OLLAMA_HOST/api/tags" >&2
        echo "  • Check service status: ps aux | grep ollama" >&2
        echo "  • Try smaller model: OLLAMA_MODEL=gemma2:2b gh commit-ai" >&2
        echo "  • Run with verbose mode: gh commit-ai --verbose" >&2

        rm -f "$temp_response" "$temp_error" "${temp_response}.exit"
        return 1
    fi

    # Validate response content
    if ! validate_api_response "$response"; then
        echo -e "${RED}Error: Invalid response from Ollama${NC}" >&2
        echo "" >&2
        echo "The Ollama API returned an unexpected response format." >&2
        echo "This could indicate:" >&2
        echo "  • Model compatibility issues" >&2
        echo "  • Corrupted model installation" >&2
        echo "  • Ollama version mismatch" >&2
        echo "" >&2
        echo "Try:" >&2
        echo "  • Update Ollama: brew upgrade ollama" >&2
        echo "  • Reinstall model: ollama rm $OLLAMA_MODEL && ollama pull $OLLAMA_MODEL" >&2
        echo "  • Run with verbose mode: gh commit-ai --verbose" >&2
        rm -f "$temp_response" "$temp_error" "${temp_response}.exit"
        return 1
    fi

    rm -f "$temp_error" "${temp_response}.exit"

    if [ "$VERBOSE" = "true" ]; then
        echo "[Verbose] Response:"
        echo "$response" | jq '.' 2>/dev/null || echo "$response"
        echo ""
    fi

    # Check for errors
    if echo "$response" | grep -q '"error"'; then
        local error_msg=$(echo "$response" | grep -o '"error":"[^"]*"' | sed 's/"error":"//;s/"$//')
        echo -e "${RED}Error from Ollama: $error_msg${NC}" >&2
        echo "" >&2

        # Check if it's a model not found error
        if echo "$error_msg" | grep -qi "model.*not found\|pull.*model"; then
            echo -e "Model '${BLUE}$OLLAMA_MODEL${NC}' is not installed." >&2
            echo "" >&2
            echo "To fix this, run:" >&2
            echo -e "  ${GREEN}ollama pull $OLLAMA_MODEL${NC}" >&2
            echo "" >&2
            echo "Or use a different model:" >&2
            echo -e "  ${GREEN}OLLAMA_MODEL=llama3.2 gh commit-ai${NC}" >&2
        else
            echo "Troubleshooting:" >&2
            echo "  - Check available models: ollama list" >&2
            echo "  - Verify Ollama status: ollama ps" >&2
            echo "  - Try verbose mode: gh commit-ai --verbose" >&2
        fi
        return 1
    fi

    # Extract commit message from response
    # Use awk to properly extract JSON string value (handles escaped quotes)
    local raw_message=$(echo "$response" | awk -F'"response":"' '{
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
        }
    }')
    unescape_json "$raw_message"
}

