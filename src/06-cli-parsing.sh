# Parse command-line arguments
DRY_RUN=false
PREVIEW=false
AMEND=false
MULTIPLE_OPTIONS=false
CHANGELOG_MODE=false
CHANGELOG_SINCE=""
CHANGELOG_FORMAT="keepachangelog"
VERBOSE=false
FORCED_TYPE=""
CUSTOM_MAX_LINES=""
NO_LOWERCASE=false

### Message history directory (will be set per-repository)
MESSAGE_HISTORY_DIR=""

# Save message to history (keeps last 5)
save_message_history() {
    local message="$1"
    local timestamp=$(date +%s)
    local history_file="$MESSAGE_HISTORY_DIR/msg_${timestamp}.txt"

    # Save the message
    echo "$message" > "$history_file"

    # Keep only the last 5 messages
    ls -t "$MESSAGE_HISTORY_DIR"/msg_*.txt 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
}

# Get last message from history
get_last_message() {
    local last_file=$(ls -t "$MESSAGE_HISTORY_DIR"/msg_*.txt 2>/dev/null | head -1)
    if [ -n "$last_file" ] && [ -f "$last_file" ]; then
        cat "$last_file"
    fi
}

# Check if last message is recent (within 5 minutes)
is_recent_message() {
    local last_file=$(ls -t "$MESSAGE_HISTORY_DIR"/msg_*.txt 2>/dev/null | head -1)
    if [ -z "$last_file" ] || [ ! -f "$last_file" ]; then
        return 1
    fi

    # Extract timestamp from filename (msg_TIMESTAMP.txt)
    local file_timestamp=$(basename "$last_file" | sed 's/msg_//;s/.txt//')
    local current_time=$(date +%s)
    local age=$((current_time - file_timestamp))

    # Recent if less than 5 minutes old (300 seconds)
    if [ "$age" -lt 300 ]; then
        return 0
    else
        return 1
    fi
}

# Clear message history (called after successful commit)
clear_message_history() {
    rm -f "$MESSAGE_HISTORY_DIR"/msg_*.txt 2>/dev/null || true
}

# ============================================================================
# API RESPONSE CACHING (Performance optimization)
# ============================================================================

# Generate cache key from diff content (reads from stdin)
get_diff_hash() {
    # Create hash of diff content for cache key (from stdin)
    if command -v md5sum &> /dev/null; then
        md5sum | awk '{print $1}'
    elif command -v md5 &> /dev/null; then
        md5
    else
        # Fallback: use first 32 chars of diff (not ideal but better than nothing)
        head -c 32 | sed 's/[^a-zA-Z0-9]//g'
    fi
}

# Get cached AI response if available and not expired
get_cached_response() {
    local cache_key="$1"
    local cache_file="${CACHE_DIR}/${cache_key}.txt"

    # Check if cache is disabled
    if [ "$DISABLE_CACHE" = "true" ]; then
        return 1
    fi

    # Check if cache file exists
    if [ ! -f "$cache_file" ]; then
        return 1
    fi

    # Check cache age (default: 24 hours = 86400 seconds)
    local cache_max_age="${CACHE_MAX_AGE:-86400}"
    local current_time=$(date +%s)
    local file_time=0

    # Get file modification time (BSD/macOS vs GNU/Linux compatible)
    if stat -f %m "$cache_file" &>/dev/null; then
        file_time=$(stat -f %m "$cache_file" 2>/dev/null || echo 0)
    else
        file_time=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
    fi

    local file_age=$((current_time - file_time))

    if [ "$file_age" -gt "$cache_max_age" ]; then
        # Cache expired
        rm -f "$cache_file" 2>/dev/null || true
        return 1
    fi

    # Return cached content
    cat "$cache_file"
    return 0
}

