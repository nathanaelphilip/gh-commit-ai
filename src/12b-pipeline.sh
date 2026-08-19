# Build Stage 1 analysis prompt for two-model pipeline
# Sends diff and code context to a code-specialized model for structured analysis
build_analysis_prompt() {
    cat <<ANALYSIS_PROMPT_EOF
You are a code analysis tool. Analyze the following git changes and produce a structured summary.

=== GIT CHANGES ===

$BRANCH_CONTEXT

$WP_CONTEXT
$FILE_CONTEXT
$FUNCTION_CONTEXT
$SEMANTIC_ANALYSIS
$FILE_RELATIONSHIPS

=== FILES CHANGED ===
$GIT_STATUS

$FILE_SUMMARIES

Stats:
$GIT_STATS

Diff:
$GIT_DIFF

=== INSTRUCTIONS ===

Produce a structured summary using this exact format (one field per line):

TYPE: <one of: feat, fix, docs, style, refactor, test, chore, perf, ci, build, revert>
SCOPE: <short noun for area changed, or NONE>
BREAKING: <true or false>
BREAKING_REASON: <explanation if breaking, or NONE>
SUMMARY: <one-line summary of the overall change, max 50 chars, imperative mood, lowercase>
CHANGES:
- <change 1, max 18 words, imperative mood>
- <change 2, max 18 words, imperative mood>
- <change 3, max 18 words, imperative mood>
KEY_FUNCTIONS: <comma-separated list of important functions/classes modified, or NONE>
CONTEXT: <one sentence explaining why this change matters or what it enables>

RULES:
- TYPE must be exactly one of the listed values
- SUMMARY must be lowercase, imperative mood ("add" not "added"), max 50 chars
- Each CHANGE bullet must be max 18 words, imperative mood
- Include 2-8 CHANGE bullets covering all significant modifications
- KEY_FUNCTIONS should list actual function/class names from the diff
- Be specific: mention file areas, function names, and technical details
- Do NOT include markdown formatting, code fences, or explanations outside the format
ANALYSIS_PROMPT_EOF
}

# Build Stage 2 synthesis prompt for two-model pipeline
# Takes structured analysis output and formats it into a proper commit message
build_synthesis_prompt() {
    local analysis_output="$1"

    cat <<SYNTHESIS_PROMPT_EOF
You are a commit message writer. Convert the following structured analysis into a properly formatted conventional commit message.

=== ANALYSIS ===
$analysis_output
=== END ANALYSIS ===

$SCOPE_INSTRUCTION

RULES:
- Summary line: max 50 chars, lowercase (except acronyms like API, HTTP, JSON, JWT, SQL)
- Each bullet: max 18 words, imperative mood
- Include WHY/impact/technical details when they add value
- ONE change per bullet line
- NO paragraphs, NO multiple sentences per bullet
- Use imperative mood: add/fix not added/fixed
- Ticket codes stay UPPERCASE: ABC-123 not abc-123
- Do NOT add ! unless BREAKING is true in the analysis
- Output ONLY the commit message, NO explanations, NO markdown, NO code fences$LANGUAGE_INSTRUCTION

$SCOPE_EXAMPLES

$FEW_SHOT_EXAMPLES
$REPO_EXAMPLES

$HISTORY_INSIGHTS

$CLOSING_INSTRUCTION$MULTIPLE_OPTIONS_INSTRUCTION
SYNTHESIS_PROMPT_EOF
}

# Normalize analysis output: convert literal \n to actual newlines
# AI providers often return text with literal \n instead of real newlines
normalize_analysis_output() {
    local text="$1"
    # Strip reasoning blocks first (analysis model may be a reasoning model),
    # then convert literal \n to actual newlines using printf %b
    text=$(strip_think_blocks "$text")
    printf "%b" "$text"
}

