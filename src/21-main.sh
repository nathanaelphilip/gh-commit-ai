# Handle version suggestion mode
if [ "$VERSION_MODE" = true ]; then
    suggest_next_version "$CREATE_TAG" "$TAG_PREFIX"
    exit 0
fi

# Handle code review mode (needs AI functions defined above)
if [ "$CODE_REVIEW_MODE" = true ]; then
    generate_code_review "$REVIEW_STAGED_ONLY"
    exit 0
fi

# Handle PR description mode (needs AI functions defined above)
if [ "$PR_DESCRIPTION_MODE" = true ]; then
    generate_pr_description "$BASE_BRANCH" "$OUTPUT_FILE"
    exit 0
fi

# Check for recent message in history (within last 5 minutes)
RECOVERED_MESSAGE=""
if is_recent_message && [ "$PREVIEW" != true ] && [ "$DRY_RUN" != true ]; then
    LAST_MESSAGE=$(get_last_message)
    if [ -n "$LAST_MESSAGE" ]; then
        echo ""
        echo "💡 Found recent commit message from history:"
        echo ""
        DISPLAY_LAST=$(convert_newlines "$LAST_MESSAGE")
        printf "%s\n\n" "$DISPLAY_LAST"
        echo -n "Reuse this message? (y/n/r to regenerate): "
        read -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Reuse the message
            COMMIT_MSG="$LAST_MESSAGE"
            RECOVERED_MESSAGE="true"
        elif [[ $REPLY =~ ^[Rr]$ ]]; then
            # User wants to regenerate - continue normally
            echo "Regenerating commit message..."
            echo ""
        else
            # Cancel
            echo "Commit cancelled"
            exit 0
        fi
    fi
fi

# Call the appropriate AI provider (skip if message was recovered)
if [ "$RECOVERED_MESSAGE" != "true" ]; then
    # Caching with debug instrumentation
    CACHE_KEY=""
    CACHED_MSG=""

    # Debug logging function (only when CACHE_DEBUG=true)
    cache_debug() {
        if [ "$CACHE_DEBUG" = "true" ]; then
            # Cross-platform timestamp (BSD date doesn't support milliseconds)
            local timestamp=$(date +%H:%M:%S 2>/dev/null || date +%T)
            echo "[$timestamp] $*" >> "${CACHE_DIR}/debug.log"
        fi
    }

    # Initialize debug log
    if [ "$CACHE_DEBUG" = "true" ]; then
        echo "=== Cache Debug Log ===" > "${CACHE_DIR}/debug.log"
    fi

    # Generate cache key from diff (with timing and error handling)
    if [ "$DISABLE_CACHE" != "true" ]; then
        cache_debug "Starting cache key generation"

        # Use the already-generated GIT_DIFF variable to avoid redundant git calls
        if [ -n "$GIT_DIFF" ]; then
            cache_debug "Using GIT_DIFF for cache key (length: ${#GIT_DIFF})"
            CACHE_KEY=$(echo "$GIT_DIFF" | get_diff_hash 2>/dev/null)
        else
            cache_debug "No diff available, generating from git"
            if [ "$AMEND_MODE" = true ]; then
                CACHE_KEY=$(git show HEAD 2>/dev/null | get_diff_hash 2>/dev/null)
            else
                CACHE_KEY=$(git diff --cached 2>/dev/null | get_diff_hash 2>/dev/null)
            fi
        fi

        cache_debug "Cache key generated: $CACHE_KEY"

        # Check cache
        if [ -n "$CACHE_KEY" ]; then
            cache_debug "Checking cache for key: $CACHE_KEY"
            CACHED_MSG=$(get_cached_response "$CACHE_KEY" 2>/dev/null) || true
            if [ -n "$CACHED_MSG" ]; then
                cache_debug "Cache check complete (found: yes)"
            else
                cache_debug "Cache check complete (found: no)"
            fi
        else
            cache_debug "ERROR: Cache key is empty"
        fi
    else
        cache_debug "Cache disabled via DISABLE_CACHE"
    fi

    # Use cached message if available
    if [ -n "$CACHED_MSG" ]; then
        cache_debug "Using cached message"
        echo "✓ Using cached commit message"
        COMMIT_MSG="$CACHED_MSG"
    else
        cache_debug "No cache hit, calling AI provider: $AI_PROVIDER"

        # Call AI provider (with timing for analytics)
        ai_start_time=$(date +%s 2>/dev/null || echo "0")

        case "$AI_PROVIDER" in
            ollama)
                cache_debug "Calling call_ollama"
                COMMIT_MSG=$(call_ollama "$PROMPT")
                cache_debug "call_ollama returned (length: ${#COMMIT_MSG})"
                ;;
            anthropic)
                cache_debug "Calling call_anthropic"
                COMMIT_MSG=$(call_anthropic "$PROMPT")
                cache_debug "call_anthropic returned (length: ${#COMMIT_MSG})"
                ;;
            openai)
                cache_debug "Calling call_openai"
                COMMIT_MSG=$(call_openai "$PROMPT")
                cache_debug "call_openai returned (length: ${#COMMIT_MSG})"
                ;;
            groq)
                cache_debug "Calling call_groq"
                COMMIT_MSG=$(call_groq "$PROMPT")
                cache_debug "call_groq returned (length: ${#COMMIT_MSG})"
                ;;
            *)
                echo -e "${RED}Error: Unknown AI provider '$AI_PROVIDER'"
                echo "Supported providers: ollama, anthropic, openai, groq"
                exit 1
                ;;
        esac

        ai_end_time=$(date +%s 2>/dev/null || echo "0")
        ai_duration_ms=$(( (ai_end_time - ai_start_time) * 1000 ))

        # Read token counts from files (written by providers to solve subshell variable export)
        token_file="/tmp/gh-commit-ai-tokens-$$"
        if [ -f "${token_file}.input" ]; then
            INPUT_TOKENS=$(cat "${token_file}.input" 2>/dev/null || echo "0")
            OUTPUT_TOKENS=$(cat "${token_file}.output" 2>/dev/null || echo "0")
            rm -f "${token_file}.input" "${token_file}.output"
        fi

        # Determine current model for analytics
        current_model=""
        case "$AI_PROVIDER" in
            ollama) current_model="$OLLAMA_MODEL" ;;
            anthropic) current_model="$ANTHROPIC_MODEL" ;;
            openai) current_model="$OPENAI_MODEL" ;;
            groq) current_model="$GROQ_MODEL" ;;
        esac

        # Track analytics
        was_streaming="false"
        should_stream && was_streaming="true"
        track_analytics "$AI_PROVIDER" "$current_model" "${INPUT_TOKENS:-0}" "${OUTPUT_TOKENS:-0}" "0" "$ai_duration_ms" "commit" "false" "$was_streaming"

        # Save to cache (with error handling)
        if [ -n "$CACHE_KEY" ] && [ -n "$COMMIT_MSG" ] && [ "$DISABLE_CACHE" != "true" ]; then
            cache_debug "Saving to cache"
            save_cached_response "$CACHE_KEY" "$COMMIT_MSG" 2>/dev/null || cache_debug "ERROR: Failed to save cache"
            cache_debug "Cache save complete"
        fi
    fi

    cache_debug "AI provider section complete"
