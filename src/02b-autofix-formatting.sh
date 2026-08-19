# ============================================================================
# Auto-Fix Formatting
# ============================================================================
#
# Detects and optionally repairs trailing whitespace and inconsistent line
# endings in staged files before the commit message is generated.
#
# These functions were deleted by accident in aeef1e3 ("fix: update wordpress
# component detection logic"), which rewrote the built script directly and
# dropped ~200 unrelated lines with it. Nothing caught it because
# tests/test_auto_fix.sh - which asserts every function below exists - was
# never run by `make test` (bats only globs *.bats) and the release workflow
# aborted before reaching it. Restored from aeef1e3^; that test now gates it.

detect_trailing_whitespace() {
    local files=()

    # Get list of staged files (text files only)
    while IFS= read -r file; do
        # Skip binary files
        if file "$file" 2>/dev/null | grep -q "text"; then
            # Check for trailing whitespace
            if grep -q '[[:space:]]$' "$file" 2>/dev/null; then
                files+=("$file")
            fi
        fi
    done < <(git diff --cached --name-only --diff-filter=ACM)

    # Return count and files
    if [ ${#files[@]} -gt 0 ]; then
        echo "${#files[@]}"
        printf '%s\n' "${files[@]}"
    else
        echo "0"
    fi
}

# Detect files with inconsistent line endings
detect_line_endings() {
    local files=()

    # Get list of staged files (text files only)
    while IFS= read -r file; do
        # Skip binary files
        if file "$file" 2>/dev/null | grep -q "text"; then
            # Check for CRLF line endings
            if file "$file" | grep -q "CRLF"; then
                local has_crlf=true
            else
                local has_crlf=false
            fi

            # Check for mixed line endings or wrong type
            if [ "$LINE_ENDING_STYLE" = "lf" ] && [ "$has_crlf" = "true" ]; then
                files+=("$file:crlf")
            elif [ "$LINE_ENDING_STYLE" = "crlf" ] && [ "$has_crlf" = "false" ]; then
                files+=("$file:lf")
            fi
        fi
    done < <(git diff --cached --name-only --diff-filter=ACM)

    # Return count and files
    if [ ${#files[@]} -gt 0 ]; then
        echo "${#files[@]}"
        printf '%s\n' "${files[@]}"
    else
        echo "0"
    fi
}

# Fix trailing whitespace in file
fix_trailing_whitespace() {
    local file="$1"

    # Remove trailing whitespace using sed (compatible with both GNU and BSD sed)
    if sed --version 2>/dev/null | grep -q "GNU"; then
        # GNU sed
        sed -i 's/[[:space:]]*$//' "$file"
    else
        # BSD sed (macOS)
        sed -i '' 's/[[:space:]]*$//' "$file"
    fi
}

# Fix line endings in file
fix_line_endings() {
    local file="$1"
    local target_style="$2"  # "lf" or "crlf"

    if [ "$target_style" = "lf" ]; then
        # Convert CRLF to LF
        if command -v dos2unix &> /dev/null; then
            dos2unix "$file" 2>/dev/null
        else
            # Fallback: use sed or tr
            if sed --version 2>/dev/null | grep -q "GNU"; then
                sed -i 's/\r$//' "$file"
            else
                sed -i '' 's/\r$//' "$file"
            fi
        fi
    else
        # Convert LF to CRLF
        if command -v unix2dos &> /dev/null; then
            unix2dos "$file" 2>/dev/null
        else
            # Fallback: use sed
            if sed --version 2>/dev/null | grep -q "GNU"; then
                sed -i 's/$/\r/' "$file"
            else
                sed -i '' 's/$/\r/' "$file"
            fi
        fi
    fi
}

# Detect files missing a trailing newline.
# Removed a week earlier than the rest, in 1845ac6, by the same kind of
# direct edit to the built script. Restored from 1845ac6^.
detect_missing_final_newline() {
    local files=()

    # Get list of staged files (text files only)
    while IFS= read -r file; do
        # Skip binary files and empty files
        if [ -s "$file" ] && file "$file" 2>/dev/null | grep -q "text"; then
            # Check if file ends with newline
            if [ -n "$(tail -c 1 "$file" 2>/dev/null)" ]; then
                files+=("$file")
            fi
        fi
    done < <(git diff --cached --name-only --diff-filter=ACM)

    # Return count and files
    if [ ${#files[@]} -gt 0 ]; then
        echo "${#files[@]}"
        printf '%s\n' "${files[@]}"
    else
        echo "0"
    fi
}


# Add a missing final newline
fix_missing_final_newline() {
    local file="$1"

    # Add newline at end if missing
    if [ -n "$(tail -c 1 "$file" 2>/dev/null)" ]; then
        echo "" >> "$file"
    fi
}


# Main auto-fix function - detect and optionally fix formatting issues
check_and_fix_formatting() {
    # Skip if not in a git repository
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        return 0
    fi

    # Skip if no staged files
    if [ -z "$(git diff --cached --name-only)" ]; then
        return 0
    fi

    # Arrays to store detected issues
    local trailing_ws_files=()
    local line_ending_files=()
    local missing_newline_files=()
    local total_issues=0

    # Detect trailing whitespace
    if [ "$AUTO_FIX_TRAILING_WHITESPACE" = "true" ]; then
        local ws_result=$(detect_trailing_whitespace)
        local ws_count=$(echo "$ws_result" | head -1)
        if [ "$ws_count" != "0" ]; then
            total_issues=$((total_issues + ws_count))
            # Use while read loop for bash 3.2 compatibility (instead of mapfile)
            trailing_ws_files=()
            while IFS= read -r line; do
                trailing_ws_files+=("$line")
            done < <(echo "$ws_result" | tail -n +2)
        fi
    fi

    # Detect line ending issues
    if [ "$AUTO_FIX_LINE_ENDINGS" = "true" ]; then
        local le_result=$(detect_line_endings)
        local le_count=$(echo "$le_result" | head -1)
        if [ "$le_count" != "0" ]; then
            total_issues=$((total_issues + le_count))
            # Use while read loop for bash 3.2 compatibility (instead of mapfile)
            line_ending_files=()
            while IFS= read -r line; do
                line_ending_files+=("$line")
            done < <(echo "$le_result" | tail -n +2)
        fi
    fi

    # Detect missing final newlines
    if [ "$AUTO_FIX_FINAL_NEWLINE" = "true" ]; then
        local nl_result=$(detect_missing_final_newline)
        local nl_count=$(echo "$nl_result" | head -1)
        if [ "$nl_count" != "0" ]; then
            total_issues=$((total_issues + nl_count))
            # Use while read loop for bash 3.2 compatibility (instead of mapfile)
            missing_newline_files=()
            while IFS= read -r line; do
                missing_newline_files+=("$line")
            done < <(echo "$nl_result" | tail -n +2)
        fi
    fi

    # If no issues found, return early
    if [ $total_issues -eq 0 ]; then
        return 0
    fi

    # Display detected issues
    echo -e "${YELLOW}⚠ Formatting issues detected:${NC}"
    [ ${#trailing_ws_files[@]} -gt 0 ] && echo "  • ${#trailing_ws_files[@]} file(s) with trailing whitespace"
    [ ${#line_ending_files[@]} -gt 0 ] && echo "  • ${#line_ending_files[@]} file(s) with incorrect line endings"
    [ ${#missing_newline_files[@]} -gt 0 ] && echo "  • ${#missing_newline_files[@]} file(s) missing final newline"
    echo ""

    # Auto-fix if enabled, otherwise ask user
    local should_fix=false
    if [ "$AUTO_FIX_FORMATTING" = "true" ]; then
        should_fix=true
        echo -e "${BLUE}Auto-fixing formatting issues...${NC}"
    else
        echo -n "Would you like to fix these issues automatically? (y/n): "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            should_fix=true
        fi
    fi

    if [ "$should_fix" = "true" ]; then
        local fixed_count=0

        # Fix trailing whitespace
        for file in "${trailing_ws_files[@]}"; do
            fix_trailing_whitespace "$file"
            git add "$file"  # Re-stage the fixed file
            fixed_count=$((fixed_count + 1))
        done

        # Fix line endings
        for file_info in "${line_ending_files[@]}"; do
            local file="${file_info%:*}"
            fix_line_endings "$file" "$LINE_ENDING_STYLE"
            git add "$file"  # Re-stage the fixed file
            fixed_count=$((fixed_count + 1))
        done

        # Fix missing newlines
        for file in "${missing_newline_files[@]+"${missing_newline_files[@]}"}"; do
            fix_missing_final_newline "$file"
            git add "$file"  # Re-stage the fixed file
            fixed_count=$((fixed_count + 1))
        done

        echo -e "${GREEN}✓ Fixed $fixed_count formatting issue(s)${NC}"
        echo ""
    else
        echo -e "${YELLOW}Continuing without fixes...${NC}"
        echo ""
    fi

    return 0
}
