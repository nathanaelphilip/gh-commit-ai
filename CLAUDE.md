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
7. **Provider Routing**: Case statement that routes to the appropriate provider based on `AI_PROVIDER`
8. **JSON Parsing**: Each provider function extracts responses using grep/sed to avoid `jq` dependency
9. **Message Post-Processing**: Applies lowercase enforcement to ensure consistent formatting
10. **Newline Conversion** (~line 1479-1484): `convert_newlines()` function that converts literal `\n` sequences to actual newlines
   - AI responses contain literal `\n` characters (from JSON encoding)
   - Uses `printf "%b"` to interpret backslash escapes
   - Applied before committing to ensure proper multi-line display in GitHub
   - Also applied when displaying messages to users and saving to files
11. **Dry-Run and Preview Modes** (lines ~577-587):
    - `--preview`: Shows message and exits immediately
    - `--dry-run`: Shows message and optionally saves to `.git/COMMIT_MSG_<timestamp>` file
12. **Interactive Editing** (lines ~325-471): Fine-grained message editing without opening a text editor
    - `parse_commit_message()`: Parses message into SUMMARY_LINE and BULLETS arrays
    - `rebuild_commit_message()`: Rebuilds message from components
    - `interactive_edit_message()`: Provides menu-driven editing interface
    - Features: Edit summary, add/remove/reorder bullets
13. **Cost Tracking** (lines ~483-600): Token usage and cost calculation for paid APIs
    - `calculate_cost()`: Calculates costs based on provider and model pricing
    - Supports Anthropic (Claude models) and OpenAI (GPT models) pricing
    - Uses bc or awk for floating-point calculations
    - `track_cumulative_cost()`: Tracks daily cumulative costs in /tmp
    - Extracts token usage from API responses (INPUT_TOKENS, OUTPUT_TOKENS)
14. **Interactive Workflow** (lines ~737-787): User confirmation with loop support for interactive editing
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
- `AI_PROVIDER`: Choose provider (default: `auto`) - Options: `auto`, `ollama`, `anthropic`, `openai`
  - `auto`: Automatically detects available providers (prefers Ollama if running, then API providers)
  - Detects Ollama availability by checking if it's running and has models installed
  - Detects Anthropic/OpenAI by checking for API keys
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

