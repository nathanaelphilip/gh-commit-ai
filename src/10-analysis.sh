# Extract best commit examples from repository history
get_best_commit_examples() {
    # Check cache first (keyed by latest commit hash)
    local latest_commit=$(git rev-parse HEAD 2>/dev/null || echo "")
    if [ -n "$latest_commit" ]; then
        local cached=$(get_cache "commit-examples-${latest_commit}" 3600 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$cached" ]; then
            echo "$cached"
            return
        fi
    fi

    # Get last 100 commits with subject and body
    local commits=$(git log --pretty=format:"%s|||%b" -100 2>/dev/null)

    [ -z "$commits" ] && return

    local examples=""
    local count=0
    local max_examples=2

    # Find well-formed commits with bullets and proper conventional format
    while IFS='|||' read -r subject body; do
        # Check if has proper format and bullets
        if [[ "$subject" =~ ^(feat|fix|docs|refactor|test|chore|perf|style) ]] && \
           [[ "$body" == *"- "* ]]; then
            # This is a good example
            if [ $count -eq 0 ]; then
                examples="EXAMPLES FROM THIS REPOSITORY:"
            fi

            examples="$examples

$subject
$body"

            count=$((count + 1))
            [ $count -ge $max_examples ] && break
        fi
    done <<< "$commits"

    if [ -n "$examples" ]; then
        # Cache the result
        if [ -n "$latest_commit" ]; then
            set_cache "commit-examples-${latest_commit}" "$examples" 2>/dev/null
        fi
        echo "$examples"
    fi
}

# Analyze the type of changes in the diff (semantic analysis)
analyze_change_type() {
    local diff="$1"
    local change_types=()

    # Count additions vs deletions
    local adds=$(echo "$diff" | grep -c "^+" 2>/dev/null)
    local dels=$(echo "$diff" | grep -c "^-" 2>/dev/null)

    # Ensure numeric values (default to 0 if empty)
    adds=${adds:-0}
    dels=${dels:-0}

    # Detect error handling additions
    if echo "$diff" | grep -qE '^\+.*(throw new|try \{|catch|except:|raise )'; then
        change_types+=("added error handling")
    fi

    # Detect TODO/FIXME additions
    if echo "$diff" | grep -qE '^\+.*(TODO|FIXME|XXX|HACK)'; then
        change_types+=("added TODOs")
    fi

    # Detect logging additions
    if echo "$diff" | grep -qE '^\+.*(console\.log|logger\.|logging\.|log\.|print\()'; then
        change_types+=("added logging")
    fi

    # Detect test additions
    if echo "$diff" | grep -qE '^\+.*(it\(|test\(|describe\(|assert|expect\()'; then
        change_types+=("added tests")
    fi

    # Detect validation additions
    if echo "$diff" | grep -qE '^\+.*(validate|check|verify|assert|ensure).*\('; then
        change_types+=("added validation")
    fi

    # Detect API/endpoint changes
    if echo "$diff" | grep -qE '^\+.*(route|endpoint|@RequestMapping|@GetMapping|@PostMapping|@app\.route)'; then
        change_types+=("added API endpoints")
    fi

    # Detect database/model changes
    if echo "$diff" | grep -qE '^\+.*(CREATE TABLE|ALTER TABLE|migration|Schema::|add_column|create_table)'; then
        change_types+=("database schema changes")
    fi

    # Detect code removal (refactoring)
    if [ "$dels" -gt 0 ] && [ "$adds" -gt 0 ] && [ "$dels" -gt $((adds * 2)) ]; then
        change_types+=("code removal/cleanup")
    fi

    # Detect new function/class additions
    if echo "$diff" | grep -qE '^\+.*(function |def |class |const .* = \()'; then
        change_types+=("new functions/classes")
    fi

    # Detect configuration changes
    if echo "$diff" | grep -qE '^\+.*(config|settings|env|ENV|CONST)'; then
        change_types+=("configuration updates")
    fi

    # Detect dependency changes
    if echo "$diff" | grep -qE '^\+.*(import |require\(|from .* import|include |use )'; then
        change_types+=("dependency changes")
    fi

    # Detect documentation
    if echo "$diff" | grep -qE '^\+.*(\/\*\*|"""|\* @|#.*:|<!-- )'; then
        change_types+=("documentation updates")
    fi

    # Return change types
    if [ ${#change_types[@]} -gt 0 ]; then
        local result=$(printf '%s\n' "${change_types[@]}" | sort -u | paste -sd "," -)
        echo "$result" | sed 's/,/, /g'
    fi
}

# Generate per-file change summaries
generate_file_summaries() {
    local status="$1"
    local summaries=""
    local count=0
    local max_files=5

    # Use git diff --numstat for accurate per-file statistics
    # Format: <added lines> <deleted lines> <filename>
    local numstat
    if [ "$AMEND_MODE" = "true" ]; then
        numstat=$(git show HEAD --numstat --format="" 2>/dev/null)
    else
        numstat=$(git diff --cached --numstat 2>/dev/null)
    fi

    # Parse git status to get changed files
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [ "$count" -ge "$max_files" ] && break

        # Extract status and filename
        local file_status=$(echo "$line" | awk '{print $1}')
        local file=$(echo "$line" | awk '{print $NF}')

        # Skip if empty
        [ -z "$file" ] && continue

        # Get stats from numstat for this file
        local adds=0
        local dels=0
        local stats=$(echo "$numstat" | grep -F "$file" | head -1)
        if [ -n "$stats" ]; then
            adds=$(echo "$stats" | awk '{print $1}')
            dels=$(echo "$stats" | awk '{print $2}')

            # Handle binary files (marked with -)
            [ "$adds" = "-" ] && adds=0
            [ "$dels" = "-" ] && dels=0
        fi

        # Ensure numeric values (default to 0 if empty)
        adds=${adds:-0}
        dels=${dels:-0}

        # Create summary
        local action=""
        case "$file_status" in
            A) action="new file" ;;
            M) action="modified" ;;
            D) action="deleted" ;;
            R) action="renamed" ;;
            *) action="changed" ;;
        esac

        # Only show files with significant changes
        if [ "$adds" -gt 2 ] || [ "$dels" -gt 2 ] || [ "$file_status" = "A" ] || [ "$file_status" = "D" ]; then
            if [ -z "$summaries" ]; then
                summaries="FILE SUMMARIES:"
            fi
            summaries="$summaries
