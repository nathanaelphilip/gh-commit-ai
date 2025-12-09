# Security Policy

## Overview

gh-commit-ai takes security seriously. This document outlines our security practices, known security features, and how to report security vulnerabilities.

## Security Features

### 1. Input Validation

All user inputs are validated to prevent injection attacks and ensure data integrity:

#### Numeric Parameter Validation
- `--threshold` flag: Validated as positive integer (> 0)
- `--max-lines` flag: Validated as positive integer (> 0)
- Configuration values from YAML files: Validated before use

#### String Parameter Validation
- `--type` flag: Restricted to allowed conventional commit types only
  - Allowed values: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`, `revert`
- Prevents arbitrary command injection through type specification

**Example Error Messages:**
```bash
# Invalid threshold
$ gh commit-ai split --threshold abc
Error: --threshold must be a positive integer, got: abc

# Invalid commit type
$ gh commit-ai --type invalid
Error: --type must be one of: feat fix docs style refactor test chore perf ci build revert, got: invalid
```

### 2. Secure Temporary File Handling

All temporary files are created with secure practices:

#### Implementation Details
- Uses `mktemp` for cryptographically secure random file names
- Sets restrictive permissions (`600` - owner read/write only)
- Automatic cleanup on script exit or error
- No predictable file names (prevents race conditions and symlink attacks)

**Before (Insecure):**
```bash
temp_file="/tmp/gh-commit-ai-$$"  # Predictable, using process ID
```

**After (Secure):**
```bash
temp_file=$(create_secure_temp_file "gh-commit-ai-prefix")  # Random, secure
chmod 600 "$temp_file"  # Restrictive permissions
```

#### Protected Data
Temporary files may contain sensitive information:
- Git diffs (may include code, credentials, secrets)
- AI API responses (commit messages, analysis)
- Intermediate processing data

### 3. API Key Protection

API keys for AI services are handled securely:

#### Storage
- **Environment Variables Only**: API keys must be set as environment variables
- **Never in Config Files**: YAML configuration files do NOT support API keys
- **No Logging**: API keys are never logged or displayed in verbose output
- **Secure Transmission**: Keys are only sent in HTTPS headers to AI providers

**Supported API Keys:**
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-proj-..."
export GROQ_API_KEY="gsk_..."
```

**Security Notes:**
- Never commit API keys to version control
- Never add API keys to `.gh-commit-ai.yml` files
- Use shell history management to avoid leaking keys:
  ```bash
  # Add space before command to avoid history (in bash/zsh)
   export ANTHROPIC_API_KEY="sk-ant-..."

  # Or clear history after setting
  history -d $((HISTCMD-1))
  ```

#### API Key Exposure Prevention
- API keys are only passed in HTTP headers (never in URLs or JSON payloads visible in logs)
- Verbose mode (`--verbose`) shows request/response but redacts headers containing keys
- Error messages never include API keys, only generic authentication errors

### 4. Command Injection Prevention

The script prevents command injection through multiple mechanisms:

#### Safe Command Construction
- User inputs are validated before use
- No direct `eval` of user-provided strings
- Git commands use hardcoded exclude patterns (not user-controllable)

#### String Sanitization
The `sanitize_string()` function removes dangerous characters:
- Null bytes (`\0`)
- Control characters
- Command substitution metacharacters: `` ` ``, `$()`, `${}`
- Shell metacharacters: `|`, `;`, `&`, `<`, `>`, `[]`, `{}`

### 5. Safe Git Operations

Git operations are performed securely:

#### Hardcoded Patterns
The `GIT_EXCLUDE_PATTERN` variable is hardcoded and not user-modifiable:
```bash
GIT_EXCLUDE_PATTERN="':(exclude)package-lock.json' ':(exclude)yarn.lock' ..."
```

This prevents users from injecting malicious patterns that could:
- Execute arbitrary commands
- Access files outside the repository
- Bypass security restrictions

#### Quoted Variables
All variables used in shell commands are properly quoted to prevent word splitting and glob expansion:
```bash
git diff "$file"  # Correct - quoted
# vs
git diff $file    # Vulnerable - unquoted
```

### 6. No Privilege Escalation

The script runs with user privileges and never:
- Requests root/sudo access
- Modifies system files
- Changes file ownership or permissions (except on its own temp files)
- Installs system-wide components without user consent

## Security Best Practices for Users

### 1. API Key Management

#### Do:
✅ Store API keys in environment variables
✅ Use shell profiles (`.bashrc`, `.zshrc`) for persistent keys
✅ Use secret management tools (1Password, pass, etc.)
✅ Rotate API keys regularly
✅ Use separate keys for development and production
✅ Check API usage regularly for anomalies

#### Don't:
❌ Commit API keys to Git repositories
❌ Store API keys in config files (`.gh-commit-ai.yml`)
❌ Share API keys via email or chat
❌ Use the same API key across multiple tools/machines
❌ Store API keys in plain text files

### 2. Repository Security

#### Sensitive Data in Commits
- **Review diffs before committing**: Use `--preview` or `--dry-run` flags
- **Use `.gitignore`**: Prevent sensitive files from being staged
- **Check AI-generated messages**: Ensure they don't leak information about sensitive code paths

#### Pre-commit Checks
```bash
# Always preview the generated message first
gh commit-ai --preview

