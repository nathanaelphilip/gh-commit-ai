# Product Improvements

This document tracks potential improvements and features for gh-commit-ai.

## High-Impact Improvements

### 1. Conventional Commit Scopes
- [x] Add support for scopes to be more specific
- [x] Format: `feat(auth): add user authentication`
- [x] Format: `fix(api): resolve connection timeout`
- [x] Format: `docs(readme): update installation steps`
- [x] Allow configuration via `USE_SCOPE` environment variable (default: disabled for simplicity)
- [ ] Allow configuration of custom scope names per project (future enhancement)

### 2. Branch Name Intelligence
- [x] Better extraction of context from branch names
- [x] Auto-detect ticket numbers: `feature/ABC-123-user-auth` → include "ABC-123" in commit
- [x] Auto-suggest type from branch: `fix/login-bug` → suggest "fix" type
- [x] Extract feature/ticket info to include in summary
- [x] Support multiple branch prefixes: feat, feature, fix, bugfix, hotfix, docs, style, refactor, test, chore

### 3. Dry-Run Mode
- [x] Implement `--dry-run` flag (generate message without committing)
- [x] Implement `--preview` flag (show message and exit)
- [x] Allow saving generated message to file (in --dry-run mode)
- [x] Add `--help` flag for usage information

### 4. Amend Support
- [x] Implement `--amend` flag to regenerate message for last commit
- [x] Support editing existing commit messages
- [x] Use `git show HEAD` to analyze last commit
- [x] Use `git commit --amend` to rewrite commit

### 5. Configuration File
- [x] Support `.gh-commit-ai.yml` in repo root
- [x] Support project-specific settings:
  - [x] Default provider
  - [x] Default model
  - [x] Diff max lines
  - [x] Use scopes
  - [ ] Default scope (future enhancement)
  - [ ] Custom ticket pattern (future enhancement)
- [x] Support global config in `~/.gh-commit-ai.yml`
- [x] Pure bash YAML parser (no dependencies)
- [x] Configuration precedence: env vars > local config > global config > defaults
- [x] Example configuration file (.gh-commit-ai.example.yml)

### 6. Interactive Bullet Editing
- [x] Allow adding/removing individual bullets after generation
- [x] Allow reordering bullets
- [x] Allow editing summary line separately
- [x] Interactive menu for modifications
- [x] Menu-driven interface with single-key commands (s/a/r/o/d/c)
- [x] Real-time preview after each edit
- [x] Pure bash implementation (no external dependencies)

### 7. Cost Tracking (for paid APIs)
- [x] Show token count after generation
- [x] Show estimated cost for Anthropic API calls
- [x] Show estimated cost for OpenAI API calls
- [x] Track cumulative costs per day
- [x] Support all major Anthropic models (Sonnet, Opus, Haiku)
- [x] Support all major OpenAI models (GPT-4o, GPT-4o-mini, GPT-4, GPT-4 Turbo)
- [x] Daily cost files stored in /tmp with automatic cleanup
- [x] Fallback to awk when bc not available

### 8. Smart Type Detection
- [x] Analyze changes to suggest type automatically:
  - [x] Only docs files changed → `docs`
  - [x] Only test files changed → `test`
  - [x] Version bumps → `chore`
  - [x] Bug keywords in diff → `fix`
- [x] Make suggestions but allow override
- [x] File pattern recognition (docs, tests, config, code)
- [x] Diff content analysis for bug-related keywords
- [x] Integration with branch intelligence (mentions both when they differ)
- [x] Works on main branch without branch naming conventions

### 9. Breaking Change Detection
- [x] Detect breaking changes in diff
- [x] Add `!` to type for breaking changes: `feat!:`
- [x] Add BREAKING CHANGE footer automatically
- [x] Detection methods:
  - [x] Explicit keywords (BREAKING CHANGE, breaking:, etc.)
  - [x] Removal of public APIs/exports
  - [x] Major version bumps (1.x.x → 2.0.0)
  - [x] Function signature changes (parameter reduction)
- [x] Automatic prompt modification to include breaking change instructions
- [x] Works with both scoped and non-scoped formats
- [x] Example:
  ```
  feat!: redesign authentication API

  - remove legacy login endpoint
  - change token format to JWT

  BREAKING CHANGE: Legacy /auth/login endpoint removed
  ```

### 10. Commit Message History Learning
- [x] Analyze last 50 commits in repo
- [x] Detect commit message patterns
- [x] Detect emoji usage patterns
- [x] Detect scope usage patterns
- [x] Match the repo's existing style automatically
- [x] Detect most common commit types
- [x] Detect capitalization preferences
- [x] Detect breaking change notation usage
- [x] Configuration option to enable/disable (LEARN_FROM_HISTORY)
- [x] Minimum 5 commits required for analysis
- [x] Passes insights to AI via prompt

### 11. Multiple Message Options
- [x] Generate 2-3 different commit messages
- [x] Let user choose between options:
  - Option 1: Concise
  - Option 2: Detailed
  - Option 3: Alternative perspective
- [x] Interactive selection menu
- [x] Single API call with `---OPTION---` separator
- [x] Numbered display of all variations
- [x] User selection with validation (1-N or 'n' to cancel)
- [x] Works with all providers (Ollama, Anthropic, OpenAI)
- [x] Each option processed through lowercase enforcement

### 12. Changelog Generation
- [x] Implement `gh commit-ai changelog` command
- [x] Generate changelog from commit history
- [x] Support `--since` flag for version ranges
- [x] Parse conventional commits and categorize by type
- [x] Support breaking change detection
- [x] Scope extraction and display
- [x] Emoji category indicators
- [x] Commit links in output
- [x] Pure bash implementation with regex parsing
- [ ] Support different changelog formats (Keep a Changelog is implemented, others future enhancement)

### 13. Pre-commit Hook Integration
- [x] Implement `gh commit-ai install-hook` command
- [x] Implement `gh commit-ai uninstall-hook` command
- [x] Support `prepare-commit-msg` hook
- [x] OPT-IN design via `GH_COMMIT_AI=1` environment variable
- [x] Skip merge/squash/amend commits
- [x] Conflict detection (won't overwrite existing hooks)
- [x] Git alias suggestion (`git ai-commit`)
- [x] Error handling and fallback
- [x] Integration with `--preview` flag
- [x] Clean uninstall with safety checks

### 14. Better Token Limit Handling
- [ ] Intelligently sample different parts of very large diffs
- [ ] Prioritize added/changed lines over deleted lines
- [ ] Focus on function/class names over implementation details
- [ ] Smart truncation for massive commits

### 15. Model Recommendations
- [ ] Analyze commit size
- [ ] Suggest optimal model based on size:
  - Small commits (<100 lines) → faster, cheaper models
  - Large commits (>500 lines) → more capable models
- [ ] Auto-select if configured

## Quick Wins (Easy to Implement)

- [x] **`--version` flag** - Show current version number
- [x] **`--help` flag** - Show comprehensive usage help (already existed, improved)
- [x] **`-v/--verbose` flag** - Show API request/response for debugging
- [x] **`--type <type>` flag** - Force a specific commit type: `gh commit-ai --type fix`
- [x] **`--max-lines <n>` flag** - Override DIFF_MAX_LINES from command line
- [x] **Message history** - Save last 5 generated messages to `/tmp` for recovery
- [x] **`--no-lowercase` flag** - Disable automatic lowercase enforcement
- [ ] **Better error messages** - More helpful error messages for common issues
- [ ] **Progress indicator** - Show spinner/progress while waiting for AI

## Community Requests

Add feature requests from users here as they come in.

---

**Note**: Check off items with `[x]` as they are completed.
