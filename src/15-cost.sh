# Calculate cost for API usage
calculate_cost() {
    local provider="$1"
    local model="$2"
    local input_tokens="$3"
    local output_tokens="$4"

    # Return early if no token data
    if [ -z "$input_tokens" ] || [ -z "$output_tokens" ]; then
        return
    fi

    local input_cost=0
    local output_cost=0
    local currency="USD"

    # Pricing per 1M tokens (as of early 2025)
    case "$provider" in
        anthropic)
            case "$model" in
                claude-3-5-sonnet-20241022|claude-3-5-sonnet-latest)
                    input_cost=3.00    # $3 per MTok
                    output_cost=15.00  # $15 per MTok
                    ;;
                claude-3-opus-20240229)
                    input_cost=15.00   # $15 per MTok
                    output_cost=75.00  # $75 per MTok
                    ;;
                claude-3-haiku-20240307)
                    input_cost=0.25    # $0.25 per MTok
                    output_cost=1.25   # $1.25 per MTok
                    ;;
                *)
                    # Default to Sonnet pricing
                    input_cost=3.00
                    output_cost=15.00
                    ;;
            esac
            ;;
        openai)
            case "$model" in
                gpt-4o)
                    input_cost=2.50    # $2.50 per MTok
                    output_cost=10.00  # $10 per MTok
                    ;;
                gpt-4o-mini)
                    input_cost=0.15    # $0.15 per MTok
                    output_cost=0.60   # $0.60 per MTok
                    ;;
                gpt-4-turbo|gpt-4-turbo-preview)
                    input_cost=10.00   # $10 per MTok
                    output_cost=30.00  # $30 per MTok
                    ;;
                gpt-4)
                    input_cost=30.00   # $30 per MTok
                    output_cost=60.00  # $60 per MTok
                    ;;
                *)
                    # Default to gpt-4o-mini pricing
                    input_cost=0.15
                    output_cost=0.60
                    ;;
            esac
            ;;
    esac

    # Calculate costs (tokens / 1,000,000 * price per million)
    # Using bc for floating point, or awk if bc not available
    if command -v bc >/dev/null 2>&1; then
        local input_cost_calc=$(echo "scale=6; $input_tokens / 1000000 * $input_cost" | bc)
        local output_cost_calc=$(echo "scale=6; $output_tokens / 1000000 * $output_cost" | bc)
        local total_cost=$(echo "scale=6; $input_cost_calc + $output_cost_calc" | bc)
    else
        # Fallback to awk if bc not available
        local input_cost_calc=$(awk "BEGIN {printf \"%.6f\", $input_tokens / 1000000 * $input_cost}")
        local output_cost_calc=$(awk "BEGIN {printf \"%.6f\", $output_tokens / 1000000 * $output_cost}")
        local total_cost=$(awk "BEGIN {printf \"%.6f\", $input_cost_calc + $output_cost_calc}")
    fi

    # Format for display (remove trailing zeros)
    local total_cost_display=$(echo "$total_cost" | sed 's/0*$//' | sed 's/\.$//')

    # If cost is very small, show more precision
    if [ $(echo "$total_cost < 0.0001" | bc 2>/dev/null || echo 0) -eq 1 ]; then
        total_cost_display=$(printf "%.6f" "$total_cost" | sed 's/0*$//' | sed 's/\.$//')
    else
        total_cost_display=$(printf "%.4f" "$total_cost" | sed 's/0*$//' | sed 's/\.$//')
    fi

    # Display token usage and cost
    local total_tokens=$((input_tokens + output_tokens))
    echo "💰 Token usage: ${total_tokens} tokens (${input_tokens} input + ${output_tokens} output)"
    echo "💰 Estimated cost: \$$total_cost_display $currency"

    # Track cumulative cost
    track_cumulative_cost "$total_cost"
}

# Track cumulative costs
track_cumulative_cost() {
    local cost="$1"
    local cost_file="/tmp/gh-commit-ai-costs-$(date +%Y%m%d)"

    # Append to daily cost file
    echo "$cost" >> "$cost_file"

    # Calculate cumulative total for today
    if command -v bc >/dev/null 2>&1; then
        local cumulative=$(awk '{sum+=$1} END {printf "%.6f", sum}' "$cost_file")
    else
        local cumulative=$(awk '{sum+=$1} END {printf "%.6f", sum}' "$cost_file")
    fi

    # Format for display
    local cumulative_display=$(printf "%.4f" "$cumulative" | sed 's/0*$//' | sed 's/\.$//')

    echo "💰 Today's total: \$$cumulative_display USD"
}

# Strip ANSI color codes from text
strip_ansi_codes() {
    local text="$1"
    # Remove ANSI escape sequences
    echo "$text" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\\033\[[0-9;]*m//g'
}

# Convert literal \n to actual newlines for better display in GitHub
convert_newlines() {
    local text="$1"
    # Use printf %b to interpret backslash escapes
    printf "%b" "$text"
}

