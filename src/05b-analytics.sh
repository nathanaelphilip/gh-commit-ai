# Local analytics tracking (opt-in)
ANALYTICS_DIR="$HOME/.gh-commit-ai/analytics"

# Track analytics for an AI invocation
# Args: provider, model, input_tokens, output_tokens, cost, duration_ms, mode, cached, streaming
track_analytics() {
    if [ "$ANALYTICS_ENABLED" != "true" ]; then
        return
    fi

    local provider="${1:-unknown}"
    local model="${2:-unknown}"
    local input_tokens="${3:-0}"
    local output_tokens="${4:-0}"
    local cost="${5:-0}"
    local duration_ms="${6:-0}"
    local mode="${7:-commit}"
    local cached="${8:-false}"
    local streaming="${9:-false}"

    # Create analytics directory if needed
    mkdir -p "$ANALYTICS_DIR" 2>/dev/null || return

    # Current month file
    local month_file="$ANALYTICS_DIR/$(date +%Y-%m).jsonl"
    local timestamp=$(date +%s)

    # Append JSON line (pure bash, no jq)
    local json_line="{\"ts\":$timestamp,\"provider\":\"$provider\",\"model\":\"$model\",\"input_tokens\":$input_tokens,\"output_tokens\":$output_tokens,\"cost\":$cost,\"duration_ms\":$duration_ms,\"mode\":\"$mode\",\"cached\":$cached,\"streaming\":$streaming}"
    echo "$json_line" >> "$month_file"
}

# Generate stats report from analytics data
generate_stats_report() {
    if [ ! -d "$ANALYTICS_DIR" ]; then
        echo "No analytics data found."
        echo ""
        echo "Analytics is currently $([ "$ANALYTICS_ENABLED" = "true" ] && echo "enabled" || echo "disabled")."
        echo "To enable: add 'analytics_enabled: true' to .gh-commit-ai.yml"
        echo "  or: export ANALYTICS_ENABLED=true"
        return
    fi

    local now=$(date +%s)
    local thirty_days_ago=$((now - 2592000))
    local seven_days_ago=$((now - 604800))
    local today_start
    today_start=$(date -v0H -v0M -v0S +%s 2>/dev/null || date -d "today 00:00" +%s 2>/dev/null || echo "$((now - now % 86400))")

    # Collect all JSONL files from recent months
    local all_data=""
    for f in "$ANALYTICS_DIR"/*.jsonl; do
        [ -f "$f" ] || continue
        all_data="${all_data}$(cat "$f")
"
    done

    if [ -z "$all_data" ]; then
        echo "No analytics data found."
        return
    fi

    # Use awk to parse JSONL and compute stats
    echo "$all_data" | awk -v now="$now" -v thirty_days="$thirty_days_ago" -v seven_days="$seven_days_ago" -v today="$today_start" '
    BEGIN {
        total = 0; commits = 0; reviews = 0; cached_count = 0
        total_cost = 0; today_cost = 0; week_cost = 0; month_cost = 0
        total_duration = 0; duration_count = 0
    }
    {
        # Extract timestamp
        if (match($0, /"ts":([0-9]+)/, m)) ts = m[1]; else next
        if (ts < thirty_days) next  # Skip old data

        total++

        # Extract mode
        if (match($0, /"mode":"([^"]+)"/, m)) mode = m[1]; else mode = "commit"
        if (mode == "commit") commits++
        else if (mode == "review") reviews++

        # Extract provider
        if (match($0, /"provider":"([^"]+)"/, m)) {
            providers[m[1]]++
        }

        # Extract cost
        if (match($0, /"cost":([0-9.]+)/, m)) {
            cost = m[1] + 0
            month_cost += cost
            if (ts >= seven_days) week_cost += cost
            if (ts >= today) today_cost += cost
        }

        # Extract duration
        if (match($0, /"duration_ms":([0-9]+)/, m)) {
            dur = m[1] + 0
            if (dur > 0) { total_duration += dur; duration_count++ }
        }

        # Extract cached
        if (match($0, /"cached":true/)) cached_count++
    }
    END {
        if (total == 0) { print "No data in the last 30 days."; exit }

        printf "Usage Statistics (last 30 days)\n"
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        printf "Commits generated:  %4d\n", commits
        printf "Code reviews:       %4d\n", reviews
        printf "Total API calls:    %4d\n", total
        printf "\n"

        # Provider breakdown
        printf "Provider breakdown:\n"
        for (p in providers) {
            pct = (providers[p] / total) * 100
            printf "  %-12s %4d (%d%%)\n", p ":", providers[p], pct
        }

        # Cost summary
        printf "\nCost summary:\n"
        printf "  Today:      $%.4f\n", today_cost
        printf "  This week:  $%.4f\n", week_cost
        printf "  This month: $%.4f\n", month_cost

        # Average generation time
        if (duration_count > 0) {
            avg_sec = (total_duration / duration_count) / 1000
            printf "\nAvg generation time: %.1fs\n", avg_sec
        }

        # Cache hit rate
        if (total > 0) {
            cache_pct = (cached_count / total) * 100
            printf "Cache hit rate:      %d%%\n", cache_pct
        }
    }
    '
}

