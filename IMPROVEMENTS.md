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

### 6. Interactive Bullet Editing (REMOVED)
**Note**: This feature was implemented but later removed to keep the tool simple and focused. Users can edit commit messages using the standard 'e' option which opens their default editor.

- ~~Allow adding/removing individual bullets after generation~~
- ~~Allow reordering bullets~~
- ~~Allow editing summary line separately~~
- ~~Interactive menu for modifications~~
- ~~Menu-driven interface with single-key commands (s/a/r/o/d/c)~~
- ~~Real-time preview after each edit~~
- ~~Pure bash implementation (no external dependencies)~~

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
- [x] Intelligently sample different parts of very large diffs
- [x] Prioritize added/changed lines over deleted lines
- [x] Focus on function/class names over implementation details
- [x] Smart truncation for massive commits
- [x] Priority-based sampling system:
  - Priority 1: File headers and chunk markers (always kept)
  - Priority 2: Function/class definitions (high priority)
  - Priority 3: Added lines sampled evenly throughout (~40% of limit)
  - Priority 4: Context lines for readability (~20% of limit)
  - Priority 5: Deleted lines (low priority, only if room available)
- [x] Maintains diff structure while reducing size
- [x] Works with all three diff sources (amend, staged, unstaged)

### 15. Model Recommendations
- [x] Analyze commit size (lines added + deleted)
- [x] Suggest optimal model based on size:
  - Small commits (<100 lines) → faster, cheaper models (haiku, gpt-4o-mini, gemma2:2b)
  - Medium commits (100-500 lines) → balanced models (current defaults)
  - Large commits (>500 lines) → more capable models (sonnet, gpt-4o, llama3.3:70b)
- [x] Auto-select if configured via AUTO_SELECT_MODEL environment variable
- [x] Shows tip when recommendation differs from current model
- [x] Works with all three providers (Ollama, Anthropic, OpenAI)

### 16. Automatic Provider & Model Detection
- [x] Auto-detect available AI providers on first run
- [x] Check for Anthropic/OpenAI API keys
- [x] Check if Ollama is running and has models installed
- [x] Automatically select best available provider
- [x] Auto-select best Ollama model from installed models
- [x] Priority list of preferred models for commit messages:
  - Prefer code-focused models (qwen2.5-coder, codellama)
  - Prefer small-to-medium models (faster, good quality)
  - Fall back to any available model
- [x] Show detection message: "Using Ollama with model: X (auto-detected)"
- [x] Helpful error when no providers available with setup instructions
- [x] Default AI_PROVIDER set to "auto" for zero-config experience
- [x] Manual override still supported (set AI_PROVIDER explicitly)

## Quick Wins (Easy to Implement)

- [x] **`--version` flag** - Show current version number
- [x] **`--help` flag** - Show comprehensive usage help (already existed, improved)
- [x] **`-v/--verbose` flag** - Show API request/response for debugging
- [x] **`--type <type>` flag** - Force a specific commit type: `gh commit-ai --type fix`
- [x] **`--max-lines <n>` flag** - Override DIFF_MAX_LINES from command line
- [x] **Message history** - Save last 5 generated messages to `/tmp` for recovery
- [x] **Message recovery** - Automatically recover last message if user accidentally exits (within 5 minutes)
- [x] **Regenerate option** - Press 'r' at confirmation to regenerate message with different wording
- [x] **`--no-lowercase` flag** - Disable automatic lowercase enforcement
- [x] **Better error messages** - More helpful error messages for common issues
- [x] **Progress indicator** - Show spinner/progress while waiting for AI

## Community Requests

Add feature requests from users here as they come in.

---

## Future Enhancements

### Additional AI Provider Support

- [ ] **Google Gemini** - Integrate Google AI Studio API
- [ ] **Azure OpenAI** - Support Azure-hosted OpenAI models
- [ ] **LM Studio** - Support local models via LM Studio
- [ ] **Groq** - Ultra-fast inference with Groq API
- [ ] **Cohere** - Add Cohere Command models
- [ ] **Mistral AI** - Support Mistral API

