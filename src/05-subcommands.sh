# Generate changelog from commit history
generate_changelog() {
    local since_ref="$1"
    local format="$2"

    # Build git log command
    local log_cmd="git log --pretty=format:'%H|%s|%b' --no-merges"
    if [ -n "$since_ref" ]; then
        # Check if the reference exists
        if ! git rev-parse "$since_ref" >/dev/null 2>&1; then
            echo -e "${RED}Error: Reference '$since_ref' not found"
            exit 1
        fi
        log_cmd="$log_cmd ${since_ref}..HEAD"
    fi

    # Get commits
    local commits=$(eval "$log_cmd")

    if [ -z "$commits" ]; then
        echo "No commits found"
        exit 0
    fi

    # Initialize arrays for different types
    local breaking_changes=()
    local features=()
    local fixes=()
    local docs=()
    local style=()
    local refactor=()
    local performance=()
    local tests=()
    local chores=()
    local other=()

    # Parse commits
    while IFS='|' read -r hash subject body; do
        # Parse conventional commit format
        local type=""
        local scope=""
        local description=""
        local is_breaking=false

        # Check for breaking change indicator
        if [[ "$subject" =~ ^([a-z]+)(\([a-z0-9_-]+\))?!:\ (.+)$ ]]; then
            type="${BASH_REMATCH[1]}"
            scope="${BASH_REMATCH[2]}"
            description="${BASH_REMATCH[3]}"
            is_breaking=true
        elif [[ "$subject" =~ ^([a-z]+)(\([a-z0-9_-]+\))?:\ (.+)$ ]]; then
            type="${BASH_REMATCH[1]}"
            scope="${BASH_REMATCH[2]}"
            description="${BASH_REMATCH[3]}"
        else
            # Not a conventional commit, skip or put in other
            type="other"
            description="$subject"
        fi

        # Remove parentheses from scope
        scope="${scope#(}"
        scope="${scope%)}"

        # Check body for BREAKING CHANGE
        if echo "$body" | grep -qiE '^BREAKING CHANGE:'; then
            is_breaking=true
        fi

        # Format entry
        local entry="- $description"
        if [ -n "$scope" ]; then
            entry="- **$scope**: $description"
        fi
        entry="$entry ([${hash:0:7}](../../commit/$hash))"

        # Categorize by type
        if [ "$is_breaking" = true ]; then
            breaking_changes+=("$entry")
        fi

        case "$type" in
            feat|feature)
                features+=("$entry")
                ;;
            fix)
                fixes+=("$entry")
                ;;
            docs)
                docs+=("$entry")
                ;;
            style)
                style+=("$entry")
                ;;
            refactor)
                refactor+=("$entry")
                ;;
            perf|performance)
                performance+=("$entry")
                ;;
            test|tests)
                tests+=("$entry")
                ;;
            chore|build|ci)
                chores+=("$entry")
                ;;
            *)
                other+=("$entry")
                ;;
        esac
    done <<< "$commits"

    # Generate changelog based on format
    echo ""
    echo "# Changelog"
    echo ""

    # Determine version header
    local version_header="Unreleased"
    if [ -n "$since_ref" ]; then
        # Try to get the next version from the since ref
        local current_version="$since_ref"
        version_header="[${current_version#v}...HEAD]"
    fi

    echo "## $version_header"
    echo ""
    echo "### Date: $(date +%Y-%m-%d)"
    echo ""

    # Breaking changes first (most important)
    if [ ${#breaking_changes[@]} -gt 0 ]; then
        echo "### ⚠️ BREAKING CHANGES"
        echo ""
        for entry in "${breaking_changes[@]}"; do
            echo "$entry"
        done
        echo ""
    fi

    # Features
    if [ ${#features[@]} -gt 0 ]; then
        echo "### ✨ Features"
        echo ""
        for entry in "${features[@]}"; do
            echo "$entry"
        done
        echo ""
    fi

    # Bug fixes
    if [ ${#fixes[@]} -gt 0 ]; then
        echo "### 🐛 Bug Fixes"
        echo ""
        for entry in "${fixes[@]}"; do
            echo "$entry"
        done
        echo ""
    fi

    # Documentation
    if [ ${#docs[@]} -gt 0 ]; then
        echo "### 📝 Documentation"
        echo ""
        for entry in "${docs[@]}"; do
            echo "$entry"
        done
        echo ""
    fi

    # Performance improvements
    if [ ${#performance[@]} -gt 0 ]; then
        echo "### ⚡ Performance"
        echo ""
        for entry in "${performance[@]}"; do
            echo "$entry"
        done
        echo ""
    fi

    # Refactoring
    if [ ${#refactor[@]} -gt 0 ]; then
        echo "### ♻️ Refactoring"
        echo ""
        for entry in "${refactor[@]}"; do
            echo "$entry"
        done
        echo ""
    fi

    # Tests
    if [ ${#tests[@]} -gt 0 ]; then
        echo "### ✅ Tests"
        echo ""
        for entry in "${tests[@]}"; do
            echo "$entry"
        done
        echo ""
    fi

    # Style changes
    if [ ${#style[@]} -gt 0 ]; then
        echo "### 💄 Style"
        echo ""
        for entry in "${style[@]}"; do
            echo "$entry"
        done
        echo ""
    fi

    # Chores
    if [ ${#chores[@]} -gt 0 ]; then
        echo "### 🔧 Chores"
        echo ""
        for entry in "${chores[@]}"; do
            echo "$entry"
        done
        echo ""
    fi

    # Other
    if [ ${#other[@]} -gt 0 ]; then
        echo "### Other Changes"
        echo ""
        for entry in "${other[@]}"; do
            echo "$entry"
        done
        echo ""
    fi
}

# Suggest next semantic version based on commits
suggest_next_version() {
    local create_tag="$1"
    local tag_prefix="$2"

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}Error: Not a git repository${NC}" >&2
        exit 1
    fi

    # Get the last tag
    local last_tag=$(git describe --tags --abbrev=0 2>/dev/null)

    if [ -z "$last_tag" ]; then
        echo -e "${YELLOW}No tags found in repository${NC}"
        echo ""
        echo "Suggested first version: ${GREEN}${tag_prefix}0.1.0${NC}"
        echo ""
        echo "Reasoning:"
        echo "  • No previous tags exist"
        echo "  • Starting with 0.1.0 (pre-release version)"
        echo "  • Use 1.0.0 when ready for first stable release"
        echo ""

        if [ "$create_tag" = true ]; then
            echo -n "Create tag ${tag_prefix}0.1.0? (y/n): "
            read -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                git tag -a "${tag_prefix}0.1.0" -m "Release ${tag_prefix}0.1.0"
                echo -e "${GREEN}✓ Tag ${tag_prefix}0.1.0 created${NC}"
                echo "Push with: git push origin ${tag_prefix}0.1.0"
            else
                echo "Tag creation cancelled"
            fi
        fi
        return 0
    fi

    # Parse the current version
    local current_version="${last_tag#$tag_prefix}"  # Remove prefix

    # Extract major, minor, patch
    if [[ ! "$current_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        echo -e "${RED}Error: Cannot parse version from tag: $last_tag${NC}" >&2
        echo "Expected format: ${tag_prefix}X.Y.Z (e.g., v1.2.3)" >&2
        exit 1
    fi

    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"
    local patch="${BASH_REMATCH[3]}"

    echo -e "${BLUE}Current version: ${NC}${last_tag}"
    echo ""

    # Get commits since last tag
    local commits=$(git log "$last_tag..HEAD" --pretty=format:"%s" 2>/dev/null)

    if [ -z "$commits" ]; then
        echo -e "${YELLOW}No new commits since ${last_tag}${NC}"
        echo ""
        echo "Next version would be: ${GREEN}${tag_prefix}${major}.${minor}.${patch}${NC} (no change)"
        return 0
    fi

    # Count commit types
    local breaking_count=0
    local feat_count=0
    local fix_count=0
    local other_count=0

    # Analyze each commit
    while IFS= read -r commit_msg; do
        # Check for breaking changes (! after type or BREAKING CHANGE in message)
        if [[ "$commit_msg" =~ ^[a-z]+(\([a-z0-9_-]+\))?!: ]] || [[ "$commit_msg" =~ BREAKING[[:space:]]CHANGE ]]; then
            ((breaking_count++))
        # Check for features
        elif [[ "$commit_msg" =~ ^feat(\([a-z0-9_-]+\))?: ]]; then
            ((feat_count++))
        # Check for fixes
        elif [[ "$commit_msg" =~ ^fix(\([a-z0-9_-]+\))?: ]]; then
            ((fix_count++))
        else
            ((other_count++))
        fi
    done <<< "$commits"

    # Determine version bump
    local bump_type=""
    local new_major=$major
    local new_minor=$minor
    local new_patch=$patch

    if [ $breaking_count -gt 0 ]; then
        # Breaking changes → Major bump
        bump_type="major"
        ((new_major++))
        new_minor=0
        new_patch=0
    elif [ $feat_count -gt 0 ]; then
        # New features → Minor bump
        bump_type="minor"
        ((new_minor++))
        new_patch=0
    elif [ $fix_count -gt 0 ]; then
        # Bug fixes → Patch bump
        bump_type="patch"
        ((new_patch++))
    else
        # Only other commits (docs, chore, etc.) → Patch bump
        bump_type="patch"
        ((new_patch++))
    fi

    local suggested_version="${tag_prefix}${new_major}.${new_minor}.${new_patch}"

    # Display analysis
    echo -e "${GREEN}Suggested version: ${suggested_version}${NC} (${bump_type} bump)"
    echo ""
    echo "Analysis of $(echo "$commits" | wc -l | tr -d ' ') commits since ${last_tag}:"
    [ $breaking_count -gt 0 ] && echo "  • ${breaking_count} breaking change(s) → Major bump required"
    [ $feat_count -gt 0 ] && echo "  • ${feat_count} new feature(s)"
    [ $fix_count -gt 0 ] && echo "  • ${fix_count} bug fix(es)"
    [ $other_count -gt 0 ] && echo "  • ${other_count} other commit(s) (docs, chore, etc.)"
    echo ""

    # Show reasoning
    echo "Reasoning:"
    if [ $breaking_count -gt 0 ]; then
        echo "  • Breaking changes detected → MAJOR bump"
        echo "  • Bumping from ${major}.${minor}.${patch} to ${new_major}.${new_minor}.${new_patch}"
    elif [ $feat_count -gt 0 ]; then
        echo "  • New features added (no breaking changes) → MINOR bump"
        echo "  • Bumping from ${major}.${minor}.${patch} to ${new_major}.${new_minor}.${new_patch}"
    else
        echo "  • Only fixes and other changes → PATCH bump"
        echo "  • Bumping from ${major}.${minor}.${patch} to ${new_major}.${new_minor}.${new_patch}"
    fi
    echo ""

    # Create tag if requested
    if [ "$create_tag" = true ]; then
        echo -n "Create tag ${suggested_version}? (y/n): "
        read -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Generate tag message from commit summary
            local tag_message="Release ${suggested_version}"
            if [ $breaking_count -gt 0 ]; then
                tag_message="${tag_message}\n\nBreaking Changes: ${breaking_count}"
            fi
            if [ $feat_count -gt 0 ]; then
                tag_message="${tag_message}\nNew Features: ${feat_count}"
            fi
            if [ $fix_count -gt 0 ]; then
                tag_message="${tag_message}\nBug Fixes: ${fix_count}"
            fi

            git tag -a "${suggested_version}" -m "$(echo -e "$tag_message")"
            echo -e "${GREEN}✓ Tag ${suggested_version} created${NC}"
            echo ""
            echo "Next steps:"
            echo "  git push origin ${suggested_version}     # Push the tag"
            echo "  git push                                 # Push commits"
        else
            echo "Tag creation cancelled"
        fi
    else
        echo "To create this tag:"
        echo "  git tag -a ${suggested_version} -m \"Release ${suggested_version}\""
        echo "  git push origin ${suggested_version}"
    fi
}

# Suggest commit splits for large changes
suggest_commit_splits() {
    local threshold="$1"
    local dry_run="$2"

    # Check if we're in a git repository
    GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
    if [ -z "$GIT_DIR" ]; then
        echo -e "${RED}Error: Not a git repository${NC}" >&2
        exit 1
    fi

    echo -e "${BLUE}← Analyzing staged changes${NC}" >&2

    # Get staged changes
    local diff_content
    diff_content=$(git diff --cached)

    if [ -z "$diff_content" ]; then
        echo -e "${RED}Error: No staged changes to analyze${NC}" >&2
        echo "Tip: Stage your changes with 'git add' first" >&2
        exit 1
    fi

    # Count total lines changed
    local stats
    stats=$(git diff --cached --numstat)
    local total_lines=0
    while IFS=$'\t' read -r added removed file; do
        if [[ "$added" =~ ^[0-9]+$ ]] && [[ "$removed" =~ ^[0-9]+$ ]]; then
            total_lines=$((total_lines + added + removed))
        fi
    done <<< "$stats"

    echo -e "✓ Analyzed $total_lines lines across $(echo "$stats" | wc -l | tr -d ' ') files"

    # Check if changes exceed threshold
    if [ $total_lines -lt $threshold ]; then
        echo -e "${GREEN}✓ Changes are below threshold ($total_lines < $threshold lines)${NC}"
        echo "Your commit is a reasonable size. No split needed!"
        exit 0
    fi

    echo -e "${YELLOW}⚠ Large commit detected: $total_lines lines (threshold: $threshold)${NC}"
    echo ""

    # Get file list with stats for AI analysis
    local file_summary=""
    while IFS=$'\t' read -r added removed file; do
        if [[ "$added" =~ ^[0-9]+$ ]] && [[ "$removed" =~ ^[0-9]+$ ]]; then
            file_summary="${file_summary}${file}: +${added} -${removed}\n"
        fi
    done <<< "$stats"

    # Sample the diff intelligently (use existing smart_sample_diff function)
    local sampled_diff
    sampled_diff=$(smart_sample_diff "$diff_content" 500)

    # Create prompt for AI
    local prompt="Analyze this large git commit and suggest how to split it into logical, smaller commits.

COMMIT SIZE: $total_lines lines changed

FILES CHANGED:
$file_summary

DIFF SAMPLE (first 500 lines):
$sampled_diff

Please suggest 2-4 logical ways to split this commit. For each suggested commit, provide:
1. A brief description of what it contains
2. The list of files that should be included
3. Why these changes belong together

Format your response as:

## Split Suggestion 1: [Description]
**Files:**
- file1.ext
- file2.ext

**Rationale:** [Why these changes belong together]

## Split Suggestion 2: [Description]
...

Focus on:
- Grouping related functionality together
- Separating different concerns (e.g., tests from implementation, docs from code)
- Creating commits that are independently reviewable
- Maintaining logical dependencies (e.g., don't split a function from its tests)

Be specific and practical."

    # Call AI to get split suggestions
    echo -e "${BLUE}← Thinking (analyzing commit structure)${NC}" >&2

    local suggestions
    suggestions=$(call_ai_for_split "$prompt")

    if [ -z "$suggestions" ]; then
        echo -e "${RED}Error: Failed to generate split suggestions${NC}" >&2
        exit 1
    fi

    # Display suggestions
    echo ""
    echo -e "${GREEN}═══ Split Suggestions ═══${NC}"
    echo ""
    echo "$suggestions"
    echo ""
    echo -e "${GREEN}═══════════════════════${NC}"
    echo ""

    # Interactive mode (if not dry-run)
    if [ "$dry_run" = "false" ]; then
        echo -e "${YELLOW}Note: Applying splits will require manual file staging.${NC}"
        echo "The suggestions above show logical groupings."
        echo ""
        echo "To apply these splits:"
        echo "  1. Reset staged changes: git reset"
        echo "  2. Stage files for first commit: git add file1 file2..."
        echo "  3. Commit: git commit -m \"message\""
        echo "  4. Repeat for each split"
        echo ""
        echo "Or use: gh commit-ai (to generate commit messages)"
    fi
}

# Helper function to call AI for split suggestions
call_ai_for_split() {
    local prompt="$1"

    # Detect and use available AI provider
    if [ "$AI_PROVIDER" = "auto" ]; then
        detect_available_providers > /dev/null
    fi

    # Route to appropriate provider
    case "$AI_PROVIDER" in
        ollama)
            call_ollama "$prompt"
            ;;
        anthropic)
            call_anthropic "$prompt"
            ;;
        openai)
            call_openai "$prompt"
            ;;
        groq)
            call_groq "$prompt"
            ;;
        *)
            echo -e "${RED}Error: Unknown AI provider: $AI_PROVIDER${NC}" >&2
            exit 1
            ;;
    esac
}

# Generate code review for changes
generate_code_review() {
    local review_all="$1"  # true = all changes, false = staged only

    # Check if we're in a git repository
    GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
    if [ -z "$GIT_DIR" ]; then
        echo -e "${RED}Error: Not a git repository${NC}" >&2
        exit 1
    fi

    echo -e "${BLUE}← Analyzing changes${NC}" >&2

    # Get the diff to review (exclude lock files)
    local diff_content
    if [ "$review_all" = false ]; then
        # Staged changes only
        diff_content=$(eval "git diff --cached $GIT_EXCLUDE_PATTERN")
        if [ -z "$diff_content" ]; then
            echo -e "${RED}Error: No staged changes to review${NC}" >&2
            echo "Tip: Stage your changes with 'git add' or use --all to review all changes" >&2
            exit 1
        fi
    else
        # All changes (staged + unstaged)
        diff_content=$(eval "git diff HEAD $GIT_EXCLUDE_PATTERN")
        if [ -z "$diff_content" ]; then
            echo -e "${RED}Error: No changes to review${NC}" >&2
            exit 1
        fi
    fi

    # Apply smart sampling if diff is too large
    diff_content=$(smart_sample_diff "$diff_content" "$DIFF_MAX_LINES")

    # Get file statistics (exclude lock files)
    local file_stats
    if [ "$review_all" = false ]; then
        file_stats=$(eval "git diff --cached --stat $GIT_EXCLUDE_PATTERN")
    else
        file_stats=$(eval "git diff HEAD --stat $GIT_EXCLUDE_PATTERN")
    fi

    echo -e "${BLUE}✓ Changes analyzed${NC}" >&2

    # Build the review prompt
    local review_prompt="You are an expert code reviewer. Analyze the following code changes and provide a comprehensive code review.

Focus on identifying:
1. **Security Issues**: SQL injection, XSS, CSRF, insecure dependencies, exposed secrets, etc.
2. **Performance Concerns**: Inefficient algorithms, unnecessary loops, memory leaks, blocking operations
3. **Code Quality**: Violations of best practices, poor naming, duplicated code, overly complex logic
4. **Error Handling**: Missing try-catch blocks, unhandled errors, improper error propagation
5. **Potential Bugs**: Logic errors, edge cases, null/undefined handling, race conditions
6. **Maintainability**: TODO/FIXME comments, magic numbers, lack of documentation, tight coupling

For each issue found:
- Use a severity marker: 🔴 Critical, 🟡 Warning, 🔵 Info
- Specify the file and line number
- Explain the issue clearly
- Suggest a fix or improvement

If no significant issues are found, provide a brief positive review.

Format your review as:
## Code Review Summary
[Brief overall assessment]

## Issues Found
[List each issue with severity, location, description, and suggestion]

## Recommendations
[General recommendations for improvement]

File changes:
\`\`\`
$file_stats
\`\`\`

Code diff:
\`\`\`diff
$diff_content
\`\`\`

Provide your review:"

    echo "" >&2

    # Use dedicated code review models if configured, otherwise fall back to regular models
    local original_ollama_model="$OLLAMA_MODEL"
    local original_anthropic_model="$ANTHROPIC_MODEL"
    local original_openai_model="$OPENAI_MODEL"
    local original_groq_model="$GROQ_MODEL"
    local using_dedicated_model=false

    if [ "$AI_PROVIDER" = "ollama" ] && [ -n "$CODE_REVIEW_MODEL" ]; then
        OLLAMA_MODEL="$CODE_REVIEW_MODEL"
        using_dedicated_model=true
        echo -e "${BLUE}Using dedicated review model: $OLLAMA_MODEL${NC}" >&2
    elif [ "$AI_PROVIDER" = "anthropic" ] && [ -n "$CODE_REVIEW_ANTHROPIC_MODEL" ]; then
        ANTHROPIC_MODEL="$CODE_REVIEW_ANTHROPIC_MODEL"
        using_dedicated_model=true
        echo -e "${BLUE}Using dedicated review model: $ANTHROPIC_MODEL${NC}" >&2
    elif [ "$AI_PROVIDER" = "openai" ] && [ -n "$CODE_REVIEW_OPENAI_MODEL" ]; then
        OPENAI_MODEL="$CODE_REVIEW_OPENAI_MODEL"
        using_dedicated_model=true
        echo -e "${BLUE}Using dedicated review model: $OPENAI_MODEL${NC}" >&2
    elif [ "$AI_PROVIDER" = "groq" ] && [ -n "$CODE_REVIEW_GROQ_MODEL" ]; then
        GROQ_MODEL="$CODE_REVIEW_GROQ_MODEL"
        using_dedicated_model=true
        echo -e "${BLUE}Using dedicated review model: $GROQ_MODEL${NC}" >&2
    else
        # Using regular model - show which one and potentially recommend a better model
        local current_model
        case "$AI_PROVIDER" in
            ollama)
                current_model="$OLLAMA_MODEL"
                echo -e "${BLUE}Using $AI_PROVIDER model: $current_model${NC}" >&2

                # Recommend better models for code review if using a small/weak model
                if [[ "$current_model" =~ (gemma2:2b|gemma3:4b|llama3.2:1b|llama3.2:3b|phi3:mini) ]]; then
                    echo -e "${YELLOW}💡 Tip: For better code reviews, consider using a larger model:${NC}" >&2
                    echo -e "${YELLOW}   CODE_REVIEW_MODEL=\"qwen2.5-coder:14b\" or \"deepseek-coder:6.7b\"${NC}" >&2
                    echo -e "${YELLOW}   Or add to .gh-commit-ai.yml: code_review_model: qwen2.5-coder:14b${NC}" >&2
                    echo "" >&2
                fi
                ;;
            anthropic)
                current_model="$ANTHROPIC_MODEL"
                echo -e "${BLUE}Using $AI_PROVIDER model: $current_model${NC}" >&2

                # Recommend Opus or Sonnet for code review if using Haiku
                if [[ "$current_model" =~ haiku ]]; then
                    echo -e "${YELLOW}💡 Tip: For more thorough code reviews, consider using Claude Sonnet or Opus${NC}" >&2
                    echo -e "${YELLOW}   CODE_REVIEW_ANTHROPIC_MODEL=\"claude-3-5-sonnet-20241022\"${NC}" >&2
                    echo "" >&2
                fi
                ;;
            openai)
                current_model="$OPENAI_MODEL"
                echo -e "${BLUE}Using $AI_PROVIDER model: $current_model${NC}" >&2

                # Recommend GPT-4o for code review if using mini
                if [[ "$current_model" =~ mini ]]; then
                    echo -e "${YELLOW}💡 Tip: For more thorough code reviews, consider using GPT-4o${NC}" >&2
                    echo -e "${YELLOW}   CODE_REVIEW_OPENAI_MODEL=\"gpt-4o\"${NC}" >&2
                    echo "" >&2
                fi
                ;;
            groq)
                current_model="$GROQ_MODEL"
                echo -e "${BLUE}Using $AI_PROVIDER model: $current_model${NC}" >&2

                # Recommend larger models for code review if using smaller models
                if [[ "$current_model" =~ (llama-3.1-8b|gemma2-9b|mixtral-8x7b) ]]; then
                    echo -e "${YELLOW}💡 Tip: For more thorough code reviews, consider using llama-3.3-70b-versatile${NC}" >&2
                    echo -e "${YELLOW}   CODE_REVIEW_GROQ_MODEL=\"llama-3.3-70b-versatile\"${NC}" >&2
                    echo "" >&2
                fi
                ;;
        esac
    fi

    # Call AI provider for review
    local review_result
    case "$AI_PROVIDER" in
        ollama)
            review_result=$(call_ollama "$review_prompt")
            ;;
        anthropic)
            review_result=$(call_anthropic "$review_prompt")
            ;;
        openai)
            review_result=$(call_openai "$review_prompt")
            ;;
        groq)
            review_result=$(call_groq "$review_prompt")
            ;;
        *)
            echo -e "${RED}Error: Unknown AI provider: $AI_PROVIDER${NC}" >&2
            exit 1
            ;;
    esac

    # Restore original models
    OLLAMA_MODEL="$original_ollama_model"
    ANTHROPIC_MODEL="$original_anthropic_model"
    OPENAI_MODEL="$original_openai_model"
    GROQ_MODEL="$original_groq_model"

    if [ -z "$review_result" ]; then
        echo -e "${RED}Error: Failed to generate code review${NC}" >&2
        exit 1
    fi

    # Display the review
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ Code Review Complete${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "$review_result"
    echo ""

    # Show cost information for paid APIs
    if [ "$AI_PROVIDER" = "anthropic" ] || [ "$AI_PROVIDER" = "openai" ]; then
        if [ -n "$INPUT_TOKENS" ] && [ -n "$OUTPUT_TOKENS" ]; then
            local total_tokens=$((INPUT_TOKENS + OUTPUT_TOKENS))
            echo -e "${BLUE}Token usage:${NC} $total_tokens tokens ($INPUT_TOKENS input + $OUTPUT_TOKENS output)"

            # Calculate and display cost
            local model
            if [ "$AI_PROVIDER" = "anthropic" ]; then
                model="$ANTHROPIC_MODEL"
            else
                model="$OPENAI_MODEL"
            fi

            local cost=$(calculate_cost "$AI_PROVIDER" "$model" "$INPUT_TOKENS" "$OUTPUT_TOKENS")
            if [ -n "$cost" ]; then
                echo -e "${BLUE}Estimated cost:${NC} \$$cost USD"

                # Track cumulative cost
                local total_cost=$(track_cumulative_cost "$cost")
                if [ -n "$total_cost" ]; then
                    echo -e "${BLUE}Today's total:${NC} \$$total_cost USD"
                fi
            fi
            echo ""
        fi
    fi
}

# Generate PR description from commits
generate_pr_description() {
    local base_branch="$1"
    local output_file="$2"

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}Error: Not a git repository${NC}" >&2
        exit 1
    fi

    # Get current branch
    local current_branch=$(git branch --show-current)
    if [ -z "$current_branch" ]; then
        echo -e "${RED}Error: Not on a branch (detached HEAD)${NC}" >&2
        exit 1
    fi

    # Auto-detect base branch if not provided
    if [ -z "$base_branch" ]; then
        # Try common base branches
        for candidate in main master develop development; do
            if git show-ref --verify --quiet refs/heads/$candidate; then
                base_branch=$candidate
                break
            fi
        done

        if [ -z "$base_branch" ]; then
            echo -e "${RED}Error: Could not auto-detect base branch${NC}" >&2
            echo "Please specify with --base <branch>" >&2
            exit 1
        fi
    fi

    # Verify base branch exists
    if ! git show-ref --verify --quiet refs/heads/$base_branch; then
        echo -e "${RED}Error: Base branch '$base_branch' does not exist${NC}" >&2
        exit 1
    fi

    # Get merge base (where branch diverged)
    local merge_base=$(git merge-base $base_branch HEAD 2>/dev/null)
    if [ -z "$merge_base" ]; then
        echo -e "${RED}Error: Could not find common ancestor with $base_branch${NC}" >&2
        exit 1
    fi

    # Get commits since divergence
    local commits=$(git log --pretty=format:"%H|%s|%b" ${merge_base}..HEAD)
    if [ -z "$commits" ]; then
        echo -e "${RED}Error: No commits found since divergence from $base_branch${NC}" >&2
        exit 1
    fi

    # Count commits
    local num_commits=$(echo "$commits" | wc -l | tr -d ' ')

    # Get overall diff stats
    local diff_stats=$(git diff --stat ${merge_base}..HEAD)

    # Get file changes summary
    local files_changed=$(git diff --name-status ${merge_base}..HEAD)

    # Build commit summary (for AI)
    local commit_summary=""
    while IFS='|' read -r hash subject body; do
        commit_summary="${commit_summary}
- ${subject}"
        if [ -n "$body" ]; then
            # Include first line of body if it exists
            local first_line=$(echo "$body" | head -1 | sed 's/^[[:space:]]*//')
            if [ -n "$first_line" ]; then
                commit_summary="${commit_summary}
  ${first_line}"
            fi
        fi
    done <<< "$commits"

    # Create prompt for AI
    local pr_prompt="Generate a comprehensive Pull Request description based on the commits and changes below.

Branch: $current_branch
Base branch: $base_branch
Number of commits: $num_commits

Commits:
$commit_summary

Diff stats:
$diff_stats

FILES CHANGED:
$files_changed

Generate a PR description with the following sections:

## Summary
A 2-3 sentence overview of what this PR accomplishes.

## Changes
- Detailed bullet points of key changes
- Organized by category if applicable (features, fixes, refactoring, etc.)

## Testing
- How to test these changes
- What scenarios to verify

FORMAT:
- Use markdown
- Be concise but comprehensive
- Focus on WHAT changed and WHY, not HOW
- Highlight any breaking changes
- Output ONLY the PR description, NO explanations"

    # Show progress
    echo "→ Analyzing $num_commits commits on branch: $current_branch" >&2
    echo "→ Comparing against: $base_branch" >&2
    echo "" >&2

    # Call AI to generate PR description
    local pr_description=""
    case "$AI_PROVIDER" in
        ollama)
            pr_description=$(call_ollama "$pr_prompt")
            ;;
        anthropic)
            pr_description=$(call_anthropic "$pr_prompt")
            ;;
        openai)
            pr_description=$(call_openai "$pr_prompt")
            ;;
        groq)
            pr_description=$(call_groq "$pr_prompt")
            ;;
        *)
            echo -e "${RED}Error: Unknown AI provider '$AI_PROVIDER'${NC}" >&2
            exit 1
            ;;
    esac

    # Strip any markdown fences
    pr_description=$(echo "$pr_description" | awk '
        /^```[a-zA-Z]*$/ { next }
        /^```$/ { next }
        /^\*\*explanation/ { exit }
        /^\*\*why/ { exit }
        /^\*\*note/ { exit }
        { print }
    ')

    # Output result
    if [ -n "$output_file" ]; then
        echo "$pr_description" > "$output_file"
        echo "✓ PR description saved to: $output_file" >&2
    else
        echo "$pr_description"
    fi
}

