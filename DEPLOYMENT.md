# Deployment Guide

This guide covers how to deploy gh-commit-ai with Homebrew support.

## Prerequisites

- Git repository pushed to GitHub
- GitHub CLI (`gh`) installed
- Homebrew installed (for testing)

## Release Methods

There are two ways to create a release:

1. **Automated (Recommended)** - GitHub Actions workflow handles everything
2. **Manual** - Step-by-step process for manual releases

---

## Method 1: Automated Release (Recommended)

The automated release workflow handles all steps automatically when you push a version tag.

### Quick Start

```bash
# 1. Update CHANGELOG.md with release notes
vim CHANGELOG.md

# 2. Commit changes
git add CHANGELOG.md
git commit -m "docs: prepare v1.0.0 release"

# 3. Create and push tag (this triggers the workflow)
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

### What the Workflow Does

When you push a tag starting with `v` (e.g., `v1.0.0`), the GitHub Actions workflow automatically:

1. **✅ Runs all tests** - Validates syntax and runs test suite
2. **📝 Generates release notes** - Extracts from CHANGELOG.md and commits
3. **📦 Creates tarball** - Packages the release
4. **🔢 Calculates SHA256** - For Homebrew formula
5. **🚀 Creates GitHub Release** - With notes and artifacts
6. **🍺 Updates Homebrew Formula** - Updates version and SHA256
7. **🔀 Creates PR** - Automated PR to merge formula updates

### After Automated Release

1. **Review the PR** - Check the auto-created pull request
2. **Merge the PR** - Approve and merge to update the formula
3. **Done!** - Users can now `brew upgrade gh-commit-ai`

### Monitoring the Workflow

Watch the workflow progress:
```bash
# View workflow runs
gh run list --workflow=release.yml

# View specific run
gh run view <run-id>

# View logs
gh run view <run-id> --log
```

---

## Method 2: Manual Release

Use this method if you need more control or the automated workflow isn't available.

### Step 1: Create a Release

### 1.1 Update Version

Update the `VERSION` variable in `gh-commit-ai`:

```bash
# In gh-commit-ai script
VERSION="1.0.0"
```

### 1.2 Create Git Tag

```bash
# Create an annotated tag
git tag -a v1.0.0 -m "Release v1.0.0"

# Push the tag
git push origin v1.0.0
```

### 1.3 Create GitHub Release

```bash
# Using GitHub CLI
gh release create v1.0.0 \
  --title "v1.0.0" \
  --notes "Release notes here..."

# Or create manually at:
# https://github.com/nathanaelphilip/gh-commit-ai/releases/new
```

## Step 2: Update Formula SHA256

After creating the release, update the formula with the correct SHA256:

```bash
./scripts/update-formula-sha.sh 1.0.0
```

This script will:
1. Download the release tarball
2. Calculate SHA256
3. Update `Formula/gh-commit-ai.rb` with the correct hash

Review the changes:

```bash
git diff Formula/gh-commit-ai.rb
```

Commit the updated formula:

```bash
git add Formula/gh-commit-ai.rb
git commit -m "chore: update formula to v1.0.0 with SHA256"
git push
```

## Step 3: Create Homebrew Tap Repository

### 3.1 Create New Repository

Create a new repository named `homebrew-gh-commit-ai`:

```bash
# Using GitHub CLI
gh repo create homebrew-gh-commit-ai --public --description "Homebrew tap for gh-commit-ai"

# Or create manually at:
# https://github.com/new
```

**Important naming:**
- Repository must be named `homebrew-<tap-name>`
- For this project: `homebrew-gh-commit-ai`
- Users will tap it with: `brew tap nathanaelphilip/gh-commit-ai`

### 3.2 Clone and Setup Tap Repository

```bash
# Clone the new tap repository
git clone https://github.com/nathanaelphilip/homebrew-gh-commit-ai.git
cd homebrew-gh-commit-ai

# Create Formula directory
mkdir -p Formula

# Copy formula from main repository
cp ../gh-commit-ai/Formula/gh-commit-ai.rb Formula/

# Create README
cat > README.md <<'EOF'
# Homebrew Tap for gh-commit-ai

