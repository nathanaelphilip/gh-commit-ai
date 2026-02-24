# ============================================================================
# PARALLEL ANALYSIS - Run all analysis functions simultaneously for speed
# ============================================================================

# Create temp files for parallel job outputs
TEMP_HISTORY="${CACHE_DIR}/temp_history_$$"
TEMP_EXAMPLES="${CACHE_DIR}/temp_examples_$$"
TEMP_CONTEXTS="${CACHE_DIR}/temp_contexts_$$"
TEMP_FUNCTIONS="${CACHE_DIR}/temp_functions_$$"
TEMP_CHANGES="${CACHE_DIR}/temp_changes_$$"
TEMP_SUMMARIES="${CACHE_DIR}/temp_summaries_$$"
TEMP_RELATIONSHIPS="${CACHE_DIR}/temp_relationships_$$"
TEMP_WP_FUNCTIONS="${CACHE_DIR}/temp_wp_functions_$$"

# Determine if this is a small commit that can skip expensive analysis
SKIP_EXPENSIVE_ANALYSIS=false
COMMIT_SIZE_INT=$(echo "${COMMIT_SIZE:-0}" | tr -d ' ')
if [ "$COMMIT_SIZE_INT" -lt "$ANALYSIS_THRESHOLD" ] && [ "$COMMIT_SIZE_INT" -gt 0 ]; then
    SKIP_EXPENSIVE_ANALYSIS=true
fi

# Spawn all analysis jobs in parallel (background)
# Skip expensive operations for small commits to improve speed
PARALLEL_JOBS=0

if [ "$LEARN_FROM_HISTORY" = "true" ]; then
    analyze_commit_history > "$TEMP_HISTORY" 2>/dev/null &
    get_best_commit_examples > "$TEMP_EXAMPLES" 2>/dev/null &
    ((PARALLEL_JOBS+=2))
fi

# Lightweight analysis (always run)
extract_file_context "$GIT_STATUS" > "$TEMP_CONTEXTS" 2>/dev/null &
generate_file_summaries "$GIT_STATUS" > "$TEMP_SUMMARIES" 2>/dev/null &
((PARALLEL_JOBS+=2))

# Expensive analysis (skip for small commits)
if [ "$SKIP_EXPENSIVE_ANALYSIS" = false ]; then
    extract_changed_functions "$GIT_DIFF" > "$TEMP_FUNCTIONS" 2>/dev/null &
    analyze_change_type "$GIT_DIFF" > "$TEMP_CHANGES" 2>/dev/null &
    detect_file_relationships "$GIT_STATUS" > "$TEMP_RELATIONSHIPS" 2>/dev/null &
    extract_wordpress_function_calls "$GIT_DIFF" > "$TEMP_WP_FUNCTIONS" 2>/dev/null &
    ((PARALLEL_JOBS+=4))
fi

# Show simple progress message for parallel analysis
if [ "$PARALLEL_JOBS" -gt 0 ]; then
    printf "⚡ Analyzing changes (%d parallel jobs)... " "$PARALLEL_JOBS" >&2
fi

# Wait for all background jobs to complete
wait

# Show completion message
if [ "$PARALLEL_JOBS" -gt 0 ]; then
    printf "✓\n" >&2
fi

# Read results from temp files
HISTORY_INSIGHTS=""
if [ "$LEARN_FROM_HISTORY" = "true" ] && [ -f "$TEMP_HISTORY" ]; then
    HISTORY_INSIGHTS=$(cat "$TEMP_HISTORY")
fi

REPO_EXAMPLES=""
if [ "$LEARN_FROM_HISTORY" = "true" ] && [ -f "$TEMP_EXAMPLES" ]; then
    REPO_EXAMPLES=$(cat "$TEMP_EXAMPLES")
    if [ -n "$REPO_EXAMPLES" ]; then
        REPO_EXAMPLES="

$REPO_EXAMPLES"
    fi
fi

