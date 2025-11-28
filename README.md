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

**Branch Intelligence:** The extension automatically extracts context from your branch name:
- **Ticket numbers**: `feature/ABC-123-login` → Includes "ABC-123" in commit message
- **Type hints**: `fix/login-bug` → Suggests "fix" type automatically
- **Supported patterns**: `feat/*`, `feature/*`, `fix/*`, `bugfix/*`, `hotfix/*`, `docs/*`, `style/*`, `refactor/*`, `test/*`, `chore/*`

**Note:** All commit messages are automatically converted to lowercase, with exceptions for:
- Technical acronyms (API, HTTP, JSON, JWT, etc.)
- Ticket numbers (e.g., ABC-123, JIRA-456)

### Configuration

You can configure the extension using environment variables:

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
  - Lower values = faster processing, especially for large commits
  - Increase if you need more context for very complex changes

```bash
# For faster processing (fewer lines)
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
3. Sends the changes to your chosen AI provider with a prompt to generate a conventional commit message
4. Enforces lowercase formatting (while preserving acronyms and ticket numbers)
5. Displays the generated message for your approval
6. Commits with the approved message

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
