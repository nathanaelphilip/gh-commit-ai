# Shell Completion for gh-commit-ai

This directory contains shell completion scripts for gh-commit-ai, providing tab completion for commands and flags.

## Supported Shells

- **Bash** - Full completion support
- **Zsh** - Full completion support with descriptions

## Features

### Command Completion
Tab-complete all available commands:
```bash
gh commit-ai <TAB>
# Shows: changelog, review, pr-description, version, semver, install-hook, etc.
```

### Flag Completion
Tab-complete flags for the main command and subcommands:
```bash
gh commit-ai --<TAB>
# Shows: --help, --preview, --dry-run, --amend, --options, --type, etc.
```

### Subcommand Flags
Each subcommand has its own flag completion:
```bash
gh commit-ai version --<TAB>
# Shows: --help, --create-tag, --prefix

gh commit-ai changelog --<TAB>
# Shows: --help, --since, --format
```

### Intelligent Value Completion

**Commit Types:**
```bash
gh commit-ai --type <TAB>
# Shows: feat, fix, docs, style, refactor, test, chore, perf, build, ci
```

**Git Tags/Refs:**
```bash
gh commit-ai changelog --since <TAB>
# Shows: v1.0.0, v0.9.0, HEAD~1, HEAD~5, HEAD~10, etc.
```

**Branches:**
```bash
gh commit-ai pr-description --base <TAB>
# Shows: main, master, develop, feature/xxx, etc.
```

**Tag Prefixes:**
```bash
gh commit-ai version --prefix <TAB>
# Shows: v, ver, version, release-
```

## Installation

### Automatic Installation (Recommended)

```bash
gh commit-ai install-completion
```

This command:
- Detects your shell (bash or zsh)
- Installs to the appropriate system or user directory
- Provides instructions for enabling completion

### Manual Installation

#### Bash

**System-wide (macOS with Homebrew):**
```bash
sudo cp completions/gh-commit-ai.bash /usr/local/etc/bash_completion.d/gh-commit-ai
```

**System-wide (Linux):**
```bash
sudo cp completions/gh-commit-ai.bash /etc/bash_completion.d/gh-commit-ai
```

**User-local:**
```bash
mkdir -p ~/.bash_completion.d
cp completions/gh-commit-ai.bash ~/.bash_completion.d/gh-commit-ai
echo 'source ~/.bash_completion.d/gh-commit-ai' >> ~/.bashrc
```

Then restart your shell or run: `source ~/.bashrc`

#### Zsh

**System-wide (macOS with Homebrew):**
```bash
sudo cp completions/_gh-commit-ai /usr/local/share/zsh/site-functions/_gh-commit-ai
```

**System-wide (Linux):**
```bash
sudo cp completions/_gh-commit-ai /usr/share/zsh/site-functions/_gh-commit-ai
```

**User-local:**
```bash
mkdir -p ~/.zsh/completion
cp completions/_gh-commit-ai ~/.zsh/completion/_gh-commit-ai

# Add to ~/.zshrc:
echo 'fpath=($HOME/.zsh/completion $fpath)' >> ~/.zshrc
echo 'autoload -Uz compinit && compinit' >> ~/.zshrc
```

Then restart your shell or run: `exec zsh`

## Uninstallation

### Automatic Uninstallation

```bash
gh commit-ai uninstall-completion
```

### Manual Uninstallation

**Bash:**
```bash
# System-wide
sudo rm /usr/local/etc/bash_completion.d/gh-commit-ai  # macOS
sudo rm /etc/bash_completion.d/gh-commit-ai            # Linux

# User-local
rm ~/.bash_completion.d/gh-commit-ai
```

**Zsh:**
```bash
# System-wide
sudo rm /usr/local/share/zsh/site-functions/_gh-commit-ai  # macOS
sudo rm /usr/share/zsh/site-functions/_gh-commit-ai        # Linux

# User-local
rm ~/.zsh/completion/_gh-commit-ai

# Clear completion cache
rm -f ~/.zcompdump && exec zsh
```

## Testing Completion

After installation, test that completion works:

```bash
# Test command completion
gh commit-ai <TAB><TAB>

# Test flag completion
gh commit-ai --<TAB><TAB>

# Test subcommand completion
gh commit-ai version --<TAB><TAB>

# Test value completion
gh commit-ai --type <TAB><TAB>
```

## Troubleshooting

### Completion not working in Bash

1. Ensure `bash-completion` is installed:
   ```bash
   # macOS
   brew install bash-completion@2

   # Linux
   sudo apt-get install bash-completion
   ```

2. Ensure bash-completion is sourced in your `~/.bashrc`:
   ```bash
   # macOS (Homebrew)
   [[ -r "/usr/local/etc/profile.d/bash_completion.sh" ]] && . "/usr/local/etc/profile.d/bash_completion.sh"

   # Linux
   if [ -f /etc/bash_completion ]; then
       . /etc/bash_completion
   fi
   ```

3. Restart your shell or run: `exec bash`

### Completion not working in Zsh

1. Ensure completion system is enabled in `~/.zshrc`:
   ```bash
   autoload -Uz compinit && compinit
   ```

2. Clear completion cache and restart:
   ```bash
   rm -f ~/.zcompdump && exec zsh
   ```

3. If using Oh My Zsh, ensure completions are loaded:
   ```bash
   # In ~/.zshrc before "source $ZSH/oh-my-zsh.sh"
   fpath=($HOME/.zsh/completion $fpath)
   ```

### Permission errors during installation

If you get permission errors with system-wide installation:

1. Use `sudo` for system directories
2. Or use user-local installation (no sudo required)
3. Ensure the completion directory exists before copying

## Development

### Bash Completion Format

The bash completion script uses the standard bash-completion API:
- `_init_completion` - Initialize completion variables
- `COMPREPLY` - Array of completion results
- `compgen` - Generate completions based on word lists
- `complete -F` - Register completion function

### Zsh Completion Format

The zsh completion script uses the zsh completion system:
- `#compdef` - Define what command to complete
- `_arguments` - Define argument specifications
- `_describe` - Describe completion options
- `_files` / `_directories` - File/directory completion

### Adding New Completions

When adding new commands or flags:

1. Update both `gh-commit-ai.bash` and `_gh-commit-ai`
2. Add to the appropriate command/flag list
3. Add case handling if the flag requires value completion
4. Test in both bash and zsh
5. Update this README

## References

- [Bash Completion Guide](https://github.com/scop/bash-completion)
- [Zsh Completion System](https://zsh.sourceforge.io/Doc/Release/Completion-System.html)
- [GitHub CLI Completion](https://cli.github.com/manual/gh_completion) (for reference)
