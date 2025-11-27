# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a GitHub CLI extension that generates AI-powered git commit messages using Ollama. The entire functionality is contained in a single bash script (`gh-commit-ai`) that can be installed as a `gh` extension.

## Architecture

### Single-Script Design
- **gh-commit-ai**: The main executable bash script that implements the entire extension
  - Uses pure bash without external dependencies (except curl, git, and standard Unix tools)
  - Integrates with Ollama's REST API to generate commit messages
  - Provides interactive prompts for user confirmation and editing

### Key Components in gh-commit-ai

1. **Git Integration** (lines 16-35): Validates git repository, checks for changes, gathers status and diff
2. **Prompt Engineering** (lines 37-56): Constructs the prompt for Ollama with specific commit message guidelines
3. **JSON Handling** (lines 54-62): Pure bash JSON creation using `escape_json()` function to avoid `jq` dependency
4. **API Communication** (lines 64-68): Calls Ollama's `/api/generate` endpoint with curl
5. **JSON Parsing** (line 71): Extracts response using grep/sed instead of `jq`
6. **Interactive Workflow** (lines 80-100): User confirmation with options to accept, reject, or edit

## Configuration

Environment variables (defined at lines 12-13):
- `OLLAMA_MODEL`: Model to use (default: `gemma3:4b`)
- `OLLAMA_HOST`: API endpoint (default: `http://localhost:11434`)

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

### Testing with Different Models
```bash
OLLAMA_MODEL="codellama" ./gh-commit-ai
OLLAMA_MODEL="llama2" gh commit-ai
```

## Commit Message Guidelines

The prompt instructs the AI to generate messages that:
- Follow conventional commit format (feat, fix, docs, style, refactor, test, chore)
- Use imperative mood
- Are concise (max 72 characters)
- Start with lowercase letter
- Focus on what changed, not how
- Extract ticket information from branch names

## Dependency Philosophy

This project intentionally avoids external dependencies beyond what's typically available on Unix-like systems:
- **No `jq`**: JSON handling uses pure bash with grep/sed
- Standard tools only: bash, curl, git, grep, sed, awk

When modifying the script, maintain this zero-dependency approach for maximum portability.
