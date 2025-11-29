# gh-commit-ai

A GitHub CLI extension that uses AI to generate git commit messages. Supports Ollama (local), Anthropic Claude, and OpenAI GPT models.

## Prerequisites

- [GitHub CLI](https://cli.github.com/) installed
- One of the following AI providers:
  - [Ollama](https://ollama.ai/) (default, free, runs locally)
  - [Anthropic API](https://www.anthropic.com/) (requires API key)
  - [OpenAI API](https://openai.com/) (requires API key)

## Installation

### Option 1: Install from GitHub (recommended)

```bash
gh extension install nathanaelphilip/gh-commit-ai
```

### Option 2: Install from local directory

If you've cloned the repository:

```bash
cd gh-commit-ai
gh extension install .
```

### Option 3: Install manually

1. Copy the `gh-commit-ai` script to your PATH:
   ```bash
   cp gh-commit-ai /usr/local/bin/
   ```

2. Make it executable:
   ```bash
   chmod +x /usr/local/bin/gh-commit-ai
   ```

### Upgrading

To upgrade to the latest version:

```bash
gh extension upgrade commit-ai
```

### Uninstalling

To remove the extension:

```bash
gh extension remove commit-ai
```

## Usage

Navigate to any git repository and run:

```bash
gh commit-ai [options]
```

**Options:**
- `--dry-run` - Generate commit message without committing (optionally save to file)
- `--preview` - Generate and display message, then exit (no interaction)
- `--amend` - Regenerate message for the last commit and amend it
- `--options` - Generate multiple message variations to choose from
- `--type <type>` - Force a specific commit type (feat, fix, docs, etc.)
- `--max-lines <n>` - Override DIFF_MAX_LINES for this run
- `--no-lowercase` - Disable automatic lowercase enforcement
- `--verbose, -v` - Show detailed API request/response for debugging
- `--version` - Show version number
- `--help, -h` - Show help message

The extension will:
1. Analyze your staged (or unstaged) changes
2. Generate a commit message using your chosen AI provider:
   - AI first identifies all significant changes
   - Then synthesizes them into one concise summary line
   - **Line 1**: Conventional commit prefix + summary (max 50 chars) that captures all changes
   - **Line 2**: Blank line
   - **Lines 3+**: Bulleted list of all significant changes
3. Enforce lowercase formatting (preserving acronyms and ticket numbers)
4. Ask for your confirmation
5. Commit the changes with the generated message

**Commit Message Format:**

Without scope (default):
```
<type>: <concise summary>

- <change 1>
- <change 2>
- <change 3>
```

With scope (`USE_SCOPE=true`):
```
<type>(<scope>): <concise summary>

- <change 1>
- <change 2>
- <change 3>
```

**Intelligent Type Detection:** The extension automatically suggests the commit type using:

1. **Branch Intelligence** - Extracts context from your branch name:
   - **Ticket numbers**: `feature/ABC-123-login` → Includes "ABC-123" in commit message
   - **Type hints**: `fix/login-bug` → Suggests "fix" type automatically
   - **Supported patterns**: `feat/*`, `feature/*`, `fix/*`, `bugfix/*`, `hotfix/*`, `docs/*`, `style/*`, `refactor/*`, `test/*`, `chore/*`

2. **Smart Type Detection** - Analyzes your changes to suggest the appropriate type:
   - **Documentation only**: Only `.md`, `.txt`, `README`, or `docs/` files → Suggests "docs"
   - **Tests only**: Only test files (`.test.js`, `.spec.py`, `tests/`, etc.) → Suggests "test"
   - **Version bumps**: Changes to `version` in `package.json`, `setup.py`, etc. → Suggests "chore"
   - **Bug fixes**: Diff contains keywords like "fix", "bug", "error", "crash" → Suggests "fix"

3. **Breaking Change Detection** - Automatically detects breaking changes and adds appropriate markers:
   - **Explicit keywords**: "BREAKING CHANGE", "breaking change", "BREAKING:" in diff
   - **API removal**: Removed `export`, `public`, or function definitions
   - **Major version bumps**: Version changes like 1.x.x → 2.0.0
   - **Signature changes**: Function parameters reduced or changed
   - **Format**: Adds `!` after type and includes `BREAKING CHANGE:` footer

4. **Commit History Learning** - Learns from your repository's commit history to match its style:
   - **Scope usage**: Detects if the repo uses scopes and how frequently
   - **Type preferences**: Identifies most commonly used types
   - **Capitalization**: Matches uppercase vs lowercase preferences
   - **Emoji usage**: Detects and matches emoji patterns
   - **Breaking changes**: Notes if the repo uses `!` notation
   - Analyzes last 50 commits (minimum 5 commits required)
   - Can be disabled with `LEARN_FROM_HISTORY=false`

The AI uses these suggestions but can override them if the actual changes indicate a different type.

**Note:** All commit messages are automatically converted to lowercase, with exceptions for:
- Technical acronyms (API, HTTP, JSON, JWT, etc.)
- Ticket numbers (e.g., ABC-123, JIRA-456)

### Configuration

You can configure the extension using configuration files or environment variables.

#### Configuration Files

The extension supports YAML configuration files for persistent settings:

**Configuration priority (highest to lowest):**
1. **Environment variables** - Override everything (e.g., `AI_PROVIDER=anthropic gh commit-ai`)
2. **Local config** - `.gh-commit-ai.yml` in repository root
3. **Global config** - `~/.gh-commit-ai.yml` in your home directory
4. **Built-in defaults** - Fallback values

**Creating a configuration file:**

```bash
# Copy the example file to your repo root
cp .gh-commit-ai.example.yml .gh-commit-ai.yml

# Or create a global config
cp .gh-commit-ai.example.yml ~/.gh-commit-ai.yml
```

**Example configuration file:**

```yaml
# AI Provider Selection
ai_provider: ollama  # Options: ollama, anthropic, openai

# Ollama Configuration
ollama_model: gemma3:12b
ollama_host: http://localhost:11434

# Anthropic Configuration
anthropic_model: claude-3-5-sonnet-20241022

# OpenAI Configuration
openai_model: gpt-4o-mini

# Commit Format
use_scope: false  # Enable conventional commit scopes

# Performance
diff_max_lines: 200  # Max diff lines to send to AI
```

**Important:**
- API keys (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`) cannot be stored in config files for security
- Set API keys as environment variables instead: `export ANTHROPIC_API_KEY="sk-ant-..."`
- Environment variables always take precedence over config file values

#### Environment Variables

You can also configure using environment variables (these override config files):

#### AI Provider Selection

- `AI_PROVIDER`: Choose your AI provider (default: `ollama`)
  - `ollama` - Use local Ollama instance
  - `anthropic` - Use Anthropic Claude API
  - `openai` - Use OpenAI GPT API

#### Ollama Configuration (default)

- `OLLAMA_MODEL`: The Ollama model to use (default: `gemma3:12b`)
- `OLLAMA_HOST`: The Ollama API host (default: `http://localhost:11434`)

```bash
gh commit-ai
# or with custom model
OLLAMA_MODEL="codellama" gh commit-ai
```

#### Anthropic Configuration

- `ANTHROPIC_API_KEY`: Your Anthropic API key (required)
- `ANTHROPIC_MODEL`: The Claude model to use (default: `claude-3-5-sonnet-20241022`)

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export AI_PROVIDER="anthropic"
gh commit-ai
```

#### OpenAI Configuration

- `OPENAI_API_KEY`: Your OpenAI API key (required)
- `OPENAI_MODEL`: The GPT model to use (default: `gpt-4o-mini`)

```bash
export OPENAI_API_KEY="sk-proj-..."
export AI_PROVIDER="openai"
gh commit-ai
```

#### Commit Format Configuration

- `USE_SCOPE`: Enable/disable conventional commit scopes (default: `false`)
  - When disabled (default): `feat: add login`
  - When enabled: `feat(auth): add login`

```bash
# Enable scopes (more specific)
USE_SCOPE=true gh commit-ai

# Disable scopes (default, simpler format)
USE_SCOPE=false gh commit-ai
```

Common scopes: `auth`, `api`, `ui`, `db`, `cli`, `docs`, `config`, `tests`, `deps`

#### Performance Configuration

- `DIFF_MAX_LINES`: Maximum diff lines to send to AI (default: `200`)
  - Uses **intelligent sampling** to prioritize important changes
  - Lower values = faster processing, especially for large commits
  - Increase if you need more context for very complex changes
  - **Smart sampling** keeps function definitions and added lines even when truncating

```bash
# For faster processing (fewer lines, but still intelligent sampling)
DIFF_MAX_LINES=100 gh commit-ai

# For more context (more lines)
DIFF_MAX_LINES=500 gh commit-ai
```

#### Quick Examples

```bash
# Use Ollama (default)
gh commit-ai

# Use Anthropic with custom model
AI_PROVIDER="anthropic" ANTHROPIC_API_KEY="sk-ant-..." gh commit-ai

# Use OpenAI with GPT-4
AI_PROVIDER="openai" OPENAI_MODEL="gpt-4o" OPENAI_API_KEY="sk-proj-..." gh commit-ai
```

### Interactive Options

When presented with a generated commit message, you can:
- Press `y` to accept and commit
- Press `n` to cancel
- Press `e` to edit the message in your default editor before committing

## How It Works

1. Checks if you're in a git repository
2. Gathers git status and diff information
3. **Intelligently samples large diffs** to stay within token limits:
   - Prioritizes function/class definitions and signatures
   - Keeps added lines over deleted lines
   - Samples evenly throughout the diff (not just the beginning)
   - Maintains diff structure while reducing size
4. Sends the changes to your chosen AI provider with a prompt to generate a conventional commit message
5. Enforces lowercase formatting (while preserving acronyms and ticket numbers)
6. Displays the generated message for your approval
7. **Shows token usage and cost** (for Anthropic and OpenAI APIs)
8. Commits with the approved message

### Advanced Options

**Force Commit Type**

Override the automatic type detection:

```bash
$ gh commit-ai --type fix
# Forces "fix:" regardless of what AI or branch intelligence suggests

$ gh commit-ai --type docs
# Forces "docs:" for documentation changes
```

**Adjust Diff Size**

Override the maximum diff lines sent to AI (default: 200):

```bash
$ gh commit-ai --max-lines 500
# Sends more context for complex commits

$ gh commit-ai --max-lines 100
# Faster generation for simple commits
```

**Verbose Mode**

See detailed API requests and responses for debugging:

```bash
$ gh commit-ai --verbose
# or
$ gh commit-ai -v

# Shows:
# - API endpoint being called
# - Full request payload
# - Complete API response
# - Useful for debugging or understanding AI behavior
```

**Version Check**

```bash
$ gh commit-ai --version
gh-commit-ai version 1.0.0
```

**Disable Lowercase Enforcement**

By default, commit messages are automatically converted to lowercase (except for acronyms and ticket numbers). You can disable this:

```bash
$ gh commit-ai --no-lowercase
# Preserves original capitalization from AI
# Example output: "Add User Authentication System" instead of "add user authentication system"
```

**Message History**

All generated messages are automatically saved to `/tmp/gh-commit-ai-history/` with timestamps. The last 5 messages are kept for recovery:

```bash
$ ls -t /tmp/gh-commit-ai-history/
msg_1701234567.txt  # Most recent
msg_1701234556.txt
msg_1701234545.txt
msg_1701234534.txt
msg_1701234523.txt  # Oldest (5th message)

# View a previous message
$ cat /tmp/gh-commit-ai-history/msg_1701234567.txt
feat: add user authentication

- implement JWT token generation
- create login endpoint
```

This is useful if you:
- Accidentally rejected a good message
- Want to compare different generations
- Need to recover a message after a crash

### Cost Tracking

When using paid AI providers (Anthropic or OpenAI), the extension automatically displays:

- **Token usage**: Input and output tokens used for the request
- **Estimated cost**: Cost for the current generation
- **Daily total**: Cumulative cost for all generations today

**Example output:**
```bash
Generated commit message:
feat: add user authentication

- implement JWT token generation
- create login endpoint

Token usage: 245 tokens (198 input + 47 output)
Estimated cost: $0.0016 USD
Today's total: $0.0048 USD
```

**Supported models with pricing:**

**Anthropic:**
- Claude 3.5 Sonnet: $3/$15 per MTok (input/output)
- Claude 3 Opus: $15/$75 per MTok
- Claude 3 Haiku: $0.25/$1.25 per MTok

**OpenAI:**
- GPT-4o: $2.50/$10 per MTok (input/output)
- GPT-4o-mini: $0.15/$0.60 per MTok
- GPT-4 Turbo: $10/$30 per MTok
- GPT-4: $30/$60 per MTok

**Note:** Ollama (local) is free and does not display cost information.

## Examples

### Basic Example

```bash
$ gh commit-ai
Analyzing changes...
Generating commit message with gemma3:12b...

Generated commit message:
feat: add user authentication

- implement JWT token generation
- create login and logout endpoints
- add password hashing with bcrypt
- create user session management
- add authentication middleware

Use this commit message? (y/n/e to edit): y
Staging all changes...
✓ Committed successfully!
```

### Example with Branch Intelligence

```bash
# Branch: feature/ABC-123-user-login
$ gh commit-ai
Analyzing changes...
Generating commit message with gemma3:12b...

Generated commit message:
feat: add user login for ABC-123

- implement login form validation
- add session token management
- create user authentication API

Use this commit message? (y/n/e to edit): y
Staging all changes...
✓ Committed successfully!
```

The extension automatically detected:
- Ticket number "ABC-123" from branch name and included it in the commit
- Type "feat" suggested from "feature/" branch prefix

### Example with Smart Type Detection

```bash
# Scenario: Only documentation files changed
$ git status
modified:   README.md
modified:   docs/installation.md
new file:   CHANGELOG.md

$ gh commit-ai
Analyzing changes...
Generating commit message with gemma3:12b...

Generated commit message:
docs: update installation guide and add changelog

- update README installation steps
- add detailed setup instructions
- create initial CHANGELOG for version history

Use this commit message? (y/n/e to edit): y
```

The extension detected that only documentation files changed and automatically suggested "docs" type.

```bash
# Scenario: Bug fix with keywords in diff
$ git diff
+++ b/auth.js
- if (user.password = hashedPassword) {
+ if (user.password === hashedPassword) {  // fix comparison bug

$ gh commit-ai
Analyzing changes...
Generating commit message with gemma3:12b...

Generated commit message:
fix: correct password comparison in authentication

- fix comparison operator bug in user validation
- change assignment to equality check

Use this commit message? (y/n/e to edit): y
```

The extension detected bug-related keywords ("fix", "bug") in the diff and suggested "fix" type.

```bash
# Scenario: Breaking change - removing public API
$ git diff
--- a/api.js
+++ b/api.js
-export function oldLogin(username, password) {
+export function login(email, password, options) {

$ gh commit-ai
Analyzing changes...
Generating commit message with gemma3:12b...

Generated commit message:
feat!: redesign authentication API

- replace oldLogin with new login function
- change username to email parameter
- add options parameter for future extensibility

BREAKING CHANGE: oldLogin() function removed, use login() with email instead

Use this commit message? (y/n/e to edit): y
```

The extension detected the removal of a public API (`export function`) and automatically:
- Added `!` suffix to indicate breaking change
- Included `BREAKING CHANGE:` footer with explanation

### Dry-Run Mode

Generate a message without committing:

```bash
$ gh commit-ai --dry-run
Analyzing changes...
Generating commit message with gemma3:12b...

Generated commit message:
feat: add user authentication

- implement JWT token generation
- create login and logout endpoints

Save to file? (y/n): y
✓ Saved to .git/COMMIT_MSG_1234567890
```

### Preview Mode

Generate and display message only (no interaction):

```bash
$ gh commit-ai --preview
Analyzing changes...
Generating commit message with gemma3:12b...

Generated commit message:
feat: add user authentication

- implement JWT token generation
- create login and logout endpoints
```

### Amend Mode

Regenerate the commit message for your last commit:

```bash
$ gh commit-ai --amend
Analyzing last commit...
Generating commit message with gemma3:12b...

Generated commit message:
feat: add user authentication

- implement JWT token generation
- create login and logout endpoints
- add password hashing

Use this commit message? (y/n/e to edit): y
✓ Amended commit successfully!
```

**Note:** This will rewrite the last commit. Only use on commits that haven't been pushed, or be prepared to force push.

### Multiple Options Mode

Generate multiple commit message variations and choose your favorite:

```bash
$ gh commit-ai --options
Analyzing changes...
Generating commit message with gemma3:12b...

Generated 3 commit message options:

Option 1:
feat: add user authentication

- implement JWT token generation
- create login endpoint

Option 2:
feat: add comprehensive user authentication system

- implement JWT token generation and validation
- create login and logout endpoints
- add password hashing with bcrypt
- create user session management
- add authentication middleware

Option 3:
feat(auth): implement user authentication

- add JWT-based authentication
- create secure login flow
- implement session management

Select option (1-3), or 'n' to cancel: 2

Selected commit message:
feat: add comprehensive user authentication system

- implement JWT token generation and validation
- create login and logout endpoints
- add password hashing with bcrypt
- create user session management
- add authentication middleware

Use this commit message? (y/n/e to edit): y
```

**How it works:**
- Option 1: Concise version with minimal details
- Option 2: Detailed version with comprehensive bullet list
- Option 3: Alternative perspective or different scope

This is useful when you want to see different ways to describe your changes before committing.

### Changelog Generation

Generate a formatted changelog from your commit history:

```bash
$ gh commit-ai changelog
Generating changelog...

# Changelog

## Unreleased

### Date: 2025-11-28

### ✨ Features

- add user authentication system ([a1b2c3d](../../commit/a1b2c3d))
- **api**: implement rate limiting ([e4f5g6h](../../commit/e4f5g6h))
- add password reset functionality ([i7j8k9l](../../commit/i7j8k9l))

### 🐛 Bug Fixes

- **auth**: fix token expiration handling ([m0n1o2p](../../commit/m0n1o2p))
- resolve memory leak in session management ([q3r4s5t](../../commit/q3r4s5t))

### 📝 Documentation

- update API documentation ([u6v7w8x](../../commit/u6v7w8x))
- add authentication examples ([y9z0a1b](../../commit/y9z0a1b))
```

**Generate changelog since a specific version:**

```bash
$ gh commit-ai changelog --since v1.0.0
Generating changelog...

# Changelog

## [1.0.0...HEAD]

### Date: 2025-11-28

### ✨ Features

- add OAuth support ([c2d3e4f](../../commit/c2d3e4f))
- implement 2FA authentication ([g5h6i7j](../../commit/g5h6i7j))

### 🐛 Bug Fixes

- fix login redirect issue ([k8l9m0n](../../commit/k8l9m0n))
```

**Features:**
- **Parses conventional commits** - Automatically categorizes by type (feat, fix, docs, etc.)
- **Breaking change detection** - Highlights breaking changes at the top with ⚠️
- **Scoped entries** - Shows scope when present (e.g., `**auth**: add login`)
- **Commit links** - Each entry links to the full commit
- **Emoji categories** - Visual indicators for each section (✨ Features, 🐛 Bug Fixes, etc.)
- **Flexible ranges** - Generate since any tag, commit, or relative ref (HEAD~10)

**Supported categories:**
- ⚠️ **BREAKING CHANGES** - Breaking changes (shown first)
- ✨ **Features** - New features (feat)
- 🐛 **Bug Fixes** - Bug fixes (fix)
- 📝 **Documentation** - Documentation changes (docs)
- ⚡ **Performance** - Performance improvements (perf)
- ♻️ **Refactoring** - Code refactoring (refactor)
- ✅ **Tests** - Test additions/changes (test)
- 💄 **Style** - Style/formatting changes (style)
- 🔧 **Chores** - Maintenance tasks (chore, build, ci)
- **Other Changes** - Non-conventional commits

**Note:** Works best with repositories that follow [Conventional Commits](https://www.conventionalcommits.org/) format.

### Git Hook Integration (Opt-In)

Install a git hook to enable AI-generated commit messages directly with `git commit`:

#### Installation

```bash
$ gh commit-ai install-hook
✓ Pre-commit hook installed successfully!

Usage (OPT-IN):
  1. Regular commits work normally:
     git commit

  2. Use AI generation when you want it:
     GH_COMMIT_AI=1 git commit

  3. Or set up a convenient alias:
     git config alias.ai-commit '!GH_COMMIT_AI=1 git commit'
     git ai-commit    # Use AI generation

To uninstall: gh commit-ai uninstall-hook
```

#### Usage

**Option 1: Set environment variable each time**
```bash
$ GH_COMMIT_AI=1 git commit
Generating commit message with AI...
✓ AI-generated message added. Review and edit if needed.

# Your editor opens with the AI-generated message
# Edit if needed, save, and the commit is created
```

**Option 2: Use the git alias (recommended)**
```bash
# Set up alias once
$ git config alias.ai-commit '!GH_COMMIT_AI=1 git commit'

# Then use it whenever you want AI generation
$ git ai-commit
Generating commit message with AI...
✓ AI-generated message added. Review and edit if needed.

# Regular git commit still works normally
$ git commit
# Opens editor with empty message (no AI)
```

**Option 3: Export variable for the session**
```bash
# Enable AI for all commits in this terminal session
$ export GH_COMMIT_AI=1
$ git commit  # Uses AI
$ git commit  # Uses AI

# Disable again
$ unset GH_COMMIT_AI
$ git commit  # Normal commit
```

#### How It Works

1. **OPT-IN by default**: The hook only runs when `GH_COMMIT_AI=1` is set
2. **Regular commits unaffected**: Normal `git commit` works exactly as before
3. **Preview mode**: Hook uses `--preview` to generate the message
4. **Editor integration**: Message is pre-filled in your commit editor
5. **Full control**: You can edit, amend, or abort before committing

#### Safety Features

- **Skips merge commits**: Doesn't interfere with merge/squash commits
- **Skips amends**: Won't override when using `git commit --amend`
- **Error handling**: Falls back to empty message if generation fails
- **Easy removal**: `gh commit-ai uninstall-hook` removes cleanly

#### Uninstallation

```bash
$ gh commit-ai uninstall-hook
✓ Pre-commit hook uninstalled successfully

Note: Git alias 'ai-commit' still exists. To remove it:
  git config --unset alias.ai-commit
```

**Benefits of the hook approach:**
- Seamless integration with existing git workflow
- No need to remember to run `gh commit-ai`
- Still provides full editing control
- Opt-in when you want it, normal commits otherwise

**When to use the hook vs direct command:**
- **Hook**: Quick commits where you trust AI to get it right
- **Direct**: When you want to see options (`--options`), costs, or have more control

## Testing

This project includes unit and integration tests using [Bats](https://github.com/bats-core/bats-core).

### Install Bats:
```bash
# macOS
brew install bats-core

# Linux
sudo apt-get install bats
```

### Run tests:
```bash
# Run all tests
bats tests/

# Run specific test file
bats tests/test_core_functions.bats
```

See [tests/README.md](tests/README.md) for more details on the test suite.

## Troubleshooting

**"Error: Not a git repository"**
- Make sure you're running the command inside a git repository

**"No changes to commit"**
- Stage your changes with `git add` or modify some files first

**"Error: Failed to generate commit message"**

For Ollama:
- Ensure Ollama is running: `ollama serve`
- Check if the model is available: `ollama list`
- Verify the Ollama host is correct

For Anthropic:
- Verify your `ANTHROPIC_API_KEY` is set correctly
- Check your API key is valid and has credits
- Ensure you have access to the specified model

For OpenAI:
- Verify your `OPENAI_API_KEY` is set correctly
- Check your API key is valid and has credits
- Ensure you have access to the specified model

**"Error: ANTHROPIC_API_KEY is not set"** or **"Error: OPENAI_API_KEY is not set"**
- Set the required API key environment variable for your chosen provider

## License

MIT
