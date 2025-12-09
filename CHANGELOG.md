# Changelog

All notable changes to gh-commit-ai will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Groq AI provider support for ultra-fast inference
  - Default model: llama-3.3-70b-versatile
  - Generous free tier: 100 requests/minute
  - Configuration via GROQ_API_KEY and GROQ_MODEL
- Homebrew formula for easy installation on macOS/Linux
  - Install with: `brew tap nathanaelphilip/gh-commit-ai && brew install gh-commit-ai`
  - Includes shell completion and example config
  - Comprehensive deployment documentation
- Repository-specific message caching
  - Prevents cached messages from leaking between different repositories
  - Uses MD5 hash of repository path for isolation
  - Each repository maintains its own message history
- Network retry logic with exponential backoff
  - Automatically retries API calls on network failures
  - Configurable via MAX_RETRIES (default: 3), RETRY_DELAY (default: 2s)
  - Exponential backoff: 2s → 4s → 8s between attempts
  - Handles timeouts, connection failures, SSL errors, and more
  - User-friendly progress messages during retries
  - Applied to all AI providers (Ollama, Anthropic, OpenAI, Groq)
  - Pre-flight check for Ollama: fast-fail when service is down (~2s vs ~14s)
- Auto-fix formatting before commit
  - Detects and optionally fixes common formatting issues
  - Trailing whitespace removal
  - Consistent line endings (LF vs CRLF)
  - Missing final newline at end of file
  - Configurable via AUTO_FIX_FORMATTING (default: false, prompts user)
  - Granular control: AUTO_FIX_TRAILING_WHITESPACE, AUTO_FIX_LINE_ENDINGS, AUTO_FIX_FINAL_NEWLINE
  - Preferred line ending style via LINE_ENDING_STYLE (default: lf)
  - Pure bash implementation with sed (BSD and GNU compatible)
  - Automatically re-stages fixed files
- Commit splitting suggestions
  - New command: `gh commit-ai split`
  - Detects large commits (configurable threshold, default: 1000 lines)
  - AI-powered analysis of staged changes
  - Suggests 2-4 logical ways to split commits
  - Groups related files together
  - Separates concerns (tests, docs, implementation)
  - Maintains logical dependencies
  - Dry-run mode with `--dry-run` flag
  - Custom threshold with `--threshold <n>` flag
  - Interactive guidance for applying splits
  - Works with all AI providers (Ollama, Anthropic, OpenAI, Groq)
- Automated release workflow
  - GitHub Actions workflow for releases (`.github/workflows/release.yml`)
  - Triggered automatically on version tag push (`v*`)
  - Runs full test suite before release
  - Generates release notes from commits and CHANGELOG.md
  - Creates GitHub releases with artifacts
  - Calculates SHA256 for Homebrew formula
  - Automatically updates Homebrew formula
  - Creates pull request with formula updates
  - Release notes generation script (`scripts/generate-release-notes.sh`)
  - Updated formula update script with SHA256 parameter support
  - Comprehensive deployment documentation (DEPLOYMENT.md)
  - Zero-touch releases: just push a tag!
- Security improvements
  - Input validation for all command-line parameters
    - `--threshold` and `--max-lines` validated as positive integers
    - `--type` restricted to allowed conventional commit types only
    - Prevents command injection and invalid inputs
  - Secure temporary file handling
    - Uses `mktemp` for cryptographically secure random filenames
    - Restrictive permissions (600 - owner read/write only)
    - Automatic cleanup on exit or error
    - Replaced all predictable temp file names with secure alternatives
  - API key protection
    - Never logged or displayed in output
    - Only transmitted via HTTPS
    - No exposure in error messages or verbose mode
  - Comprehensive security documentation
    - New SECURITY.md file with security policy
    - Security section added to README.md
    - Best practices for API key management
    - Guidelines for secure usage
- Man page documentation
  - Traditional Unix man page (man/gh-commit-ai.1)
  - Comprehensive documentation covering all features
  - Includes commands, options, configuration, examples, and troubleshooting
  - New commands: `gh commit-ai install-man` and `gh commit-ai uninstall-man`
  - Follows standard man page format and conventions
  - Accessible offline with `man gh-commit-ai`
- Enhanced error handling and user experience
  - Network connectivity detection before API calls
    - Pre-flight check for internet connectivity
    - Host reachability verification for each provider
    - Early detection of offline mode with helpful guidance
  - Contextual error messages with actionable suggestions
    - Clear explanations of what went wrong
    - Multiple possible causes for each error type
    - Step-by-step troubleshooting instructions
    - Alternative provider suggestions when appropriate
  - Enhanced API key error messages
    - Provider-specific setup instructions
    - Direct links to API key management pages
    - Example commands for setting environment variables
    - Ollama fallback suggestions (no API key needed)
  - Improved retry failure messages
    - Detailed context after all retry attempts exhausted
    - Specific troubleshooting for each provider
    - Service status check URLs
    - Diff size reduction suggestions for timeouts
  - Response validation
    - Validates API response format before processing
    - Detects corrupted or unexpected responses
    - Provides guidance for API version issues
  - Applied to all AI providers (Ollama, Anthropic, OpenAI, Groq)

### Fixed
- **Critical**: Message history now properly scoped per repository
  - Previous: All repositories shared the same cache directory
  - Now: Each repository has its own isolated cache based on path hash
  - Prevents wrong commit messages from being suggested in different repos
- **Critical**: Breaking change detection false positives
  - Previous: Adding new functions could incorrectly be flagged as breaking changes
  - Now: Only flags breaking changes when the SAME function is modified
  - Improved function signature detection to compare function names
  - Adding new features/block types no longer incorrectly marked as breaking
- Bash 3.2 compatibility issue with `mapfile` command
  - Previous: Used `mapfile` which is not available in bash 3.2 (default on macOS)
  - Now: Uses `while read` loop for array population (bash 3.2 compatible)
  - Fixes "mapfile: command not found" error on macOS and older systems

### Changed
- Message history directory format changed from `/tmp/gh-commit-ai-history` to `/tmp/gh-commit-ai-history-<repo-hash>`
- Auto-detection priority updated: Ollama → Groq → Anthropic → OpenAI
- **Breaking**: `AUTO_FIX_TRAILING_WHITESPACE` default changed from `true` to `false`
  - Previous: Trailing whitespace was automatically detected/fixed by default
  - Now: Trailing whitespace detection is disabled by default
  - Users can re-enable with: `export AUTO_FIX_TRAILING_WHITESPACE=true`
  - Or set `auto_fix_trailing_whitespace: true` in config file

## [1.0.0] - 2024-XX-XX

### Added
- Initial release
- AI-powered commit message generation
- Support for multiple AI providers (Ollama, Anthropic, OpenAI)
- Conventional commit format with optional scopes
- Smart type detection from branch names and file changes
- Breaking change detection
- Commit history learning
- Gitmoji support
- Multi-language support (15+ languages)
- Code review mode
- PR description generation
- Semantic version suggestions
- Changelog generation
- Shell completion (bash, zsh)
- Commit message templates
- Configuration file support (.gh-commit-ai.yml)
- Message recovery within 5 minutes
- Interactive editing
- Cost tracking for paid APIs
- Integration tests
- Comprehensive documentation

[Unreleased]: https://github.com/nathanaelphilip/gh-commit-ai/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/nathanaelphilip/gh-commit-ai/releases/tag/v1.0.0
