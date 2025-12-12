# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a GitHub CLI extension that generates AI-powered git commit messages using AI models from multiple providers (Ollama, Anthropic, OpenAI). The entire functionality is contained in a single bash script (`gh-commit-ai`) that can be installed as a `gh` extension.

## Architecture

### Single-Script Design
- **gh-commit-ai**: The main executable bash script that implements the entire extension
  - Uses pure bash without external dependencies (except curl, git, and standard Unix tools)
  - Multi-provider support with pluggable API integration
  - Provides interactive prompts for user confirmation and editing

### Key Components in gh-commit-ai

1. **Command-Line Argument Parsing** (lines ~22-71): Handles optional flags
   - `--dry-run`: Generate message without committing (with optional file save)
   - `--preview`: Generate and display message, then exit
   - `--amend`: Regenerate message for last commit
   - `--help, -h`: Show usage information
2. **Git Integration** (lines ~73-115): Validates git repository, checks for changes, gathers status and diff
   - **Amend Mode** (lines ~80-92): When `--amend` is used, analyzes the last commit instead of staged changes
     - Uses `git show HEAD` to get last commit's diff
     - Gets file changes and stats from last commit
     - Generates new message based on what was in that commit
   - **Performance optimization**: Limits diff to configurable number of lines (default 200) via `DIFF_MAX_LINES`
   - Also captures `git diff --stat` for file-level overview without full content
   - **Branch Intelligence** (lines ~186-206):
     - Extracts current branch name
     - Detects ticket numbers using pattern `[A-Z][A-Z0-9]+-[0-9]+` (e.g., ABC-123, JIRA-456)
     - Suggests commit type based on branch prefix (feat/*, fix/*, docs/*, etc.)
     - Passes branch context to AI for better commit messages
   - **Smart Type Detection** (lines ~208-273):
     - `detect_smart_type()`: Analyzes changed files and diff content
     - Categorizes files: docs, tests, config, code
     - Detects patterns:
       - Documentation-only changes → "docs"
       - Test-only changes → "test"
       - Version bumps in config files → "chore"
       - Bug keywords in diff (fix, bug, error, crash, etc.) → "fix"
     - Smart suggestions can override branch suggestions when branch gives no hint
     - When both exist, mentions both for AI to consider
   - **Breaking Change Detection** (lines ~293-360):
     - `detect_breaking_changes()`: Analyzes diff for breaking changes
     - Returns "true|reason" or "false|" to indicate if breaking change detected
     - Detection methods:
       - Explicit keywords: BREAKING CHANGE, breaking:, etc.
       - API removal: Removed export/public functions
       - Major version bumps: 1.x.x → 2.0.0
       - Signature changes: Function parameters reduced
     - Integrates with prompt to add `!` suffix and BREAKING CHANGE footer
   - **Commit History Learning** (lines ~366-475):
     - `analyze_commit_history()`: Analyzes last 50 commits to detect patterns
     - Can be disabled with `LEARN_FROM_HISTORY=false`
     - Detects:
       - Emoji usage patterns
       - Scope usage frequency (percentage)
       - Most common commit types
       - Capitalization preferences
       - Breaking change notation usage
     - Builds insights string passed to AI in prompt
     - Requires minimum 5 commits in repository
3. **Prompt Engineering** (lines ~118-191): Two-stage thinking prompt that:
   - **Stage 1**: AI identifies all significant changes and lists them as bullets
   - **Stage 2**: AI synthesizes those bullets into one concise summary line
   - **Output**: Summary line first (with type prefix and optional scope), then the detailed bullet list
   - **Scope support**: Conditionally includes scope instructions based on `USE_SCOPE` setting
   - This ensures the summary accurately captures ALL changes, not just some of them
4. **JSON Handling** (~line 193-195): Pure bash JSON creation using `escape_json()` function to avoid `jq` dependency
5. **Lowercase Enforcement** (~lines 197-235): `enforce_lowercase()` function that converts commit messages to lowercase while preserving:
   - Ticket numbers (e.g., ABC-123, JIRA-456)
   - Common acronyms (API, HTTP, JSON, JWT, SQL, etc.)
6. **Provider Functions**:
   - `call_ollama()`: Integrates with local Ollama API
   - `call_anthropic()`: Integrates with Anthropic Claude API (requires API key)
   - `call_openai()`: Integrates with OpenAI GPT API (requires API key)
   - `call_groq()`: Integrates with Groq API (requires API key, ultra-fast inference)
7. **Network Retry Logic** (lines ~187-265): Automatic retry with exponential backoff for API calls
   - `retry_api_call()`: Wrapper function that handles network failures gracefully
   - Configuration variables (lines ~182-185):
     - `MAX_RETRIES`: Number of retry attempts (default: 3)
     - `RETRY_DELAY`: Initial delay between retries in seconds (default: 2)
     - `CONNECT_TIMEOUT`: Connection timeout in seconds (default: 10)
     - `MAX_TIME`: Maximum time for entire request in seconds (default: 120)
   - **Exponential Backoff**: Doubles delay after each attempt (2s → 4s → 8s)
   - **Error Detection**: Handles comprehensive curl error codes:
     - Code 6: Could not resolve host
     - Code 7: Failed to connect
     - Code 28: Timeout
     - Code 35: SSL connection error
     - Code 52: Empty response from server
     - Code 56: Network error (receive failure)
   - **User Feedback**: Shows retry progress with user-friendly messages
   - **Provider Integration**: All four providers use retry_api_call wrapper (lines ~3219-3577)
8. **Provider Routing**: Case statement that routes to the appropriate provider based on `AI_PROVIDER`
9. **JSON Parsing**: Each provider function extracts responses using grep/sed to avoid `jq` dependency
10. **Message Post-Processing**: Applies lowercase enforcement to ensure consistent formatting
11. **Newline Conversion** (~line 1479-1484): `convert_newlines()` function that converts literal `\n` sequences to actual newlines
   - AI responses contain literal `\n` characters (from JSON encoding)
   - Uses `printf "%b"` to interpret backslash escapes
   - Applied before committing to ensure proper multi-line display in GitHub
   - Also applied when displaying messages to users and saving to files
12. **Dry-Run and Preview Modes** (lines ~577-587):
    - `--preview`: Shows message and exits immediately
    - `--dry-run`: Shows message and optionally saves to `.git/COMMIT_MSG_<timestamp>` file
13. **Interactive Editing** (lines ~325-471): Fine-grained message editing without opening a text editor
    - `parse_commit_message()`: Parses message into SUMMARY_LINE and BULLETS arrays
    - `rebuild_commit_message()`: Rebuilds message from components
    - `interactive_edit_message()`: Provides menu-driven editing interface
    - Features: Edit summary, add/remove/reorder bullets
14. **Cost Tracking** (lines ~483-600): Token usage and cost calculation for paid APIs
    - `calculate_cost()`: Calculates costs based on provider and model pricing
    - Supports Anthropic (Claude models) and OpenAI (GPT models) pricing
    - Uses bc or awk for floating-point calculations
    - `track_cumulative_cost()`: Tracks daily cumulative costs in /tmp
    - Extracts token usage from API responses (INPUT_TOKENS, OUTPUT_TOKENS)
15. **Interactive Workflow** (lines ~737-787): User confirmation with loop support for interactive editing
    - `y`: Accept and commit
    - `n`: Cancel
    - `e`: Edit in default editor
    - `i`: Interactive editing mode
16. **Message History & Recovery** (lines ~1140-1188): Repository-specific message caching
    - `save_message_history()`: Saves generated messages to temporary storage
    - `get_last_message()`: Retrieves the most recent message
    - `is_recent_message()`: Checks if message is less than 5 minutes old
    - `clear_message_history()`: Removes cached messages after successful commit
    - **Repository Scoping** (lines ~1900-1918): Messages are scoped per repository
      - Uses MD5 hash of repository path to create unique cache directory
      - Format: `/tmp/gh-commit-ai-history-<repo-hash>/`
      - Prevents message leakage between different repositories
      - Each repository maintains its own separate message history
      - Keeps last 5 messages per repository
    - Automatic recovery if user accidentally exits within 5 minutes
    - Asks user if they want to reuse the recovered message

## Configuration

### Configuration Files

The extension supports YAML configuration files for persistent settings (implemented in lines 11-78):

**Supported Config Files:**
1. **Global config**: `~/.gh-commit-ai.yml` - Applies to all repositories
2. **Local config**: `.gh-commit-ai.yml` - Repository-specific (overrides global)
3. **Example template**: `.gh-commit-ai.example.yml` - Copy this to create your own

**YAML Parser** (lines 11-56):
- `parse_yaml_config()` - Pure bash YAML parser (no `yq` dependency)
- Supports simple `key: value` format with comments
- Maps YAML keys to `CONFIG_*` variables
- Supported keys: `ai_provider`, `ollama_model`, `ollama_host`, `anthropic_model`, `openai_model`, `use_scope`, `diff_max_lines`, `code_review_model`, `code_review_anthropic_model`, `code_review_openai_model`

**Configuration Loading** (lines 58-67):
- Global config loaded first: `parse_yaml_config "$HOME/.gh-commit-ai.yml"`
- Local config loaded second: `parse_yaml_config ".gh-commit-ai.yml"`
- Local config values override global config values

**Configuration Precedence** (lines 69-78):
1. **Environment variables** (highest priority) - Override everything
2. **Local config** (`.gh-commit-ai.yml` in repo root) - Override global config
3. **Global config** (`~/.gh-commit-ai.yml` in home) - Override defaults
4. **Built-in defaults** (lowest priority) - Fallback values

Example: `AI_PROVIDER="${AI_PROVIDER:-${CONFIG_AI_PROVIDER:-ollama}}"`
- First checks `AI_PROVIDER` env var
- Falls back to `CONFIG_AI_PROVIDER` from config file
- Falls back to `ollama` as default

**Security Note:**
- API keys (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`) are NOT supported in config files
- These must be set as environment variables for security reasons
- Config files should not contain sensitive credentials

### Environment Variables

Environment variables take precedence over config files (defined at lines 69-78):

**Provider Selection:**
- `AI_PROVIDER`: Choose provider (default: `auto`) - Options: `auto`, `ollama`, `anthropic`, `openai`, `groq`
  - `auto`: Automatically detects available providers (prefers Ollama → Groq → Anthropic → OpenAI)
  - Detects Ollama availability by checking if it's running and has models installed
  - Detects Anthropic/OpenAI/Groq by checking for API keys
  - Shows helpful error if no providers are available

**Ollama (default, local, free):**
- `OLLAMA_MODEL`: Model to use (default: `gemma3:12b`)
- `OLLAMA_HOST`: API endpoint (default: `http://localhost:11434`)

**Anthropic (API key required):**
- `ANTHROPIC_API_KEY`: Your Anthropic API key
- `ANTHROPIC_MODEL`: Model to use (default: `claude-3-5-sonnet-20241022`)

**OpenAI (API key required):**
- `OPENAI_API_KEY`: Your OpenAI API key
- `OPENAI_MODEL`: Model to use (default: `gpt-4o-mini`)

**Groq (API key required, ultra-fast, generous free tier):**
- `GROQ_API_KEY`: Your Groq API key
- `GROQ_MODEL`: Model to use (default: `llama-3.3-70b-versatile`)
- Features: Ultra-fast inference (10-20x faster), 100 requests/minute free tier
- Get API key at: https://console.groq.com/keys

**Commit Format:**
- `USE_SCOPE`: Enable/disable conventional commit scopes (default: `false`)
  - When disabled (default), generates: `feat: add login`
  - When enabled, generates: `feat(auth): add login`

- `USE_GITMOJI`: Enable/disable gitmoji emoji prefixes (default: `false`)
  - When disabled (default), generates: `feat: add login`
  - When enabled, generates: `✨ feat: add login`
  - Gitmoji mappings:
    - ✨ feat: new feature
    - 🐛 fix: bug fix
    - 📝 docs: documentation
    - 💄 style: formatting/styling
    - ♻️ refactor: code refactoring
    - ✅ test: adding tests
    - 🔧 chore: tooling/config/maintenance
    - 🚀 perf: performance improvement
    - 🔒 security: security fix
  - Can be combined with `USE_SCOPE`: `✨ feat(auth): add login`

**Performance:**
- `DIFF_MAX_LINES`: Maximum diff lines to send to AI (default: `200`) - Reduces token usage and speeds up generation

**Code Review Models (Optional):**
- `CODE_REVIEW_MODEL`: Dedicated Ollama model for code reviews (falls back to `OLLAMA_MODEL` if not set)
- `CODE_REVIEW_ANTHROPIC_MODEL`: Dedicated Anthropic model for code reviews (falls back to `ANTHROPIC_MODEL` if not set)
- `CODE_REVIEW_OPENAI_MODEL`: Dedicated OpenAI model for code reviews (falls back to `OPENAI_MODEL` if not set)
- These allow using larger, more capable models for reviews while using faster models for commit messages
- Recommended: `qwen2.5-coder:14b`, `deepseek-coder:6.7b`, `claude-3-5-sonnet`, `gpt-4o`

## Command-Line Options

The script supports several command-line flags:

**`--dry-run`**
- Generates commit message but doesn't commit
- After showing the message, asks if you want to save it to a file
- Saves to `.git/COMMIT_MSG_<timestamp>` if confirmed
- Useful for testing or reviewing messages before committing

**`--preview`**
- Generates and displays the commit message
- Exits immediately without any interaction
- Useful for scripting or quick previews

**`--amend`**
- Analyzes the last commit (HEAD) instead of staged changes
- Generates a new commit message based on what's in that commit
- Uses `git commit --amend` to rewrite the commit message
- **Warning:** Only use on commits that haven't been pushed, or be prepared to force push

**`--options`**
- Generates 3 different commit message variations
- Variations: concise, detailed, and alternative perspective
- Displays all options with numbers
- User selects their preferred option
- Useful for exploring different ways to describe changes

**`--help, -h`**
- Shows usage information
- Lists all available options and environment variables
- Provides examples

**Example usage:**
```bash
# Preview mode
gh commit-ai --preview

# Dry-run mode
gh commit-ai --dry-run

# Amend mode (rewrite last commit message)
gh commit-ai --amend

# Normal mode (default)
gh commit-ai
```

## Message Recovery

The extension automatically saves generated commit messages to a temporary history and offers to recover recent messages if you accidentally exit. This prevents having to regenerate messages and saves API costs.

### Overview

**Recovery System Architecture:**
1. All generated messages saved to `/tmp/gh-commit-ai-history/msg_<timestamp>.txt`
2. Keeps last 5 messages in history
3. On startup, checks for messages generated within last 5 minutes
4. Offers to reuse recent message or regenerate
5. Recovery skipped for `--preview` and `--dry-run` modes

**Key Functions:**
- `save_message_history()` (lines ~632-642): Saves message to history with timestamp
- `get_last_message()` (lines ~644-650): Retrieves last message from history
- `is_recent_message()` (lines ~652-670): Checks if last message is within 5 minutes
- `clear_message_history()` (lines ~672-675): Clears all saved messages (called after successful commit)

### Recovery Flow

**When Recovery Triggers:**
- A message was generated within last 5 minutes
- Not in preview or dry-run mode
- User runs `gh commit-ai` again

**Recovery Prompt:**
```
💡 Found recent commit message from history:

feat: add user authentication

- implement JWT token generation
- create login endpoint

Reuse this message? (y/n/r to regenerate):
```

**Options:**
- `y`: Reuse the recovered message (skip AI generation, save costs)
- `n`: Cancel and exit
- `r`: Regenerate a new message (call AI again)

### Integration Points

**Location in Code:**
- Recovery check: lines ~2517-2545 (before AI provider call)
- Conditional AI generation: lines ~2547-2691 (skipped if message recovered)
- Recovery display: lines ~2693-2698 (show recovered message)

**Execution Flow:**
```
1. User runs gh commit-ai
2. IF recent message exists:
   a. Display last message
   b. Ask: reuse (y) / cancel (n) / regenerate (r)
   c. If reuse: skip AI generation, use recovered message
   d. If regenerate: continue to AI generation
   e. If cancel: exit
3. ELSE: continue to AI generation
4. Process message (lowercase, template, etc.)
5. Display and ask for confirmation
```

### Regenerate Option

Users can also regenerate from the confirmation prompt after seeing any message:

```
Use this commit message? (y/n/e to edit/r to regenerate):
```

**Regenerate Flow (lines ~2777-2845):**
1. User presses `r` at confirmation
2. Call AI provider again with same prompt
3. Apply all post-processing (strip fences, lowercase, template)
4. Save new message to history
5. Display regenerated message
6. Loop back to confirmation prompt

**Benefits:**
- Try different phrasings without manual editing
- Generate multiple variations to pick the best
- Costs one additional API call per regeneration

### Use Cases

**Scenario 1: Accidental Exit**
```bash
# Generate message
$ gh commit-ai
✓ Generated commit message: ...
Use this commit message? (y/n/e/r):
# User accidentally presses Ctrl+C or closes terminal

# Run again within 5 minutes
$ gh commit-ai
💡 Found recent commit message from history: ...
Reuse this message? (y/n/r): y
✓ Recovered commit message: ...
# Message recovered, no API call needed
```

**Scenario 2: Want Different Wording**
```bash
$ gh commit-ai
✓ Generated commit message: feat: implement user auth
Use this commit message? (y/n/e/r): r

Regenerating commit message...
✓ Regenerated commit message: feat: add authentication system
Use this commit message? (y/n/e/r): y
# New wording, same functionality
```

**Scenario 3: Recovery After System Crash**
```bash
# Terminal crashes during confirmation
# Restart within 5 minutes
$ gh commit-ai
💡 Found recent commit message from history: ...
Reuse this message? (y/n/r): y
# Continue where you left off
```

### Configuration

**Time Window:**
- Default: 5 minutes (300 seconds)
- Configurable in code: `is_recent_message()` function (line 664)
- To change: modify `if [ "$age" -lt 300 ]; then`

**History Location:**
- Directory: `/tmp/gh-commit-ai-history/`
- Automatically cleaned by system (in /tmp)
- Keeps last 5 messages only

**History Format:**
- Filename: `msg_<unix_timestamp>.txt`
- Content: Raw commit message (with lowercase and template applied)
- Sorted by modification time

### Benefits

1. **Cost Savings**: Reuse messages without calling AI API again
2. **Time Savings**: Instant recovery vs. waiting for generation
3. **Consistency**: Preserve exact wording if you liked it
4. **Flexibility**: Can regenerate if you want something different
5. **Safety Net**: Protection against accidental exits

### Notes

- Recovery only offers messages from within last 5 minutes
- Older messages are not offered (prevents stale messages)
- Preview and dry-run modes skip recovery (expected to be read-only)
- History is per-machine (stored in /tmp)
- Messages survive terminal crashes but not system reboots
- **History is cleared after successful commit** (prevents reusing committed messages)
  - Cleared after: `y` (accept), `e` (edit), both normal and `--amend` modes
  - Function: `clear_message_history()` (line ~673)

## Interactive Editing Mode

The interactive editing feature (invoked with `i` during confirmation) allows fine-grained editing without opening a text editor.

**Architecture:**

1. **Message Parsing** (`parse_commit_message()`):
   - Splits commit message into components
   - Extracts first line as `SUMMARY_LINE`
   - Extracts all lines starting with `- ` as `BULLETS` array
   - Uses bash arrays for in-memory manipulation

2. **Message Rebuilding** (`rebuild_commit_message()`):
   - Reconstructs message from `SUMMARY_LINE` and `BULLETS`
   - Maintains proper formatting (blank line between summary and bullets)
   - Uses `echo -e` to handle newlines

3. **Interactive Menu** (`interactive_edit_message()`):
   - Menu-driven interface with single-key commands
   - Operations:
     - `s`: Edit summary line with read prompt
     - `a`: Add new bullet to end of array
     - `r`: Remove bullet by number (with validation)
     - `o`: Reorder bullets (move from position X to Y)
     - `d`: Done - return edited message
     - `c`: Cancel - return original message
   - Uses `clear` command to redraw screen after each operation
   - Returns 0 on success (done), 1 on cancel

4. **Integration with Confirmation Loop**:
   - Main confirmation prompt wrapped in `while true` loop
   - Pressing `i` calls `interactive_edit_message()`
   - On success, updates `COMMIT_MSG` and shows updated message
   - Loops back to confirmation for final approval
   - On cancel, exits the script

**Benefits:**
- Quick edits without leaving the terminal
- No need to learn git commit editor commands
- Visual feedback after each operation
- Can make multiple changes in sequence
- Reorder provides better organization of changes

## Cost Tracking for Paid APIs

The extension automatically tracks and displays costs when using Anthropic or OpenAI APIs.

**Architecture:**

1. **Token Extraction**:
   - `call_anthropic()`: Extracts `input_tokens` and `output_tokens` from API response
   - `call_openai()`: Extracts `prompt_tokens` and `completion_tokens` from API response
   - Stores values in global variables: `INPUT_TOKENS` and `OUTPUT_TOKENS`

2. **Cost Calculation** (`calculate_cost()`):
   - Takes provider, model, input tokens, and output tokens as parameters
   - Maintains pricing table for all supported models (as of early 2025)
   - Uses bc for floating-point arithmetic (with awk fallback)
   - Calculates: `(input_tokens / 1M * input_price) + (output_tokens / 1M * output_price)`
   - Formats output with appropriate precision (more decimals for very small costs)

3. **Cumulative Tracking** (`track_cumulative_cost()`):
   - Stores individual costs in daily file: `/tmp/gh-commit-ai-costs-YYYYMMDD`
   - Calculates sum of all costs for the current day
   - Displays "Today's total" after each generation
   - Files are automatically cleaned up by system (in /tmp)

4. **Display**:
   - Shows after message generation but before confirmation
   - Format: "Token usage: X tokens (Y input + Z output)"
   - Format: "Estimated cost: $X.XXXX USD"
   - Format: "Today's total: $X.XXXX USD"
   - Only displayed for Anthropic and OpenAI (not Ollama)

**Supported Models and Pricing:**

| Provider | Model | Input (per MTok) | Output (per MTok) |
|----------|-------|------------------|-------------------|
| Anthropic | Claude 3.5 Sonnet | $3.00 | $15.00 |
| Anthropic | Claude 3 Opus | $15.00 | $75.00 |
| Anthropic | Claude 3 Haiku | $0.25 | $1.25 |
| OpenAI | GPT-4o | $2.50 | $10.00 |
| OpenAI | GPT-4o-mini | $0.15 | $0.60 |
| OpenAI | GPT-4 Turbo | $10.00 | $30.00 |
| OpenAI | GPT-4 | $30.00 | $60.00 |

**Notes:**
- Ollama is free (runs locally) and does not show cost information
- Costs are estimates based on published pricing
- Daily totals reset at midnight (tracked by date in filename)

## Testing

### Unit Tests

The project includes a comprehensive test suite using [Bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

**Test Coverage:**
- Core functions (JSON escaping, lowercase enforcement)
- Command-line interface and argument parsing
- Branch intelligence (ticket extraction, type detection)
- Error handling

**Running Tests:**
```bash
# Install bats (macOS)
brew install bats-core

# Run all tests
bats tests/

# Run specific test file
bats tests/test_core_functions.bats
bats tests/test_cli.bats
bats tests/test_branch_intelligence.bats
```

**Test Files:**
- `tests/test_helper.bash` - Helper functions and fixtures
- `tests/test_core_functions.bats` - Tests for escape_json() and enforce_lowercase()
- `tests/test_cli.bats` - Tests for command-line interface
- `tests/test_branch_intelligence.bats` - Tests for branch name parsing

See [tests/README.md](tests/README.md) for detailed testing documentation.

**Note:** The test suite covers unit-testable functions. Integration testing with actual API calls and git operations should be done manually.

## Testing the Extension

### Local Development
```bash
# Test the script directly
./gh-commit-ai

# Install as a GitHub CLI extension from local directory
gh extension install .

# Test as an extension
gh commit-ai

# Uninstall for testing reinstallation
gh extension remove commit-ai
```

### Testing with Different Providers
```bash
# Test with Ollama (default)
./gh-commit-ai
OLLAMA_MODEL="codellama" ./gh-commit-ai

# Test with Anthropic
AI_PROVIDER="anthropic" ANTHROPIC_API_KEY="sk-ant-..." ./gh-commit-ai
AI_PROVIDER="anthropic" ANTHROPIC_MODEL="claude-3-opus-20240229" ANTHROPIC_API_KEY="sk-ant-..." gh commit-ai

# Test with OpenAI
AI_PROVIDER="openai" OPENAI_API_KEY="sk-proj-..." ./gh-commit-ai
AI_PROVIDER="openai" OPENAI_MODEL="gpt-4o" OPENAI_API_KEY="sk-proj-..." gh commit-ai
```

## Commit Message Guidelines

The prompt uses a two-stage approach to ensure accurate summaries:

**Two-Stage Generation Process:**
1. **Stage 1 (Analysis)**: AI identifies and lists all significant changes as bullets
2. **Stage 2 (Synthesis)**: AI creates a one-line summary that captures the essence of ALL changes
3. **Output**: Summary line appears first, followed by the detailed bullets

**Mandatory Format:**

Without scope (default):
```
<type>: <concise summary capturing all changes (max 50 chars)>

- <change 1>
- <change 2>
- <change 3>
```

With scope (`USE_SCOPE=true`):
```
<type>(<scope>): <concise summary capturing all changes (max 50 chars)>

- <change 1>
- <change 2>
- <change 3>
```

Common scopes: `auth`, `api`, `ui`, `db`, `cli`, `docs`, `config`, `tests`, `deps`

**Rules enforced by the prompt:**
1. First line MUST start with: feat, fix, docs, style, refactor, test, or chore
2. Summary must describe the overall purpose/theme of all changes below it
3. First line must be 50 characters or less
4. Blank line after first line
5. All significant changes listed as bullet points
6. Use imperative mood (add, fix, update - not added, fixed, updated)
7. Use lowercase only (except acronyms and ticket numbers)

**Example (default, without scope):**
```
feat: add user authentication

- implement JWT token generation
- create login endpoint
- add password hashing
- create user session management
```

The summary "add user authentication" captures the overall purpose of all four changes listed below it.

**Example (with scope enabled):**
```
feat(auth): add user authentication

- implement JWT token generation
- create login endpoint
- add password hashing
- create user session management
```

When `USE_SCOPE=true`, the scope "(auth)" is added to indicate this is authentication-related.

**Lowercase Enforcement:** Even if the AI generates uppercase letters, the `enforce_lowercase()` function automatically converts the message to lowercase while intelligently preserving:
- Ticket number patterns (e.g., ABC-123, JIRA-456, EWQ-789)
- Common technical acronyms (API, HTTP, JSON, JWT, SQL, etc.)

Examples:
- Input: "Feat: Add User Authentication With JWT" → Output: "feat: add user authentication with JWT"
- Input: "Fix: Resolve API Connection Issue For EWQ-123" → Output: "fix: resolve API connection issue for EWQ-123"

## Commit Templates

The extension supports custom commit message templates that allow you to control the exact format of your commit messages. Templates are applied after the AI generates the message content, giving you full control over the final format.

### Overview

**Template System Architecture:**
1. AI generates commit message with standard format (type, scope, summary, bullets)
2. Template system parses the AI-generated message into components
3. If `.gh-commit-ai-template` exists, applies custom template
4. Otherwise, uses built-in format (no change)

**Key Functions:**
- `detect_project_type()` (lines ~1794-1842): Detects project type from files (web-app, library, cli, general)
- `load_template()` (lines ~1844-1892): Loads custom template or returns built-in template
- `parse_commit_components()` (lines ~1894-1948): Parses AI message into template variables
- `apply_template()` (lines ~1950-2023): Substitutes variables and returns formatted message

### Template Variables

All available variables that can be used in templates:

| Variable | Description | Example |
|----------|-------------|---------|
| `{{emoji}}` | Gitmoji emoji (if enabled) | ✨ |
| `{{type}}` | Commit type | feat |
| `{{scope}}` | Scope with parentheses | (auth) |
| `{{breaking_marker}}` | ! if breaking change | ! |
| `{{message}}` | Summary message | add user authentication |
| `{{bullets}}` | Bullet points | - implement JWT<br>- create login endpoint |
| `{{breaking}}` | BREAKING CHANGE footer | BREAKING CHANGE: removed... |
| `{{ticket}}` | Ticket from branch | ABC-123 |
| `{{branch}}` | Current branch name | feature/ABC-123-auth |
| `{{author}}` | Git author name | John Doe |
| `{{date}}` | Current date | 2025-12-02 |
| `{{files_changed}}` | Number of files | 5 |

**Note:** Empty variables are automatically removed from the output.

### Template File

**Location:** `.gh-commit-ai-template` in repository root

**Format:** Plain text file with template variables using `{{variable}}` syntax

**When to Use:**
- Only applied if `.gh-commit-ai-template` file exists
- Without this file, uses standard conventional commit format
- Opt-in by design - doesn't affect default behavior

### Built-in Templates

The extension includes built-in templates based on detected project type:

**Web App Template** (detects: package.json with react/vue/angular/webpack/vite):
```
{{emoji}} {{type}}{{scope}}: {{message}}

{{bullets}}
{{breaking}}
```

**Library Template** (detects: setup.py, Cargo.toml, go.mod):
```
{{emoji}} {{type}}{{scope}}: {{message}}

{{bullets}}
{{breaking}}

Changes: {{files_changed}} files changed
```

**CLI Tool Template** (detects: bin/ or cmd/ directory):
```
{{emoji}} {{type}}{{scope}}: {{message}}

{{bullets}}
{{breaking}}
```

**General Template** (default fallback):
```
{{emoji}} {{type}}{{scope}}: {{message}}

{{bullets}}
{{breaking}}
```

### Example Templates

**Standard Template (default):**
```
{{emoji}} {{type}}{{scope}}: {{message}}

{{bullets}}
{{breaking}}
```

**Template with Ticket Number:**
```
{{emoji}} {{type}}{{scope}}: {{message}}

{{bullets}}
{{breaking}}

Ticket: {{ticket}}
```

**Detailed Template with Metadata:**
```
{{emoji}} {{type}}{{scope}}: {{message}}

{{bullets}}
{{breaking}}

Branch: {{branch}}
Ticket: {{ticket}}
Files: {{files_changed}} changed
Date: {{date}}
```

**Angular Style (no emoji):**
```
{{type}}{{scope}}: {{message}}

{{bullets}}

{{breaking}}
```

**Minimal (summary only):**
```
{{emoji}} {{type}}{{scope}}: {{message}}
```

**Custom Project Format:**
```
[{{ticket}}] {{emoji}} {{type}}{{scope}}: {{message}}

Changes:
{{bullets}}

{{breaking}}

Reviewed-by: {{author}}
Committed: {{date}}
```

### Usage

**1. Create Template File:**
```bash
# Copy example template
cp .gh-commit-ai-template.example .gh-commit-ai-template

# Edit to keep only the template you want
nano .gh-commit-ai-template
```

**2. Customize Template:**
```bash
# Example: Add ticket number to all commits
cat > .gh-commit-ai-template << 'EOF'
{{emoji}} {{type}}{{scope}}: {{message}}

{{bullets}}
{{breaking}}

Ticket: {{ticket}}
EOF
```

**3. Generate Commit:**
```bash
# Template will be automatically applied
gh commit-ai
```

### Integration with Existing Features

Templates work seamlessly with all existing features:

- **USE_SCOPE=true**: `{{scope}}` will include (scope) or be empty
- **USE_GITMOJI=true**: `{{emoji}}` will include emoji or be empty
- **Branch Intelligence**: `{{ticket}}` extracted from branch name
- **Breaking Changes**: `{{breaking_marker}}` becomes ! and `{{breaking}}` includes footer
- **Lowercase Enforcement**: Applied before template processing
- **Multiple Options Mode**: Each option formatted with same template

### Project Type Detection

The extension automatically detects project type to select appropriate built-in template:

**Detection Logic:**
1. **Web App**: package.json contains react/vue/angular/svelte/next/nuxt/webpack/vite
2. **Library**:
   - Python: setup.py or pyproject.toml exists
   - Rust: Cargo.toml with [lib] section
   - Go: go.mod exists without main.go
   - Node: package.json with "type": "module"
3. **CLI Tool**:
   - bin/ or cmd/ directory exists
   - Cargo.toml without [lib]
   - Go with package main
4. **General**: Default fallback for all other projects

**Note:** Project type only affects built-in templates. Custom `.gh-commit-ai-template` always takes precedence.

### Template Processing Flow

**Execution Order (lines 2603-2613 for single message, 2556-2567 for multiple options):**
```
1. AI generates message → COMMIT_MSG
2. Strip markdown fences
3. Validate message not empty
4. Enforce lowercase (unless NO_LOWERCASE=true)
5. IF .gh-commit-ai-template exists:
   a. Detect project type
   b. Load template
   c. Parse message components
   d. Apply template substitution
   e. Clean up empty lines
6. Save to history
7. Display to user
```

**Example Flow:**
```bash
# AI generates:
feat: add user authentication

- implement JWT token generation
- create login endpoint

# Template (.gh-commit-ai-template):
[{{ticket}}] {{type}}: {{message}}

Changes:
{{bullets}}

# Final output (branch: feature/ABC-123-auth):
[ABC-123] feat: add user authentication

Changes:
- implement JWT token generation
- create login endpoint
```

### Tips and Best Practices

1. **Start Simple**: Copy one of the example templates and customize incrementally
2. **Test First**: Use `--dry-run` or `--preview` to test templates without committing
3. **Remove Comments**: Template file should only contain the template itself
4. **Empty Variables**: Don't worry about empty variables - they're automatically removed
5. **Preserve Format**: The AI generates the content; template just rearranges it
6. **Version Control**: Add `.gh-commit-ai-template` to your repo for team consistency
7. **Per-Project**: Each repo can have its own template for project-specific needs

### Example: Setting Up Team Template

```bash
# Create team template
cat > .gh-commit-ai-template << 'EOF'
{{emoji}} {{type}}{{scope}}: {{message}}

{{bullets}}
{{breaking}}

Ticket: {{ticket}}
Reviewed-by: {{author}}
EOF

# Commit to repo
git add .gh-commit-ai-template
git commit -m "chore: add commit message template for team"

# Team members pull and automatically use template
git pull
gh commit-ai  # Uses team template
```

### Troubleshooting

**Template not being applied:**
- Verify `.gh-commit-ai-template` exists in repo root
- Check file has no syntax errors (just plain text with {{variables}})
- Run with `--preview` to test without committing

**Variables showing as empty:**
- `{{ticket}}`: Requires branch name with pattern ABC-123
- `{{emoji}}`: Requires USE_GITMOJI=true
- `{{scope}}`: Requires USE_SCOPE=true or AI detected scope
- `{{breaking}}`: Only present for actual breaking changes

**Formatting issues:**
- Template uses exact spacing/newlines from template file
- Empty lines are preserved
- Lines with only empty variables are removed

## Intelligent Type Detection

The extension uses two complementary systems to suggest the appropriate commit type:

### 1. Branch Intelligence

Extracts context from branch names to improve commit message accuracy.

**Ticket Number Detection:**
- Pattern: `[A-Z][A-Z0-9]+-[0-9]+` (e.g., ABC-123, JIRA-456, PROJ-789)
- Example: Branch `feature/ABC-123-user-login` → Extracts "ABC-123"
- The ticket number is passed to the AI and included in the commit message

**Type Suggestion from Branch Prefix:**
- `feat/*` or `feature/*` → suggests "feat"
- `fix/*`, `bugfix/*`, or `hotfix/*` → suggests "fix"
- `docs/*` or `doc/*` → suggests "docs"
- `style/*` → suggests "style"
- `refactor/*` → suggests "refactor"
- `test/*` or `tests/*` → suggests "test"
- `chore/*` → suggests "chore"

### 2. Smart Type Detection

Analyzes actual changes (files and diff content) to intelligently suggest commit types.

**Architecture:**

`detect_smart_type()` function (lines 209-273) performs multi-stage analysis:

**Stage 1: File Classification**
- Parses `git status` output to extract changed filenames
- Categorizes each file into:
  - **Documentation**: `.md`, `.txt`, `.rst`, `.adoc`, `docs/`, `README`, `CHANGELOG`, `LICENSE`
  - **Tests**: `tests/`, `test/`, `*.test.*`, `*.spec.*`, `*_test.*`, `*_spec.*`, `__tests__/`
  - **Config**: `.json`, `.yml`, `.yaml`, `.toml`, `.ini`, `.conf`, `.config`, `.*rc`, `package.json`, `setup.py`, `Cargo.toml`, `go.mod`
  - **Code**: Everything else
- Counts files in each category

**Stage 2: Pattern Detection**
1. **Documentation-only changes**:
   - If `doc_count > 0` AND `test_count = 0` AND `code_count = 0`
   - Returns "docs"

2. **Test-only changes**:
   - If `test_count > 0` AND `doc_count = 0` AND `code_count = 0`
   - Returns "test"

3. **Version bumps**:
   - If config files changed AND diff contains `+"version"` or `+version =`
   - Returns "chore"

4. **Bug fixes**:
   - If diff contains added lines with keywords: "fix", "bug", "issue", "error", "crash", "problem", "broken", "incorrect", "wrong"
   - Uses case-insensitive grep: `grep -qiE '^\+.*(fix|bug|...)'`
   - Returns "fix"

**Stage 3: Integration with Branch Intelligence**
- If branch gives no suggestion, smart type is used
- If branch gives a suggestion, it takes precedence (branch is explicit user intent)
- If both differ, prompt mentions both: "Suggested type: feat (based on branch name, smart detection also suggests: docs)"
- AI can consider both suggestions and override if actual changes warrant it

**Example Flow:**
```bash
# Scenario 1: No branch hint, only docs changed
Branch: main (no type hint)
Files: README.md, docs/api.md
Smart detection: "docs"
→ Suggested type: docs (based on file analysis)

# Scenario 2: Branch says "feat" but only docs changed
Branch: feature/add-docs (suggests "feat")
Files: README.md
Smart detection: "docs"
→ Suggested type: feat (based on branch name, smart detection also suggests: docs)
# AI sees both and can choose appropriately

# Scenario 3: Branch says nothing, bug keywords found
Branch: update-auth (no type hint)
Files: auth.js
Diff: "+ // fix authentication bug"
Smart detection: "fix"
→ Suggested type: fix (based on file analysis)
```

**Benefits:**
- Accurate suggestions even without branch naming conventions
- Catches common patterns (docs-only, tests-only, version bumps)
- Detects bug fixes from code comments and commit intent
- Works alongside branch intelligence for best results

### 3. Breaking Change Detection

Automatically detects breaking changes in the diff and instructs the AI to add the `!` suffix and BREAKING CHANGE footer.

**Architecture:**

`detect_breaking_changes()` function (lines 294-355) performs pattern-based analysis:

**Detection Methods:**

1. **Explicit Keywords**:
   - Searches for "BREAKING CHANGE", "breaking change", "BREAKING:", "breaking:" in added lines
   - Case-insensitive grep: `grep -qiE '^\+.*(BREAKING CHANGE|...)'`
   - Most reliable method - developer explicitly marked it

2. **API Removal Detection**:
   - Detects removed lines with public API declarations
   - Patterns: `export (function|class|const|...)`, `public (class|function|...)`, `def ...`, `function ...`
   - Regex: `grep -qE '^-.*\b(export (function|class|...)|public |def |function )'`
   - Assumes removed public APIs are breaking changes

3. **Major Version Bumps**:
   - Extracts version numbers from config file diffs
   - Looks for version changes in `package.json`, `setup.py`, `Cargo.toml`, etc.
   - Compares major version number: if `new_major > old_major` → breaking
   - Example: 1.5.3 → 2.0.0 is detected as breaking

4. **Function Signature Changes**:
   - Detects when function signatures change (parameters removed)
   - Compares removed and added function definitions
   - Counts commas to estimate parameter count
   - If `new_count < old_count` → likely breaking
   - Heuristic-based, not 100% accurate

**Integration:**

- Stores result in `IS_BREAKING` ("true" or "false") and `BREAKING_REASON` (explanation)
- Adds to `BRANCH_CONTEXT`: "BREAKING CHANGE DETECTED: {reason}"
- Updates `CLOSING_INSTRUCTION`: "This is a BREAKING CHANGE - add ! after type and include BREAKING CHANGE footer."
- Updates `SCOPE_INSTRUCTION` and examples to show breaking change format

**Output Format:**

Without scope:
```
feat!: redesign authentication API

- replace oldLogin with new login function
- change username to email parameter

BREAKING CHANGE: oldLogin() function removed, use login() with email instead
```

With scope:
```
feat!(auth): redesign authentication API

- replace oldLogin with new login function
- change username to email parameter

BREAKING CHANGE: oldLogin() function removed, use login() with email instead
```

**Benefits:**
- Automatic detection of common breaking change patterns
- Ensures proper conventional commit format
- Helps maintain semantic versioning discipline
- AI can still override if detection is incorrect

### 4. Commit History Learning

Automatically analyzes the repository's commit history to detect and match existing commit message patterns.

**Architecture:**

`analyze_commit_history()` function (lines 367-469) performs statistical analysis of recent commits:

**Data Collection:**
- Retrieves last 50 commits using `git log --pretty=format:"%s" -n 50`
- Returns empty if disabled (`LEARN_FROM_HISTORY=false`)
- Requires minimum 5 commits (exits early for new repos)

**Pattern Detection:**

1. **Emoji Usage**:
   - Searches for Unicode emoji characters or `:emoji:` shortcodes
   - Counts occurrences across all commits
   - Reports if repository uses emojis

2. **Scope Usage**:
   - Pattern: `^[a-z]+\([a-z]+\):`  (e.g., `feat(auth):`)
   - Calculates percentage of commits using scopes
   - Example: "Uses scopes in 75% of commits"

3. **Type Preferences**:
   - Counts usage of each conventional commit type
   - Types: feat, fix, docs, chore, refactor, test, style
   - Identifies most common type
   - Case-insensitive detection with `grep -ciE`

4. **Capitalization Preferences**:
   - Compares lowercase vs uppercase first words
   - Pattern lowercase: `^[a-z]+(...)?!?: [a-z]`
   - Pattern uppercase: `^[a-z]+(...)?!?: [A-Z]`
   - Reports which style is preferred

5. **Breaking Change Notation**:
   - Detects `!:` pattern in commit messages
   - Notes if repository uses breaking change markers
   - Example: `feat!: redesign API`

**Integration:**

- Stores insights in `HISTORY_INSIGHTS` variable
- Inserted into prompt between `BRANCH_CONTEXT` and file changes
- Format:
  ```
  Repository commit style (based on last 50 commits):
  - Uses scopes in 60% of commits
  - Most common type: feat
  - Prefers lowercase commit messages
  - Sometimes uses emojis
  - Uses breaking change notation (!) when appropriate

  Match this repository's style in your commit message.
  ```

**Configuration:**

- Enable/disable: `LEARN_FROM_HISTORY` (default: `true`)
- Can be set via:
  - Environment variable: `LEARN_FROM_HISTORY=false gh commit-ai`
  - Config file: `learn_from_history: false`
- When disabled, function returns empty string

**Example Scenarios:**

1. **Repository with scope convention**:
   ```
   Last 50 commits:
   - feat(api): add endpoints
   - fix(ui): resolve button issue
   - docs(readme): update setup

   → AI learns: "Uses scopes in 100% of commits"
   → Generated: feat(auth): add user login
   ```

2. **Repository without scopes**:
   ```
   Last 50 commits:
   - feat: add user authentication
   - fix: resolve database connection
   - docs: update readme

   → AI learns: "Rarely uses scopes"
   → Generated: feat: add user login
   ```

3. **Repository with emojis**:
   ```
   Last 50 commits:
   - ✨ feat: add new feature
   - 🐛 fix: resolve bug

   → AI learns: "Sometimes uses emojis"
   → May generate: ✨ feat: add user login
   ```

**Benefits:**
- Automatic adaptation to repository conventions
- No manual style guide configuration needed
- Maintains consistency across team
- Works with existing codebases
- Can be disabled for standardized workflows

## Advanced Commit Message Intelligence

The tool includes 8 layers of intelligence to generate highly specific and accurate commit messages. These features work together to understand not just what files changed, but the semantic meaning of those changes.

### 1. Few-Shot Learning Examples (Lines 3430-3467)

Built-in examples teach the AI how to write specific commit messages:

**Architecture:**
- Hardcoded examples in the prompt showing good vs bad messages
- Examples demonstrate proper specificity (video handling, authentication, payment processing)
- Includes function name mentions and proper formatting
- Shows anti-patterns to avoid (generic messages like "fix: resolve bug")

**Example:**
```
Good: feat: add video upload with format validation
- implement uploadVideo() function
- add support for mp4, avi, mov formats

Bad: feat: add feature ❌
```

**Benefits:**
- Teaches AI by example (few-shot learning)
- Establishes clear quality standards
- Shows how to mention specific areas and functions
- Prevents generic/vague messages

### 2. Function/Class Name Detection (Lines 3424-3522)

Automatically extracts code symbols being modified:

**Architecture:**
- `extract_changed_functions()`: Parses diff for function and class declarations
- Multi-language support:
  - **PHP**: `function uploadVideo()`, `class UserController`
  - **Python**: `def processPayment()`
  - **JavaScript/TypeScript**: `const validateUser = function`, `function handleSubmit()`
  - **Classes**: `class VideoProcessor`, `class AuthMiddleware`
- Limits to 8 most significant functions/classes (avoids clutter)
- Uses regex patterns to match various declaration styles

**Integration:**
```bash
Modified functions/classes: uploadVideo(), processPayment(), UserController
Consider mentioning these in your commit message if they represent significant changes.
```

**Benefits:**
- AI knows exact functions being changed
- Encourages mentioning specific code elements
- Helps write technical, precise commit messages
- Works across multiple programming languages

**Example Output:**
```
feat: add video upload with validation

- implement uploadVideo() function
- add validateFormat() helper
- update VideoController class
```

### 3. Repository Commit Examples (Lines 3524-3557)

Learns from your repository's best existing commits:

**Architecture:**
- `get_best_commit_examples()`: Analyzes last 100 commits
- Finds commits with:
  - Proper conventional commit format (feat:, fix:, etc.)
  - Bullet points (multi-line body)
  - Good structure
- Shows 2 best examples to the AI
- Disabled if repository has no good examples

**Format:**
```
EXAMPLES FROM THIS REPOSITORY:

feat: add user authentication

- implement JWT token generation
- create login endpoint
- add password hashing
```

**Benefits:**
- Uses your repo's actual style as training data
- No need to configure examples manually
- Adapts to each project's conventions
- Complements history insights (which analyze patterns)

**Integration:**
- Works alongside `analyze_commit_history()` (pattern detection)
- History insights: "Uses scopes 60% of time"
- Repo examples: Shows actual good commits from this repo

### 4. Domain-Specific Pattern Detection (Lines 3399-3454)

Recognizes 50+ framework and technology patterns:

**Architecture:**
- Extended `extract_file_context()` with domain-specific case statements
- Detects framework conventions from file paths and names
- Provides context-specific labels for the AI

**Supported Frameworks:**

**Laravel:**
```
*Controller.php          → "Laravel controller"
app/models/*Model.php    → "Laravel model"
database/migrations/*    → "Laravel migration"
*Middleware.php          → "Laravel middleware"
*Request.php             → "Laravel request validation"
database/seeders/*       → "Laravel seeder"
*Provider.php            → "Laravel service provider"
resources/views/*        → "Laravel Blade views"
```

**React/Vue/Angular:**
```
*Component.tsx           → "React component"
*.tsx, *.jsx             → "React/TypeScript"
*hook*.ts, use*.ts       → "React hooks"
*.vue                    → "Vue component"
*component.ts            → "Angular component"
*service.ts              → "Angular service"
*module.ts               → "Angular/NestJS module"
```

**WordPress:**
```
wp-content/themes/*      → "WordPress theme"
wp-content/plugins/*     → "WordPress plugin"
functions.php            → "WordPress theme functions"
wp-admin/*               → "WordPress admin"
```

**Django/Flask:**
```
*/views.py               → "Django/Flask views"
*/models.py              → "Django models"
*/serializers.py         → "Django serializers"
*/forms.py               → "Django forms"
*/urls.py                → "Django URL routing"
```

**Ruby on Rails:**
```
*_controller.rb          → "Rails controller"
*_model.rb               → "Rails model"
db/migrate/*             → "Rails migration"
*_helper.rb              → "Rails helper"
```

**Docker/DevOps:**
```
Dockerfile               → "Docker configuration"
docker-compose.yml       → "Docker Compose"
.github/workflows/*      → "CI/CD pipeline"
kubernetes/*, k8s/*      → "Kubernetes config"
```

**Benefits:**
- Framework-aware commit messages
- More specific context than generic "controller" or "model"
- Works automatically without configuration
- Covers most popular frameworks

**Example:**
```
Input: app/Http/Controllers/VideoController.php
Output: Detected code areas: Laravel controller, video handling

Commit: feat: add video upload endpoint to Laravel controller
```

### 5. Semantic Diff Analysis (Lines 3559-3634)

Understands the semantic meaning of changes:

**Architecture:**
- `analyze_change_type()`: Analyzes diff content for patterns
- Detects 12 types of semantic changes
- Uses grep patterns to identify code structures

**Detection Categories:**

1. **Error Handling:**
   - Pattern: `throw new`, `try {`, `catch`, `except:`, `raise`
   - Output: "added error handling"

2. **TODOs/Technical Debt:**
   - Pattern: `TODO`, `FIXME`, `XXX`, `HACK`
   - Output: "added TODOs"

3. **Logging:**
   - Pattern: `console.log`, `logger.`, `logging.`, `log.`, `print(`
   - Output: "added logging"

4. **Tests:**
   - Pattern: `it(`, `test(`, `describe(`, `assert`, `expect(`
   - Output: "added tests"

5. **Validation:**
   - Pattern: `validate`, `check`, `verify`, `assert`, `ensure`
   - Output: "added validation"

6. **API Endpoints:**
   - Pattern: `route`, `endpoint`, `@RequestMapping`, `@GetMapping`, `@app.route`
   - Output: "added API endpoints"

7. **Database Changes:**
   - Pattern: `CREATE TABLE`, `ALTER TABLE`, `migration`, `Schema::`
   - Output: "database schema changes"

8. **Code Removal:**
   - Logic: Deletions > 2x additions
   - Output: "code removal/cleanup"

9. **New Functions/Classes:**
   - Pattern: `function`, `def`, `class`, `const ... = (`
   - Output: "new functions/classes"

10. **Configuration:**
    - Pattern: `config`, `settings`, `env`, `ENV`, `CONST`
    - Output: "configuration updates"

11. **Dependencies:**
    - Pattern: `import`, `require(`, `from ... import`, `include`, `use`
    - Output: "dependency changes"

12. **Documentation:**
    - Pattern: `/**`, `"""`, `* @`, `#...:`, `<!--`
    - Output: "documentation updates"

**Integration:**
```
Type of changes detected: added error handling, new functions/classes, added logging
```

**Benefits:**
- AI understands the nature of changes
- More context than just "modified video.php"
- Helps choose appropriate commit type
- Detects cross-cutting concerns

**Example:**
```
Detected: added error handling, added validation, new functions/classes

Generated commit:
feat: add video upload with validation and error handling

- implement uploadVideo() function
- add try-catch for network errors
- validate file size and format
- add logging for debugging
```

### 6. Per-File Change Summaries (Lines 3636-3677)

Pre-digests changes for each file:

**Architecture:**
- `generate_file_summaries()`: Creates one-line summary per file
- Shows file status (new, modified, deleted, renamed)
- Counts additions and deletions per file
- Only shows files with significant changes (>2 lines or new/deleted)

**Format:**
```
FILE SUMMARIES:
- video.php: modified (+45/-12 lines)
- auth/login.php: modified (+23/-5 lines)
- tests/VideoTest.php: new file (+67/-0 lines)
- old_uploader.php: deleted (-120/-0 lines)
```

**Benefits:**
- Quick overview of change magnitude
- AI can prioritize which files to emphasize
- Shows new files and deletions clearly
- Helps identify main areas of work

**Integration:**
- Appears before the full diff in the prompt
- Complements git stats
- More readable than raw `git diff --stat`

### 7. Multi-File Relationship Detection (Lines 3679-3728)

Identifies patterns across multiple files:

**Architecture:**
- `detect_file_relationships()`: Analyzes files together
- Detects 7 common multi-file patterns
- Returns high-level relationships

**Detected Patterns:**

1. **Migration + Model:**
   - Pattern: `migration` + `model` or `schema`
   - Output: "database migration with model changes"
   - Example: `database/migrations/001_users.sql` + `app/models/User.php`

2. **Test + Source:**
   - Pattern: Test files + non-test files
   - Output: "includes test coverage"
   - Example: `video.php` + `tests/VideoTest.php`

3. **Component + Style:**
   - Pattern: `.tsx/.jsx/.vue` + `.css/.scss/.sass`
   - Output: "component with styling changes"
   - Example: `VideoPlayer.tsx` + `VideoPlayer.scss`

4. **Controller + View:**
   - Pattern: `controller` + `view` or `template`
   - Output: "controller and view updates"
   - Example: `VideoController.php` + `views/video/upload.blade.php`

5. **API + Documentation:**
   - Pattern: `api/endpoint/route` + `readme/doc/swagger`
   - Output: "API changes with documentation"
   - Example: `routes/api.php` + `docs/API.md`

6. **Config + Code:**
   - Pattern: Config files + multiple other files
   - Output: "configuration changes with code"
   - Example: `.env` + `video.php` + `auth.php`

7. **Docker + CI:**
   - Pattern: `Dockerfile/docker-compose` + CI files
   - Output: "Docker and CI/CD updates"
   - Example: `Dockerfile` + `.github/workflows/deploy.yml`

**Integration:**
```
Related file changes: database migration with model changes, includes test coverage
```

**Benefits:**
- Captures architectural context
- Shows holistic nature of changes
- Encourages mentioning all aspects
- Detects best practices (tests with code)

**Example:**
```
Input:
- database/migrations/add_videos_table.sql
- app/models/Video.php
- tests/VideoModelTest.php

Context: database migration with model changes, includes test coverage

Generated:
feat: add video model with database schema

- create videos table migration
- implement Video model with relations
- add comprehensive test coverage
```

### 8. Integrated Intelligence System

All layers work together in the prompt:

**Prompt Structure:**
```
1. Few-shot examples (teach by example)
2. Repository examples (learn from history)
3. Branch context (ticket number, suggested type)
4. History insights (scope usage, emoji usage)
5. Detected code areas (video handling, authentication)
6. Modified functions (uploadVideo(), validateUser())
7. Semantic analysis (added error handling, new functions)
8. File relationships (includes test coverage)
9. File summaries (video.php: +45/-12 lines)
10. Full file list
11. Git stats
12. Diff sample
13. Closing instructions (mention specific areas!)
```

**Information Flow:**
```
Files Changed
    ↓
extract_file_context() → "video handling, authentication"
    ↓
extract_changed_functions() → "uploadVideo(), validateUser()"
    ↓
analyze_change_type() → "added error handling, new functions"
    ↓
detect_file_relationships() → "includes test coverage"
    ↓
generate_file_summaries() → "video.php: +45/-12"
    ↓
ALL CONTEXT → AI Model → Specific Commit Message
```

**Example of Full Context:**

```
Input:
- Modified: video.php (+45/-12)
- Modified: tests/VideoTest.php (+67/-0)

Generated Context:
- Detected areas: video handling, tests
- Functions: uploadVideo(), validateFormat()
- Change types: new functions/classes, added validation, added tests
- Relationships: includes test coverage
- File summaries: significant changes to video processing

AI Receives:
"You're working on video handling. New functions uploadVideo() and
validateFormat() were added. Changes include validation and tests.
Make sure to mention video processing and testing in your message."

Generated Commit:
feat: add video upload with format validation

- implement uploadVideo() function with size limits
- add validateFormat() for mp4/avi/mov support
- include comprehensive test coverage
- add input validation and error handling
```

**Benefits of Integrated System:**

1. **Redundancy:** Multiple ways to detect the same context (increases accuracy)
2. **Specificity:** Each layer adds more precise information
3. **Robustness:** If one layer fails, others still provide context
4. **Complementary:** Different layers answer different questions:
   - "What area?" → File context
   - "What functions?" → Function extraction
   - "What kind of change?" → Semantic analysis
   - "How are files related?" → Relationship detection

**Configuration:**

All features work automatically with no configuration. Optional controls:

```bash
# Disable history learning (disables repo examples too)
LEARN_FROM_HISTORY=false gh commit-ai

# All other features are always active
```

**Performance:**

- Minimal overhead (<500ms for most commits)
- Efficient regex-based parsing
- Only processes sampled diff (respects DIFF_MAX_LINES)
- Functions run in parallel where possible

**Real-World Impact:**

**Before (generic):**
```
❌ fix: resolve bug
❌ feat: add feature
❌ update: change files
```

**After (specific):**
```
✅ fix: resolve video upload timeout for large files
   - increase uploadVideo() max file size to 500MB
   - add progress tracking
   - improve error handling

✅ feat: add Laravel user authentication endpoints
   - implement UserController with JWT middleware
   - create login and registration routes
   - add request validation
   - include test coverage

✅ refactor: improve video processing error handling
   - add try-catch in processVideo()
   - add logging for debugging
   - validate input formats
```

**Quality Metrics:**

With all 8 layers active, commit messages typically include:
- ✅ Specific area/feature name (95%+ of commits)
- ✅ Function/class names mentioned (when significant)
- ✅ Nature of change described (error handling, validation, etc.)
- ✅ Related changes noted (tests, documentation, etc.)
- ✅ Follows repository conventions automatically

## Code Review Mode

The tool includes a `review` subcommand that performs AI-powered code review on your changes before committing.

**Usage:**
```bash
gh commit-ai review [--all]
```

**Architecture:**

The `generate_code_review()` function (lines 457-604) provides comprehensive code review:

**Features:**
- Reviews staged changes by default
- Optional `--all` flag to review all changes (staged + unstaged)
- Analyzes changes across 6 categories:
  1. Security vulnerabilities (SQL injection, XSS, CSRF, exposed secrets)
  2. Performance concerns (inefficient algorithms, memory leaks)
  3. Code quality (best practices, naming, duplication)
  4. Error handling (missing try-catch, unhandled errors)
  5. Potential bugs (logic errors, edge cases, race conditions)
  6. Maintainability (TODO/FIXME, magic numbers, documentation)

**Review Format:**
- Severity markers: 🔴 Critical, 🟡 Warning, 🔵 Info
- File and line number references for each issue
- Clear explanation of the problem
- Suggested fixes and improvements
- Overall assessment and recommendations

**Implementation Details:**

1. **Change Detection** (lines 470-487):
   - Gets `git diff --cached` for staged changes
   - Gets `git diff HEAD` for all changes (with `--all` flag)
   - Validates that changes exist to review

2. **Smart Sampling** (line 490):
   - Uses `smart_sample_diff()` to handle large diffs
   - Respects `DIFF_MAX_LINES` configuration
   - Maintains context while reducing size

3. **Comprehensive Prompt** (lines 502-541):
   - Structured review request with clear categories
   - Requests specific format (summary, issues, recommendations)
   - Includes file stats and code diff with proper formatting

4. **AI Integration** (lines 545-561):
   - Works with all providers (Ollama, Anthropic, OpenAI)
   - Same provider routing as commit message generation
   - Error handling for failed reviews

5. **Results Display** (lines 568-603):
   - Formatted output with colored headers
   - Token usage and cost tracking for paid APIs
   - Daily cumulative cost display

**Examples:**
```bash
# Review staged changes
git add src/auth.js
gh commit-ai review

# Review all changes (staged + unstaged)
gh commit-ai review --all

# Example workflow: review before committing
git add .
gh commit-ai review
# Fix any issues identified
gh commit-ai  # Generate commit message
```

**Benefits:**
- Catches issues before they enter version control
- Educational: learn from AI suggestions
- Consistent review quality across team
- Identifies security and performance issues early
- Complements commit message generation

**Dedicated Review Models:**

Code review requires deeper analysis than commit message generation, so you can configure dedicated models for reviews:

```bash
# Environment variables
export CODE_REVIEW_MODEL="qwen2.5-coder:14b"  # For Ollama
export CODE_REVIEW_ANTHROPIC_MODEL="claude-3-opus-20240229"  # For Anthropic
export CODE_REVIEW_OPENAI_MODEL="gpt-4o"  # For OpenAI

# Or in .gh-commit-ai.yml
code_review_model: qwen2.5-coder:14b
code_review_anthropic_model: claude-3-opus-20240229
code_review_openai_model: gpt-4o
```

**Recommended Models for Code Review:**
- **Ollama**: `qwen2.5-coder:14b`, `deepseek-coder:6.7b`, `codellama:13b`
- **Anthropic**: `claude-3-5-sonnet-20241022`, `claude-3-opus-20240229`
- **OpenAI**: `gpt-4o`, `gpt-4-turbo`

If no dedicated model is configured, the tool falls back to the regular model and shows a helpful tip if you're using a small model.

## Semantic Versioning Suggestions

The tool includes a `version` subcommand (alias: `semver`) that analyzes commits and suggests the next semantic version number.

**Usage:**
```bash
gh commit-ai version [--create-tag] [--prefix <prefix>]
gh commit-ai semver -t  # Short alias with tag creation
```

**Architecture:**

The `suggest_next_version()` function (lines 471-645) provides intelligent version suggestions:

**Features:**
- Analyzes all commits since the last git tag
- Suggests version bump based on conventional commits:
  - **Major bump (X.0.0)**: Breaking changes detected (feat!, fix!, BREAKING CHANGE)
  - **Minor bump (0.X.0)**: New features added (feat:)
  - **Patch bump (0.0.X)**: Only bug fixes or other changes (fix:, docs:, chore:)
- Counts and categorizes commit types
- Provides clear reasoning for suggested bump
- Interactive tag creation with confirmation
- Generates tag message with commit summary
- Handles first version (suggests 0.1.0 when no tags exist)

**Implementation Details:**

1. **Tag Detection** (lines 482-509):
   - Gets last tag with `git describe --tags --abbrev=0`
   - If no tags exist, suggests v0.1.0 as first version
   - Interactive creation for first tag

2. **Version Parsing** (lines 511-523):
   - Extracts version from tag (removes prefix)
   - Parses major.minor.patch components
   - Validates format (X.Y.Z)
   - Supports custom prefixes (default: "v")

3. **Commit Analysis** (lines 528-558):
   - Gets all commits since last tag
   - Analyzes each commit message with regex:
     - Breaking: `^[a-z]+(...)?!:` or `BREAKING CHANGE`
     - Features: `^feat(...)?:`
     - Fixes: `^fix(...)?:`
     - Other: everything else
   - Counts each category

4. **Version Bump Logic** (lines 560-585):
   - Priority: Breaking > Features > Fixes > Other
   - Major bump resets minor and patch to 0
   - Minor bump resets patch to 0
   - Patch bump increments only patch

5. **Output Display** (lines 589-644):
   - Shows current version and suggested version
   - Displays commit analysis with counts
   - Explains reasoning for bump type
   - Provides git commands for tagging

6. **Tag Creation** (lines 614-640):
   - Interactive confirmation (y/n)
   - Generates tag message with commit stats
   - Creates annotated tag with `git tag -a`
   - Shows next steps (push commands)

**Examples:**
```bash
# Check suggested version
gh commit-ai version

# Create tag automatically
gh commit-ai version --create-tag

# Use custom prefix
gh commit-ai version --prefix "release-"

# Short alias
gh commit-ai semver -t
```

**Example Output:**
```
Current version: v0.1.0

Suggested version: v0.2.0 (minor bump)

Analysis of 14 commits since v0.1.0:
  • 9 new feature(s)
  • 4 bug fix(es)
  • 1 other commit(s) (docs, chore, etc.)

Reasoning:
  • New features added (no breaking changes) → MINOR bump
  • Bumping from 0.1.0 to 0.2.0

To create this tag:
  git tag -a v0.2.0 -m "Release v0.2.0"
  git push origin v0.2.0
```

**Benefits:**
- Automates version number selection
- Follows semantic versioning strictly
- Based on conventional commits
- Reduces human error in versioning
- Clear audit trail of reasoning
- Integrates with existing git workflow

## Changelog Generation

The tool includes a `changelog` subcommand that generates formatted changelogs from conventional commit history.

**Usage:**
```bash
gh commit-ai changelog [--since <ref>] [--format <format>]
```

**Architecture:**

1. **Command Detection** (lines 93-132):
   - Checks if first argument is "changelog"
   - Sets `CHANGELOG_MODE=true`
   - Parses changelog-specific flags (`--since`, `--format`)
   - Has separate help text for changelog command

2. **Execution Flow** (lines 437-441):
   - Runs before main commit message generation
   - Exits immediately after generating changelog
   - Independent of normal commit workflow

3. **Changelog Generation Function** (lines 84-313):
   ```bash
   generate_changelog() {
       # 1. Build git log command
       # 2. Parse commits with conventional format regex
       # 3. Categorize by type (feat, fix, docs, etc.)
       # 4. Detect breaking changes
       # 5. Format output with emoji categories
   }
   ```

**Parsing Logic:**

1. **Conventional Commit Regex**:
   ```bash
   # With breaking change: feat!: description
   ^([a-z]+)(\([a-z0-9_-]+\))?!:\ (.+)$

   # Standard: feat(scope): description
   ^([a-z]+)(\([a-z0-9_-]+\))?:\ (.+)$

   # Non-conventional: any text
   type="other"
   ```

2. **Breaking Change Detection**:
   - `!` suffix in commit type (e.g., `feat!:`)
   - `BREAKING CHANGE:` in commit body

3. **Categorization**:
   - Uses bash arrays for each category
   - Breaking changes tracked separately
   - Commit can appear in multiple categories (breaking + feature)

4. **Output Format**:
   ```markdown
   # Changelog

   ## [version...HEAD] or Unreleased

   ### Date: YYYY-MM-DD

   ### ⚠️ BREAKING CHANGES (if any)
   - entry with link

   ### ✨ Features
   - entry with link
   - **scope**: entry with link

   ### 🐛 Bug Fixes
   - entry with link

   [... other categories ...]
   ```

**Supported Categories:**
- ⚠️ BREAKING CHANGES (always first)
- ✨ Features (feat, feature)
- 🐛 Bug Fixes (fix)
- 📝 Documentation (docs)
- ⚡ Performance (perf, performance)
- ♻️ Refactoring (refactor)
- ✅ Tests (test, tests)
- 💄 Style (style)
- 🔧 Chores (chore, build, ci)
- Other Changes (non-conventional)

**Features:**
- **Parses conventional commits** - Extracts type, scope, description
- **Range support** - `--since v1.0.0`, `--since HEAD~10`
- **Commit links** - Each entry links to full commit (format: `../../commit/hash`)
- **Scope extraction** - Shows scope when present: `**api**: add endpoint`
- **No merges** - Automatically excludes merge commits
- **Pure bash** - No external dependencies, regex-based parsing

**Limitations:**
- Only shows conventional commits properly categorized
- Non-conventional commits go to "Other Changes"
- Relies on proper commit message format
- No AI involvement (fast, deterministic)

**Future Enhancements** (from IMPROVEMENTS.md):
- Support different changelog formats (currently fixed to Keep a Changelog style)
- Version range comparisons (e.g., v1.0.0...v2.0.0)
- Output to file option
- Template customization

## Git Hook Integration (Opt-In)

The tool supports installing a `prepare-commit-msg` hook for seamless git workflow integration.

**Usage:**
```bash
gh commit-ai install-hook
gh commit-ai uninstall-hook
```

**Architecture:**

1. **Install Command** (lines 363-441):
   - Creates `.git/hooks/prepare-commit-msg` file
   - Checks for existing hooks to avoid conflicts
   - Provides instructions for opt-in usage
   - Suggests git alias setup

2. **Uninstall Command** (lines 443-476):
   - Verifies hook is from gh-commit-ai before removing
   - Removes hook file
   - Notifies about remaining git alias

3. **Hook Script** (embedded in install command):
   ```bash
   #!/bin/bash
   # gh-commit-ai hook
   # This hook is OPT-IN: only runs when GH_COMMIT_AI=1

   COMMIT_MSG_FILE="$1"
   COMMIT_SOURCE="$2"

   # Only run if explicitly enabled
   if [ "$GH_COMMIT_AI" != "1" ]; then
       exit 0
   fi

   # Skip merge/squash/amend commits
   if [ "$COMMIT_SOURCE" = "merge" ] || ...; then
       exit 0
   fi

   # Generate message using --preview
   GENERATED_MSG=$(gh commit-ai --preview 2>&1 | grep -A 1000 "Generated commit message:" | tail -n +2)

   # Write to commit message file
   echo "$GENERATED_MSG" > "$COMMIT_MSG_FILE"
   ```

**Opt-In Mechanism:**

The hook checks for `GH_COMMIT_AI=1` environment variable:
- **Not set**: Hook exits immediately (exit 0), normal git behavior
- **Set to 1**: Hook runs AI generation

**Usage Patterns:**

1. **One-time opt-in:**
   ```bash
   GH_COMMIT_AI=1 git commit
   ```

2. **Git alias (recommended):**
   ```bash
   git config alias.ai-commit '!GH_COMMIT_AI=1 git commit'
   git ai-commit
   ```

3. **Session-wide:**
   ```bash
   export GH_COMMIT_AI=1
   git commit  # Uses AI
   git commit  # Uses AI
   unset GH_COMMIT_AI
   ```

**Safety Features:**

1. **Conflict Detection:**
   - Checks for existing `prepare-commit-msg` hook
   - Only installs if no hook exists OR existing hook is from gh-commit-ai
   - Prevents overwriting user's custom hooks

2. **Commit Type Filtering:**
   - Skips merge commits (`COMMIT_SOURCE=merge`)
   - Skips squash commits (`COMMIT_SOURCE=squash`)
   - Skips amend commits (`COMMIT_SOURCE=commit`)
   - Only runs for new commits

3. **Error Handling:**
   - Falls back to empty message if generation fails
   - User still gets editor to write message manually
   - Logs status to stderr (not in commit message)

4. **Clean Uninstall:**
   - Verifies hook ownership before deletion
   - Warns about remaining git alias
   - Won't remove non-gh-commit-ai hooks

**Integration with --preview:**

Hook leverages existing `--preview` flag:
- Generates message without committing
- Displays to stdout (for parsing)
- No interactive prompts
- Fast, no user input required

**Benefits of Opt-In Approach:**

- **Non-intrusive**: Zero impact on normal `git commit`
- **User control**: Explicit decision each time (or via alias)
- **No surprises**: Clear when AI is running
- **No latency**: Regular commits unchanged
- **Team-friendly**: Each developer chooses independently

**Limitations:**

- Doesn't show token usage/cost (hook needs to be fast)
- No interactive editing (i/e options not available)
- No `--options` flag support (single generation only)
- Editor opens after generation (can't preview first)

**Future Enhancements:**
- Config option for default AI providers in hooks
- Support for custom hook templates
- Ability to chain with existing hooks
- Cache recent messages for reuse

## Performance Optimizations

The script is optimized for speed:
- **Limited diff context**: Only sends first 200 lines of diff to AI (configurable via `DIFF_MAX_LINES`)
- **Concise prompt**: Minimal prompt text (compared to verbose examples in previous versions)
- **Stat overview**: Uses `git diff --stat` to give file-level overview without full content
- **Result**: Significantly faster processing, especially for large commits with many changes

For very large commits, the AI still gets enough context from:
- File list from `git status --short`
- Summary stats from `git diff --stat`
- First 200 lines of actual diff showing the nature of changes

## Dependency Philosophy

This project intentionally avoids external dependencies beyond what's typically available on Unix-like systems:
- **No `jq`**: JSON handling uses pure bash with grep/sed
- Standard tools only: bash, curl, git, grep, sed, awk

When modifying the script, maintain this zero-dependency approach for maximum portability.

## Adding New AI Providers

The script uses a pluggable architecture for AI providers. To add a new provider:

1. **Add configuration variables** at the top (lines 12-18)
2. **Create a provider function** following this pattern:
   ```bash
   call_newprovider() {
       local prompt="$1"
       # Validate API key if needed
       # Build JSON payload with escape_json()
       # Call API with curl
       # Parse response with grep/sed
       # Return cleaned message
   }
   ```
3. **Add case statement entry** (lines 134-150) for the new provider
4. **Update documentation** in README.md and CLAUDE.md

Each provider function should:
- Accept the prompt as first argument
- Validate required credentials
- Use `escape_json()` for JSON string escaping
- Use pure bash/grep/sed for JSON parsing (no jq)
- Return the commit message as output

## Intelligent Diff Sampling

### Overview

For large commits, sending the entire diff to the AI can exceed token limits and increase costs. The `smart_sample_diff()` function intelligently samples large diffs to stay within limits while preserving the most important information.

### Algorithm

The sampling uses a priority-based system:

**Priority 1: Structural Elements (MUST KEEP)**
- File headers: `diff --git a/file b/file`
- Index lines: `index abc123..def456`
- File markers: `--- a/file`, `+++ b/file`
- Chunk headers: `@@ -10,5 +10,8 @@`

These are essential for diff structure and must always be included.

**Priority 2: Function/Class Definitions (HIGH)**
- Lines matching: `function`, `def `, `class `, `const `, `export `, `public `, `private `, `func `
- Captured with: `grep -E '^\+.*(function |def |class |const |export |public |private |func )'`
- Helps AI understand new functionality being added

**Priority 3: Added Lines (MEDIUM-HIGH)**
- All lines starting with `+` (except `+++` file markers)
- Sampled evenly throughout the diff using modulo sampling
- Target: ~40% of max_lines limit
- Calculation: `sample_rate = total_added_lines / target_added + 1`

**Priority 4: Context Lines (MEDIUM)**
- Lines starting with a space (unchanged context)
- Provides readability and structure
- Limited to ~20% of max_lines
- Only first N context lines are kept

**Priority 5: Deleted Lines (LOW)**
- Lines starting with `-` (except `---` file markers)
- Only included if there's remaining space after priorities 1-4
- Limited to remaining_space / 2
- Deleted code is least important for understanding new changes

### Implementation Details

```bash
smart_sample_diff() {
    local full_diff="$1"
    local max_lines="$2"
    
    # 1. Check if under limit (return full diff if so)
    total_lines=$(echo "$full_diff" | wc -l)
    if [ "$total_lines" -le "$max_lines" ]; then
        echo "$full_diff"
        return
    fi
    
    # 2. Extract to temp file for processing
    # 3. Build priority_file with high-priority lines
    # 4. Sample added lines evenly (modulo sampling)
    # 5. Add context lines for readability
    # 6. Fill remaining space with deleted lines
    # 7. Sort by line number, remove duplicates, limit to max_lines
    # 8. Output sampled diff
}
```

### Benefits

1. **Function-aware**: Preserves function signatures even in large diffs
2. **Even sampling**: Samples from entire diff, not just beginning
3. **Prioritizes additions**: New code is more important than deleted code
4. **Maintains structure**: Keeps file headers and chunk markers for valid diffs
5. **Flexible**: Adapts to available line budget

### Usage

The function is automatically used in three places:

1. **Amend mode**: `smart_sample_diff "$(git show HEAD)" "$DIFF_MAX_LINES"`
2. **Staged changes**: `smart_sample_diff "$(git diff --cached)" "$DIFF_MAX_LINES"`
3. **Unstaged changes**: `smart_sample_diff "$(git diff)" "$DIFF_MAX_LINES"`

### Performance

- **Time complexity**: O(n) where n = diff size
- **Space complexity**: O(n) for temp files
- **Overhead**: Minimal (<100ms for most diffs)
- **Benefit**: Significant for large commits (1000+ line diffs)

### Configuration

Users can adjust the sampling via `DIFF_MAX_LINES`:

```bash
# Aggressive sampling (faster, cheaper)
DIFF_MAX_LINES=50 gh commit-ai

# Standard (default)
DIFF_MAX_LINES=200 gh commit-ai

# Generous (more context)
DIFF_MAX_LINES=500 gh commit-ai
```

