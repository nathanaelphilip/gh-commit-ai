# Contributing to gh-commit-ai

Thank you for your interest in contributing to gh-commit-ai! This guide will help you get set up and productive quickly.

## Prerequisites

- **bash 4+** (macOS ships with bash 3; install newer via `brew install bash`)
- **curl** (for API calls)
- **git** (obviously)
- **bats-core** (for running tests): `brew install bats-core`
- **make** (for building from source modules)

## Development Setup

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/gh-commit-ai.git
cd gh-commit-ai

# The project uses a build-based modularization system
# Source modules live in src/, the built script is gh-commit-ai
make build    # Concatenate src/ modules into gh-commit-ai
make verify   # Verify all functions are present
make test     # Run unit tests (requires bats-core)

# Test the script directly
./gh-commit-ai --help

# Or install as a gh extension for integration testing
gh extension install .
gh commit-ai --help
```

## Architecture Overview

### Build System

The project uses a single-file deployment model for `gh extension install .` compatibility. Source code is split into numbered modules in `src/` that are concatenated by `make build`:

```
src/
  00-header.sh              # Shebang, set -e, VERSION, colors
  01-config.sh              # YAML parser, config loading, defaults, validation
  02-security.sh            # Temp files, input validation, PII/secret detection
  03-retry.sh               # retry_api_call(), streaming_api_call()
  04-providers-detect.sh    # Auto-detect available providers
  05-subcommands.sh         # changelog, version, split, code review, PR description
  05b-analytics.sh          # Local analytics tracking and stats report
  06-cli-parsing.sh         # CLI argument parsing, message history, subcommand routing
  07-utils.sh               # Utilities: spinner, diff sampling, streaming parsers
  08-git-analysis.sh        # Type detection, breaking changes, history learning
  09-wordpress.sh           # WordPress-specific file context and function lookup
  10-analysis.sh            # Commit examples, semantic analysis, file relationships
  11-parallel.sh            # Parallel analysis orchestration
  12-prompt.sh              # Secret scanning, few-shot examples, prompt construction
  13-json-utils.sh          # JSON escaping, lowercase enforcement, auto-fix
  14-templates.sh           # Project type detection, template system
  15-cost.sh                # Token cost calculation, cumulative tracking
  16-options-ui.sh          # Multiple options UI (--options mode)
  17-providers-ollama.sh    # Ollama provider (local)
  18-providers-anthropic.sh # Anthropic Claude provider
  19-providers-openai.sh    # OpenAI GPT provider
  20-providers-groq.sh      # Groq provider (OpenAI-compatible)
  21-main.sh                # Main execution flow
```

**Key rule**: Numeric prefixes control concatenation order. Functions must be defined before they're called.

### Data Flow

```
User runs gh commit-ai
  -> CLI parsing (flags, subcommands)
  -> Git analysis (diff, status, branch)
  -> Parallel analysis (type detection, file context, etc.)
  -> Secret scanning (for cloud providers)
  -> Prompt construction (context + instructions)
  -> AI provider call (streaming or non-streaming)
  -> Post-processing (lowercase, template, auto-fix)
  -> User confirmation (accept/edit/regenerate)
  -> Git commit
