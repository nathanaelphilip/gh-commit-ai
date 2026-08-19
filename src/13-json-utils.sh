# Escape a string for embedding in JSON.
#
# The sed pass handles backslash, double quote, CR and tab; the awk pass joins
# lines with \n and escapes every remaining control character as \uXXXX. That
# last part matters: RFC 8259 requires all of U+0000-U+001F to be escaped, and
# emitting a raw one (ESC is the common case - captured terminal output, ANSI
# logs, some binaries) produced invalid JSON and an opaque provider 400 with
# nothing pointing at the cause.
#
# LC_ALL=C keeps awk byte-oriented, so multibyte UTF-8 passes through untouched.
escape_json() {
    echo "$1" \
        | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r/\\r/g; s/\t/\\t/g' \
        | LC_ALL=C awk '
            BEGIN {
                for (i = 1; i <= 31; i++) ctrl[sprintf("%c", i)] = sprintf("\\u%04x", i)
            }
            {
                out = ""
                n = length($0)
                for (i = 1; i <= n; i++) {
                    c = substr($0, i, 1)
                    out = out (c in ctrl ? ctrl[c] : c)
                }
                printf "%s\\n", out
            }
        ' \
        | sed '$ s/\\n$//'
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
            ticket_counter=$((ticket_counter + 1))
        fi
    done < "$tickets_file"

    # Convert entire message to lowercase
    temp_message=$(echo "$temp_message" | tr '[:upper:]' '[:lower:]')

    # Restore ticket numbers
    ticket_counter=0
    while IFS= read -r ticket; do
        if [ -n "$ticket" ]; then
            temp_message=$(echo "$temp_message" | sed "s/__ticket${ticket_counter}__/$ticket/g")
            ticket_counter=$((ticket_counter + 1))
        fi
    done < "$tickets_file"

    rm -f "$tickets_file"

    # Restore common acronyms (case-insensitive search and replace)
    local acronyms="API HTTP HTTPS JSON XML SQL JWT OAuth REST CLI UI UX CSS HTML JS TS URL URI PDF CSV IDE SDK CI CD AWS GCP DNS SSL TLS SSH FTP SMTP TCP UDP IP DOM npm NPM README TODO FIXME"

    # Restore them in a single awk pass over whole words. This used to be a loop
    # of sed calls using \b, which is a GNU extension: BSD sed (macOS) silently
    # ignores it, so every acronym stayed lowercased there.
    temp_message=$(echo "$temp_message" | ACRONYMS="$acronyms" awk '
        BEGIN {
            n = split(ENVIRON["ACRONYMS"], list, " ")
            for (i = 1; i <= n; i++) canonical[tolower(list[i])] = list[i]
        }
        {
            out = ""
            rest = $0
            while (match(rest, /[A-Za-z0-9]+/)) {
                word = substr(rest, RSTART, RLENGTH)
                key = tolower(word)
                if (key in canonical) word = canonical[key]
                out = out substr(rest, 1, RSTART - 1) word
                rest = substr(rest, RSTART + RLENGTH)
            }
            print out rest
        }
    ')

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
        line_num=$((line_num + 1))
    done <<< "$message"

    # Fix summary line (first line)
    if [ -n "$first_line" ]; then
        # Remove trailing period from summary line (conventional commits shouldn't have periods)
        first_line=$(echo "$first_line" | sed 's/\.$//')

        # Fix missing space after colon (e.g., "feat:add" -> "feat: add").
        # The leading (.*[^[:alnum:]:])? allows an optional gitmoji prefix: the
        # pattern used to anchor on ^[a-z]+, so with USE_GITMOJI=true the line
        # started with an emoji and a missing space was never fixed.
        first_line=$(echo "$first_line" | sed -E 's/^(.*[[:space:]])?([a-z]+)(\([^)]+\))?:([^ ])/\1\2\3: \4/')

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

