# Per-run private directory for the --options working files.
#
# These used to be fixed paths under /tmp: readable by any local user,
# clobbered when two runs overlapped, and symlink-attackable in the window after
# each `rm -f`. OPTIONS_DIR is created 700 by mktemp and removed by the EXIT
# trap.
#
# Created eagerly rather than lazily: a lazy helper called via $(...) would run
# in a subshell, so the assignment would not survive and every call site would
# get a different directory.
OPTIONS_DIR=""
if [ "$MULTIPLE_OPTIONS" = "true" ]; then
    OPTIONS_DIR=$(create_secure_temp_dir "gh-commit-ai-options") || exit 1
    register_temp_path "$OPTIONS_DIR"
fi

# Parse multiple commit message options from AI response
parse_multiple_options() {
    local response="$1"

    # Extract recommendation if present
    if echo "$response" | grep -q "\[RECOMMENDATION\]"; then
        echo "$response" | sed -n '/\[RECOMMENDATION\]/,$ p' | tail -n +2 > "$OPTIONS_DIR/ai_recommendation.txt"
    fi

    # Parse with a simple sed/bash approach for better compatibility
    local current_option=0
    local in_option=0
    local in_reasoning=0

    # Process line by line
    echo "$response" | while IFS= read -r line; do
        # Check for section markers
        if echo "$line" | grep -q '^\[OPTION [0-9]\]'; then
            current_option=$((current_option + 1))
            in_option=1
            in_reasoning=0
            continue
        elif echo "$line" | grep -q '^\[REASONING\]'; then
            in_option=0
            in_reasoning=1
            continue
        elif echo "$line" | grep -q '^\[RECOMMENDATION\]'; then
            break
        elif echo "$line" | grep -q '^---OPTION---'; then
            continue
        fi

        # Write to appropriate file
        if [ "$in_option" = "1" ] && [ "$current_option" -gt 0 ]; then
            echo "$line" >> "$OPTIONS_DIR/option_${current_option}.txt"
        elif [ "$in_reasoning" = "1" ] && [ "$current_option" -gt 0 ]; then
            echo "$line" >> "$OPTIONS_DIR/reasoning_${current_option}.txt"
        fi
    done

    # If no structured format found, fallback to old simple parsing
    if [ ! -f "$OPTIONS_DIR/option_1.txt" ]; then
        current_option=1
        echo "$response" | while IFS= read -r line; do
            if echo "$line" | grep -q "^---OPTION---$"; then
                current_option=$((current_option + 1))
            else
                echo "$line" >> "$OPTIONS_DIR/option_${current_option}.txt"
            fi
        done
    fi

    # If still no options, treat as single option
    if [ ! -f "$OPTIONS_DIR/option_1.txt" ]; then
        echo "$response" > "$OPTIONS_DIR/option_1.txt"
        echo "1"
        return
    fi

    # Count how many options we have
    count=0
    for f in "$OPTIONS_DIR"/option_*.txt; do
        [ -f "$f" ] && count=$((count + 1))
    done

    echo "$count"
}

# Display multiple options for user selection
display_options() {
    local num_options="$1"

    echo -e "Generated ${num_options} commit message options:\n"

    for i in $(seq 1 $num_options); do
        local option_file="$OPTIONS_DIR/option_${i}.txt"
        local reasoning_file="$OPTIONS_DIR/reasoning_${i}.txt"

        if [ -f "$option_file" ]; then
            local option_content=$(cat "$option_file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            echo -e "${GREEN}Option $i:${NC}"
            echo -e "$option_content"

            # Display reasoning if available
            if [ -f "$reasoning_file" ]; then
                local reasoning=$(cat "$reasoning_file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                echo -e "\n${YELLOW}Reasoning:${NC} $reasoning"
            fi
            echo ""
        fi
    done

    # Display AI recommendation if available
    if [ -f "$OPTIONS_DIR/ai_recommendation.txt" ]; then
        local recommendation=$(cat "$OPTIONS_DIR/ai_recommendation.txt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}AI Recommendation:${NC}"
        echo -e "$recommendation"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    fi
}

# Get user's option selection
select_option() {
    local num_options="$1"

    while true; do
        echo -n "Select option (1-${num_options}), or 'n' to cancel: "
        read -n 1 -r
        echo

        if [[ $REPLY =~ ^[Nn]$ ]]; then
            echo "cancelled"
            return
        fi

        if [[ $REPLY =~ ^[0-9]+$ ]] && [ "$REPLY" -ge 1 ] && [ "$REPLY" -le "$num_options" ]; then
            echo "$REPLY"
            return
        fi

        echo -e "${RED}❌ Invalid selection. Please enter 1-${num_options} or 'n' to cancel."
    done
}

