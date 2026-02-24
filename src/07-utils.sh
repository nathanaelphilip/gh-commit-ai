# Show spinner while waiting
show_spinner() {
    local pid=$1
    local message="$2"
    local delay=0.15
    local arrows=("←" "↖" "↑" "↗" "→" "↘" "↓" "↙")
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${arrows[$i]} ${message}" >&2
        i=$(( (i + 1) % 8 ))
        sleep $delay
    done
    printf "\r%-50s\r" " " >&2  # Clear the line
}

# Intelligently sample diff for large changes
# Prioritizes: function signatures > added lines > context > deleted lines
smart_sample_diff() {
    local full_diff="$1"
    local max_lines="$2"

    # Count total lines
    local total_lines=$(echo "$full_diff" | wc -l | tr -d ' ')

    # If under limit, return full diff
    if [ "$total_lines" -le "$max_lines" ]; then
        echo "$full_diff"
        return
    fi

    # Otherwise, intelligently sample
    local temp_file
    temp_file=$(create_secure_temp_file "gh-commit-ai-smart-sample") || return 1
    echo "$full_diff" > "$temp_file"

    # Extract high-priority lines
    local priority_file
    priority_file=$(create_secure_temp_file "gh-commit-ai-priority") || {
        rm -f "$temp_file"
        return 1
    }
    > "$priority_file"

    # Priority 1: File headers and chunk headers (MUST keep)
    grep -E '^(diff --git|index |---|\+\+\+|@@)' "$temp_file" >> "$priority_file" 2>/dev/null || true

    # Priority 2: Function/class definitions (HIGH priority)
    grep -E '^\+.*(function |def |class |const |export |public |private |func )' "$temp_file" >> "$priority_file" 2>/dev/null || true

    # Priority 3: Added lines (MEDIUM-HIGH priority)
    # Sample added lines evenly throughout the diff
    local added_lines=$(grep -n '^\+[^+]' "$temp_file" | wc -l | tr -d ' ')
    if [ "$added_lines" -gt 0 ]; then
        # Calculate sample rate to get ~40% of max_lines from added lines
        local target_added=$((max_lines * 40 / 100))
        local sample_rate=$((added_lines / target_added + 1))

        grep -n '^\+[^+]' "$temp_file" | awk -v rate="$sample_rate" 'NR % rate == 1' | cut -d: -f1 | while read line_num; do
            sed -n "${line_num}p" "$temp_file" >> "$priority_file"
        done
    fi

    # Priority 4: Context lines around changes (MEDIUM priority)
    # Get a few context lines for readability
    grep -E '^ [a-zA-Z]' "$temp_file" | head -n $((max_lines * 20 / 100)) >> "$priority_file" 2>/dev/null || true

    # Priority 5: Deleted lines (LOW priority) - only sample if we have room
    local current_count=$(cat "$priority_file" | wc -l | tr -d ' ')
    if [ "$current_count" -lt "$max_lines" ]; then
        local remaining=$((max_lines - current_count))
        grep -E '^\-[^-]' "$temp_file" | head -n $((remaining / 2)) >> "$priority_file" 2>/dev/null || true
    fi

    # Sort by line number to maintain diff structure, remove duplicates, and limit
    cat "$priority_file" | sort -u | head -n "$max_lines"

    # Cleanup
    rm -f "$temp_file" "$priority_file"
}

# Analyze commit size (count lines changed)
analyze_commit_size() {
    local diff="$1"

    # Count added and deleted lines (ignore context lines)
    local added=$(echo "$diff" | grep -c '^\+[^+]' 2>/dev/null || echo "0")
    local deleted=$(echo "$diff" | grep -c '^\-[^-]' 2>/dev/null || echo "0")
    local total=$((added + deleted))

    echo "$total"
}

# Check if we're in a git repository (cache the result)
# PERFORMANCE OPTIMIZATION: Cache all git repository info upfront
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
if [ -z "$GIT_DIR" ]; then
    echo -e "${RED}Error: Not a git repository"
    exit 1
fi

# Cache branch name early (avoids later git call)
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# Get repository-specific identifier for message history
# This ensures cached messages don't leak between different repositories
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$REPO_ROOT" ]; then
    # Create a hash of the repository path to use as a unique identifier
    if command -v md5sum &> /dev/null; then
        REPO_HASH=$(echo -n "$REPO_ROOT" | md5sum | awk '{print $1}')
    elif command -v md5 &> /dev/null; then
        REPO_HASH=$(echo -n "$REPO_ROOT" | md5 | awk '{print $1}')
    else
        # Fallback: use basename of repo (less robust but better than nothing)
        REPO_HASH=$(basename "$REPO_ROOT")
    fi
    MESSAGE_HISTORY_DIR="/tmp/gh-commit-ai-history-${REPO_HASH}"
    CACHE_DIR="/tmp/gh-commit-ai-cache-${REPO_HASH}"
else
    # Fallback to non-scoped directory (shouldn't happen in valid git repos)
    MESSAGE_HISTORY_DIR="/tmp/gh-commit-ai-history"
    CACHE_DIR="/tmp/gh-commit-ai-cache"
fi
mkdir -p "$MESSAGE_HISTORY_DIR"
mkdir -p "$CACHE_DIR"

# Note: Cache cleanup happens automatically in save_cached_response() to avoid startup delay

# ============================================================================
# Cache Helper Functions
# ============================================================================

