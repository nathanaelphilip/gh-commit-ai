# Handle changelog mode
if [ "$CHANGELOG_MODE" = true ]; then
    echo "Generating changelog"
    generate_changelog "$CHANGELOG_SINCE" "$CHANGELOG_FORMAT"
    exit 0
fi

# Handle split mode
if [ "$SPLIT_MODE" = true ]; then
    suggest_commit_splits "$SPLIT_THRESHOLD" "$SPLIT_DRY_RUN"
    exit 0
fi

# Handle amend mode differently
if [ "$AMEND" = true ]; then
    # Check if there's at least one commit
    if ! git rev-parse HEAD >/dev/null 2>&1; then
        echo -e "${RED}Error: No commits to amend"
        exit 1
    fi

    # Create secure temp files for inter-process communication
    status_file=$(create_secure_temp_file "gh-commit-ai-status") || exit 1
    stats_file=$(create_secure_temp_file "gh-commit-ai-stats") || { rm -f "$status_file"; exit 1; }
    diff_file=$(create_secure_temp_file "gh-commit-ai-diff") || { rm -f "$status_file" "$stats_file"; exit 1; }
    size_file=$(create_secure_temp_file "gh-commit-ai-size") || { rm -f "$status_file" "$stats_file" "$diff_file"; exit 1; }

    # Get the changes from the last commit with loading animation (optimized - minimal git calls)
    (
        # Get all needed data with just two git calls (show for diff, numstat for stats)
        SHOW_OUTPUT=$(eval "git show --numstat HEAD $GIT_EXCLUDE_PATTERN")

        # Extract stats from numstat output (before the diff starts)
        GIT_STATS=$(echo "$SHOW_OUTPUT" | awk '/^[0-9]+\t[0-9]+\t/ {print $3}' | head -10 | awk '{print "M " $0}')

        # Extract full diff (after numstat section)
        FULL_DIFF=$(echo "$SHOW_OUTPUT" | awk '/^diff --git/,0')

        # Extract file list for status
        GIT_STATUS=$(echo "$SHOW_OUTPUT" | awk '/^diff --git/ {print "M " $4}' | sed 's|^M b/|M |')

        GIT_DIFF=$(smart_sample_diff "$FULL_DIFF" "$DIFF_MAX_LINES")

        # Calculate commit size (lines added + deleted) from numstat
        COMMIT_SIZE=$(echo "$SHOW_OUTPUT" | awk '/^[0-9]+\t[0-9]+\t/ {added+=$1; deleted+=$2} END {print added+deleted}')

        # Export to temp file for parent process
        echo "$GIT_STATUS" > "$status_file"
        echo "$GIT_STATS" > "$stats_file"
        echo "$GIT_DIFF" > "$diff_file"
        echo "$COMMIT_SIZE" > "$size_file"
    ) &
    ANALYZE_PID=$!

    show_spinner "$ANALYZE_PID" "Analyzing last commit"
    wait "$ANALYZE_PID"

    # Read results from temp files
    GIT_STATUS=$(cat "$status_file" 2>/dev/null || echo "")
    GIT_STATS=$(cat "$stats_file" 2>/dev/null || echo "")
    GIT_DIFF=$(cat "$diff_file" 2>/dev/null || echo "")
    COMMIT_SIZE=$(cat "$size_file" 2>/dev/null || echo "0")
    rm -f "$status_file" "$stats_file" "$diff_file" "$size_file"

    echo "✓ Commit analyzed"
