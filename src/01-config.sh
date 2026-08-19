# Simple YAML parser (supports only simple key: value pairs)
parse_yaml_config() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        return
    fi

    while IFS=: read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Trim whitespace
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Remove quotes from value
        value=$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')

        # Only set if not already set by environment variable
        case "$key" in
            ai_provider|AI_PROVIDER)
                CONFIG_AI_PROVIDER="${CONFIG_AI_PROVIDER:-$value}"
                ;;
            ollama_model|OLLAMA_MODEL)
                CONFIG_OLLAMA_MODEL="${CONFIG_OLLAMA_MODEL:-$value}"
                ;;
            ollama_host|OLLAMA_HOST)
                CONFIG_OLLAMA_HOST="${CONFIG_OLLAMA_HOST:-$value}"
                ;;
            ollama_num_ctx|OLLAMA_NUM_CTX)
                CONFIG_OLLAMA_NUM_CTX="${CONFIG_OLLAMA_NUM_CTX:-$value}"
                ;;
            temperature|AI_TEMPERATURE)
                CONFIG_AI_TEMPERATURE="${CONFIG_AI_TEMPERATURE:-$value}"
                ;;
            prompt_style|PROMPT_STYLE)
                CONFIG_PROMPT_STYLE="${CONFIG_PROMPT_STYLE:-$value}"
                ;;
            anthropic_model|ANTHROPIC_MODEL)
                CONFIG_ANTHROPIC_MODEL="${CONFIG_ANTHROPIC_MODEL:-$value}"
                ;;
            openai_model|OPENAI_MODEL)
                CONFIG_OPENAI_MODEL="${CONFIG_OPENAI_MODEL:-$value}"
                ;;
            groq_model|GROQ_MODEL)
                CONFIG_GROQ_MODEL="${CONFIG_GROQ_MODEL:-$value}"
                ;;
            enable_fallback|ENABLE_FALLBACK)
                CONFIG_ENABLE_FALLBACK="${CONFIG_ENABLE_FALLBACK:-$value}"
                ;;
            fallback_provider|FALLBACK_PROVIDER)
                CONFIG_FALLBACK_PROVIDER="${CONFIG_FALLBACK_PROVIDER:-$value}"
                ;;
            use_scope|USE_SCOPE)
                CONFIG_USE_SCOPE="${CONFIG_USE_SCOPE:-$value}"
                ;;
            diff_max_lines|DIFF_MAX_LINES)
                CONFIG_DIFF_MAX_LINES="${CONFIG_DIFF_MAX_LINES:-$value}"
                ;;
            learn_from_history|LEARN_FROM_HISTORY)
                CONFIG_LEARN_FROM_HISTORY="${CONFIG_LEARN_FROM_HISTORY:-$value}"
                ;;
            use_gitmoji|USE_GITMOJI)
                CONFIG_USE_GITMOJI="${CONFIG_USE_GITMOJI:-$value}"
                ;;
            code_review_model|CODE_REVIEW_MODEL)
                CONFIG_CODE_REVIEW_MODEL="${CONFIG_CODE_REVIEW_MODEL:-$value}"
                ;;
            code_review_anthropic_model|CODE_REVIEW_ANTHROPIC_MODEL)
                CONFIG_CODE_REVIEW_ANTHROPIC_MODEL="${CONFIG_CODE_REVIEW_ANTHROPIC_MODEL:-$value}"
                ;;
            code_review_openai_model|CODE_REVIEW_OPENAI_MODEL)
                CONFIG_CODE_REVIEW_OPENAI_MODEL="${CONFIG_CODE_REVIEW_OPENAI_MODEL:-$value}"
                ;;
            code_review_groq_model|CODE_REVIEW_GROQ_MODEL)
                CONFIG_CODE_REVIEW_GROQ_MODEL="${CONFIG_CODE_REVIEW_GROQ_MODEL:-$value}"
                ;;
            commit_language|COMMIT_LANGUAGE)
                CONFIG_COMMIT_LANGUAGE="${CONFIG_COMMIT_LANGUAGE:-$value}"
                ;;
            analysis_threshold|ANALYSIS_THRESHOLD)
                CONFIG_ANALYSIS_THRESHOLD="${CONFIG_ANALYSIS_THRESHOLD:-$value}"
                ;;
            auto_fix|AUTO_FIX)
                CONFIG_AUTO_FIX="${CONFIG_AUTO_FIX:-$value}"
                ;;
            auto_fix_formatting|AUTO_FIX_FORMATTING)
                CONFIG_AUTO_FIX_FORMATTING="${CONFIG_AUTO_FIX_FORMATTING:-$value}"
                ;;
            auto_fix_trailing_whitespace|AUTO_FIX_TRAILING_WHITESPACE)
                CONFIG_AUTO_FIX_TRAILING_WHITESPACE="${CONFIG_AUTO_FIX_TRAILING_WHITESPACE:-$value}"
                ;;
            auto_fix_line_endings|AUTO_FIX_LINE_ENDINGS)
                CONFIG_AUTO_FIX_LINE_ENDINGS="${CONFIG_AUTO_FIX_LINE_ENDINGS:-$value}"
                ;;
            auto_fix_final_newline|AUTO_FIX_FINAL_NEWLINE)
                CONFIG_AUTO_FIX_FINAL_NEWLINE="${CONFIG_AUTO_FIX_FINAL_NEWLINE:-$value}"
                ;;
            line_ending_style|LINE_ENDING_STYLE)
                CONFIG_LINE_ENDING_STYLE="${CONFIG_LINE_ENDING_STYLE:-$value}"
                ;;
            stream_enabled|STREAM_ENABLED)
                CONFIG_STREAM_ENABLED="${CONFIG_STREAM_ENABLED:-$value}"
                ;;
            skip_secret_scan|SKIP_SECRET_SCAN)
                CONFIG_SKIP_SECRET_SCAN="${CONFIG_SKIP_SECRET_SCAN:-$value}"
                ;;
            analytics_enabled|ANALYTICS_ENABLED)
                CONFIG_ANALYTICS_ENABLED="${CONFIG_ANALYTICS_ENABLED:-$value}"
                ;;
            pipeline_enabled|PIPELINE_ENABLED)
                CONFIG_PIPELINE_ENABLED="${CONFIG_PIPELINE_ENABLED:-$value}"
                ;;
            analysis_model|ANALYSIS_MODEL)
                CONFIG_ANALYSIS_MODEL="${CONFIG_ANALYSIS_MODEL:-$value}"
                ;;
            analysis_provider|ANALYSIS_PROVIDER)
                CONFIG_ANALYSIS_PROVIDER="${CONFIG_ANALYSIS_PROVIDER:-$value}"
                ;;
            analysis_anthropic_model|ANALYSIS_ANTHROPIC_MODEL)
                CONFIG_ANALYSIS_ANTHROPIC_MODEL="${CONFIG_ANALYSIS_ANTHROPIC_MODEL:-$value}"
                ;;
            analysis_openai_model|ANALYSIS_OPENAI_MODEL)
                CONFIG_ANALYSIS_OPENAI_MODEL="${CONFIG_ANALYSIS_OPENAI_MODEL:-$value}"
                ;;
            analysis_groq_model|ANALYSIS_GROQ_MODEL)
                CONFIG_ANALYSIS_GROQ_MODEL="${CONFIG_ANALYSIS_GROQ_MODEL:-$value}"
                ;;
            *)
                # Track unknown keys for validation warnings
                CONFIG_UNKNOWN_KEYS+=("$key")
                ;;
        esac
    done < "$config_file"
}

