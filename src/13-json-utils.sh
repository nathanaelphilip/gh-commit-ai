# Escape JSON strings (replace backslash, double quote, newline, carriage return, tab)
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\r/\\r/g; s/\t/\\t/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//'
}

# Unescape JSON strings (handle unicode escapes like \u0026)
unescape_json() {
    local text="$1"

    # First, decode unicode escapes (\uXXXX)
    # This handles common cases like \u0026 (&), \u003c (<), \u003e (>)
    while [[ "$text" =~ \\u([0-9a-fA-F]{4}) ]]; do
        local hex="${BASH_REMATCH[1]}"
        local dec=$((16#$hex))
        # Use printf to convert to actual character
        local char=$(printf "\\$(printf '%03o' "$dec")")
        text="${text/\\u$hex/$char}"
    done

    # Then handle standard JSON escapes
    text="${text//\\\\/\\}"    # \\ -> \
    text="${text//\\\"/\"}"    # \" -> "

    echo "$text"
}

# Enforce lowercase on commit message while preserving acronyms and ticket numbers
enforce_lowercase() {
    local message="$1"
    local temp_message="$message"

    # First, protect ticket numbers by replacing them with placeholders
    # Pattern: ABC-123, JIRA-456, etc.
    local ticket_counter=0
    local tickets_file=$(mktemp)

    # Find all ticket numbers and store them
    echo "$message" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' > "$tickets_file"

    # Replace tickets with placeholders
    while IFS= read -r ticket; do
        if [ -n "$ticket" ]; then
            temp_message=$(echo "$temp_message" | sed "s/$ticket/__TICKET${ticket_counter}__/g")
            ((ticket_counter++))
        fi
    done < "$tickets_file"

    # Convert entire message to lowercase
    temp_message=$(echo "$temp_message" | tr '[:upper:]' '[:lower:]')

    # Restore ticket numbers
    ticket_counter=0
    while IFS= read -r ticket; do
        if [ -n "$ticket" ]; then
            temp_message=$(echo "$temp_message" | sed "s/__ticket${ticket_counter}__/$ticket/g")
            ((ticket_counter++))
        fi
    done < "$tickets_file"

    rm -f "$tickets_file"

    # Restore common acronyms (case-insensitive search and replace)
    local acronyms="API HTTP HTTPS JSON XML SQL JWT OAuth REST CLI UI UX CSS HTML JS TS URL URI PDF CSV IDE SDK CI CD AWS GCP DNS SSL TLS SSH FTP SMTP TCP UDP IP DOM npm NPM README TODO FIXME"

    for acronym in $acronyms; do
        local lowercase_acronym=$(echo "$acronym" | tr '[:upper:]' '[:lower:]')
        # Use word boundaries to avoid partial matches
        temp_message=$(echo "$temp_message" | sed "s/\b$lowercase_acronym\b/$acronym/g")
    done

    echo "$temp_message"
}

# Auto-fix common formatting issues in commit messages
auto_fix_message() {
    local message="$1"
    local fixed="$message"

    # Split into lines for processing
    local first_line=""
    local rest_lines=""
    local line_num=0

    while IFS= read -r line; do
        if [ $line_num -eq 0 ]; then
            first_line="$line"
        else
            if [ -n "$rest_lines" ]; then
                rest_lines="$rest_lines"$'\n'"$line"
            else
                rest_lines="$line"
            fi
        fi
        ((line_num++))
    done <<< "$message"

    # Fix summary line (first line)
    if [ -n "$first_line" ]; then
        # Remove trailing period from summary line (conventional commits shouldn't have periods)
        first_line=$(echo "$first_line" | sed 's/\.$//')

        # Fix missing space after colon (e.g., "feat:add" -> "feat: add")
        first_line=$(echo "$first_line" | sed -E 's/^([a-z]+)(\([^)]+\))?:([^ ])/\1\2: \3/')

        # Remove multiple consecutive spaces
        first_line=$(echo "$first_line" | sed 's/  \+/ /g')

        # Trim leading/trailing whitespace
        first_line=$(echo "$first_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi

    # Fix body lines
    if [ -n "$rest_lines" ]; then
        local fixed_rest=""
        local prev_blank=false
        local in_blank_sequence=false

        while IFS= read -r line; do
            # Remove trailing whitespace from all lines
            line=$(echo "$line" | sed 's/[[:space:]]*$//')

            # Check if line is blank
            if [ -z "$line" ]; then
                # Only keep one blank line between sections
                if [ "$prev_blank" = false ]; then
                    if [ -n "$fixed_rest" ]; then
                        fixed_rest="$fixed_rest"$'\n'"$line"
                    else
                        fixed_rest="$line"
                    fi
                    prev_blank=true
                fi
                continue
            fi

            prev_blank=false

            # Fix bullet points
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]* ]]; then
                # Normalize bullet point spacing (ensure single space after dash)
                line=$(echo "$line" | sed -E 's/^([[:space:]]*)-[[:space:]]+/\1- /')

                # Remove empty bullet points (just "- " with no content)
                if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*$ ]]; then
                    continue
                fi

                # Remove multiple consecutive spaces in bullet content
                line=$(echo "$line" | sed 's/  \+/ /g')
            fi

            # Add the fixed line
            if [ -n "$fixed_rest" ]; then
                fixed_rest="$fixed_rest"$'\n'"$line"
            else
                fixed_rest="$line"
            fi
        done <<< "$rest_lines"

        rest_lines="$fixed_rest"
    fi

    # Reconstruct message
    if [ -n "$rest_lines" ]; then
        echo "$first_line"
        echo ""
        echo "$rest_lines"
    else
        echo "$first_line"
    fi
}

