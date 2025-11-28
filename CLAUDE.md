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

1. **Command-Line Argument Parsing** (lines ~22-64): Handles optional flags
   - `--dry-run`: Generate message without committing (with optional file save)
   - `--preview`: Generate and display message, then exit
   - `--help, -h`: Show usage information
2. **Git Integration** (lines ~66-116): Validates git repository, checks for changes, gathers status and diff
   - **Performance optimization**: Limits diff to configurable number of lines (default 200) via `DIFF_MAX_LINES`
   - Also captures `git diff --stat` for file-level overview without full content
   - **Branch Intelligence** (lines ~95-116):
     - Extracts current branch name
     - Detects ticket numbers using pattern `[A-Z][A-Z0-9]+-[0-9]+` (e.g., ABC-123, JIRA-456)
     - Suggests commit type based on branch prefix (feat/*, fix/*, docs/*, etc.)
     - Passes branch context to AI for better commit messages
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
10. **Dry-Run and Preview Modes** (lines ~341-358):
    - `--preview`: Shows message and exits immediately
    - `--dry-run`: Shows message and optionally saves to `.git/COMMIT_MSG_<timestamp>` file
11. **Interactive Workflow**: User confirmation with options to accept, reject, or edit

## Configuration

Environment variables (defined at lines 12-18):

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

# Normal mode (default)
gh commit-ai
```

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

## Branch Intelligence

The script automatically extracts context from branch names to improve commit message accuracy:

**Ticket Number Detection:**
- Pattern: `[A-Z][A-Z0-9]+-[0-9]+` (e.g., ABC-123, JIRA-456, PROJ-789)
- Example: Branch `feature/ABC-123-user-login` → Extracts "ABC-123"
- The ticket number is passed to the AI and included in the commit message

**Type Suggestion:**
Branch prefixes automatically suggest commit types:
- `feat/*` or `feature/*` → suggests "feat"
- `fix/*`, `bugfix/*`, or `hotfix/*` → suggests "fix"
- `docs/*` or `doc/*` → suggests "docs"
- `style/*` → suggests "style"
- `refactor/*` → suggests "refactor"
- `test/*` or `tests/*` → suggests "test"
- `chore/*` → suggests "chore"

**How It Works:**
1. Script extracts branch name using `git rev-parse --abbrev-ref HEAD`
2. Searches for ticket number pattern in branch name
3. Matches branch prefix against known patterns
4. Passes this context to AI in the prompt
5. AI uses this information to generate more accurate commit messages

**Example:**
```bash
# Branch: feature/PROJ-456-add-authentication
# AI receives:
# - Branch name: feature/PROJ-456-add-authentication
# - Ticket number: PROJ-456 (include this in commit)
# - Suggested type: feat

# Generated commit (default, without scope):
feat: add user authentication for PROJ-456

# Generated commit (with USE_SCOPE=true):
feat(auth): add user authentication for PROJ-456
```

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