# Known config keys for validation
KNOWN_CONFIG_KEYS="ai_provider ollama_model ollama_host ollama_num_ctx temperature prompt_style anthropic_model openai_model groq_model use_scope use_gitmoji diff_max_lines learn_from_history auto_fix analysis_threshold commit_language code_review_model code_review_anthropic_model code_review_openai_model code_review_groq_model stream_enabled skip_secret_scan analytics_enabled pipeline_enabled analysis_model analysis_provider analysis_anthropic_model analysis_openai_model analysis_groq_model"

# Unknown keys collector
CONFIG_UNKNOWN_KEYS=()

# Validate configuration values and warn about issues
validate_config() {
    local has_warnings=false

    # Check for unknown keys (likely typos)
    if [ ${#CONFIG_UNKNOWN_KEYS[@]} -gt 0 ]; then
        for unknown_key in "${CONFIG_UNKNOWN_KEYS[@]}"; do
            # Find closest match
            local best_match=""
            local best_distance=999
            for known_key in $KNOWN_CONFIG_KEYS; do
                # Simple prefix match for suggestion
                if [[ "$known_key" == "$unknown_key"* ]] || [[ "$unknown_key" == "$known_key"* ]]; then
                    best_match="$known_key"
                    break
                fi
                # Check if they share a common prefix of 3+ chars
                local prefix_len=0
                local min_len=${#unknown_key}
                [ ${#known_key} -lt $min_len ] && min_len=${#known_key}
                for ((i=0; i<min_len; i++)); do
                    if [ "${unknown_key:$i:1}" = "${known_key:$i:1}" ]; then
                        prefix_len=$((prefix_len + 1))
                    else
                        break
                    fi
                done
                if [ $prefix_len -ge 3 ] && [ $prefix_len -gt $((best_distance == 999 ? 0 : best_distance)) ]; then
                    best_match="$known_key"
                    best_distance=$prefix_len
                fi
            done
            if [ -n "$best_match" ]; then
                echo "Warning: Unknown config key '$unknown_key'. Did you mean '$best_match'?" >&2
            else
                echo "Warning: Unknown config key '$unknown_key' in config file." >&2
            fi
            has_warnings=true
        done
    fi

    # Validate enum values
    if [ -n "$CONFIG_AI_PROVIDER" ]; then
        case "$CONFIG_AI_PROVIDER" in
            auto|ollama|anthropic|openai|groq) ;;
            *)
                echo "Warning: Invalid ai_provider '$CONFIG_AI_PROVIDER'. Must be: auto, ollama, anthropic, openai, groq" >&2
                has_warnings=true
                ;;
        esac
    fi

    # Validate boolean values
    for var_name in CONFIG_USE_SCOPE CONFIG_USE_GITMOJI CONFIG_AUTO_FIX CONFIG_LEARN_FROM_HISTORY CONFIG_SKIP_SECRET_SCAN CONFIG_ANALYTICS_ENABLED CONFIG_PIPELINE_ENABLED; do
        local val="${!var_name}"
        if [ -n "$val" ] && [ "$val" != "true" ] && [ "$val" != "false" ]; then
            local key_name=$(echo "$var_name" | sed 's/^CONFIG_//' | tr '[:upper:]' '[:lower:]')
            echo "Warning: $key_name must be 'true' or 'false', got '$val'" >&2
            has_warnings=true
        fi
    done

    # Validate numeric values
    if [ -n "$CONFIG_DIFF_MAX_LINES" ] && [ "$CONFIG_DIFF_MAX_LINES" != "auto" ] && ! [[ "$CONFIG_DIFF_MAX_LINES" =~ ^[0-9]+$ ]]; then
        echo "Warning: diff_max_lines must be 'auto' or a positive integer, got '$CONFIG_DIFF_MAX_LINES'" >&2
        has_warnings=true
    fi

    if [ -n "$CONFIG_ANALYSIS_THRESHOLD" ] && ! [[ "$CONFIG_ANALYSIS_THRESHOLD" =~ ^[0-9]+$ ]]; then
        echo "Warning: analysis_threshold must be a positive integer, got '$CONFIG_ANALYSIS_THRESHOLD'" >&2
        has_warnings=true
    fi

    # Validate stream_enabled
    if [ -n "$CONFIG_STREAM_ENABLED" ]; then
        case "$CONFIG_STREAM_ENABLED" in
            auto|true|false) ;;
            *)
                echo "Warning: stream_enabled must be 'auto', 'true', or 'false', got '$CONFIG_STREAM_ENABLED'" >&2
                has_warnings=true
                ;;
        esac
    fi

    # Validate language code
    if [ -n "$CONFIG_COMMIT_LANGUAGE" ]; then
        case "$CONFIG_COMMIT_LANGUAGE" in
            en|es|fr|de|ja|zh|pt|ru|it|ko|nl|pl|tr|ar|hi) ;;
            *)
                echo "Warning: Unknown commit_language '$CONFIG_COMMIT_LANGUAGE'. Supported: en, es, fr, de, ja, zh, pt, ru, it, ko, nl, pl, tr, ar, hi" >&2
                has_warnings=true
                ;;
        esac
    fi

    if [ "$has_warnings" = true ]; then
        echo "" >&2
    fi
}