### Advanced Features

#### 17. Gitmoji Support
- [x] Add emoji prefixes to commit types
- [x] Configuration option to enable/disable gitmoji
- [x] Standard mappings:
  - ✨ feat: new feature
  - 🐛 fix: bug fix
  - 📝 docs: documentation
  - 💄 style: formatting
  - ♻️ refactor: code refactoring
  - ✅ test: adding tests
  - 🔧 chore: tooling/config/maintenance
  - 🚀 perf: performance improvement
  - 🔒 security: security fix
- [x] Works with both scoped and non-scoped formats
- [x] Examples:
  - `✨ feat: add user authentication`
  - `🐛 fix(api): resolve timeout issue`
  - `✨ feat!(auth): redesign authentication API`
- [x] Learn emoji usage from commit history (already supported via history learning feature)

#### 18. Commit Templates
- [x] Support custom commit message templates per project
- [x] Template variables: `{{type}}`, `{{scope}}`, `{{message}}`, `{{emoji}}`, `{{bullets}}`, `{{breaking}}`, `{{ticket}}`, `{{branch}}`, `{{author}}`, `{{date}}`, `{{files_changed}}`
- [x] Project type detection (web app, library, CLI tool, general)
- [x] Template file: `.gh-commit-ai-template`
- [x] Built-in templates for common project types
- [x] Example template file: `.gh-commit-ai-template.example`
- [x] Comprehensive documentation in CLAUDE.md
- [x] Parsing and variable substitution system
- [x] Integration with all existing features (scopes, gitmoji, breaking changes, etc.)

#### 19. Multi-language Support
- [ ] Generate commit messages in different languages
- [ ] Configuration: `COMMIT_LANGUAGE` (en, es, fr, de, ja, zh, etc.)
- [ ] Auto-detect from git config or system locale
- [ ] Maintain conventional commit format across languages

#### 20. PR Description Generator
- [x] New command: `gh commit-ai pr-description`
- [x] Analyze commits since branch diverged from main
- [x] Generate comprehensive PR description
- [x] Include summary, changes, testing notes
- [x] Support `--base` flag to specify base branch
- [x] Support `--output` flag to save to file
- [x] Auto-detect base branch (main/master)
- [x] Comprehensive help with examples

#### 21. Commit Splitting Suggestions
- [ ] Detect when commit is too large (>1000 lines)
- [ ] AI suggests logical ways to split the commit
- [ ] Group related changes together
- [ ] Interactive mode to review and apply splits
- [ ] Preserve git history properly

#### 22. Code Review Mode
- [x] New command: `gh commit-ai review`
- [x] Analyze diff for potential issues:
  - Security vulnerabilities
  - Performance concerns
  - Code style violations
  - Missing error handling
  - Potential bugs
  - TODO/FIXME comments
- [x] Provide suggestions before committing
- [x] Support `--all` flag to review all changes (staged + unstaged)
- [x] Default to reviewing staged changes only
- [x] Comprehensive prompt with 6 categories of issues
- [x] Severity markers (🔴 Critical, 🟡 Warning, 🔵 Info)
- [x] File and line number references
- [x] Detailed explanations and fix suggestions
- [x] Cost tracking for paid APIs
- [x] Works with all providers (Ollama, Anthropic, OpenAI)
- [x] Smart diff sampling for large changes

#### 23. Semantic Versioning Suggestions
- [x] Analyze commits since last tag
- [x] Suggest next version number based on changes:
  - Major: breaking changes detected
  - Minor: new features added
  - Patch: only bug fixes