else
    # Check if there are changes to commit (exclude lock files from check)
    if eval "git diff --cached --quiet $GIT_EXCLUDE_PATTERN" && eval "git diff --quiet $GIT_EXCLUDE_PATTERN"; then
        echo "No changes to commit"
        exit 0
    fi

    # Create secure temp files for inter-process communication
    status_file=$(create_secure_temp_file "gh-commit-ai-status") || exit 1
    stats_file=$(create_secure_temp_file "gh-commit-ai-stats") || { rm -f "$status_file"; exit 1; }
    diff_file=$(create_secure_temp_file "gh-commit-ai-diff") || { rm -f "$status_file" "$stats_file"; exit 1; }
    size_file=$(create_secure_temp_file "gh-commit-ai-size") || { rm -f "$status_file" "$stats_file" "$diff_file"; exit 1; }

    # Get git status and diff with loading animation (optimized - minimal git calls)
    (
        # PERFORMANCE OPTIMIZATION: Use single git diff call with --numstat to get everything
        # This avoids redundant git diff calls (44% faster)
        FULL_NUMSTAT_OUTPUT=$(eval "git diff --cached --numstat $GIT_EXCLUDE_PATTERN" 2>/dev/null || echo "")
        if [ -z "$FULL_NUMSTAT_OUTPUT" ]; then
            FULL_NUMSTAT_OUTPUT=$(eval "git diff --numstat $GIT_EXCLUDE_PATTERN" 2>/dev/null || echo "")
            IS_STAGED=false
        else
            IS_STAGED=true
        fi

        # Extract numstat data (header lines before the diff)
        NUMSTAT_DATA=$(echo "$FULL_NUMSTAT_OUTPUT" | awk '/^[0-9]+\t[0-9]+\t/ {print}')

        # Generate GIT_STATUS from numstat data (avoids separate git status call)
        GIT_STATUS=$(echo "$NUMSTAT_DATA" | awk '{print "M " $3}')

        # Extract file list for GIT_STATS (first 10 files)
        GIT_STATS=$(echo "$NUMSTAT_DATA" | awk '{print $3}' | head -10 | awk '{print "M " $0}')

        # Get full diff for AI (single call)
        if [ "$IS_STAGED" = "true" ]; then
            FULL_DIFF=$(eval "git diff --cached $GIT_EXCLUDE_PATTERN" 2>/dev/null)
        else
            FULL_DIFF=$(eval "git diff $GIT_EXCLUDE_PATTERN" 2>/dev/null)
        fi
        GIT_DIFF=$(smart_sample_diff "$FULL_DIFF" "$DIFF_MAX_LINES")

        # Calculate commit size from numstat
        COMMIT_SIZE=$(echo "$NUMSTAT_DATA" | awk '{added+=$1; deleted+=$2} END {print added+deleted}')

        # Export to temp file for parent process
        echo "$GIT_STATUS" > "$status_file"
        echo "$GIT_STATS" > "$stats_file"
        echo "$GIT_DIFF" > "$diff_file"
        echo "$COMMIT_SIZE" > "$size_file"
    ) &
    ANALYZE_PID=$!

    show_spinner "$ANALYZE_PID" "Analyzing changes"
    wait "$ANALYZE_PID"

    # Read results from temp files
    GIT_STATUS=$(cat "$status_file" 2>/dev/null || echo "")
    GIT_STATS=$(cat "$stats_file" 2>/dev/null || echo "")
    GIT_DIFF=$(cat "$diff_file" 2>/dev/null || echo "")
    COMMIT_SIZE=$(cat "$size_file" 2>/dev/null || echo "0")
    rm -f "$status_file" "$stats_file" "$diff_file" "$size_file"

    echo "✓ Changes analyzed"

    # Show auto-detection info if applicable
    if [ "$AUTO_DETECTED" = "true" ]; then
        case "$AI_PROVIDER" in
            ollama)
                echo "Using Ollama with model: $OLLAMA_MODEL (auto-detected)"
                ;;
            anthropic)
                echo "Using Anthropic Claude (auto-detected)"
                ;;
            openai)
                echo "Using OpenAI (auto-detected)"
                ;;
        esac
    fi
fi

# Extract ticket number from branch name (e.g., feature/ABC-123-description → ABC-123)
# Note: BRANCH_NAME already cached earlier for performance
TICKET_NUMBER=""
if [ -n "$BRANCH_NAME" ]; then
    TICKET_NUMBER=$(echo "$BRANCH_NAME" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1)
fi