fi

# Strip markdown code fences and explanations if AI added them
# Remove lines that are just code fences and any explanatory text after the commit
COMMIT_MSG=$(echo "$COMMIT_MSG" | awk '
    /^```[a-zA-Z]*$/ { next }   # Skip opening fence line
    /^```$/ { next }             # Skip closing fence line
    /^\*\*explanation/ { exit }  # Stop at explanation section
    /^\*\*why/ { exit }          # Stop at why section
    /^\*\*note/ { exit }         # Stop at note section
    { print }
' | awk '
    # Remove trailing blank lines
    { lines[NR] = $0 }
    END {
        for (i = 1; i <= NR; i++) {
            if (i == NR) {
                # Last line - check if followed by blanks
                if (lines[i] != "") print lines[i]
            } else if (lines[i] != "" || lines[i+1] != "") {
                print lines[i]
            }
        }
    }
')

if [ -z "$COMMIT_MSG" ] || [ "$COMMIT_MSG" = "null" ]; then
    echo -e "${RED}Error: Failed to generate commit message"
    echo "Please check your API configuration and try again."
    exit 1
fi

# Handle multiple options mode
if [ "$MULTIPLE_OPTIONS" = "true" ]; then
    # Clean up any existing temp files
    rm -f /tmp/option_*.txt /tmp/reasoning_*.txt /tmp/ai_recommendation.txt 2>/dev/null

    # Parse options from response
    num_options=$(parse_multiple_options "$COMMIT_MSG")

    # Enforce lowercase on each option (unless disabled)
    if [ "$NO_LOWERCASE" != "true" ]; then
        for i in $(seq 1 $num_options); do
            if [ -f "/tmp/option_${i}.txt" ]; then
                option_content=$(cat "/tmp/option_${i}.txt")
                lowercased=$(enforce_lowercase "$option_content")
                echo "$lowercased" > "/tmp/option_${i}.txt"
            fi
        done
    fi

    # Auto-fix common formatting issues on each option (unless disabled)
    if [ "$AUTO_FIX" = "true" ]; then
        for i in $(seq 1 $num_options); do
            if [ -f "/tmp/option_${i}.txt" ]; then
                option_content=$(cat "/tmp/option_${i}.txt")
                fixed=$(auto_fix_message "$option_content")
                echo "$fixed" > "/tmp/option_${i}.txt"
            fi
        done
    fi

    # Apply template to each option if custom template exists
    if [ -f ".gh-commit-ai-template" ]; then
        PROJECT_TYPE=$(detect_project_type)
        TEMPLATE=$(load_template "$PROJECT_TYPE")
        for i in $(seq 1 $num_options); do
            if [ -f "/tmp/option_${i}.txt" ]; then
                option_content=$(cat "/tmp/option_${i}.txt")
                templated=$(apply_template "$TEMPLATE" "$option_content")
                echo "$templated" > "/tmp/option_${i}.txt"
            fi
        done
    fi

    # Display all options
    echo ""
    display_options "$num_options"

    # Show cost information for paid APIs
    if [ "$AI_PROVIDER" = "anthropic" ]; then
        calculate_cost "anthropic" "$ANTHROPIC_MODEL" "$INPUT_TOKENS" "$OUTPUT_TOKENS"
        echo ""
    elif [ "$AI_PROVIDER" = "openai" ]; then
        calculate_cost "openai" "$OPENAI_MODEL" "$INPUT_TOKENS" "$OUTPUT_TOKENS"
        echo ""
    fi

    # Get user selection
    selected=$(select_option "$num_options")

    if [ "$selected" = "cancelled" ]; then
        echo "Commit cancelled"
        rm -f /tmp/option_*.txt /tmp/reasoning_*.txt /tmp/ai_recommendation.txt 2>/dev/null
        exit 0
    fi

    # Load selected option
    COMMIT_MSG=$(cat "/tmp/option_${selected}.txt")
    rm -f /tmp/option_*.txt /tmp/reasoning_*.txt /tmp/ai_recommendation.txt 2>/dev/null

    # Save to message history
    save_message_history "$COMMIT_MSG"

    # Show selected message
    echo -e "\nSelected commit message:"
    echo "$COMMIT_MSG"
    echo ""
else
    # Single message mode - enforce lowercase (unless disabled)
    if [ "$NO_LOWERCASE" != "true" ]; then
        COMMIT_MSG=$(enforce_lowercase "$COMMIT_MSG")
    fi

    # Auto-fix common formatting issues (unless disabled)
    if [ "$AUTO_FIX" = "true" ]; then
        COMMIT_MSG=$(auto_fix_message "$COMMIT_MSG")
    fi

    # Apply template if custom template exists
    if [ -f ".gh-commit-ai-template" ]; then
        PROJECT_TYPE=$(detect_project_type)
        TEMPLATE=$(load_template "$PROJECT_TYPE")
        COMMIT_MSG=$(apply_template "$TEMPLATE" "$COMMIT_MSG")
    fi

    # Save to message history
    save_message_history "$COMMIT_MSG"

    # Show the generated commit message with proper newlines
    echo -e "\n✓ Generated commit message:"
    DISPLAY_MSG=$(convert_newlines "$COMMIT_MSG")
    printf "%s\n\n" "$DISPLAY_MSG"

    # Show cost information for paid APIs
    if [ "$AI_PROVIDER" = "anthropic" ]; then
        calculate_cost "anthropic" "$ANTHROPIC_MODEL" "$INPUT_TOKENS" "$OUTPUT_TOKENS"
        echo ""
    elif [ "$AI_PROVIDER" = "openai" ]; then
        calculate_cost "openai" "$OPENAI_MODEL" "$INPUT_TOKENS" "$OUTPUT_TOKENS"
        echo ""
    fi
fi

# If message was recovered, display it
if [ "$RECOVERED_MESSAGE" = "true" ]; then
    echo -e "\n✓ Recovered commit message:"
    DISPLAY_MSG=$(convert_newlines "$COMMIT_MSG")
    printf "%s\n\n" "$DISPLAY_MSG"
fi

# Handle preview mode - just show and exit
if [ "$PREVIEW" = true ]; then
    exit 0
fi

# Handle dry-run mode - ask if user wants to save to file
if [ "$DRY_RUN" = true ]; then
    read -p "Save to file? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        COMMIT_FILE=".git/COMMIT_MSG_$(date +%s)"
        # Strip ANSI codes and convert newlines before saving
        CLEAN_MSG=$(strip_ansi_codes "$COMMIT_MSG")
        CLEAN_MSG=$(convert_newlines "$CLEAN_MSG")
        printf "%s" "$CLEAN_MSG" > "$COMMIT_FILE"
        echo "✓ Saved to $COMMIT_FILE"
    else
        echo "Message not saved"
    fi
    exit 0
fi

# Ask for confirmation
while true; do
    echo -n "Use this commit message? (y/n/e to edit/r to regenerate): "
    read -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Strip any ANSI color codes before committing
        CLEAN_MSG=$(strip_ansi_codes "$COMMIT_MSG")
        # Convert literal \n to actual newlines
        CLEAN_MSG=$(convert_newlines "$CLEAN_MSG")

        if [ "$AMEND" = true ]; then
            # Amend the last commit with new message using HEREDOC for proper newline handling
            git commit --amend -m "$(cat <<EOF
$CLEAN_MSG
EOF
)"
            echo "✓ Amended commit successfully!"
            clear_message_history
        else
            # Stage all changes if nothing is staged
            if git diff --cached --quiet; then
                echo "Staging all changes"
                git add -A
            fi

            # Commit with the generated message using HEREDOC for proper newline handling
            git commit -m "$(cat <<EOF