# Load configuration from files (global then local)
# Global config (in user's home directory)
if [ -f "$HOME/.gh-commit-ai.yml" ]; then
    parse_yaml_config "$HOME/.gh-commit-ai.yml"
fi

# Local config (in current repository)
if [ -f ".gh-commit-ai.yml" ]; then
    parse_yaml_config ".gh-commit-ai.yml"
fi

# Validate configuration
validate_config

# Configuration (priority: env vars > local config > global config > defaults)
AI_PROVIDER="${AI_PROVIDER:-${CONFIG_AI_PROVIDER:-auto}}"  # Options: auto, ollama, anthropic, openai, groq
OLLAMA_MODEL="${OLLAMA_MODEL:-${CONFIG_OLLAMA_MODEL:-qwen3:8b}}"
OLLAMA_HOST="${OLLAMA_HOST:-${CONFIG_OLLAMA_HOST:-http://localhost:11434}}"
# Context window for Ollama. Ollama defaults to only 4096 tokens and SILENTLY
# truncates prompts that exceed it — with our large diff+instruction prompt this
# drops the diff or the format rules and wrecks commit quality on big commits.
# Sized to comfortably fit the instruction prompt plus diff_max_lines: auto,
# which can send up to ~1000 diff lines.
OLLAMA_NUM_CTX="${OLLAMA_NUM_CTX:-${CONFIG_OLLAMA_NUM_CTX:-16384}}"
# Sampling temperature. Commit generation is a structured, low-creativity task;
# high temperature is the main source of run-to-run inconsistency ("great on some
# commits, vague on others"). Low values keep output faithful to the diff.
AI_TEMPERATURE="${AI_TEMPERATURE:-${CONFIG_AI_TEMPERATURE:-0.3}}"
# Prompt style: "full" (default, all context layers + few-shot walls) or "slim"
# (lean, diff-focused prompt). Slim reduces instruction overload on smaller models
# and anchors the model on the actual diff. Set to A/B which yields better messages.
PROMPT_STYLE="${PROMPT_STYLE:-${CONFIG_PROMPT_STYLE:-full}}"
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-${CONFIG_ANTHROPIC_MODEL:-claude-sonnet-4-6}}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
OPENAI_MODEL="${OPENAI_MODEL:-${CONFIG_OPENAI_MODEL:-gpt-4o-mini}}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
GROQ_MODEL="${GROQ_MODEL:-${CONFIG_GROQ_MODEL:-openai/gpt-oss-120b}}"
GROQ_API_KEY="${GROQ_API_KEY:-}"
DIFF_MAX_LINES="${DIFF_MAX_LINES:-${CONFIG_DIFF_MAX_LINES:-200}}"  # Limit diff lines for faster processing
USE_SCOPE="${USE_SCOPE:-${CONFIG_USE_SCOPE:-false}}"  # Enable/disable conventional commit scopes
USE_GITMOJI="${USE_GITMOJI:-${CONFIG_USE_GITMOJI:-false}}"  # Enable/disable gitmoji prefixes
LEARN_FROM_HISTORY="${LEARN_FROM_HISTORY:-${CONFIG_LEARN_FROM_HISTORY:-true}}"  # Enable/disable learning from commit history
AUTO_FIX="${AUTO_FIX:-${CONFIG_AUTO_FIX:-true}}"  # Enable/disable automatic fixing of common formatting issues
# Staged-file formatting auto-fix (see src/02b-autofix-formatting.sh). Defaults
# preserved from before the accidental removal in aeef1e3: opt-in overall, and
# when enabled it prompts rather than rewriting files silently.
AUTO_FIX_FORMATTING="${AUTO_FIX_FORMATTING:-${CONFIG_AUTO_FIX_FORMATTING:-false}}"  # Fix without asking
AUTO_FIX_TRAILING_WHITESPACE="${AUTO_FIX_TRAILING_WHITESPACE:-${CONFIG_AUTO_FIX_TRAILING_WHITESPACE:-false}}"  # Detect trailing whitespace
AUTO_FIX_LINE_ENDINGS="${AUTO_FIX_LINE_ENDINGS:-${CONFIG_AUTO_FIX_LINE_ENDINGS:-true}}"  # Detect inconsistent line endings
AUTO_FIX_FINAL_NEWLINE="${AUTO_FIX_FINAL_NEWLINE:-${CONFIG_AUTO_FIX_FINAL_NEWLINE:-true}}"  # Detect missing final newline
LINE_ENDING_STYLE="${LINE_ENDING_STYLE:-${CONFIG_LINE_ENDING_STYLE:-lf}}"  # Preferred line ending: "lf" (Unix) or "crlf" (Windows)
ANALYSIS_THRESHOLD="${ANALYSIS_THRESHOLD:-${CONFIG_ANALYSIS_THRESHOLD:-15}}"  # Skip expensive analysis for commits smaller than this (lines changed)
# Code review specific models (optional - falls back to regular models if not set)
CODE_REVIEW_MODEL="${CODE_REVIEW_MODEL:-${CONFIG_CODE_REVIEW_MODEL:-}}"  # Dedicated model for code reviews (Ollama)
CODE_REVIEW_ANTHROPIC_MODEL="${CODE_REVIEW_ANTHROPIC_MODEL:-${CONFIG_CODE_REVIEW_ANTHROPIC_MODEL:-}}"  # Anthropic model for reviews
CODE_REVIEW_OPENAI_MODEL="${CODE_REVIEW_OPENAI_MODEL:-${CONFIG_CODE_REVIEW_OPENAI_MODEL:-}}"  # OpenAI model for reviews
CODE_REVIEW_GROQ_MODEL="${CODE_REVIEW_GROQ_MODEL:-${CONFIG_CODE_REVIEW_GROQ_MODEL:-}}"  # Groq model for reviews