# Detect suggested type from branch name
SUGGESTED_TYPE=""
if [ -n "$BRANCH_NAME" ]; then
    case "$BRANCH_NAME" in
        feat/*|feature/*) SUGGESTED_TYPE="feat" ;;
        fix/*|bugfix/*|hotfix/*) SUGGESTED_TYPE="fix" ;;
        docs/*|doc/*) SUGGESTED_TYPE="docs" ;;
        style/*) SUGGESTED_TYPE="style" ;;
        refactor/*) SUGGESTED_TYPE="refactor" ;;
        test/*|tests/*) SUGGESTED_TYPE="test" ;;
        chore/*) SUGGESTED_TYPE="chore" ;;
    esac
fi

# Smart type detection based on changed files and content
detect_smart_type() {
    local files="$1"
    local diff="$2"

    # Get list of changed files (extract filenames from git status)
    local changed_files=$(echo "$files" | awk '{print $NF}')

    # Count different file types
    local doc_count=0
    local test_count=0
    local config_count=0
    local code_count=0
    local total_count=0

    while IFS= read -r file; do
        [ -z "$file" ] && continue
        total_count=$((total_count + 1))

        # Check for documentation files
        if [[ "$file" =~ \.(md|txt|rst|adoc)$ ]] || [[ "$file" =~ ^docs?/ ]] || [[ "$file" =~ ^documentation/ ]] || [[ "$file" =~ README|CHANGELOG|LICENSE ]]; then
            doc_count=$((doc_count + 1))
        # Check for test files
        elif [[ "$file" =~ ^tests?/ ]] || [[ "$file" =~ \.(test|spec)\. ]] || [[ "$file" =~ [_-](test|spec)\. ]] || [[ "$file" =~ __tests?__/ ]]; then
            test_count=$((test_count + 1))
        # Check for config files
        elif [[ "$file" =~ \.(json|ya?ml|toml|ini|conf|config)$ ]] || [[ "$file" =~ ^\..*rc$ ]] || [[ "$file" =~ package\.json|setup\.py|Cargo\.toml|go\.mod ]]; then
            config_count=$((config_count + 1))
        else
            code_count=$((code_count + 1))
        fi
    done <<< "$changed_files"

    # Return early if no files detected
    [ $total_count -eq 0 ] && return

    # If only docs changed, suggest docs
    if [ $doc_count -gt 0 ] && [ $test_count -eq 0 ] && [ $code_count -eq 0 ]; then
        echo "docs"
        return
    fi

    # If only tests changed, suggest test
    if [ $test_count -gt 0 ] && [ $doc_count -eq 0 ] && [ $code_count -eq 0 ]; then
        echo "test"
        return
    fi

    # Check for version bumps in config files
    if [ $config_count -gt 0 ]; then
        if echo "$diff" | grep -qE '^\+.*"version".*:' || \
           echo "$diff" | grep -qE '^\+.*version\s*='; then
            echo "chore"
            return
        fi
    fi

    # Check for bug-related keywords in diff
    if echo "$diff" | grep -qiE '^\+.*(fix|bug|issue|error|crash|problem|broken|incorrect|wrong)'; then
        echo "fix"
        return
    fi

    # No strong signal detected
    echo ""
}

# Run smart type detection
SMART_TYPE=$(detect_smart_type "$GIT_STATUS" "$GIT_DIFF")

# Track where the suggestion came from for better prompting
TYPE_SOURCE=""
if [ -n "$SUGGESTED_TYPE" ]; then
    TYPE_SOURCE="branch name"
fi

# Smart type detection can override if branch gives no suggestion
if [ -z "$SUGGESTED_TYPE" ] && [ -n "$SMART_TYPE" ]; then
    SUGGESTED_TYPE="$SMART_TYPE"
    TYPE_SOURCE="file analysis"
elif [ -n "$SMART_TYPE" ] && [ "$SMART_TYPE" != "$SUGGESTED_TYPE" ]; then
    # Both exist but differ - mention both in context
    TYPE_SOURCE="branch name (smart detection also suggests: $SMART_TYPE)"
fi

# Override with forced type if provided
if [ -n "$FORCED_TYPE" ]; then
    SUGGESTED_TYPE="$FORCED_TYPE"
    TYPE_SOURCE="user-specified via --type flag"
fi

# Detect breaking changes
detect_breaking_changes() {
    local diff="$1"
    local breaking_detected=false
    local breaking_reason=""

    # Check for explicit breaking change keywords in diff
    if echo "$diff" | grep -qiE '^\+.*(BREAKING CHANGE|breaking change|BREAKING:|breaking:)'; then
        breaking_detected=true
        breaking_reason="explicit breaking change keyword in diff"
        echo "true|$breaking_reason"
        return
    fi

    # Check for removal of public APIs/exports
    # Look for lines being removed that contain export, public, or function definitions
    if echo "$diff" | grep -qE '^-.*\b(export (function|class|const|let|var|default|interface|type)|public (class|function|static|final)|def [a-zA-Z_]|function [a-zA-Z_])'; then
        breaking_detected=true
        breaking_reason="removal of public API/function"
        echo "true|$breaking_reason"
        return
    fi

    # Check for major version bumps (0.x.x -> 1.0.0, 1.x.x -> 2.0.0, etc.)
    # Look for version changes in package.json, setup.py, Cargo.toml, etc.
    local old_version=$(echo "$diff" | grep -E '^-.*"version".*:|^-.*version\s*=' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    local new_version=$(echo "$diff" | grep -E '^\+.*"version".*:|^\+.*version\s*=' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    if [ -n "$old_version" ] && [ -n "$new_version" ]; then
        local old_major=$(echo "$old_version" | cut -d. -f1)
        local new_major=$(echo "$new_version" | cut -d. -f1)

        if [ "$new_major" -gt "$old_major" ]; then
            breaking_detected=true
            breaking_reason="major version bump ($old_version -> $new_version)"
            echo "true|$breaking_reason"
            return
        fi
    fi

    # Check for signature changes (parameter removal/change)
    # Only flag if we can identify the SAME function being modified
    # Look for function name patterns to ensure we're comparing the same function
    local removed_functions=$(echo "$diff" | grep -E '^-.*\b(function |def |const |let |var |export (function|const|let|var)) [a-zA-Z_][a-zA-Z0-9_]*\s*\(' | sed 's/^-.*\b\(function\|def\|const\|let\|var\|export\) \+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\2/' | sort)
    local added_functions=$(echo "$diff" | grep -E '^\+.*\b(function |def |const |let |var |export (function|const|let|var)) [a-zA-Z_][a-zA-Z0-9_]*\s*\(' | sed 's/^\+.*\b\(function\|def\|const\|let\|var\|export\) \+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\2/' | sort)

    # Find functions that appear in both removed and added (same name = modified function)
    local modified_functions=$(comm -12 <(echo "$removed_functions") <(echo "$added_functions") 2>/dev/null)

    if [ -n "$modified_functions" ]; then
        # Found functions with same name being modified - check if parameters reduced
        while IFS= read -r func_name; do
            [ -z "$func_name" ] && continue

            local removed_sig=$(echo "$diff" | grep -E "^-.*\b(function |def |const |let |var |export .*) ${func_name}\s*\(" | head -1)
            local added_sig=$(echo "$diff" | grep -E "^\+.*\b(function |def |const |let |var |export .*) ${func_name}\s*\(" | head -1)

            if [ -n "$removed_sig" ] && [ -n "$added_sig" ]; then
                # Extract parameter lists
                local removed_params=$(echo "$removed_sig" | grep -oE '\([^)]*\)' | head -1)
                local added_params=$(echo "$added_sig" | grep -oE '\([^)]*\)' | head -1)

                # Count parameters (rough heuristic using commas)
                local old_count=$(echo "$removed_params" | tr -cd ',' | wc -c)
                local new_count=$(echo "$added_params" | tr -cd ',' | wc -c)

                # Only flag if parameters were removed (breaking change)
                if [ "$new_count" -lt "$old_count" ]; then
                    breaking_detected=true
                    breaking_reason="function '${func_name}' signature changed (parameters reduced)"
                    echo "true|$breaking_reason"
                    return
                fi
            fi
        done <<< "$modified_functions"
    fi

    echo "false|"
}

# Run breaking change detection (skip for docs-only commits - no code changes)
if [ "$SMART_TYPE" = "docs" ]; then
    # Docs-only commits can't have breaking changes
    BREAKING_RESULT="false|"
else
    BREAKING_RESULT=$(detect_breaking_changes "$GIT_DIFF")
fi
IS_BREAKING=$(echo "$BREAKING_RESULT" | cut -d'|' -f1)
BREAKING_REASON=$(echo "$BREAKING_RESULT" | cut -d'|' -f2)

# Analyze commit history to learn repository patterns
analyze_commit_history() {
    # Check if we should learn from history
    if [ "$LEARN_FROM_HISTORY" != "true" ]; then
        echo ""
        return
    fi

    # Check cache first (keyed by latest commit hash)
    local latest_commit=$(git rev-parse HEAD 2>/dev/null || echo "")
    if [ -n "$latest_commit" ]; then
        local cached=$(get_cache "commit-history-${latest_commit}" 3600 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$cached" ]; then
            echo "$cached"
            return
        fi
    fi

    # Get last 50 commits (or less if repo is new)
    local commits=$(git log --pretty=format:"%s" -n 50 2>/dev/null)

    if [ -z "$commits" ]; then
        echo ""
        return
    fi

    local total_commits=$(echo "$commits" | wc -l | LC_ALL=C tr -d ' ')

    # Return early if very few commits
    if [ "$total_commits" -lt 5 ]; then
        echo ""
        return
    fi

    # Detect emoji usage
    local emoji_count=$(echo "$commits" | grep -cE '[\x{1F600}-\x{1F64F}\x{1F300}-\x{1F5FF}\x{1F680}-\x{1F6FF}\x{1F1E0}-\x{1F1FF}\x{2600}-\x{26FF}\x{2700}-\x{27BF}]|:[a-z_]+:' 2>/dev/null || echo "0")
    local uses_emoji=false
    if [ "$emoji_count" -gt 0 ]; then
        uses_emoji=true
    fi

    # Detect scope usage (look for parentheses after type)
    local scope_count=$(echo "$commits" | grep -cE '^[a-z]+\([a-z]+\):' 2>/dev/null || echo "0")
    scope_count=$(echo "$scope_count" | LC_ALL=C tr -d '\n' | LC_ALL=C tr -d ' ')
    local uses_scopes=false
    local scope_percentage=0
    if [ "$scope_count" -gt 0 ] 2>/dev/null; then
        uses_scopes=true
        scope_percentage=$((scope_count * 100 / total_commits))
    fi

    # Detect conventional commit types used
    local feat_count=$(echo "$commits" | grep -ciE '^feat[(!:]' 2>/dev/null || echo "0")
    feat_count=$(echo "$feat_count" | LC_ALL=C tr -d '\n' | LC_ALL=C tr -d ' ')
    local fix_count=$(echo "$commits" | grep -ciE '^fix[(!:]' 2>/dev/null || echo "0")
    fix_count=$(echo "$fix_count" | LC_ALL=C tr -d '\n' | LC_ALL=C tr -d ' ')
    local docs_count=$(echo "$commits" | grep -ciE '^docs[(!:]' 2>/dev/null || echo "0")
    docs_count=$(echo "$docs_count" | LC_ALL=C tr -d '\n' | LC_ALL=C tr -d ' ')
    local chore_count=$(echo "$commits" | grep -ciE '^chore[(!:]' 2>/dev/null || echo "0")
    chore_count=$(echo "$chore_count" | LC_ALL=C tr -d '\n' | LC_ALL=C tr -d ' ')
    local refactor_count=$(echo "$commits" | grep -ciE '^refactor[(!:]' 2>/dev/null || echo "0")
    refactor_count=$(echo "$refactor_count" | LC_ALL=C tr -d '\n' | LC_ALL=C tr -d ' ')
    local test_count=$(echo "$commits" | grep -ciE '^test[(!:]' 2>/dev/null || echo "0")
    test_count=$(echo "$test_count" | LC_ALL=C tr -d '\n' | LC_ALL=C tr -d ' ')
    local style_count=$(echo "$commits" | grep -ciE '^style[(!:]' 2>/dev/null || echo "0")
    style_count=$(echo "$style_count" | LC_ALL=C tr -d '\n' | LC_ALL=C tr -d ' ')

    # Detect capitalization preference (first word after type)
    local lowercase_count=$(echo "$commits" | grep -cE '^[a-z]+(\([a-z]+\))?!?: [a-z]' 2>/dev/null || echo "0")
    lowercase_count=$(echo "$lowercase_count" | LC_ALL=C tr -d '\n' | LC_ALL=C tr -d ' ')
    local uppercase_count=$(echo "$commits" | grep -cE '^[a-z]+(\([a-z]+\))?!?: [A-Z]' 2>/dev/null || echo "0")
    uppercase_count=$(echo "$uppercase_count" | LC_ALL=C tr -d '\n' | LC_ALL=C tr -d ' ')
    local prefers_lowercase=true
    if [ "$uppercase_count" -gt "$lowercase_count" ] 2>/dev/null; then
        prefers_lowercase=false
    fi

    # Detect breaking change usage
    local breaking_count=$(echo "$commits" | grep -cE '!:' 2>/dev/null || echo "0")
    breaking_count=$(echo "$breaking_count" | LC_ALL=C tr -d '\n' | LC_ALL=C tr -d ' ')
    local uses_breaking_changes=false
    if [ "$breaking_count" -gt 0 ]; then
        uses_breaking_changes=true
    fi

    # Build history insights
    local insights="Repository commit style (based on last $total_commits commits):"

    # Report scope usage
    if [ "$uses_scopes" = "true" ]; then
        insights="$insights\n- Uses scopes in ${scope_percentage}% of commits"
    else
        insights="$insights\n- Rarely uses scopes"
    fi

    # Report type preferences
    local most_common_type="feat"
    local max_count=$feat_count
    [ "$fix_count" -gt "$max_count" ] 2>/dev/null && most_common_type="fix" && max_count=$fix_count
    [ "$docs_count" -gt "$max_count" ] 2>/dev/null && most_common_type="docs" && max_count=$docs_count
    [ "$chore_count" -gt "$max_count" ] 2>/dev/null && most_common_type="chore" && max_count=$chore_count

    insights="$insights\n- Most common type: $most_common_type"

    # Report capitalization
    if [ "$prefers_lowercase" = "true" ]; then
        insights="$insights\n- Prefers lowercase commit messages"
    else
        insights="$insights\n- Uses capitalized commit messages"
    fi

    # Report emoji usage
    if [ "$uses_emoji" = "true" ]; then
        insights="$insights\n- Sometimes uses emojis"
    fi

    # Report breaking change usage
    if [ "$uses_breaking_changes" = "true" ]; then
        insights="$insights\n- Uses breaking change notation (!) when appropriate"
    fi

    insights="$insights\n\nMatch this repository's style in your commit message."

    # Cache the result
    if [ -n "$latest_commit" ]; then
        set_cache "commit-history-${latest_commit}" "$insights" 2>/dev/null
    fi

    echo -e "$insights"
}

# Detect WordPress plugin/theme updates
# Returns "plugin:name" or "theme:name" if any files are in plugin/theme directories
detect_wordpress_plugin_update() {
    local files="$1"
    local plugin_names=()
    local theme_names=()
    local total_files=0
    local plugin_files=0
    local theme_files=0
    local single_plugin_threshold=80  # 80% threshold for bulk update detection

    # Parse each filename and check if it's in a plugin/theme directory
    while IFS= read -r line; do
        # Skip empty lines
        [ -z "$line" ] && continue

        # Extract filename (remove git status prefix like "M " or "A ")
        local file=$(echo "$line" | awk '{print $NF}')

        # Convert to lowercase for pattern matching
        local file_lower=$(echo "$file" | tr '[:upper:]' '[:lower:]')

        total_files=$((total_files + 1))

        # Check if file is in wp-content/plugins/
        if [[ "$file_lower" =~ wp-content/plugins/([^/]+) ]]; then
            local plugin_name="${BASH_REMATCH[1]}"

            # Add plugin name to array if not already there
            if [[ ! " ${plugin_names[@]} " =~ " ${plugin_name} " ]]; then
                plugin_names+=("$plugin_name")
            fi

            plugin_files=$((plugin_files + 1))
        fi

        # Check if file is in wp-content/themes/
        if [[ "$file_lower" =~ wp-content/themes/([^/]+) ]]; then
            local theme_name="${BASH_REMATCH[1]}"

            # Add theme name to array if not already there
            if [[ ! " ${theme_names[@]} " =~ " ${theme_name} " ]]; then
                theme_names+=("$theme_name")
            fi

            theme_files=$((theme_files + 1))
        fi
    done <<< "$files"

    # Check for single plugin bulk update (80%+ of files in one plugin)
    if [ ${#plugin_names[@]} -eq 1 ] && [ $total_files -gt 0 ]; then
        local plugin_name="${plugin_names[0]}"
        local percentage=$((plugin_files * 100 / total_files))

        if [ $percentage -ge $single_plugin_threshold ]; then
            echo "plugin-bulk:${plugin_name}"
            return 0
        fi
    fi

    # If any plugin files found, return plugin names (comma-separated if multiple)
    if [ ${#plugin_names[@]} -gt 0 ]; then
        # Join plugin names with commas
        local plugin_list=$(IFS=,; echo "${plugin_names[*]}")
        echo "plugin:${plugin_list}"
        return 0
    fi

    # If any theme files found, return theme names (comma-separated if multiple)
    if [ ${#theme_names[@]} -gt 0 ]; then
        # Join theme names with commas
        local theme_list=$(IFS=,; echo "${theme_names[*]}")
        echo "theme:${theme_list}"
        return 0
    fi

    return 1
}