$CLEAN_MSG
EOF
)"
            echo "✓ Committed successfully!"
            clear_message_history
        fi
        break
    elif [[ $REPLY =~ ^[Ee]$ ]]; then
        # Strip any ANSI color codes before editing
        CLEAN_MSG=$(strip_ansi_codes "$COMMIT_MSG")
        # Convert literal \n to actual newlines
        CLEAN_MSG=$(convert_newlines "$CLEAN_MSG")

        # Allow user to edit the message in editor using HEREDOC for proper newline handling
        if [ "$AMEND" = true ]; then
            git commit --amend -e -m "$(cat <<EOF
$CLEAN_MSG
EOF
)"
            echo "✓ Amended commit with edited message!"
            clear_message_history
        else
            git commit -e -m "$(cat <<EOF
$CLEAN_MSG
EOF
)"
            echo "✓ Committed with edited message!"
            clear_message_history
        fi
        break
    elif [[ $REPLY =~ ^[Rr]$ ]]; then
        # Regenerate the commit message
        echo "Regenerating commit message..."
        echo ""

        # Call the AI provider again
        case "$AI_PROVIDER" in
            ollama)
                COMMIT_MSG=$(call_ollama "$PROMPT")
                ;;
            anthropic)
                COMMIT_MSG=$(call_anthropic "$PROMPT")
                ;;
            openai)
                COMMIT_MSG=$(call_openai "$PROMPT")
                ;;
        esac

        # Strip markdown code fences
        COMMIT_MSG=$(echo "$COMMIT_MSG" | awk '
            /^```[a-zA-Z]*$/ { next }
            /^```$/ { next }
            /^\*\*explanation/ { exit }
            /^\*\*why/ { exit }
            /^\*\*note/ { exit }
            { print }
        ' | awk '
            { lines[NR] = $0 }
            END {
                for (i = 1; i <= NR; i++) {
                    if (i == NR) {
                        if (lines[i] != "") print lines[i]
                    } else if (lines[i] != "" || lines[i+1] != "") {
                        print lines[i]
                    }
                }
            }
        ')

        # Enforce lowercase (unless disabled)
        if [ "$NO_LOWERCASE" != "true" ]; then
            COMMIT_MSG=$(enforce_lowercase "$COMMIT_MSG")
        fi

        # Auto-fix common formatting issues (unless disabled)
        if [ "$AUTO_FIX" = "true" ]; then
            COMMIT_MSG=$(auto_fix_message "$COMMIT_MSG")
        fi

        # Apply template if custom template exists
        if [ -f ".gh-commit-ai-template" ]; then
            PROJECT_TYPE=$(detect_project_type)
            TEMPLATE=$(load_template "$PROJECT_TYPE")
            COMMIT_MSG=$(apply_template "$TEMPLATE" "$COMMIT_MSG")
        fi

        # Save to message history
        save_message_history "$COMMIT_MSG"

        # Show the new message
        echo -e "\n✓ Regenerated commit message:"
        DISPLAY_MSG=$(convert_newlines "$COMMIT_MSG")
        printf "%s\n\n" "$DISPLAY_MSG"

        # Show cost information for paid APIs
        if [ "$AI_PROVIDER" = "anthropic" ]; then
            calculate_cost "anthropic" "$ANTHROPIC_MODEL" "$INPUT_TOKENS" "$OUTPUT_TOKENS"
            echo ""
        elif [ "$AI_PROVIDER" = "openai" ]; then
            calculate_cost "openai" "$OPENAI_MODEL" "$INPUT_TOKENS" "$OUTPUT_TOKENS"
            echo ""
        fi

        # Loop back to confirmation prompt
    else
        echo "Commit cancelled"
        exit 0
    fi
done
