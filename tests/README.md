# Tests for gh-commit-ai

This directory contains unit and integration tests for the gh-commit-ai script using the [Bats](https://github.com/bats-core/bats-core) testing framework.

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

### Run specific test file:
```bash
bats tests/test_core_functions.bats
bats tests/test_cli.bats
bats tests/test_branch_intelligence.bats
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

## Test Coverage

### Covered:
- ✅ JSON escaping function
- ✅ Lowercase enforcement with acronym preservation
- ✅ Ticket number preservation
- ✅ Command-line argument parsing
- ✅ Branch intelligence (ticket extraction and type detection)
- ✅ Error handling (no git repo, no commits, etc.)

### Not Covered (Manual Testing Required):
- ⚠️  AI API calls (Ollama, Anthropic, OpenAI)
- ⚠️  Interactive prompts
- ⚠️  Actual git commit operations
- ⚠️  File I/O operations

**Note:** Testing actual API calls and git operations requires integration tests with mocking, which is complex in bash. These should be tested manually or with a more advanced testing setup.

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

To run tests in CI/CD:

```yaml
# Example GitHub Actions workflow
- name: Install Bats
  run: |
    git clone https://github.com/bats-core/bats-core.git
    cd bats-core
    sudo ./install.sh /usr/local

- name: Run Tests
  run: bats tests/
```

## Troubleshooting

**"bats: command not found"**
- Install bats following the installation instructions above

**Tests failing on file permissions**
- Make sure `gh-commit-ai` is executable: `chmod +x gh-commit-ai`

**Tests failing with "git: command not found"**
- Ensure git is installed and available in PATH
