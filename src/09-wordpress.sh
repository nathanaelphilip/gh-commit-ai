# Extract semantic context from changed filenames
extract_file_context() {
    local files="$1"
    local contexts=()

    # Parse each filename and extract semantic meaning
    while IFS= read -r line; do
        # Skip empty lines
        [ -z "$line" ] && continue

        # Extract filename (remove git status prefix like "M " or "A ")
        local file=$(echo "$line" | awk '{print $NF}')

        # Convert to lowercase for pattern matching
        local file_lower=$(echo "$file" | tr '[:upper:]' '[:lower:]')

        # Extract context based on filename patterns
        case "$file_lower" in
            *video*) contexts+=("video handling") ;;
            *audio*|*sound*|*music*) contexts+=("audio processing") ;;
            *image*|*photo*|*picture*|*img*) contexts+=("image handling") ;;
            *auth*|*login*|*signin*|*signup*) contexts+=("authentication") ;;
            *user*|*profile*|*account*) contexts+=("user management") ;;
            *payment*|*checkout*|*billing*|*invoice*) contexts+=("payment processing") ;;
            *order*|*cart*|*shopping*) contexts+=("order management") ;;
            *product*|*catalog*|*inventory*) contexts+=("product catalog") ;;
            *email*|*mail*|*notification*) contexts+=("email/notifications") ;;
            *report*|*analytics*|*dashboard*) contexts+=("reporting/analytics") ;;
            *search*|*query*|*filter*) contexts+=("search functionality") ;;
            *upload*|*download*|*file*) contexts+=("file handling") ;;
            *api/*|*endpoint*|*route*) contexts+=("API endpoints") ;;
            *component*/*|*components/*) contexts+=("UI components") ;;
            *database*|*db/*|*migration*|*schema*) contexts+=("database") ;;
            *model*/*|*models/*) contexts+=("data models") ;;
            *service*/*|*services/*) contexts+=("services layer") ;;
            *controller*/*|*controllers/*) contexts+=("controllers") ;;
            *view*/*|*views/*|*template*) contexts+=("views/templates") ;;
            *test*|*spec*|*.test.*|*.spec.*) contexts+=("tests") ;;
            *doc*|*readme*) contexts+=("documentation") ;;
            *config*|*.json|*.yml|*.yaml|*.toml) contexts+=("configuration") ;;
            *security*|*permission*|*role*) contexts+=("security/permissions") ;;
            *cache*|*redis*|*memcache*) contexts+=("caching") ;;
            *queue*|*job*|*worker*) contexts+=("background jobs") ;;
            *webhook*|*callback*|*integration*) contexts+=("integrations") ;;
            *export*|*import*) contexts+=("data import/export") ;;
        esac

        # Domain-specific patterns
        # Laravel
        case "$file_lower" in
            *controller.php) contexts+=("Laravel controller") ;;
            *model.php|app/models/*) contexts+=("Laravel model") ;;
            database/migrations/*) contexts+=("Laravel migration") ;;
            *middleware.php|app/http/middleware/*) contexts+=("Laravel middleware") ;;
            *request.php|app/http/requests/*) contexts+=("Laravel request validation") ;;
            *seeder.php|database/seeders/*) contexts+=("Laravel seeder") ;;
            *provider.php|app/providers/*) contexts+=("Laravel service provider") ;;
            resources/views/*) contexts+=("Laravel Blade views") ;;
        esac

        # React/Vue/Angular
        case "$file_lower" in
            *component.tsx|*component.jsx) contexts+=("React component") ;;
            *.tsx|*.jsx) contexts+=("React/TypeScript") ;;
            *hook*.ts|*hook*.js|use*.ts|use*.js) contexts+=("React hooks") ;;
            *.vue) contexts+=("Vue component") ;;
            *component.ts|*component.js) contexts+=("Angular component") ;;
            *service.ts|*service.js) contexts+=("Angular service") ;;
            *module.ts) contexts+=("Angular/NestJS module") ;;
        esac

        # WordPress
        case "$file_lower" in
            wp-content/themes/*)
                # Extract theme name from path
                if [[ "$file_lower" =~ wp-content/themes/([^/]+) ]]; then
                    local theme_name="${BASH_REMATCH[1]}"
                    contexts+=("$theme_name theme")
                else
                    contexts+=("WordPress theme")
                fi
                ;;
            wp-content/plugins/*)
                # Extract plugin name from path
                if [[ "$file_lower" =~ wp-content/plugins/([^/]+) ]]; then
                    local plugin_name="${BASH_REMATCH[1]}"
                    contexts+=("$plugin_name plugin")
                else
                    contexts+=("WordPress plugin")
                fi
                ;;
            *functions.php) contexts+=("WordPress theme functions") ;;
            wp-admin/*) contexts+=("WordPress admin") ;;
        esac

        # Django/Flask
        case "$file_lower" in
            */views.py) contexts+=("Django/Flask views") ;;
            */models.py) contexts+=("Django models") ;;
            */serializers.py) contexts+=("Django serializers") ;;
            */forms.py) contexts+=("Django forms") ;;
            */urls.py) contexts+=("Django URL routing") ;;
        esac

        # Ruby on Rails
        case "$file_lower" in
            *_controller.rb|app/controllers/*) contexts+=("Rails controller") ;;
            *_model.rb|app/models/*) contexts+=("Rails model") ;;
            db/migrate/*) contexts+=("Rails migration") ;;
            *_helper.rb|app/helpers/*) contexts+=("Rails helper") ;;
        esac

        # Docker/DevOps
        case "$file_lower" in
            dockerfile|*dockerfile*) contexts+=("Docker configuration") ;;
            docker-compose.yml|docker-compose.yaml) contexts+=("Docker Compose") ;;
            .github/workflows/*|.gitlab-ci.yml) contexts+=("CI/CD pipeline") ;;
            kubernetes/*|k8s/*|*.yaml|*.yml) contexts+=("Kubernetes config") ;;
        esac

        # Also extract from directory names
        if [[ "$file_lower" == *"/"* ]]; then
            local dir=$(dirname "$file_lower")
            local base=$(basename "$dir")
            case "$base" in
                video*|videos) contexts+=("video handling") ;;
                audio*|sounds|music) contexts+=("audio processing") ;;
                image*|images|photos) contexts+=("image handling") ;;
                auth*|authentication) contexts+=("authentication") ;;
                user*|users|profiles) contexts+=("user management") ;;
                payment*|payments|billing) contexts+=("payment processing") ;;
                order*|orders) contexts+=("order management") ;;
                product*|products) contexts+=("product catalog") ;;
                api|apis) contexts+=("API endpoints") ;;
                admin*|dashboard) contexts+=("admin dashboard") ;;
            esac
        fi
    done <<< "$files"

    # Return unique contexts as comma-separated string
    if [ ${#contexts[@]} -gt 0 ]; then
        printf '%s\n' "${contexts[@]}" | sort -u | paste -sd ", " -
    fi
}

# Extract function and class names from diff
extract_changed_functions() {
    local diff="$1"
    local functions=()

    # Extract function names from various languages
    # PHP: function name() or public function name()
    while IFS= read -r line; do
        if [[ "$line" =~ ^\+.*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            functions+=("${BASH_REMATCH[1]}()")
        fi
    done <<< "$diff"

    # Python: def name(
    while IFS= read -r line; do
        if [[ "$line" =~ ^\+.*def[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            functions+=("${BASH_REMATCH[1]}()")
        fi
    done <<< "$diff"

    # JavaScript/TypeScript: function name( or const name = function
    while IFS= read -r line; do
        if [[ "$line" =~ ^\+.*(const|let|var)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*= ]] || \
           [[ "$line" =~ ^\+.*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            local name="${BASH_REMATCH[2]:-${BASH_REMATCH[1]}}"
            [[ "$name" != "const" && "$name" != "let" && "$name" != "var" ]] && functions+=("${name}()")
        fi
    done <<< "$diff"

    # Class names: class ClassName
    while IFS= read -r line; do
        if [[ "$line" =~ ^\+.*class[[:space:]]+([A-Z][a-zA-Z0-9_]*) ]]; then
            functions+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$diff"

    # Return unique function/class names (limit to first 8 to avoid clutter)
    if [ ${#functions[@]} -gt 0 ]; then
        local result=$(printf '%s\n' "${functions[@]}" | sort -u | head -8 | paste -sd "," -)
        echo "$result" | sed 's/,/, /g'
    fi
}

# Extract WordPress function calls from diff
extract_wordpress_function_calls() {
    local diff="$1"

    # Whitelist of important WordPress functions to detect
    local wp_functions="register_post_type|register_taxonomy|add_action|add_filter|wp_enqueue_script|wp_enqueue_style|register_nav_menu|add_theme_support|register_sidebar|register_widget"

    # Extract function calls with first argument
    # Pattern: +.*function_name('argument' or "argument")
    local functions=$(echo "$diff" | grep -E "^\+.*(${wp_functions})\(" | \
        sed -E "s/.*($wp_functions)[^'\"]*['\"]([^'\"]+)['\"].*/\1:\2/" | \
        grep ":" | \
        sort -u | \
        head -10)

    # Return comma-separated format (function_name:arg_value,...)
    if [ -n "$functions" ]; then
        echo "$functions" | tr '\n' ',' | sed 's/,$//'
    fi
}