Homebrew tap for [gh-commit-ai](https://github.com/nathanaelphilip/gh-commit-ai), an AI-powered git commit message generator.

## Installation

```bash
brew tap nathanaelphilip/gh-commit-ai
brew install gh-commit-ai
```

## Usage

See the [main repository](https://github.com/nathanaelphilip/gh-commit-ai) for documentation.

## Updating

To update the formula after a new release:

1. Update version and SHA256 in `Formula/gh-commit-ai.rb`
2. Test locally: `brew install --build-from-source ./Formula/gh-commit-ai.rb`
3. Commit and push changes

EOF

# Commit and push
git add .
git commit -m "feat: initial formula for gh-commit-ai v1.0.0"
git push origin main
```

## Step 4: Test Installation

### 4.1 Test from Tap

```bash
# Add your tap
brew tap nathanaelphilip/gh-commit-ai

# Install
brew install gh-commit-ai

# Test
gh-commit-ai --version
gh-commit-ai --help
```

### 4.2 Test in Clean Environment

For thorough testing, test in a Docker container or fresh VM:

```dockerfile
FROM ubuntu:latest
RUN apt-get update && apt-get install -y curl git
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
RUN brew tap nathanaelphilip/gh-commit-ai
RUN brew install gh-commit-ai
RUN gh-commit-ai --version
```

### 4.3 Uninstall Test

```bash
brew uninstall gh-commit-ai
brew untap nathanaelphilip/gh-commit-ai
```

## Step 5: Update Main Repository Documentation

Update the main repository README to reference the Homebrew installation:

```markdown
## Installation

### Homebrew (Recommended)

\`\`\`bash
brew tap nathanaelphilip/gh-commit-ai
brew install gh-commit-ai
\`\`\`
```

## Subsequent Releases

For future releases, follow this process:

### 1. Update Version

```bash
# Update VERSION in gh-commit-ai script
vim gh-commit-ai

# Commit changes
git add gh-commit-ai
git commit -m "chore: bump version to 1.1.0"
git push
```

### 2. Create Release

```bash
git tag -a v1.1.0 -m "Release v1.1.0"
git push origin v1.1.0
gh release create v1.1.0 --title "v1.1.0" --notes "Release notes..."
```

### 3. Update Formula

```bash
# Update SHA256
./scripts/update-formula-sha.sh 1.1.0

# Commit formula changes
git add Formula/gh-commit-ai.rb
git commit -m "chore: update formula to v1.1.0"
git push
```

### 4. Update Tap Repository

```bash
cd ../homebrew-gh-commit-ai

# Copy updated formula
cp ../gh-commit-ai/Formula/gh-commit-ai.rb Formula/

# Commit and push
git add Formula/gh-commit-ai.rb
git commit -m "feat: update to v1.1.0"
git push
```

### 5. Test Update

```bash
brew update
brew upgrade gh-commit-ai
gh-commit-ai --version  # Should show new version
```

## Troubleshooting

### Formula Audit Failures

Run audit to check for issues:

```bash
cd homebrew-gh-commit-ai
brew audit --strict Formula/gh-commit-ai.rb
```

Common issues:
- Incorrect SHA256 (run update-formula-sha.sh again)
- Missing license file in repository
- URL points to non-existent release

### Installation Failures

Check formula syntax:

```bash
ruby -c Formula/gh-commit-ai.rb
```

Test installation with verbose output:

```bash
brew install --verbose --build-from-source ./Formula/gh-commit-ai.rb
```

### SHA256 Mismatch

If users report SHA256 mismatch:

1. Verify the release tarball URL is correct
2. Re-download and recalculate:
   ```bash
   ./scripts/update-formula-sha.sh <version>
   ```
3. Update tap repository with correct SHA256

## Best Practices

1. **Test Before Pushing**: Always test formula locally before pushing to tap
2. **Version Tags**: Use annotated tags (`-a`) for releases
3. **Changelog**: Maintain CHANGELOG.md with release notes
4. **Semantic Versioning**: Follow semver (MAJOR.MINOR.PATCH)
5. **Formula Updates**: Update tap within 24 hours of main release
6. **Communication**: Announce releases in GitHub Releases

## Automation (Future)

Consider setting up GitHub Actions to automate:

1. Formula SHA256 updates on release
2. Automatic tap repository updates
3. Installation testing in CI/CD
4. Release notes generation

Example workflow:

```yaml
name: Update Homebrew Formula

on:
  release:
    types: [published]

jobs:
  update-formula:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Update Formula
        run: ./scripts/update-formula-sha.sh ${{ github.event.release.tag_name }}
      # ... more steps to push to tap repo
```

## Support

- Issues: https://github.com/nathanaelphilip/gh-commit-ai/issues
- Tap Issues: https://github.com/nathanaelphilip/homebrew-gh-commit-ai/issues
