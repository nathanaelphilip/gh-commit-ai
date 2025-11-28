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
7. **Provider Routing**: Case statement that routes to the appropriate provider based on `AI_PROVIDER`
8. **JSON Parsing**: Each provider function extracts responses using grep/sed to avoid `jq` dependency
9. **Message Post-Processing**: Applies lowercase enforcement to ensure consistent formatting
10. **Dry-Run and Preview Modes** (lines ~577-587):
    - `--preview`: Shows message and exits immediately
    - `--dry-run`: Shows message and optionally saves to `.git/COMMIT_MSG_<timestamp>` file
11. **Interactive Editing** (lines ~325-471): Fine-grained message editing without opening a text editor
    - `parse_commit_message()`: Parses message into SUMMARY_LINE and BULLETS arrays
    - `rebuild_commit_message()`: Rebuilds message from components
    - `interactive_edit_message()`: Provides menu-driven editing interface
    - Features: Edit summary, add/remove/reorder bullets
12. **Cost Tracking** (lines ~483-600): Token usage and cost calculation for paid APIs
    - `calculate_cost()`: Calculates costs based on provider and model pricing
    - Supports Anthropic (Claude models) and OpenAI (GPT models) pricing
    - Uses bc or awk for floating-point calculations
    - `track_cumulative_cost()`: Tracks daily cumulative costs in /tmp
    - Extracts token usage from API responses (INPUT_TOKENS, OUTPUT_TOKENS)
13. **Interactive Workflow** (lines ~737-787): User confirmation with loop support for interactive editing
    - `y`: Accept and commit
    - `n`: Cancel
    - `e`: Edit in default editor
    - `i`: Interactive editing mode

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
- Supported keys: `ai_provider`, `ollama_model`, `ollama_host`, `anthropic_model`, `openai_model`, `use_scope`, `diff_max_lines`

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
- `AI_PROVIDER`: Choose provider (default: `ollama`) - Options: `ollama`, `anthropic`, `openai`

**Ollama (default, local, free):**
- `OLLAMA_MODEL`: Model to use (default: `gemma3:12b`)
- `OLLAMA_HOST`: API endpoint (default: `http://localhost:11434`)

**Anthropic (API key required):**
- `ANTHROPIC_API_KEY`: Your Anthropic API key
- `ANTHROPIC_MODEL`: Model to use (default: `claude-3-5-sonnet-20241022`)

**OpenAI (API key required):**
- `OPENAI_API_KEY`: Your OpenAI API key
- `OPENAI_MODEL`: Model to use (default: `gpt-4o-mini`)

**Commit Format:**
- `USE_SCOPE`: Enable/disable conventional commit scopes (default: `false`)
  - When disabled (default), generates: `feat: add login`
  - When enabled, generates: `feat(auth): add login`

**Performance:**
- `DIFF_MAX_LINES`: Maximum diff lines to send to AI (default: `200`) - Reduces token usage and speeds up generation

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