# Look up WordPress function documentation (local database first, then API)
lookup_wordpress_function() {
    local function_name="$1"

    # Cache directory for WordPress function documentation
    local cache_dir="/tmp/gh-commit-ai-wp-docs-cache"
    local cache_file="$cache_dir/$function_name"

    # Check cache first to avoid repeated lookups
    if [ -f "$cache_file" ]; then
        cat "$cache_file"
        return
    fi

    # Check local database first (fast, no network required)
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local local_db="${script_dir}/data/wordpress-functions.txt"

    # If installed via gh extension, try extension directory
    if [ ! -f "$local_db" ]; then
        local_db="${HOME}/.local/share/gh/extensions/gh-commit-ai/data/wordpress-functions.txt"
    fi

    # If installed via homebrew, try homebrew directory
    if [ ! -f "$local_db" ] && command -v brew &>/dev/null; then
        local brew_prefix=$(brew --prefix 2>/dev/null)
        local_db="${brew_prefix}/opt/gh-commit-ai/data/wordpress-functions.txt"
    fi

    if [ -f "$local_db" ]; then
        # Look up function in local database (format: function_name|description)
        local description=$(grep "^${function_name}|" "$local_db" | cut -d'|' -f2-)
        if [ -n "$description" ]; then
            # Cache the result
            mkdir -p "$cache_dir"
            echo "$description" > "$cache_file"
            echo "$description"
            return
        fi
    fi

    # Fallback to API for uncommon functions (with reduced timeout)
    local url="https://developer.wordpress.org/wp-json/wp/v2/wp-parser-function?slug=$function_name"
    local response=$(curl -s --connect-timeout 1 --max-time 2 "$url" 2>/dev/null)

    # Parse JSON response (no jq dependency - use grep/sed)
    # Extract description from excerpt field, strip HTML tags
    local description=$(echo "$response" | \
        grep -o '"rendered":"<p>[^<]*' | \
        sed 's/"rendered":"<p>//' | \
        head -1)

    # Cache the result if successful
    if [ -n "$description" ]; then
        mkdir -p "$cache_dir"
        echo "$description" > "$cache_file"
        echo "$description"
    fi
}