# Save AI response to cache
save_cached_response() {
    local cache_key="$1"
    local response="$2"
    local cache_file="${CACHE_DIR}/${cache_key}.txt"

    # Don't cache if disabled
    if [ "$DISABLE_CACHE" = "true" ]; then
        return
    fi

    # Save response
    echo "$response" > "$cache_file"

    # Clean up old cache entries (keep last 100)
    ls -t "$CACHE_DIR"/*.txt 2>/dev/null | tail -n +101 | xargs rm -f 2>/dev/null || true
}

# Clear expired cache entries (called periodically during save)
clear_expired_cache() {
    local cache_max_age="${CACHE_MAX_AGE:-86400}"
    local current_time=$(date +%s)

    # Find and remove expired cache files (use ls for better compatibility)
    for file in "$CACHE_DIR"/*.txt; do
        [ -f "$file" ] 2>/dev/null || continue

        local file_time=0
        if stat -f %m "$file" &>/dev/null; then
            file_time=$(stat -f %m "$file" 2>/dev/null || echo 0)
        else
            file_time=$(stat -c %Y "$file" 2>/dev/null || echo 0)
        fi

        local age=$((current_time - file_time))
        if [ "$age" -gt "$cache_max_age" ]; then
            rm -f "$file" 2>/dev/null || true
        fi
    done
}

# Check for subcommands
if [ "$1" = "changelog" ]; then
    CHANGELOG_MODE=true
    shift

    # Parse changelog-specific flags
    while [[ $# -gt 0 ]]; do
        case $1 in
            --since)
                CHANGELOG_SINCE="$2"
                shift 2
                ;;
            --format)
                CHANGELOG_FORMAT="$2"
                shift 2
                ;;
            --help|-h)
                echo "gh-commit-ai changelog - Generate changelog from commit history"
                echo ""
                echo "Usage: gh commit-ai changelog [options]"
                echo ""
                echo "Options:"
                echo "  --since <ref>   Generate changelog since tag/commit (e.g., v1.0.0)"
                echo "  --format <fmt>  Changelog format (default: keepachangelog)"
                echo "  --help, -h      Show this help message"
                echo ""
                echo "Examples:"
                echo "  gh commit-ai changelog"
                echo "  gh commit-ai changelog --since v1.0.0"
                echo "  gh commit-ai changelog --since HEAD~10"
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown changelog option $1"
                echo "Use 'gh commit-ai changelog --help' for usage information"
                exit 1
                ;;
        esac
    done
elif [ "$1" = "split" ]; then
    SPLIT_MODE=true
    shift

    # Parse split-specific flags
    SPLIT_DRY_RUN=false
    SPLIT_THRESHOLD=1000
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run|-n)
                SPLIT_DRY_RUN=true
                shift
                ;;
            --threshold|-t)
                SPLIT_THRESHOLD="$2"
                # Validate threshold is a positive integer
                if ! validate_positive_integer "$SPLIT_THRESHOLD" "--threshold"; then
                    exit 1
                fi
                shift 2
                ;;
            --help|-h)
                echo "gh-commit-ai split - Suggest how to split large commits"
                echo ""
                echo "Usage: gh commit-ai split [options]"
                echo ""
                echo "Analyzes staged changes and suggests logical ways to split them"
                echo "into multiple smaller commits for better git history."
                echo ""
                echo "Options:"
                echo "  --dry-run, -n         Show suggestions without creating commits"
                echo "  --threshold, -t <n>   Line count threshold for large commits (default: 1000)"
                echo "  --help, -h            Show this help message"
                echo ""
                echo "Examples:"
                echo "  gh commit-ai split"
                echo "  gh commit-ai split --dry-run"
                echo "  gh commit-ai split --threshold 500"
                echo ""
                echo "The tool will:"
                echo "  1. Analyze your staged changes"
                echo "  2. Group related files together"
                echo "  3. Suggest logical commit splits"
                echo "  4. Let you interactively apply the splits"
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown split option $1${NC}"
                echo "Use 'gh commit-ai split --help' for usage information"
                exit 1
                ;;
        esac
    done
elif [ "$1" = "version" ] || [ "$1" = "semver" ]; then
    VERSION_MODE=true
    shift

    # Parse version-specific flags
    CREATE_TAG=false
    TAG_PREFIX="v"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --create-tag|-t)
                CREATE_TAG=true
                shift
                ;;
            --prefix)
                TAG_PREFIX="$2"
                shift 2
                ;;
            --help|-h)
                echo "gh-commit-ai version - Suggest next semantic version"
                echo ""
                echo "Usage: gh commit-ai version [options]"
                echo "       gh commit-ai semver [options]"
                echo ""
                echo "Options:"
                echo "  --create-tag, -t    Create git tag for suggested version"
                echo "  --prefix <prefix>   Tag prefix (default: 'v')"
                echo "  --help, -h          Show this help message"
                echo ""
                echo "Analyzes commits since last tag to suggest next version:"
                echo "  • Breaking changes → Major bump (1.0.0 → 2.0.0)"
                echo "  • New features → Minor bump (1.0.0 → 1.1.0)"
                echo "  • Bug fixes only → Patch bump (1.0.0 → 1.0.1)"
                echo ""
                echo "Examples:"
                echo "  gh commit-ai version              # Suggest next version"
                echo "  gh commit-ai version --create-tag # Suggest and create tag"
                echo "  gh commit-ai semver -t            # Short alias with tag creation"
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown version option $1"
                echo "Use 'gh commit-ai version --help' for usage information"
                exit 1
                ;;
        esac
    done
elif [ "$1" = "install-hook" ]; then
    # Install prepare-commit-msg hook
    HOOK_DIR=".git/hooks"
    HOOK_FILE="$HOOK_DIR/prepare-commit-msg"

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}Error: Not a git repository"
        exit 1
    fi

    # Create hooks directory if it doesn't exist
    mkdir -p "$HOOK_DIR"

    # Check if hook already exists
    if [ -f "$HOOK_FILE" ]; then
        # Check if it's our hook
        if grep -q "gh-commit-ai hook" "$HOOK_FILE" 2>/dev/null; then
            echo "Hook already installed"
            exit 0
        else
            echo -e "${RED}Error: A prepare-commit-msg hook already exists"
            echo "Please manually merge or remove: $HOOK_FILE"
            exit 1
        fi
    fi

    # Create the hook
    cat > "$HOOK_FILE" << 'EOF'
#!/bin/bash
# gh-commit-ai hook
# This hook is OPT-IN: only runs when GH_COMMIT_AI=1

COMMIT_MSG_FILE="$1"
COMMIT_SOURCE="$2"

# Only run if explicitly enabled via environment variable
if [ "$GH_COMMIT_AI" != "1" ]; then
    exit 0
fi

# Don't run for merge commits, squash, or amend
if [ "$COMMIT_SOURCE" = "merge" ] || [ "$COMMIT_SOURCE" = "squash" ] || [ "$COMMIT_SOURCE" = "commit" ]; then
    exit 0
fi

# Generate commit message using gh-commit-ai
echo "Generating commit message with AI" >&2

# Run gh-commit-ai in preview mode to get the message
GENERATED_MSG=$(gh commit-ai --preview 2>&1 | grep -A 1000 "Generated commit message:" | tail -n +2)

if [ -n "$GENERATED_MSG" ]; then
    # Write the generated message to the commit message file
    echo "$GENERATED_MSG" > "$COMMIT_MSG_FILE"
    echo "✓ AI-generated message added. Review and edit if needed." >&2
else
    echo "✗ Failed to generate message, opening editor with empty message" >&2
fi
EOF

    chmod +x "$HOOK_FILE"

    echo "✓ Pre-commit hook installed successfully!"
    echo ""
    echo "Usage (OPT-IN):"
    echo "  1. Regular commits work normally:"
    echo "     git commit"
    echo ""
    echo "  2. Use AI generation when you want it:"
    echo "     GH_COMMIT_AI=1 git commit"
    echo ""
    echo "  3. Or set up a convenient alias:"
    echo "     git config alias.ai-commit '!GH_COMMIT_AI=1 git commit'"
    echo "     git ai-commit    # Use AI generation"
    echo ""
    echo "To uninstall: gh commit-ai uninstall-hook"

    exit 0

elif [ "$1" = "uninstall-hook" ]; then
    # Uninstall prepare-commit-msg hook
    HOOK_FILE=".git/hooks/prepare-commit-msg"

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}Error: Not a git repository"
        exit 1
    fi

    if [ ! -f "$HOOK_FILE" ]; then
        echo "No hook to uninstall"
        exit 0
    fi

    # Check if it's our hook
    if ! grep -q "gh-commit-ai hook" "$HOOK_FILE" 2>/dev/null; then
        echo -e "${RED}Error: Hook file exists but is not from gh-commit-ai"
        echo "Please manually review: $HOOK_FILE"
        exit 1
    fi

    rm "$HOOK_FILE"
    echo "✓ Pre-commit hook uninstalled successfully"

    # Also remove the git alias if it exists
    if git config --get alias.ai-commit > /dev/null 2>&1; then
        echo ""
        echo "Note: Git alias 'ai-commit' still exists. To remove it:"
        echo "  git config --unset alias.ai-commit"
    fi

    exit 0
elif [ "$1" = "install-man" ]; then
    # Install man page
    echo "Installing man page for gh-commit-ai..."
    echo ""

    # Determine script directory (where man/ folder is)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    MAN_SOURCE="$SCRIPT_DIR/man/gh-commit-ai.1"

    if [ ! -f "$MAN_SOURCE" ]; then
        echo "Error: Man page not found at $MAN_SOURCE"
        exit 1
    fi

    # Determine where to install man page
    # Try standard locations in order of preference
    if [ -d "/usr/local/share/man/man1" ] && [ -w "/usr/local/share/man/man1" ]; then
        MAN_DIR="/usr/local/share/man/man1"
    elif [ -d "$HOME/.local/share/man/man1" ]; then
        MAN_DIR="$HOME/.local/share/man/man1"
    elif [ -d "$HOME/.local/share/man" ]; then
        mkdir -p "$HOME/.local/share/man/man1"
        MAN_DIR="$HOME/.local/share/man/man1"
    else
        # Create user man directory
        mkdir -p "$HOME/.local/share/man/man1"
        MAN_DIR="$HOME/.local/share/man/man1"
    fi

    # Copy man page
    cp "$MAN_SOURCE" "$MAN_DIR/gh-commit-ai.1"

    if [ $? -eq 0 ]; then
        echo "✓ Man page installed to $MAN_DIR/gh-commit-ai.1"
        echo ""
        echo "You can now view the manual with:"
        echo "  man gh-commit-ai"
        echo ""

        # Update man database if possible
        if command -v mandb >/dev/null 2>&1; then
            echo "Updating man database..."
            mandb -q 2>/dev/null || true
        fi

        # Check if man can find it
        if man -w gh-commit-ai >/dev/null 2>&1; then
            echo "✓ Man page is accessible"
        else
            echo "Note: You may need to add $HOME/.local/share/man to your MANPATH:"
            echo "  export MANPATH=\"\$HOME/.local/share/man:\$MANPATH\""
        fi
    else
        echo "Error: Failed to install man page"
        exit 1
    fi

    exit 0
elif [ "$1" = "uninstall-man" ]; then
    # Uninstall man page
    echo "Uninstalling man page for gh-commit-ai..."
    echo ""

    # Check standard locations
    MAN_LOCATIONS=(
        "/usr/local/share/man/man1/gh-commit-ai.1"
        "$HOME/.local/share/man/man1/gh-commit-ai.1"
    )

    FOUND=false
    for man_file in "${MAN_LOCATIONS[@]}"; do
        if [ -f "$man_file" ]; then
            rm -f "$man_file"
            echo "✓ Removed $man_file"
            FOUND=true
        fi
    done

    if [ "$FOUND" = false ]; then
        echo "No man page found to remove"
    else
        echo ""
        echo "Man page uninstalled successfully"

        # Update man database if possible
        if command -v mandb >/dev/null 2>&1; then
            echo "Updating man database..."
            mandb -q 2>/dev/null || true
        fi
    fi

    exit 0
elif [ "$1" = "install-completion" ]; then
    # Install shell completion
    echo "Installing shell completion for gh-commit-ai..."
    echo ""

    # Detect shell
    CURRENT_SHELL=$(basename "$SHELL")

    # Determine script directory (where completions/ folder is)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [ "$CURRENT_SHELL" = "bash" ]; then
        # Bash completion
        COMPLETION_SOURCE="$SCRIPT_DIR/completions/gh-commit-ai.bash"

        if [ ! -f "$COMPLETION_SOURCE" ]; then
            echo -e "${RED}Error: Completion file not found: $COMPLETION_SOURCE${NC}"
            exit 1
        fi

        # Try standard locations
        if [ -d "/usr/local/etc/bash_completion.d" ]; then
            # macOS (Homebrew)
            sudo cp "$COMPLETION_SOURCE" "/usr/local/etc/bash_completion.d/gh-commit-ai"
            echo "✓ Installed to /usr/local/etc/bash_completion.d/gh-commit-ai"
        elif [ -d "/etc/bash_completion.d" ]; then
            # Linux
            sudo cp "$COMPLETION_SOURCE" "/etc/bash_completion.d/gh-commit-ai"
            echo "✓ Installed to /etc/bash_completion.d/gh-commit-ai"
        else
            # User-local installation
            mkdir -p "$HOME/.bash_completion.d"
            cp "$COMPLETION_SOURCE" "$HOME/.bash_completion.d/gh-commit-ai"
            echo "✓ Installed to $HOME/.bash_completion.d/gh-commit-ai"
            echo ""
            echo "Add this to your ~/.bashrc to enable:"
            echo "  source $HOME/.bash_completion.d/gh-commit-ai"
        fi

        echo ""
        echo "Restart your shell or run: source ~/.bashrc"

    elif [ "$CURRENT_SHELL" = "zsh" ]; then
        # Zsh completion
        COMPLETION_SOURCE="$SCRIPT_DIR/completions/_gh-commit-ai"

        if [ ! -f "$COMPLETION_SOURCE" ]; then
            echo -e "${RED}Error: Completion file not found: $COMPLETION_SOURCE${NC}"
            exit 1
        fi

        # Try standard locations
        if [ -d "/usr/local/share/zsh/site-functions" ]; then
            # macOS (Homebrew)
            sudo cp "$COMPLETION_SOURCE" "/usr/local/share/zsh/site-functions/_gh-commit-ai"
            echo "✓ Installed to /usr/local/share/zsh/site-functions/_gh-commit-ai"
        elif [ -d "/usr/share/zsh/site-functions" ]; then
            # Linux
            sudo cp "$COMPLETION_SOURCE" "/usr/share/zsh/site-functions/_gh-commit-ai"
            echo "✓ Installed to /usr/share/zsh/site-functions/_gh-commit-ai"
        else
            # User-local installation
            mkdir -p "$HOME/.zsh/completion"
            cp "$COMPLETION_SOURCE" "$HOME/.zsh/completion/_gh-commit-ai"
            echo "✓ Installed to $HOME/.zsh/completion/_gh-commit-ai"
            echo ""
            echo "Add this to your ~/.zshrc to enable:"
            echo "  fpath=(\$HOME/.zsh/completion \$fpath)"
            echo "  autoload -Uz compinit && compinit"
        fi

        echo ""
        echo "Restart your shell or run: exec zsh"

    else
        echo -e "${YELLOW}Warning: Unknown shell: $CURRENT_SHELL${NC}"
        echo "Supported shells: bash, zsh"
        echo ""
        echo "Manual installation:"
        echo "  Bash: Copy completions/gh-commit-ai.bash to your bash completion directory"
        echo "  Zsh:  Copy completions/_gh-commit-ai to your zsh completion directory"
        exit 1
    fi

    exit 0
elif [ "$1" = "uninstall-completion" ]; then
    # Uninstall shell completion
    echo "Uninstalling shell completion for gh-commit-ai..."
    echo ""

    # Detect shell
    CURRENT_SHELL=$(basename "$SHELL")

    if [ "$CURRENT_SHELL" = "bash" ]; then
        # Try standard locations
        REMOVED=false

        if [ -f "/usr/local/etc/bash_completion.d/gh-commit-ai" ]; then
            sudo rm "/usr/local/etc/bash_completion.d/gh-commit-ai"
            echo "✓ Removed from /usr/local/etc/bash_completion.d/"
            REMOVED=true
        fi

        if [ -f "/etc/bash_completion.d/gh-commit-ai" ]; then
            sudo rm "/etc/bash_completion.d/gh-commit-ai"
            echo "✓ Removed from /etc/bash_completion.d/"
            REMOVED=true
        fi

        if [ -f "$HOME/.bash_completion.d/gh-commit-ai" ]; then
            rm "$HOME/.bash_completion.d/gh-commit-ai"
            echo "✓ Removed from $HOME/.bash_completion.d/"
            REMOVED=true
        fi

        if [ "$REMOVED" = false ]; then
            echo "No completion file found to remove"
        else
            echo ""
            echo "Restart your shell for changes to take effect"
        fi

    elif [ "$CURRENT_SHELL" = "zsh" ]; then
        # Try standard locations
        REMOVED=false

        if [ -f "/usr/local/share/zsh/site-functions/_gh-commit-ai" ]; then
            sudo rm "/usr/local/share/zsh/site-functions/_gh-commit-ai"
            echo "✓ Removed from /usr/local/share/zsh/site-functions/"
            REMOVED=true
        fi

        if [ -f "/usr/share/zsh/site-functions/_gh-commit-ai" ]; then
            sudo rm "/usr/share/zsh/site-functions/_gh-commit-ai"
            echo "✓ Removed from /usr/share/zsh/site-functions/"
            REMOVED=true
        fi

        if [ -f "$HOME/.zsh/completion/_gh-commit-ai" ]; then
            rm "$HOME/.zsh/completion/_gh-commit-ai"
            echo "✓ Removed from $HOME/.zsh/completion/"
            REMOVED=true
        fi

        if [ "$REMOVED" = false ]; then
            echo "No completion file found to remove"
        else
            echo ""
            echo "Run: rm -f ~/.zcompdump && exec zsh"
        fi

    else
        echo -e "${YELLOW}Warning: Unknown shell: $CURRENT_SHELL${NC}"
        echo "Supported shells: bash, zsh"
        exit 1
    fi

    exit 0
elif [ "$1" = "pr-description" ]; then
    PR_DESCRIPTION_MODE=true
    shift

    # Parse pr-description-specific flags
    BASE_BRANCH=""
    OUTPUT_FILE=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --base)
                BASE_BRANCH="$2"
                shift 2
                ;;
            --output|-o)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --help|-h)
                echo "gh-commit-ai pr-description - Generate PR description from commits"
                echo ""
                echo "Usage: gh commit-ai pr-description [options]"
                echo ""
                echo "Options:"
                echo "  --base <branch>     Base branch to compare against (default: auto-detect)"
                echo "  --output, -o <file> Save to file instead of stdout"
                echo "  --help, -h          Show this help message"
                echo ""
                echo "Examples:"
                echo "  gh commit-ai pr-description"
                echo "  gh commit-ai pr-description --base main"
                echo "  gh commit-ai pr-description --output pr.md"
                echo "  gh pr create --body \"\$(gh commit-ai pr-description)\""
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown pr-description option $1"
                echo "Use 'gh commit-ai pr-description --help' for usage information"
                exit 1
                ;;
        esac
    done
elif [ "$1" = "review" ]; then
    CODE_REVIEW_MODE=true
    shift

    # Parse review-specific flags
    REVIEW_STAGED_ONLY=true  # Default to staged changes
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                REVIEW_STAGED_ONLY=false
                shift
                ;;
            --help|-h)
                echo "gh-commit-ai review - Code review assistant for your changes"
                echo ""
                echo "Usage: gh commit-ai review [options]"
                echo ""
                echo "Options:"
                echo "  --all               Review all changes (staged + unstaged)"
                echo "  --help, -h          Show this help message"
                echo ""
                echo "Reviews your changes for:"
                echo "  • Security vulnerabilities"
                echo "  • Performance concerns"
                echo "  • Code style issues"
                echo "  • Missing error handling"
                echo "  • Potential bugs"
                echo "  • TODO/FIXME comments"
                echo ""
                echo "Examples:"
                echo "  gh commit-ai review              # Review staged changes"
                echo "  gh commit-ai review --all        # Review all changes"
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown review option $1"
                echo "Use 'gh commit-ai review --help' for usage information"
                exit 1
                ;;
        esac
    done
elif [ "$1" = "stats" ]; then
    generate_stats_report
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --preview)
            PREVIEW=true
            shift
            ;;
        --amend)
            AMEND=true
            shift
            ;;
        --options)
            MULTIPLE_OPTIONS=true
            shift
            ;;
        --version)
            echo "gh-commit-ai version $VERSION"
            exit 0
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --type)
            FORCED_TYPE="$2"
            # Validate type is one of the allowed conventional commit types
            if ! validate_allowed_values "$FORCED_TYPE" "--type" "feat" "fix" "docs" "style" "refactor" "test" "chore" "perf" "ci" "build" "revert"; then
                exit 1
            fi
            shift 2
            ;;
        --max-lines)
            CUSTOM_MAX_LINES="$2"
            # Validate max-lines is a positive integer
            if ! validate_positive_integer "$CUSTOM_MAX_LINES" "--max-lines"; then
                exit 1
            fi
            shift 2
            ;;
        --no-lowercase)
            NO_LOWERCASE=true
            shift
            ;;
        --no-stream)
            STREAM_ENABLED="false"
            shift
            ;;
        --help|-h)
            echo "gh-commit-ai - AI-powered git commit message generator"
            echo ""
            echo "Usage: gh commit-ai [options]"
            echo "       gh commit-ai <command> [options]"
            echo ""
            echo "Commands:"
            echo "  (default)            Generate commit message for current changes"
            echo "  review               Review code changes for potential issues"
            echo "  version              Suggest next semantic version number"
            echo "  changelog            Generate changelog from commit history"
            echo "  pr-description       Generate PR description from branch commits"
            echo "  install-hook         Install git hook for opt-in AI commits"
            echo "  uninstall-hook       Remove git hook"
            echo "  install-man          Install man page"
            echo "  uninstall-man        Remove man page"
            echo "  stats                Show usage statistics (requires analytics_enabled)"
            echo "  install-completion   Install shell completion (bash/zsh)"
            echo "  uninstall-completion Remove shell completion"
            echo ""
            echo "Options:"
            echo "  --dry-run           Generate commit message without committing"
            echo "  --preview           Generate and display message, then exit"
            echo "  --amend             Regenerate message for last commit"
            echo "  --options           Generate multiple variations to choose from"
            echo "  --type <type>       Force a specific commit type (feat, fix, docs, etc.)"
            echo "  --max-lines <n>     Override DIFF_MAX_LINES for this run"
            echo "  --no-lowercase      Disable automatic lowercase enforcement"
            echo "  --no-stream         Disable streaming output from AI provider"
            echo "  --verbose, -v       Show detailed API request/response info"
            echo "  --version           Show version number"
            echo "  --help, -h          Show this help message"
            echo ""
            echo "Interactive Options (when reviewing commit message):"
            echo "  y - Accept and commit"
            echo "  n - Cancel"
            echo "  e - Edit in your default editor"
            echo ""
            echo "Environment Variables:"
            echo "  AI_PROVIDER         AI provider (auto, ollama, anthropic, openai, groq)"
            echo "                      Default: auto (detects what's available)"
            echo "  COMMIT_LANGUAGE     Language for commit messages (en, es, fr, de, ja, zh, etc.)"
            echo "                      Default: auto-detect from system locale"
            echo "  USE_SCOPE           Enable/disable scopes (true/false)"
            echo "  USE_GITMOJI         Enable/disable gitmoji prefixes (true/false)"
            echo "  AUTO_FIX            Auto-fix common formatting issues (true/false)"
            echo "                      Default: true"
            echo "  DIFF_MAX_LINES      Maximum diff lines to send to AI"
            echo "  GH_COMMIT_AI        Set to 1 to enable hook (opt-in)"
            echo ""
            echo "Configuration Files:"
            echo "  .gh-commit-ai.yml       Local config (repo root)"
            echo "  ~/.gh-commit-ai.yml     Global config"
            echo ""
            echo "Examples:"
            echo "  gh commit-ai"
            echo "  gh commit-ai --dry-run"
            echo "  gh commit-ai --preview"
            echo "  gh commit-ai --amend"
            echo "  gh commit-ai changelog"
            echo "  gh commit-ai changelog --since v1.0.0"
            echo "  gh commit-ai install-hook"
            echo "  gh commit-ai install-completion"
            echo "  GH_COMMIT_AI=1 git commit    # With hook installed"
            echo "  USE_SCOPE=false gh commit-ai"
            echo "  USE_GITMOJI=true gh commit-ai"
            echo "  AUTO_FIX=false gh commit-ai      # Disable auto-fix"
            echo "  COMMIT_LANGUAGE=es gh commit-ai    # Spanish messages"
            echo "  COMMIT_LANGUAGE=ja gh commit-ai    # Japanese messages"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Apply command-line overrides
if [ -n "$CUSTOM_MAX_LINES" ]; then
    DIFF_MAX_LINES="$CUSTOM_MAX_LINES"
fi