# Parse structured analysis output into components
# Returns 0 on success, 1 on failure (invalid/empty output)
parse_analysis_output() {
    local analysis="$1"

    # Normalize: convert literal \n to real newlines for grep
    local normalized
    normalized=$(normalize_analysis_output "$analysis")

    # Verify we got the required TYPE field at minimum
    if ! echo "$normalized" | grep -q "^TYPE:"; then
        return 1
    fi

    # Verify we got SUMMARY field
    if ! echo "$normalized" | grep -q "^SUMMARY:"; then
        return 1
    fi

    return 0
}

# Two-model pipeline orchestrator
# Calls Stage 1 (analysis) then Stage 2 (synthesis), accumulates tokens
# Returns 0 on success, 1 on failure (caller should fall back to single-model)
call_pipeline() {
    local original_prompt="$1"

    # Determine analysis provider (defaults to current AI_PROVIDER)
    local analysis_provider="${ANALYSIS_PROVIDER:-$AI_PROVIDER}"

    # Determine analysis model based on provider
    local analysis_model=""
    case "$analysis_provider" in
        ollama)
            analysis_model="${ANALYSIS_MODEL:-$OLLAMA_MODEL}"
            ;;
        anthropic)
            analysis_model="${ANALYSIS_ANTHROPIC_MODEL:-$ANTHROPIC_MODEL}"
            ;;
        openai)
            analysis_model="${ANALYSIS_OPENAI_MODEL:-$OPENAI_MODEL}"
            ;;
        groq)
            analysis_model="${ANALYSIS_GROQ_MODEL:-$GROQ_MODEL}"
            ;;
        *)
            echo "Pipeline: unknown analysis provider '$analysis_provider'" >&2
            return 1
            ;;
    esac

    # Determine synthesis provider and model (uses default provider/model)
    local synthesis_provider="$AI_PROVIDER"
    local synthesis_model=""
    case "$synthesis_provider" in
        ollama) synthesis_model="$OLLAMA_MODEL" ;;
        anthropic) synthesis_model="$ANTHROPIC_MODEL" ;;
        openai) synthesis_model="$OPENAI_MODEL" ;;
        groq) synthesis_model="$GROQ_MODEL" ;;
    esac

    # --- Stage 1: Analysis ---
    SPINNER_MESSAGE="Analyzing changes"
    # Save current state
    local saved_ollama_model="$OLLAMA_MODEL"
    local saved_anthropic_model="$ANTHROPIC_MODEL"
    local saved_openai_model="$OPENAI_MODEL"
    local saved_groq_model="$GROQ_MODEL"
    local saved_ai_provider="$AI_PROVIDER"
    local saved_verbose="${VERBOSE:-}"

    # Swap to analysis provider/model for stage 1
    # Verbose must be disabled because call_* functions output verbose info to stdout,
    # which would corrupt the captured analysis_output
    # Streaming stays enabled: the stream parser only shows a spinner (no raw tokens),
    # and streaming prevents curl timeout during slow model loading for large models
    AI_PROVIDER="$analysis_provider"
    VERBOSE="false"
    case "$analysis_provider" in
        ollama) OLLAMA_MODEL="$analysis_model" ;;
        anthropic) ANTHROPIC_MODEL="$analysis_model" ;;
        openai) OPENAI_MODEL="$analysis_model" ;;
        groq) GROQ_MODEL="$analysis_model" ;;
    esac

    # Build analysis prompt
    local analysis_prompt
    analysis_prompt=$(build_analysis_prompt)

    # Call provider for Stage 1
    local analysis_output=""
    local stage1_exit=0
    case "$AI_PROVIDER" in
        ollama)
            analysis_output=$(call_ollama "$analysis_prompt") || stage1_exit=$?
            ;;
        anthropic)
            analysis_output=$(call_anthropic "$analysis_prompt") || stage1_exit=$?
            ;;
        openai)
            analysis_output=$(call_openai "$analysis_prompt") || stage1_exit=$?
            ;;
        groq)
            analysis_output=$(call_groq "$analysis_prompt") || stage1_exit=$?
            ;;
    esac

    # Capture Stage 1 token counts
    local stage1_input_tokens=0
    local stage1_output_tokens=0
    local token_file="/tmp/gh-commit-ai-tokens-$$"
    if [ -f "${token_file}.input" ]; then
        stage1_input_tokens=$(cat "${token_file}.input" 2>/dev/null || echo "0")
        stage1_output_tokens=$(cat "${token_file}.output" 2>/dev/null || echo "0")
        rm -f "${token_file}.input" "${token_file}.output"
    fi

    # Restore original state
    OLLAMA_MODEL="$saved_ollama_model"
    ANTHROPIC_MODEL="$saved_anthropic_model"
    OPENAI_MODEL="$saved_openai_model"
    GROQ_MODEL="$saved_groq_model"
    AI_PROVIDER="$saved_ai_provider"
    VERBOSE="$saved_verbose"

    # Check if Stage 1 failed
    if [ "$stage1_exit" != "0" ] || [ -z "$analysis_output" ]; then
        echo "Pipeline Stage 1 failed, falling back to single-model..." >&2
        return 1
    fi

    # Normalize analysis output: convert literal \n to real newlines
    analysis_output=$(normalize_analysis_output "$analysis_output")

    # Validate analysis output has required structure
    if ! parse_analysis_output "$analysis_output"; then
        echo "Pipeline: analysis output missing required fields, falling back..." >&2
        if [ "$VERBOSE" = "true" ]; then
            echo "[Verbose] Stage 1 raw output:" >&2
            echo "$analysis_output" >&2
            echo "" >&2
        fi
        return 1
    fi

    # Show verbose analysis output between stages
    if [ "$VERBOSE" = "true" ]; then
        echo "" >&2
        echo "[Verbose] Stage 1 analysis output:" >&2
        echo "$analysis_output" >&2
        echo "" >&2
    fi

    # --- Stage 2: Synthesis ---
    SPINNER_MESSAGE="Generating"
    # Build synthesis prompt with analysis output
    local synthesis_prompt
    synthesis_prompt=$(build_synthesis_prompt "$analysis_output")

    # Call provider for Stage 2 (uses default provider/model, streaming restored)
    local synthesis_output=""
    local stage2_exit=0
    case "$AI_PROVIDER" in
        ollama)
            synthesis_output=$(call_ollama "$synthesis_prompt") || stage2_exit=$?
            ;;
        anthropic)
            synthesis_output=$(call_anthropic "$synthesis_prompt") || stage2_exit=$?
            ;;
        openai)
            synthesis_output=$(call_openai "$synthesis_prompt") || stage2_exit=$?
            ;;
        groq)
            synthesis_output=$(call_groq "$synthesis_prompt") || stage2_exit=$?
            ;;
    esac

    # Capture Stage 2 token counts
    local stage2_input_tokens=0
    local stage2_output_tokens=0
    if [ -f "${token_file}.input" ]; then
        stage2_input_tokens=$(cat "${token_file}.input" 2>/dev/null || echo "0")
        stage2_output_tokens=$(cat "${token_file}.output" 2>/dev/null || echo "0")
        rm -f "${token_file}.input" "${token_file}.output"
    fi

    # Accumulate total token counts and write back for cost tracking
    local total_input=$((stage1_input_tokens + stage2_input_tokens))
    local total_output=$((stage1_output_tokens + stage2_output_tokens))
    echo "$total_input" > "${token_file}.input"
    echo "$total_output" > "${token_file}.output"

    # Show per-stage breakdown in verbose mode
    if [ "$VERBOSE" = "true" ]; then
        echo "" >&2
        echo "[Verbose] Pipeline token usage:" >&2
        echo "  Stage 1 ($analysis_provider/$analysis_model): ${stage1_input_tokens} input, ${stage1_output_tokens} output" >&2
        echo "  Stage 2 ($synthesis_provider/$synthesis_model): ${stage2_input_tokens} input, ${stage2_output_tokens} output" >&2
        echo "  Total: ${total_input} input, ${total_output} output" >&2
    fi

    # Check if Stage 2 failed
    if [ "$stage2_exit" != "0" ] || [ -z "$synthesis_output" ]; then
        echo "Pipeline Stage 2 failed, falling back to single-model..." >&2
        return 1
    fi

    echo "$synthesis_output"
    return 0
}