# Provider fallback configuration
# When the configured provider fails with a transient error (rate limit,
# token-limit-exceeded, network/timeout, service downtime), silently retry with a
# local model so a commit message still gets generated instead of aborting.
ENABLE_FALLBACK="${ENABLE_FALLBACK:-${CONFIG_ENABLE_FALLBACK:-true}}"  # Auto-fall back to a local model on provider failure
FALLBACK_PROVIDER="${FALLBACK_PROVIDER:-${CONFIG_FALLBACK_PROVIDER:-ollama}}"  # Provider to fall back to (local, no rate limits)

# Streaming configuration
STREAM_ENABLED="${STREAM_ENABLED:-${CONFIG_STREAM_ENABLED:-auto}}"  # auto, true, false - stream AI responses to terminal

# Secret scanning configuration
SKIP_SECRET_SCAN="${SKIP_SECRET_SCAN:-${CONFIG_SKIP_SECRET_SCAN:-false}}"  # Skip secret detection in diffs

# Analytics configuration
ANALYTICS_ENABLED="${ANALYTICS_ENABLED:-${CONFIG_ANALYTICS_ENABLED:-false}}"  # Enable local usage analytics

# Two-model pipeline configuration
PIPELINE_ENABLED="${PIPELINE_ENABLED:-${CONFIG_PIPELINE_ENABLED:-false}}"  # Enable two-stage pipeline
ANALYSIS_MODEL="${ANALYSIS_MODEL:-${CONFIG_ANALYSIS_MODEL:-}}"  # Ollama model for Stage 1 analysis
ANALYSIS_PROVIDER="${ANALYSIS_PROVIDER:-${CONFIG_ANALYSIS_PROVIDER:-}}"  # Provider override for Stage 1
ANALYSIS_ANTHROPIC_MODEL="${ANALYSIS_ANTHROPIC_MODEL:-${CONFIG_ANALYSIS_ANTHROPIC_MODEL:-}}"  # Anthropic model for analysis
ANALYSIS_OPENAI_MODEL="${ANALYSIS_OPENAI_MODEL:-${CONFIG_ANALYSIS_OPENAI_MODEL:-}}"  # OpenAI model for analysis
ANALYSIS_GROQ_MODEL="${ANALYSIS_GROQ_MODEL:-${CONFIG_ANALYSIS_GROQ_MODEL:-}}"  # Groq model for analysis

