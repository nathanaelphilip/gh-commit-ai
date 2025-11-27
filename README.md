# gh-commit-ai

A GitHub CLI extension that uses Ollama to generate AI-powered git commit messages.

## Prerequisites

- [GitHub CLI](https://cli.github.com/) installed
- [Ollama](https://ollama.ai/) installed and running
- `jq` for JSON parsing: `brew install jq` (macOS) or `apt-get install jq` (Linux)

## Installation

### Option 1: Install from local directory

```bash
gh extension install .
```

### Option 2: Install manually

1. Copy the `gh-commit-ai` script to your PATH:
   ```bash
   cp gh-commit-ai /usr/local/bin/
   ```

2. Make it executable:
   ```bash
   chmod +x /usr/local/bin/gh-commit-ai
   ```

## Usage

Navigate to any git repository and run:

```bash
gh commit-ai
```

The extension will:
1. Analyze your staged (or unstaged) changes
2. Generate a commit message using Ollama
3. Ask for your confirmation
4. Commit the changes with the generated message

### Configuration

You can configure the extension using environment variables:

- `OLLAMA_MODEL`: The Ollama model to use (default: `gemma3:4b`)
- `OLLAMA_HOST`: The Ollama API host (default: `http://localhost:11434`)

Example:

```bash
export OLLAMA_MODEL="codellama"
gh commit-ai
```

Or use inline:

```bash
OLLAMA_MODEL="codellama" gh commit-ai
```

### Interactive Options

When presented with a generated commit message, you can:
- Press `y` to accept and commit
- Press `n` to cancel
- Press `e` to edit the message in your default editor before committing

## How It Works

1. Checks if you're in a git repository
2. Gathers git status and diff information
3. Sends the changes to Ollama with a prompt to generate a conventional commit message
4. Displays the generated message for your approval
5. Commits with the approved message

## Example

```bash
$ gh commit-ai
Analyzing changes...
Generating commit message with gemma3:4b...

Generated commit message:
feat: add user authentication with JWT tokens

Use this commit message? (y/n/e to edit): y
Staging all changes...
✓ Committed successfully!
```

## Troubleshooting

**"Error: Not a git repository"**
- Make sure you're running the command inside a git repository

**"No changes to commit"**
- Stage your changes with `git add` or modify some files first

**"Error: Failed to generate commit message"**
- Ensure Ollama is running: `ollama serve`
- Check if the model is available: `ollama list`
- Verify the Ollama host is correct

**"jq: command not found"**
- Install jq: `brew install jq` (macOS) or your system's package manager

## License

MIT