- [x] Consider conventional commit types
- [x] Integration with version bump commands
- [x] New command: `gh commit-ai version` (alias: `semver`)
- [x] Automatic version parsing and validation
- [x] Detailed analysis of commit types since last tag
- [x] Breaking change detection (! suffix or BREAKING CHANGE)
- [x] Feature, fix, and other commit counting
- [x] Clear reasoning for suggested bump type
- [x] `--create-tag` flag to create tag automatically
- [x] `--prefix` flag for custom tag prefixes
- [x] First version suggestion (0.1.0) when no tags exist
- [x] Interactive tag creation with confirmation
- [x] Tag message generation with commit summary

#### 24. Auto-fix Formatting
- [ ] Detect and fix common formatting issues before commit
- [ ] Trailing whitespace removal
- [ ] Consistent line endings
- [ ] Missing newline at end of file
- [ ] Configurable rules per project

### Quality & Polish

#### Testing & Reliability
- [ ] **Integration tests** - Test with actual API calls (Ollama, Anthropic, OpenAI)
- [ ] **Unit tests** - Test individual bash functions
- [ ] **Mock API responses** - Test without real API calls
- [ ] **Test fixtures** - Sample diffs and expected outputs
- [ ] **CI/CD pipeline** - Automated testing on push
- [ ] **Cross-platform testing** - macOS, Linux, WSL

#### Performance
- [ ] **Performance profiling** - Identify slow operations
- [ ] **Optimize git commands** - Reduce number of git calls
- [ ] **Parallel processing** - Process multiple files concurrently
- [ ] **Caching** - Cache API responses for identical diffs
- [ ] **Benchmark suite** - Track performance over time

#### Security
- [ ] **Security audit** - Review for vulnerabilities
- [ ] **Input validation** - Sanitize all user inputs
- [ ] **API key handling** - Secure storage recommendations
- [ ] **Dependency scanning** - Check for vulnerable dependencies (none currently)
- [ ] **Code signing** - Sign releases for verification

#### Error Handling
- [ ] **Network failure recovery** - Retry with exponential backoff
- [ ] **Timeout handling** - Configurable timeouts for API calls
- [ ] **Offline mode** - Better messaging when APIs unreachable
- [ ] **Partial failure recovery** - Handle incomplete responses
- [ ] **Better error messages** - More context and suggestions

### Developer Experience

#### Documentation & Discoverability
- [ ] **Bash completion** - Tab completion for commands and flags
- [ ] **Man page** - Traditional Unix man page (`man gh-commit-ai`)
- [ ] **Demo video** - Screencast showing features
- [ ] **Animated GIFs** - Visual examples in README
- [ ] **Tutorial** - Step-by-step getting started guide
- [ ] **FAQ section** - Common questions and answers
- [ ] **Troubleshooting guide** - Debug common issues

#### Development Tools
- [ ] **Development mode** - Easy setup for contributors
- [ ] **Debug mode** - Enhanced logging for debugging
- [ ] **Test helpers** - Scripts to test locally
- [ ] **Contribution guide** - Clear guidelines for contributors
- [ ] **Code style guide** - Bash style conventions

#### Release Management
- [ ] **Automated releases** - GitHub Actions for releases
- [ ] **Semantic versioning** - Follow semver strictly
- [ ] **Release notes** - Auto-generate from commits
- [ ] **Binary distribution** - Pre-packaged downloads
- [ ] **Homebrew formula** - Easy install on macOS
- [ ] **Package managers** - apt, yum, pacman support

### Analytics & Insights

#### Usage Statistics (Privacy-respecting)
- [ ] **Local analytics** - Track feature usage (opt-in, local only)
- [ ] **Performance metrics** - API latency, success rates
- [ ] **Model comparison** - Track which models work best
- [ ] **Cost tracking dashboard** - Visualize API costs over time
- [ ] **Export reports** - Generate usage summaries

#### Commit Insights
- [ ] **Repository health** - Analyze commit patterns
- [ ] **Team statistics** - Aggregate team commit metrics
- [ ] **Commit quality score** - Rate commit message quality
- [ ] **Trends over time** - Track improvements

---

**Note**: Check off items with `[x]` as they are completed.