# Language configuration for commit messages
COMMIT_LANGUAGE="${COMMIT_LANGUAGE:-${CONFIG_COMMIT_LANGUAGE:-}}"  # Language for commit messages (en, es, fr, de, ja, zh, etc.)

# Detect language from git config or system locale if not explicitly set
detect_language() {
    # If already set, use it
    if [ -n "$COMMIT_LANGUAGE" ]; then
        echo "$COMMIT_LANGUAGE"
        return
    fi

    # Try to get from git config
    local git_language=$(git config --get commit.language 2>/dev/null || echo "")
    if [ -n "$git_language" ]; then
        echo "$git_language"
        return
    fi

    # Try to detect from system locale
    local lang_var="${LANG:-${LC_ALL:-}}"
    if [ -n "$lang_var" ]; then
        # Extract language code (e.g., en_US.UTF-8 -> en, es_ES.UTF-8 -> es)
        local lang_code=$(echo "$lang_var" | cut -d'_' -f1 | cut -d'.' -f1)
        if [ -n "$lang_code" ] && [ "$lang_code" != "C" ] && [ "$lang_code" != "POSIX" ]; then
            echo "$lang_code"
            return
        fi
    fi

    # Default to English
    echo "en"
}

# Detect and set the language
DETECTED_LANGUAGE=$(detect_language)
COMMIT_LANGUAGE="${COMMIT_LANGUAGE:-$DETECTED_LANGUAGE}"

