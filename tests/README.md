# Tests for gh-commit-ai

This directory contains unit, integration, and end-to-end tests for the gh-commit-ai script using the [Bats](https://github.com/bats-core/bats-core) testing framework.

## Installation

### Install Bats

**macOS (Homebrew):**
```bash
brew install bats-core
```

**Linux (apt):**
```bash
sudo apt-get install bats
```

**From source:**
```bash
git clone https://github.com/bats-core/bats-core.git
cd bats-core
./install.sh /usr/local
```

## Running Tests

### Run all tests:
```bash
bats tests/
```

### Run specific test suite:
```bash
# Unit tests
bats tests/test_core_functions.bats
bats tests/test_cli.bats
bats tests/test_branch_intelligence.bats
bats tests/test_mock_responses.bats

# Integration tests (require API access)
bats tests/test_integration_ollama.bats      # Requires Ollama running
bats tests/test_integration_anthropic.bats   # Requires ANTHROPIC_API_KEY
bats tests/test_integration_openai.bats      # Requires OPENAI_API_KEY

# End-to-end workflow tests
bats tests/test_e2e_workflows.bats
```

### Run with verbose output:
```bash
bats -t tests/
```

### Run with TAP output:
```bash
bats --tap tests/
```

## Test Files

### `test_helper.bash`
Helper functions and setup/teardown for all tests:
- `setup()` - Creates temporary directory before each test
- `teardown()` - Cleans up after each test
- `create_test_repo()` - Creates a test git repository
- `source_script_functions()` - Loads functions from main script for unit testing

### `test_core_functions.bats`
Tests for core utility functions:
- **escape_json()** - Tests JSON string escaping
  - Double quotes, backslashes, newlines, tabs
  - Empty strings
- **enforce_lowercase()** - Tests lowercase enforcement
  - Basic text conversion
  - Preserving acronyms (API, HTTP, JSON, JWT, SQL, etc.)
  - Preserving ticket numbers (ABC-123, JIRA-456, etc.)
  - Conventional commit formats

### `test_cli.bats`
Tests for command-line interface:
- Help flag (`--help`, `-h`)
- Unknown options
- Repository validation
- Empty repository handling
- Amend mode with no commits

### `test_branch_intelligence.bats`
Tests for branch name intelligence:
- **Ticket Number Extraction:**
  - From various branch formats (feature/ABC-123, fix/JIRA-456, etc.)
  - Handling branches without tickets
- **Type Detection:**
  - feat, fix, docs, chore, refactor, test, style
  - Multiple prefix variations (feature/feat, bugfix/fix/hotfix, test/tests, etc.)

### `test_mock_responses.bats`
Tests for API response parsing without real API calls:
- **JSON Parsing:**
  - Ollama response format parsing
  - Anthropic response format parsing
  - OpenAI response format parsing
  - Token count extraction
- **Message Processing:**
  - Multiple option handling
  - Lowercase enforcement
  - JSON escaping
  - Newline conversion
  - Smart diff sampling

### `test_integration_ollama.bats`
Integration tests with Ollama (requires Ollama running):
- Generate commit messages for various change types
- Test amend mode
- Test large diff handling
- Test scope configuration
- Test lock file filtering

**Prerequisites:**
```bash
# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Pull a model
ollama pull gemma3:12b

# Start Ollama
ollama serve
```

### `test_integration_anthropic.bats`
Integration tests with Anthropic API (requires API key):
- Generate commit messages with Claude models
- Test cost tracking and token usage
- Test error handling
- Test different model variants

**Prerequisites:**
```bash
export ANTHROPIC_API_KEY="sk-ant-your-key-here"
```

### `test_integration_openai.bats`
Integration tests with OpenAI API (requires API key):
- Generate commit messages with GPT models
- Test cost tracking and token usage
- Test error handling
- Test different model variants

**Prerequisites:**
```bash
export OPENAI_API_KEY="sk-proj-your-key-here"
```

### `test_e2e_workflows.bats`
End-to-end workflow tests:
- **Commands:**
  - Help flags for all commands
  - Version command and semantic versioning
  - Changelog generation
  - Code review mode
  - PR description generation
- **Features:**
  - Config file loading
  - Branch intelligence
  - Smart type detection
  - Lock file exclusion
  - Message history

### Test Fixtures (`fixtures/`)
Sample diffs used for testing:
- `simple_feature.diff` - Basic feature addition
- `bug_fix.diff` - Bug fix with validation
- `docs_only.diff` - Documentation changes
- `large_refactor.diff` - Code refactoring

## Test Coverage

### ✅ Fully Covered:
- JSON escaping and parsing
- Lowercase enforcement with acronym preservation
- Ticket number preservation
- Command-line argument parsing
- Branch intelligence (ticket extraction and type detection)
- Error handling (no git repo, no commits, etc.)
- API response parsing (mock tests)
- Lock file filtering
- Config file loading
- All command help flags

### ✅ Integration Tested:
- Ollama API integration (when running)
- Anthropic API integration (when API key provided)
- OpenAI API integration (when API key provided)
- Commit message generation
- Amend mode
- Cost tracking
- Smart diff sampling

### ⚠️  Limited Coverage:
- Interactive prompts (requires manual testing)
- Actual git commit operations (requires manual testing)
- Editor integration (requires manual testing)

## Adding New Tests

To add a new test file:

1. Create a new `.bats` file in the `tests/` directory
2. Load the test helper at the top:
   ```bash
   load test_helper
   ```
3. Add `setup()` and `teardown()` if needed
4. Write tests using the `@test` decorator:
   ```bash
   @test "description of test" {
       # Test code here
       run some_command
       [ "$status" -eq 0 ]
       [[ "$output" == *"expected"* ]]
   }
   ```

## Continuous Integration

This project uses GitHub Actions for automated testing. See [`.github/workflows/test.yml`](../.github/workflows/test.yml) for the full configuration.

### CI Pipeline

The CI pipeline runs on every push and pull request:

1. **Unit Tests** - Runs on Ubuntu and macOS
   - Core functions
   - CLI interface
   - Branch intelligence
   - Mock responses

2. **Workflow Tests** - Runs on Ubuntu and macOS
   - End-to-end workflows
   - Command help texts
   - Config file loading
   - Version/changelog/review commands

3. **Integration Tests (Ollama)** - Ubuntu only, main branch
   - Installs Ollama
   - Pulls gemma2:2b model
   - Tests actual commit generation

4. **Integration Tests (Anthropic/OpenAI)** - Main branch only
   - Runs if API keys are configured as secrets
   - Skips gracefully if keys not available

5. **Linting** - Shellcheck validation
   - Non-blocking (for now)

6. **Coverage Report** - Test summary
   - Generates test results in TAP format
   - Reports pass/fail counts

### Setting Up CI for Your Fork

1. **Enable GitHub Actions** in your repository settings

2. **Add API Key Secrets** (optional, for full integration tests):
   - Go to Settings → Secrets → Actions
   - Add `ANTHROPIC_API_KEY` (optional)
   - Add `OPENAI_API_KEY` (optional)

3. **CI will run automatically** on:
   - Every push to main/develop
   - Every pull request

### Local CI Testing

Run the same tests that CI runs:

```bash
# Unit tests (fast)
bats tests/test_core_functions.bats \
     tests/test_cli.bats \
     tests/test_branch_intelligence.bats \
     tests/test_mock_responses.bats

# Workflow tests
bats tests/test_e2e_workflows.bats

# Integration tests (requires setup)
export ANTHROPIC_API_KEY="your-key"
bats tests/test_integration_ollama.bats      # Requires Ollama
bats tests/test_integration_anthropic.bats   # Requires API key
bats tests/test_integration_openai.bats      # Requires API key

# All tests with TAP output
bats --tap tests/*.bats
```

## Troubleshooting

**"bats: command not found"**
- Install bats following the installation instructions above

**Tests failing on file permissions**
- Make sure `gh-commit-ai` is executable: `chmod +x gh-commit-ai`

**Tests failing with "git: command not found"**
- Ensure git is installed and available in PATH