```

### Provider Pattern

All four providers follow the same pattern:

1. Validate credentials/connectivity
2. Attempt streaming if enabled (try first, fall back to non-streaming)
3. Non-streaming: retry with exponential backoff + spinner
4. Parse response, extract message and token counts
5. Write token counts to `/tmp/gh-commit-ai-tokens-$$` files (subshell workaround)

## Code Style

- **No external dependencies** beyond curl, git, and standard Unix tools (no `jq`, no `yq`)
- **Pure bash** JSON handling with `escape_json()` and awk-based parsing
- **Functions over scripts**: Keep logic in named functions for testability
- **Error messages to stderr**: Always `echo "..." >&2` for errors/warnings
- **Color codes**: Use `$RED` and `$NC` for errors; avoid other colors in new code
- **Comments**: Document non-obvious logic, especially regex patterns

### Naming Conventions

- Functions: `snake_case` (e.g., `detect_smart_type()`)
- Global variables: `UPPER_SNAKE_CASE` (e.g., `AI_PROVIDER`)
- Local variables: `lower_snake_case` with `local` keyword
- Config variables: `CONFIG_UPPER_SNAKE_CASE` (parsed from YAML)

## Adding a New Provider

Adding a provider requires changes in 4 places:

### 1. Configuration (`src/01-config.sh`)

```bash
# Add to YAML parser case statement
newprovider_model|NEWPROVIDER_MODEL)
    CONFIG_NEWPROVIDER_MODEL="${CONFIG_NEWPROVIDER_MODEL:-$value}"
    ;;

# Add config defaults
NEWPROVIDER_MODEL="${NEWPROVIDER_MODEL:-${CONFIG_NEWPROVIDER_MODEL:-default-model}}"
NEWPROVIDER_API_KEY="${NEWPROVIDER_API_KEY:-}"
```

### 2. Provider Detection (`src/04-providers-detect.sh`)

Add detection logic in `detect_available_providers()`.

### 3. Provider Function (`src/XX-providers-newprovider.sh`)

Create a new module file following the existing provider pattern:

```bash
call_newprovider() {
    local prompt="$1"
    # 1. Validate API key
    # 2. Check network connectivity
    # 3. Try streaming (if should_stream)
    # 4. Fall back to non-streaming with retry_api_call
    # 5. Parse response, extract message
    # 6. Write token counts to files
    # 7. Return message via unescape_json
}
```

### 4. Main Flow (`src/21-main.sh`)

Add case in the provider routing:

```bash
case "$AI_PROVIDER" in
    newprovider)
        COMMIT_MSG=$(call_newprovider "$PROMPT")
        ;;
```

## Testing

### Running Tests

```bash
# All tests
make test

# Specific test file
bats tests/test_core_functions.bats
bats tests/test_cli.bats
bats tests/test_branch_intelligence.bats

# With verbose output
bats --verbose-run tests/
```

### Test Structure

- `tests/test_helper.bash` - Helper functions, loads script functions
- `tests/test_core_functions.bats` - Unit tests for JSON escaping, lowercase
- `tests/test_cli.bats` - CLI argument parsing tests
- `tests/test_branch_intelligence.bats` - Branch name parsing tests
- `tests/test_e2e_workflows.bats` - End-to-end workflow tests
- `tests/test_mock_responses.bats` - Mock API response tests

### Adding Tests

```bash
# In tests/test_your_feature.bats
#!/usr/bin/env bats

load test_helper

@test "your feature does something" {
    source_script_functions
    result=$(your_function "input")
    [ "$result" = "expected output" ]
}
```

### Manual Testing

```bash
# Test with different providers
./gh-commit-ai --preview
AI_PROVIDER=anthropic ./gh-commit-ai --dry-run
STREAM_ENABLED=true ./gh-commit-ai --preview

# Test config validation
echo "typo_key: value" > .gh-commit-ai.yml
./gh-commit-ai --help  # Should show warning

# Test secret detection
# Stage a file with a fake API key, run gh commit-ai
```

## Pull Request Process

1. **Branch naming**: `feat/description`, `fix/description`, `docs/description`
2. **Commit format**: Use conventional commits (`feat:`, `fix:`, `docs:`, etc.)
3. **Build before committing**: Run `make build && make verify` to ensure the built script is up to date
4. **Test**: Run `make test` (when bats is available)
5. **One concern per PR**: Keep PRs focused on a single change

## Release Process

1. Update `VERSION` in `src/00-header.sh`
2. Run `make build`
3. Run `gh commit-ai changelog` to generate changelog
4. Commit: `chore: bump version to X.Y.Z`
5. Tag: `gh commit-ai version --create-tag`
6. Push: `git push && git push --tags`