# Build WordPress context from function calls and documentation
build_wordpress_context() {
    local wp_function_calls="$1"

    if [ -z "$wp_function_calls" ]; then
        return
    fi

    local context="🚨 WORDPRESS FUNCTIONS DETECTED - READ THIS FIRST 🚨\n\n"
    local first_func=""
    local first_arg=""

    # Create temp dir for parallel lookups
    local lookup_temp_dir=$(mktemp -d)
    local lookup_pids=()

    # Parse comma-separated function calls and start parallel lookups
    IFS=',' read -ra CALLS <<< "$wp_function_calls"
    local call_index=0
    for call in "${CALLS[@]}"; do
        [ -z "$call" ] && continue

        # Split function_name:arg_value
        IFS=':' read -r func_name arg_value <<< "$call"

        # Save first function for example
        if [ -z "$first_func" ]; then
            first_func="$func_name"
            first_arg="$arg_value"
        fi

        # Start parallel lookup in background
        (
            local func_desc=$(lookup_wordpress_function "$func_name")
            echo "$func_name|$arg_value|$func_desc" > "$lookup_temp_dir/${call_index}.txt"
        ) &
        lookup_pids+=($!)

        ((call_index++))
    done

    # Wait for all parallel lookups to complete
    for pid in "${lookup_pids[@]}"; do
        wait "$pid" 2>/dev/null
    done

    # Build context from parallel lookup results (in order)
    for i in $(seq 0 $((call_index - 1))); do
        if [ -f "$lookup_temp_dir/${i}.txt" ]; then
            local result=$(cat "$lookup_temp_dir/${i}.txt")
            IFS='|' read -r func_name arg_value func_desc <<< "$result"

            # Build context line with function, argument, and description
            if [ -n "$func_desc" ]; then
                context="${context}${func_name}('${arg_value}'): ${func_desc}\n"
            else
                # Fallback if API lookup fails
                context="${context}${func_name}('${arg_value}')\n"
            fi
        fi
    done

    # Cleanup temp dir
    rm -rf "$lookup_temp_dir" 2>/dev/null

    # Add immediate instructions using the detected function
    if [ -n "$first_func" ]; then
        context="${context}\n⚠️ YOUR SUMMARY LINE MUST USE THE FUNCTION NAME ABOVE:\n"
        if [ "$first_func" = "register_post_type" ]; then
            context="${context}  ✓ CORRECT: 'feat: register ${first_arg} custom post type'\n"
            context="${context}  ✗ WRONG: 'feat: update ${first_arg} post type fields'\n"
        elif [ "$first_func" = "register_taxonomy" ]; then
            context="${context}  ✓ CORRECT: 'feat: add ${first_arg} taxonomy'\n"
            context="${context}  ✗ WRONG: 'feat: update ${first_arg} taxonomy fields'\n"
        else
            context="${context}  ✓ Start with: 'feat: ${first_func} ${first_arg}...'\n"
            context="${context}  ✗ Do NOT start with: 'feat: update...'\n"
        fi
        context="${context}Write what is being REGISTERED/ADDED, not what is being 'updated'.\n"
    fi

    echo -e "$context"
}

