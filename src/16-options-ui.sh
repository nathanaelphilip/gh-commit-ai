# Parse multiple commit message options from AI response
parse_multiple_options() {
    local response="$1"

    # Extract recommendation if present
    if echo "$response" | grep -q "\[RECOMMENDATION\]"; then
        echo "$response" | sed -n '/\[RECOMMENDATION\]/,$ p' | tail -n +2 > /tmp/ai_recommendation.txt
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
            echo "$line" >> "/tmp/option_${current_option}.txt"
        elif [ "$in_reasoning" = "1" ] && [ "$current_option" -gt 0 ]; then
            echo "$line" >> "/tmp/reasoning_${current_option}.txt"
        fi
    done

    # If no structured format found, fallback to old simple parsing
    if [ ! -f "/tmp/option_1.txt" ]; then
        current_option=1
        echo "$response" | while IFS= read -r line; do
            if echo "$line" | grep -q "^---OPTION---$"; then
                current_option=$((current_option + 1))
            else
                echo "$line" >> "/tmp/option_${current_option}.txt"
            fi
        done
    fi

    # If still no options, treat as single option
    if [ ! -f "/tmp/option_1.txt" ]; then
        echo "$response" > "/tmp/option_1.txt"
        echo "1"
        return
    fi

    # Count how many options we have
    count=0
    for f in /tmp/option_*.txt; do
        [ -f "$f" ] && count=$((count + 1))
    done

    echo "$count"
}

# Display multiple options for user selection
display_options() {
    local num_options="$1"

    echo -e "Generated ${num_options} commit message options:\n"

    for i in $(seq 1 $num_options); do
        local option_file="/tmp/option_${i}.txt"
        local reasoning_file="/tmp/reasoning_${i}.txt"

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
    if [ -f "/tmp/ai_recommendation.txt" ]; then
        local recommendation=$(cat "/tmp/ai_recommendation.txt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
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

