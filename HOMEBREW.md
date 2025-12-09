# Homebrew Installation

This repository contains a Homebrew formula for easy installation of gh-commit-ai.

## Installation

### Option 1: Using Homebrew Tap (Recommended)

```bash
# Add the tap
brew tap nathanaelphilip/gh-commit-ai

# Install gh-commit-ai
brew install gh-commit-ai
```

### Option 2: Direct Formula URL

```bash
brew install nathanaelphilip/gh-commit-ai/gh-commit-ai
```

## What Gets Installed

- **Main script**: `/usr/local/bin/gh-commit-ai` (Intel) or `/opt/homebrew/bin/gh-commit-ai` (Apple Silicon)
- **Bash completion**: `/usr/local/etc/bash_completion.d/gh-commit-ai`
- **Zsh completion**: `/usr/local/share/zsh/site-functions/_gh-commit-ai`
- **Example config**: `/usr/local/share/gh-commit-ai/.gh-commit-ai.example.yml`

## Usage

After installation, you can use gh-commit-ai in two ways:

### 1. As a standalone command:
```bash
cd your-git-repo
gh-commit-ai
```

### 2. As a gh extension (requires separate installation):
```bash
gh extension install nathanaelphilip/gh-commit-ai
gh commit-ai
```

## Setup

### 1. Copy Example Configuration (Optional)

```bash
cp /usr/local/share/gh-commit-ai/.gh-commit-ai.example.yml ~/.gh-commit-ai.yml
```

Edit `~/.gh-commit-ai.yml` to customize your settings.

### 2. Choose AI Provider

**Ollama (Free, Local)**
```bash
# Install Ollama from https://ollama.ai
ollama pull qwen2.5-coder:7b
gh-commit-ai  # Will auto-detect Ollama
```

**Groq (Ultra-fast, Free Tier)**
```bash
export GROQ_API_KEY="gsk-..."
gh-commit-ai
```

**Anthropic Claude**
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
AI_PROVIDER=anthropic gh-commit-ai
```

**OpenAI GPT**
```bash
export OPENAI_API_KEY="sk-proj-..."
AI_PROVIDER=openai gh-commit-ai
```

### 3. Enable Shell Completion (Optional)

```bash
gh-commit-ai install-completion
```

## Updating

```bash
brew update
brew upgrade gh-commit-ai
```

## Uninstalling

```bash
brew uninstall gh-commit-ai
brew untap nathanaelphilip/gh-commit-ai  # Optional: remove the tap
```

## Troubleshooting

### "gh: command not found"

Install GitHub CLI first:
```bash
brew install gh
```

### Permission Issues

If you get permission errors, ensure Homebrew directories are writable:
```bash
sudo chown -R $(whoami) /usr/local/bin /usr/local/share
```

### Completion Not Working

1. Ensure bash-completion or zsh completion is enabled:
   ```bash
   # For bash
   brew install bash-completion@2

   # For zsh (built-in on macOS)
   autoload -Uz compinit && compinit
   ```

2. Restart your shell:
   ```bash
   exec $SHELL
   ```

## Development

To test the formula locally before releasing:

```bash
# Install from local formula
brew install --build-from-source ./Formula/gh-commit-ai.rb

# Or use brew tap for local testing
brew tap-new nathanaelphilip/local-test
brew extract --version=1.0.0 gh-commit-ai nathanaelphilip/local-test
```

## Creating a Release

1. Update VERSION in `gh-commit-ai` script
2. Create and push a git tag:
   ```bash
   git tag -a v1.0.0 -m "Release v1.0.0"
   git push origin v1.0.0
   ```
3. Update the formula's `url` and `sha256`:
   ```bash
   # Download the release tarball
   curl -L https://github.com/nathanaelphilip/gh-commit-ai/archive/refs/tags/v1.0.0.tar.gz -o release.tar.gz

   # Calculate SHA256
   shasum -a 256 release.tar.gz

   # Update Formula/gh-commit-ai.rb with the hash
   ```

## Support

- GitHub Issues: https://github.com/nathanaelphilip/gh-commit-ai/issues
- Documentation: https://github.com/nathanaelphilip/gh-commit-ai

## License

MIT License - See LICENSE file for details