# Use dry-run to see the message without committing
gh commit-ai --dry-run
```

### 3. Code Review Mode Security

When using `gh commit-ai review`:
- Review suggestions carefully before implementing fixes
- AI may miss security issues or suggest insecure fixes
- Always perform manual security review for security-critical code
- Don't blindly trust AI suggestions

### 4. Network Security

#### HTTPS Only
- All AI provider APIs use HTTPS
- Certificate verification is enabled by default
- No plaintext transmission of data

#### Proxy Support
The tool respects system proxy settings via curl:
```bash
export https_proxy="https://proxy.example.com:8080"
export http_proxy="http://proxy.example.com:8080"
```

### 5. Local AI Providers (Ollama)

When using Ollama (default):
- ✅ No data leaves your machine
- ✅ No API keys required
- ✅ No network requests (runs locally)
- ⚠️ Ensure Ollama is running only on `localhost`
- ⚠️ Don't expose Ollama to the network unless necessary

## Reporting Security Vulnerabilities

### How to Report

If you discover a security vulnerability in gh-commit-ai, please report it responsibly:

1. **DO NOT** open a public GitHub issue
2. Email the maintainer directly at: [security contact - TBD]
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### Response Timeline

- **24 hours**: Initial acknowledgment
- **7 days**: Preliminary assessment and response
- **30 days**: Fix developed and tested
- **Public disclosure**: After fix is released

### Security Updates

Security updates are released as:
- **Patch versions** (1.0.x) for security fixes
- Documented in `CHANGELOG.md` with `Security` section
- GitHub Security Advisories for critical issues

## Known Limitations

### 1. AI Provider Security

The tool sends git diffs to AI providers (Anthropic, OpenAI, Groq) for analysis:
- **Data transmission**: Your code diffs are sent to third-party APIs
- **Data retention**: Depends on provider's data retention policy
- **Privacy**: Review provider's privacy policy before use

**Mitigation:**
- Use Ollama (local AI) for sensitive repositories
- Review diff content before sending (use `--preview`)
- Use `DIFF_MAX_LINES` to limit data sent

### 2. Temporary File Cleanup

While secure temp files are used:
- Files may persist briefly if script crashes unexpectedly
- System `/tmp` cleanup policies apply
- Consider using `TMPDIR` on encrypted volumes for sensitive repos

### 3. Shell History

Commands with API keys may be stored in shell history:
```bash
# Vulnerable - key stored in history
gh commit-ai --type feat

# If you set ANTHROPIC_API_KEY inline
ANTHROPIC_API_KEY="sk-ant-..." gh commit-ai  # Key in history!
```

**Mitigation:**
- Set API keys in `.bashrc`/`.zshrc`, not inline
- Use space prefix to avoid history in bash/zsh
- Configure shell to not store sensitive commands

## Security Audit

Last security audit: [Date - TBD]

### Audit Checklist

- [x] Input validation on all user inputs
- [x] Secure temporary file creation
- [x] API key protection
- [x] Command injection prevention
- [x] Proper variable quoting
- [x] No privilege escalation
- [x] HTTPS-only communication
- [x] Error message sanitization
- [ ] Third-party dependency audit (none currently)
- [ ] Automated security testing in CI/CD
- [ ] Penetration testing

## Security Contact

For security-related questions or concerns:
- GitHub Issues: https://github.com/nathanaelphilip/gh-commit-ai/issues (for non-sensitive questions)
- Security vulnerabilities: [Email TBD]

## License

This security policy is licensed under the same license as the project (see LICENSE file).

---

**Last updated**: 2024-12-05
**Version**: 1.0.0
