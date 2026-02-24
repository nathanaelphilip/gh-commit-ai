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

    # Check Ollama (running and has models)
    if curl -s --connect-timeout 1 "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
        local models=$(curl -s "$OLLAMA_HOST/api/tags" 2>/dev/null | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' | wc -l)
        if [ "$models" -gt 0 ]; then
            available="${available}ollama "
        fi
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

    # Query Ollama for available models
    local models=$(curl -s "$OLLAMA_HOST/api/tags" 2>/dev/null | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//')

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

# Auto-select provider if set to "auto"
AUTO_DETECTED=false
if [ "$AI_PROVIDER" = "auto" ]; then
    # Detect what's available
    available_providers=$(detect_available_providers)

    if [ -z "$available_providers" ]; then
        echo -e "${RED}Error: No AI providers available${NC}"
        echo ""
        echo "Available options:"
        echo "  1. Install Ollama (free, local): https://ollama.ai"
        echo "     Then run: ollama pull qwen2.5-coder:7b"
        echo ""
        echo "  2. Set up Groq API (ultra-fast, generous free tier):"
        echo "     export GROQ_API_KEY=\"gsk-...\""
        echo "     Get your key from: https://console.groq.com/keys"
        echo ""
        echo "  3. Set up Anthropic API:"
        echo "     export ANTHROPIC_API_KEY=\"sk-ant-...\""
        echo ""
        echo "  4. Set up OpenAI API:"
        echo "     export OPENAI_API_KEY=\"sk-proj-...\""
        exit 1
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

