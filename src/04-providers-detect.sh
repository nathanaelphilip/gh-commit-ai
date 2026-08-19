# One cached fetch of Ollama's model list, shared by availability detection and
# model selection.
#
# A single run used to hit $OLLAMA_HOST/api/tags up to four times: twice
# back-to-back in detect_available_providers (once to test reachability, once to
# count models), again in get_best_ollama_model on a cold cache, and a fourth
# time as call_ollama's preflight. Since AI_PROVIDER defaults to "auto", a user
# with only a cloud key set still paid for the localhost probes on every run.
#
# The TTL is short - the point is to collapse the calls within one run, not to
# remember for long that Ollama was down.
OLLAMA_TAGS_CACHE="/tmp/gh-commit-ai-ollama-tags-$(id -u 2>/dev/null || echo 0)"
OLLAMA_TAGS_TTL=60

# Models that cannot generate a commit message. An embedding-only install (say a
# lone nomic-embed-text pulled for an unrelated project) used to count as
# "ollama is available", beat a correctly configured cloud key, and then fail.
ollama_model_is_chat_capable() {
    case "$1" in
        *embed*|*bge-*|*minilm*|*paraphrase*) return 1 ;;
        *) return 0 ;;
    esac
}

ollama_model_list() {
    local age

    if [ -f "$OLLAMA_TAGS_CACHE" ]; then
        age=$(( $(date +%s) - $(stat -f%m "$OLLAMA_TAGS_CACHE" 2>/dev/null || stat -c%Y "$OLLAMA_TAGS_CACHE" 2>/dev/null || echo 0) ))
        if [ "$age" -lt "$OLLAMA_TAGS_TTL" ]; then
            cat "$OLLAMA_TAGS_CACHE"
            return 0
        fi
    fi

    local models
    models=$(curl -s --connect-timeout 1 "$OLLAMA_HOST/api/tags" 2>/dev/null \
        | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//')

    local chat_models="" model
    while IFS= read -r model; do
        [ -n "$model" ] || continue
        ollama_model_is_chat_capable "$model" || continue
        chat_models="${chat_models}${model}
"
    done <<EOF
$models
EOF

    printf '%s' "$chat_models" > "$OLLAMA_TAGS_CACHE" 2>/dev/null || true
    chmod 600 "$OLLAMA_TAGS_CACHE" 2>/dev/null || true
    printf '%s' "$chat_models"
}

# Auto-detect available AI providers and models
detect_available_providers() {
    local available=""

    # Check Anthropic (API key set)
    if [ -n "$ANTHROPIC_API_KEY" ]; then
        available="${available}anthropic "
    fi

    # Check OpenAI (API key set)
    if [ -n "$OPENAI_API_KEY" ]; then
        available="${available}openai "
    fi

    # Check Groq (API key set)
    if [ -n "$GROQ_API_KEY" ]; then
        available="${available}groq "
    fi

    # Check Ollama (running, and has at least one model that can actually chat).
    # One cached call now covers both questions.
    if [ -n "$(ollama_model_list)" ]; then
        available="${available}ollama "
    fi

    echo "$available" | xargs  # Trim whitespace
}

# Get largest available Ollama model by parameter count
get_best_ollama_model() {
    # Use global cache (not repo-specific)
    local cache_file="/tmp/gh-commit-ai-ollama-model-cache"
    local cache_ttl=3600  # 1 hour

    # Check cache first
    if [ -f "$cache_file" ]; then
        local file_age=$(($(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || stat -c%Y "$cache_file" 2>/dev/null)))
        if [ "$file_age" -lt "$cache_ttl" ]; then
            cat "$cache_file"
            return
        fi
    fi

    # Query Ollama for available models (shared cache - see ollama_model_list)
    local models=$(ollama_model_list)

    if [ -z "$models" ]; then
        echo ""
        return
    fi

    local largest_model=""
    local largest_size=0

    # Parse each model name and extract parameter size
    while IFS= read -r model; do
        # Extract size from model name (e.g., "70b", "32b", "7b", "1.5b")
        # Matches patterns like :70b, :32b, :7b, :1.5b, -70b, -32b, etc.
        local size=$(echo "$model" | grep -oE '[:_-]([0-9]+\.?[0-9]*)b' | grep -oE '[0-9]+\.?[0-9]*' | head -1)

        if [ -n "$size" ]; then
            # Convert to integer for comparison (multiply by 10 to handle decimals like 1.5b)
            local size_int=$(echo "$size * 10" | bc 2>/dev/null | cut -d. -f1)

            if [ -z "$size_int" ]; then
                # Fallback if bc not available
                size_int=$(printf "%.0f" "$(echo "$size * 10" | awk '{print $1 * $3}')")
            fi

            # Pick the largest model
            if [ "$size_int" -gt "$largest_size" ]; then
                largest_size="$size_int"
                largest_model="$model"
            fi
        fi
    done <<< "$models"

    # If we found a model with size, use it
    if [ -n "$largest_model" ]; then
        echo "$largest_model" | tee "$cache_file"
        return
    fi

    # Fallback: just return first model (for models without size in name)
    echo "$models" | head -1 | tee "$cache_file"
}

# Fail only when a provider is actually about to be used. See the comment in the
# auto-detection block below.
AI_PROVIDER_UNAVAILABLE=false

require_ai_provider() {
    [ "$AI_PROVIDER_UNAVAILABLE" = "true" ] || return 0

    echo -e "${RED}Error: No AI providers available${NC}" >&2
    echo "" >&2
    echo "Available options:" >&2
    echo "  1. Install Ollama (free, local): https://ollama.ai" >&2
    echo "     Then run: ollama pull qwen3:8b" >&2
    echo "" >&2
    echo "  2. Set up Groq API (ultra-fast, generous free tier):" >&2
    echo "     export GROQ_API_KEY=\"gsk-...\"" >&2
    echo "     Get your key from: https://console.groq.com/keys" >&2
    echo "" >&2
    echo "  3. Set up Anthropic API:" >&2
    echo "     export ANTHROPIC_API_KEY=\"sk-ant-...\"" >&2
    echo "" >&2
    echo "  4. Set up OpenAI API:" >&2
    echo "     export OPENAI_API_KEY=\"sk-proj-...\"" >&2
    exit 1
}

# Auto-select provider if set to "auto"
AUTO_DETECTED=false
if [ "$AI_PROVIDER" = "auto" ]; then
    # Detect what's available
    available_providers=$(detect_available_providers)

    if [ -z "$available_providers" ]; then
        # Deliberately not fatal here. This block runs before argument parsing,
        # so exiting would make --help, --version, "Not a git repository" and
        # "No changes to commit" all unreachable on a machine that has no
        # provider configured yet - exactly the machine whose user needs to read
        # --help. Record it instead and let require_ai_provider fail at the point
        # where a provider is genuinely needed.
        AI_PROVIDER_UNAVAILABLE=true
    fi

    # Pick the best available provider (prefer local/free first, then fast/free APIs, then paid APIs)
    if echo "$available_providers" | grep -q "ollama"; then
        AI_PROVIDER="ollama"
        # Auto-select best Ollama model
        detected_model=$(get_best_ollama_model)
        if [ -n "$detected_model" ]; then
            OLLAMA_MODEL="$detected_model"
            AUTO_DETECTED=true
        fi

        # Ollama outranks the cloud providers, and a background Ollama is easy
        # to forget about. Say so up front rather than letting someone wonder
        # why the key they exported was ignored.
        if [ -n "$ANTHROPIC_API_KEY" ] || [ -n "$OPENAI_API_KEY" ] || [ -n "$GROQ_API_KEY" ]; then
            echo "Note: using local Ollama ($OLLAMA_MODEL); a cloud API key is set but Ollama takes precedence." >&2
            echo "      Set AI_PROVIDER explicitly (e.g. AI_PROVIDER=anthropic) to use it instead." >&2
        fi
    elif echo "$available_providers" | grep -q "groq"; then
        AI_PROVIDER="groq"
        AUTO_DETECTED=true
    elif echo "$available_providers" | grep -q "anthropic"; then
        AI_PROVIDER="anthropic"
        AUTO_DETECTED=true
    elif echo "$available_providers" | grep -q "openai"; then
        AI_PROVIDER="openai"
        AUTO_DETECTED=true
    fi
fi