# Map language codes to full names for display
get_language_name() {
    case "$1" in
        en) echo "English" ;;
        es) echo "Spanish" ;;
        fr) echo "French" ;;
        de) echo "German" ;;
        ja) echo "Japanese" ;;
        zh) echo "Chinese" ;;
        pt) echo "Portuguese" ;;
        ru) echo "Russian" ;;
        it) echo "Italian" ;;
        ko) echo "Korean" ;;
        nl) echo "Dutch" ;;
        pl) echo "Polish" ;;
        tr) echo "Turkish" ;;
        ar) echo "Arabic" ;;
        hi) echo "Hindi" ;;
        *) echo "English" ;;
    esac
}

# Git diff exclusion patterns - exclude lock files and other generated files
# These files are auto-generated and not useful for AI analysis
GIT_EXCLUDE_PATTERN="':(exclude)package-lock.json' ':(exclude)yarn.lock' ':(exclude)pnpm-lock.yaml' ':(exclude)Gemfile.lock' ':(exclude)Cargo.lock' ':(exclude)poetry.lock' ':(exclude)composer.lock' ':(exclude)Pipfile.lock' ':(exclude)go.sum' ':(exclude)*.min.js' ':(exclude)*.min.css'"

# Network retry configuration
MAX_RETRIES="${MAX_RETRIES:-3}"  # Maximum number of retry attempts
RETRY_DELAY="${RETRY_DELAY:-2}"  # Initial retry delay in seconds (doubles each retry)
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-10}"  # Connection timeout in seconds
MAX_TIME="${MAX_TIME:-120}"  # Maximum time for entire request in seconds

# ============================================================================
# Security Functions
# ============================================================================