# Get cached value if fresh (within TTL)
# Args: cache_key, ttl_seconds
# Returns: cached content if valid, empty otherwise
get_cache() {
    local cache_key="$1"
    local ttl="${2:-3600}"  # Default 1 hour
    local cache_file="${CACHE_DIR}/${cache_key}"

    if [ -f "$cache_file" ]; then
        local file_age=$(($(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || stat -c%Y "$cache_file" 2>/dev/null)))
        if [ "$file_age" -lt "$ttl" ]; then
            cat "$cache_file"
            return 0
        fi
    fi
    return 1
}

# Save value to cache
# Args: cache_key, content
set_cache() {
    local cache_key="$1"
    local content="$2"
    local cache_file="${CACHE_DIR}/${cache_key}"

    echo "$content" > "$cache_file"
}

# Determine if streaming should be enabled
# Returns 0 (true) if streaming should be used, 1 (false) otherwise
should_stream() {
    # Explicit disable
    if [ "$STREAM_ENABLED" = "false" ]; then
        return 1
    fi

    # Explicit enable
    if [ "$STREAM_ENABLED" = "true" ]; then
        return 0
    fi

    # Auto mode: enable if stdout is a TTY and not in special modes
    if [ "$STREAM_ENABLED" = "auto" ]; then
        # Disable for non-interactive modes
        if [ "$PREVIEW" = "true" ] || [ "$DRY_RUN" = "true" ] || \
           [ "$MULTIPLE_OPTIONS" = "true" ] || [ "$VERBOSE" = "true" ]; then
            return 1
        fi
        # Enable if stderr is a TTY (we stream to stderr for visual feedback)
        if [ -t 2 ]; then
            return 0
        fi
        return 1
    fi

    return 1
}

# Streaming arrow animation state
STREAM_ARROWS=("←" "↖" "↑" "↗" "→" "↘" "↓" "↙")
STREAM_ARROW_IDX=0

# Get next rotating arrow for streaming output
next_stream_arrow() {
    printf "%s" "${STREAM_ARROWS[$STREAM_ARROW_IDX]}"
    STREAM_ARROW_IDX=$(( (STREAM_ARROW_IDX + 1) % 8 ))
}

# Parse Ollama streaming response
# Each line is a JSON object: {"response":"token","done":false}
# Args: accum_file (where to write full response)
parse_ollama_stream() {
    local accum_file="$1"
    local full_response=""

    printf "\r%s Generating" "$(next_stream_arrow)" >&2

    while IFS= read -r line; do
        [ -z "$line" ] && continue

        if echo "$line" | grep -q '"done":true'; then
            break
        fi

        local token=$(echo "$line" | awk -F'"response":"' '{
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

        if [ -n "$token" ]; then
            full_response="${full_response}${token}"
            printf "\r%s" "$(next_stream_arrow)" >&2
        fi
    done

    printf "\r%-50s\r" " " >&2
    echo "$full_response" > "$accum_file"
}

# Parse Anthropic SSE streaming response
# Events: message_start, content_block_delta, message_delta, message_stop
# Args: accum_file
parse_anthropic_stream() {
    local accum_file="$1"
    local full_response=""
    local input_tokens=0
    local output_tokens=0

    printf "\r%s Generating" "$(next_stream_arrow)" >&2

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [[ "$line" == :* ]] && continue
        [[ "$line" == event:* ]] && continue

        if [[ "$line" == data:* ]]; then
            local data="${line#data: }"

            if echo "$data" | grep -q '"type":"message_start"'; then
                input_tokens=$(echo "$data" | grep -o '"input_tokens":[0-9]*' | grep -o '[0-9]*')
            fi

            if echo "$data" | grep -q '"type":"content_block_delta"'; then
                local token=$(echo "$data" | awk -F'"text":"' '{
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

                if [ -n "$token" ]; then
                    full_response="${full_response}${token}"
                    printf "\r%s" "$(next_stream_arrow)" >&2
                fi
            fi

            if echo "$data" | grep -q '"type":"message_delta"'; then
                output_tokens=$(echo "$data" | grep -o '"output_tokens":[0-9]*' | grep -o '[0-9]*')
            fi
        fi
    done

    printf "\r%-50s\r" " " >&2

    echo "$full_response" > "$accum_file"
    echo "${input_tokens:-0}" > "${accum_file}.input_tokens"
    echo "${output_tokens:-0}" > "${accum_file}.output_tokens"
}

# Parse OpenAI/Groq SSE streaming response
# Events: data: {"choices":[{"delta":{"content":"token"}}]}
# Args: accum_file
parse_openai_stream() {
    local accum_file="$1"
    local full_response=""
    local input_tokens=0
    local output_tokens=0

    printf "\r%s Generating" "$(next_stream_arrow)" >&2

    while IFS= read -r line; do
        [ -z "$line" ] && continue

        if [ "$line" = "data: [DONE]" ]; then
            break
        fi

        if [[ "$line" == data:* ]]; then
            local data="${line#data: }"

            local token=$(echo "$data" | awk -F'"content":"' '{
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

            if [ -n "$token" ]; then
                full_response="${full_response}${token}"
                printf "\r%s" "$(next_stream_arrow)" >&2
            fi

            if echo "$data" | grep -q '"usage"'; then
                input_tokens=$(echo "$data" | grep -o '"prompt_tokens":[0-9]*' | grep -o '[0-9]*')
                output_tokens=$(echo "$data" | grep -o '"completion_tokens":[0-9]*' | grep -o '[0-9]*')
            fi
        fi
    done

    printf "\r%-50s\r" " " >&2

    echo "$full_response" > "$accum_file"
    # Write token counts to sidecar files
    echo "${input_tokens:-0}" > "${accum_file}.input_tokens"
    echo "${output_tokens:-0}" > "${accum_file}.output_tokens"
}

