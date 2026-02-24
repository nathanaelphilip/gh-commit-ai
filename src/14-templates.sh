# Detect project type based on files present
detect_project_type() {
    # Web application indicators
    if [ -f "package.json" ]; then
        local pkg_content=$(cat "package.json" 2>/dev/null || echo "")
        if echo "$pkg_content" | grep -qE '(react|vue|angular|svelte|next|nuxt|webpack|vite)'; then
            echo "web-app"
            return
        fi
        if echo "$pkg_content" | grep -q '"type".*:.*"module"'; then
            echo "library"
            return
        fi
    fi

    # CLI tool indicators
    if [ -d "bin" ] || [ -d "cmd" ]; then
        echo "cli"
        return
    fi

    # Library indicators
    if [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
        echo "library"
        return
    fi

    if [ -f "Cargo.toml" ]; then
        local cargo_content=$(cat "Cargo.toml" 2>/dev/null || echo "")
        if echo "$cargo_content" | grep -q '\[lib\]'; then
            echo "library"
            return
        fi
        echo "cli"
        return
    fi

    if [ -f "go.mod" ]; then
        if [ -f "main.go" ] && grep -q "package main" "main.go" 2>/dev/null; then
            echo "cli"
            return
        fi
        echo "library"
        return
    fi

    # Default
    echo "general"
}

# Load template from file or return built-in template
load_template() {
    local project_type="$1"

    # Check for local template file
    if [ -f ".gh-commit-ai-template" ]; then
        cat ".gh-commit-ai-template"
        return
    fi

    # Return built-in template based on project type
    case "$project_type" in
        web-app)
            cat <<'EOF'
{{emoji}} {{type}}{{scope}}: {{message}}

{{bullets}}
{{breaking}}
EOF
            ;;
        library)
            cat <<'EOF'
{{emoji}} {{type}}{{scope}}: {{message}}

{{bullets}}
{{breaking}}

Changes: {{files_changed}} files changed
EOF
            ;;
        cli)
            cat <<'EOF'
{{emoji}} {{type}}{{scope}}: {{message}}

{{bullets}}
{{breaking}}
EOF
            ;;
        *)
            # General/default template - same as current format
            cat <<'EOF'
{{emoji}} {{type}}{{scope}}: {{message}}

{{bullets}}
{{breaking}}
EOF
            ;;
    esac
}

# Parse commit message components from AI-generated message
parse_commit_components() {
    local message="$1"

    # Extract first line (summary with type/scope)
    local first_line=$(echo "$message" | head -1)

    # Parse type, emoji, scope, and summary
    local emoji=""
    local type=""
    local scope=""
    local summary=""
    local breaking_marker=""

    # Check for emoji at start
    if [[ "$first_line" =~ ^([[:space:]]*)([^[:space:][:alnum:]]+)[[:space:]]+ ]]; then
        emoji="${BASH_REMATCH[2]}"
        first_line="${first_line#*${emoji}}"
        first_line="${first_line#"${first_line%%[![:space:]]*}"}" # trim leading spaces
    fi

    # Parse type with optional scope and breaking marker
    # Patterns: feat:, feat(scope):, feat!:, feat(scope)!:
    if [[ "$first_line" =~ ^([a-z]+)(\([a-z0-9_-]+\))?(!)?:[[:space:]]*(.+)$ ]]; then
        type="${BASH_REMATCH[1]}"
        scope="${BASH_REMATCH[2]}"  # includes parentheses
        breaking_marker="${BASH_REMATCH[3]}"
        summary="${BASH_REMATCH[4]}"
    else
        # Fallback: treat entire line as summary
        summary="$first_line"
    fi

    # Extract bullets (lines starting with -)
    local bullets=$(echo "$message" | tail -n +2 | awk '/^[[:space:]]*-/ {print}' | sed '/^$/d')

    # Extract BREAKING CHANGE footer if present
    local breaking=""
    if echo "$message" | grep -q "^BREAKING CHANGE:"; then
        breaking=$(echo "$message" | sed -n '/^BREAKING CHANGE:/,$ p')
    fi

    # Export as variables that can be used by apply_template
    echo "TYPE=$type"
    echo "EMOJI=$emoji"
    echo "SCOPE=$scope"
    echo "BREAKING_MARKER=$breaking_marker"
    echo "SUMMARY=$summary"
    echo "BULLETS<<BULLETS_EOF"
    echo "$bullets"
    echo "BULLETS_EOF"
    echo "BREAKING<<BREAKING_EOF"
    echo "$breaking"
    echo "BREAKING_EOF"
}

# Apply template variables and return formatted message
apply_template() {
    local template="$1"
    local message="$2"

    # Parse components from AI message
    local components=$(parse_commit_components "$message")

    # Extract component values using heredoc parsing
    local TYPE=$(echo "$components" | grep "^TYPE=" | cut -d= -f2-)
    local EMOJI=$(echo "$components" | grep "^EMOJI=" | cut -d= -f2-)
    local SCOPE=$(echo "$components" | grep "^SCOPE=" | cut -d= -f2-)
    local BREAKING_MARKER=$(echo "$components" | grep "^BREAKING_MARKER=" | cut -d= -f2-)
    local SUMMARY=$(echo "$components" | grep "^SUMMARY=" | cut -d= -f2-)

    # Extract multiline values (bullets and breaking)
    local BULLETS=$(echo "$components" | sed -n '/^BULLETS<<BULLETS_EOF$/,/^BULLETS_EOF$/p' | sed '1d;$d')
    local BREAKING=$(echo "$components" | sed -n '/^BREAKING<<BREAKING_EOF$/,/^BREAKING_EOF$/p' | sed '1d;$d')

    # Get additional template variables
    local BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    local TICKET=$(echo "$BRANCH" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1 || echo "")
    local AUTHOR=$(git config user.name 2>/dev/null || echo "")
    local DATE=$(date +"%Y-%m-%d")
    local FILES_CHANGED=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')

    # Build scope string with format: (scope) or empty
    local SCOPE_STR=""
    if [ -n "$SCOPE" ]; then
        SCOPE_STR="$SCOPE"
    fi

    # Build breaking marker: ! or empty
    local BREAKING_STR=""
    if [ -n "$BREAKING_MARKER" ]; then
        BREAKING_STR="!"
    fi

    # Apply template substitutions
    local result="$template"

    # Simple variable substitution
    result="${result//\{\{emoji\}\}/$EMOJI}"
    result="${result//\{\{type\}\}/$TYPE}"
    result="${result//\{\{scope\}\}/$SCOPE_STR}"
    result="${result//\{\{breaking_marker\}\}/$BREAKING_STR}"
    result="${result//\{\{message\}\}/$SUMMARY}"
    result="${result//\{\{bullets\}\}/$BULLETS}"
    result="${result//\{\{breaking\}\}/$BREAKING}"
    result="${result//\{\{ticket\}\}/$TICKET}"
    result="${result//\{\{branch\}\}/$BRANCH}"
    result="${result//\{\{author\}\}/$AUTHOR}"
    result="${result//\{\{date\}\}/$DATE}"
    result="${result//\{\{files_changed\}\}/$FILES_CHANGED}"

    # Clean up: remove lines that only contain empty template variables
    result=$(echo "$result" | sed '/^[[:space:]]*$/d')

    # Remove trailing blank lines
    result=$(echo "$result" | awk '
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

    echo "$result"
}