FILE_CONTEXT=""
if [ -f "$TEMP_CONTEXTS" ]; then
    EXTRACTED_CONTEXTS=$(cat "$TEMP_CONTEXTS")
    if [ -n "$EXTRACTED_CONTEXTS" ]; then
        FILE_CONTEXT="
Detected code areas being modified: $EXTRACTED_CONTEXTS
Make sure your commit message reflects the specific area(s) being changed.
Analyze the diff content to understand the nature and purpose of the changes.
"
    fi
fi

FUNCTION_CONTEXT=""
if [ -f "$TEMP_FUNCTIONS" ]; then
    EXTRACTED_FUNCTIONS=$(cat "$TEMP_FUNCTIONS")
    if [ -n "$EXTRACTED_FUNCTIONS" ]; then
        FUNCTION_CONTEXT="
Modified functions/classes: $EXTRACTED_FUNCTIONS
Consider mentioning these in your commit message if they represent significant changes."
    fi
fi

SEMANTIC_ANALYSIS=""
if [ -f "$TEMP_CHANGES" ]; then
    CHANGE_TYPES=$(cat "$TEMP_CHANGES")
    if [ -n "$CHANGE_TYPES" ]; then
        SEMANTIC_ANALYSIS="
Type of changes detected: $CHANGE_TYPES"
    fi
fi

FILE_SUMMARIES=""
if [ -f "$TEMP_SUMMARIES" ]; then
    FILE_SUMMARIES=$(cat "$TEMP_SUMMARIES")
fi

FILE_RELATIONSHIPS=""
if [ -f "$TEMP_RELATIONSHIPS" ]; then
    DETECTED_RELATIONSHIPS=$(cat "$TEMP_RELATIONSHIPS")
    if [ -n "$DETECTED_RELATIONSHIPS" ]; then
        FILE_RELATIONSHIPS="
Related file changes: $DETECTED_RELATIONSHIPS"
    fi
fi

# Extract WordPress function calls and build context in parallel
# Start building WordPress context in background while we continue
TEMP_WP_CONTEXT=$(mktemp)
if [ -f "$TEMP_WP_FUNCTIONS" ]; then
    WP_FUNCTION_CALLS=$(cat "$TEMP_WP_FUNCTIONS")
    if [ -n "$WP_FUNCTION_CALLS" ]; then
        # Run build_wordpress_context in background
        build_wordpress_context "$WP_FUNCTION_CALLS" > "$TEMP_WP_CONTEXT" 2>/dev/null &
        WP_CONTEXT_PID=$!
    fi
fi

# Cleanup temp files (after reading WordPress functions)
rm -f "$TEMP_HISTORY" "$TEMP_EXAMPLES" "$TEMP_CONTEXTS" "$TEMP_FUNCTIONS" "$TEMP_CHANGES" "$TEMP_SUMMARIES" "$TEMP_RELATIONSHIPS" "$TEMP_WP_FUNCTIONS" 2>/dev/null

# Wait for WordPress context to finish building and read result
WP_CONTEXT=""
if [ -n "${WP_CONTEXT_PID:-}" ]; then
    wait "$WP_CONTEXT_PID" 2>/dev/null
    WP_CONTEXT=$(cat "$TEMP_WP_CONTEXT" 2>/dev/null || echo "")
    rm -f "$TEMP_WP_CONTEXT" 2>/dev/null
fi

# Check for WordPress plugin bulk update
WP_COMPONENT_TYPE=""
WP_COMPONENT_NAME=""
DETECTED_WP_COMPONENT=$(detect_wordpress_plugin_update "$GIT_STATUS" || true)
if [ $? -eq 0 ] && [ -n "$DETECTED_WP_COMPONENT" ]; then
    # Parse type:name format
    WP_COMPONENT_TYPE=$(echo "$DETECTED_WP_COMPONENT" | cut -d: -f1)
    WP_COMPONENT_NAME=$(echo "$DETECTED_WP_COMPONENT" | cut -d: -f2)
fi