- $file: $action (+$adds/-$dels lines)"
            count=$((count + 1))
        fi
    done <<< "$status"

    echo "$summaries"
}

# Detect relationships between changed files
detect_file_relationships() {
    local files="$1"
    local relationships=()

    # Convert to lowercase for matching
    local files_lower=$(echo "$files" | tr '[:upper:]' '[:lower:]')

    # Migration + Model pattern
    if echo "$files_lower" | grep -q "migration" && echo "$files_lower" | grep -qE "(model|schema)"; then
        relationships+=("database migration with model changes")
    fi

    # Test + Source pattern
    local has_test=$(echo "$files_lower" | grep -cE "(test|spec)" 2>/dev/null)
    local total_files=$(echo "$files" | wc -l | tr -d ' ')

    # Ensure numeric values
    has_test=${has_test:-0}
    total_files=${total_files:-0}

    if [ "$has_test" -gt 0 ] && [ "$total_files" -gt "$has_test" ]; then
        relationships+=("includes test coverage")
    fi

    # Component + Style pattern
    if echo "$files_lower" | grep -qE "\.(tsx|jsx|vue)" && echo "$files_lower" | grep -qE "\.(css|scss|sass|less)"; then
        relationships+=("component with styling changes")
    fi

    # Controller + View pattern
    if echo "$files_lower" | grep -q "controller" && echo "$files_lower" | grep -qE "(view|template)"; then
        relationships+=("controller and view updates")
    fi

    # API + Documentation pattern
    if echo "$files_lower" | grep -qE "(api|endpoint|route)" && echo "$files_lower" | grep -qE "(readme|doc|swagger)"; then
        relationships+=("API changes with documentation")
    fi

    # Config + Code pattern
    if echo "$files_lower" | grep -qE "(config|\.env|settings)" && echo "$files" | wc -l | awk '{if ($1 > 1) print "yes"}' | grep -q "yes"; then
        relationships+=("configuration changes with code")
    fi

    # Docker + CI pattern
    if echo "$files_lower" | grep -qE "(dockerfile|docker-compose)" && echo "$files_lower" | grep -qE "(\.github|\.gitlab|jenkins|ci)"; then
        relationships+=("Docker and CI/CD updates")
    fi

    # Return relationships
    if [ ${#relationships[@]} -gt 0 ]; then
        printf '%s\n' "${relationships[@]}" | paste -sd ", " -
    fi
}

