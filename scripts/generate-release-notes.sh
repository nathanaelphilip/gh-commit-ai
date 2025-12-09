#!/bin/bash
# Generate release notes from commits since last tag

set -e

VERSION_TAG="$1"

if [ -z "$VERSION_TAG" ]; then
    echo "Usage: $0 <version-tag>" >&2
    exit 1
fi

# Get the previous tag
PREVIOUS_TAG=$(git describe --tags --abbrev=0 "$VERSION_TAG^" 2>/dev/null || echo "")

if [ -z "$PREVIOUS_TAG" ]; then
    # First release - use all commits
    COMMIT_RANGE="HEAD"
    RELEASE_TITLE="Initial Release"
else
    COMMIT_RANGE="${PREVIOUS_TAG}..${VERSION_TAG}"
    RELEASE_TITLE="Release ${VERSION_TAG}"
fi

echo "# ${RELEASE_TITLE}"
echo ""
echo "**Full Changelog**: https://github.com/${GITHUB_REPOSITORY}/compare/${PREVIOUS_TAG}...${VERSION_TAG}" 2>/dev/null || echo ""
echo ""

# Extract changelog entries for this version from CHANGELOG.md
if [ -f "CHANGELOG.md" ]; then
    # Try to extract the Unreleased section
    awk '
    /^## \[Unreleased\]/ { in_section=1; next }
    /^## \[/ { in_section=0 }
    in_section && /^### / { print; next }
    in_section && /^- / { print; next }
    in_section && NF { print }
    ' CHANGELOG.md
    echo ""
fi

# Categorize commits
echo "## What's Changed"
echo ""

# Arrays to store commits by category
declare -a features
declare -a fixes
declare -a docs
declare -a chores
declare -a breaking
declare -a other

# Parse commits
while IFS= read -r commit; do
    # Extract commit message (first line only)
    message=$(git log -1 --format=%s "$commit")
    author=$(git log -1 --format="%an" "$commit")

    # Check for breaking changes
    if echo "$message" | grep -qE '^[a-z]+(\([a-z0-9_-]+\))?!:'; then
        breaking+=("- $message by @$author")
    fi

    # Categorize by conventional commit type
    if echo "$message" | grep -qE '^feat(\([a-z0-9_-]+\))?:'; then
        features+=("- $message by @$author")
    elif echo "$message" | grep -qE '^fix(\([a-z0-9_-]+\))?:'; then
        fixes+=("- $message by @$author")
    elif echo "$message" | grep -qE '^docs?(\([a-z0-9_-]+\))?:'; then
        docs+=("- $message by @$author")
    elif echo "$message" | grep -qE '^(chore|build|ci|refactor|style|test|perf)(\([a-z0-9_-]+\))?:'; then
        chores+=("- $message by @$author")
    else
        other+=("- $message by @$author")
    fi
done < <(git rev-list --no-merges $COMMIT_RANGE)

# Print breaking changes first (if any)
if [ ${#breaking[@]} -gt 0 ]; then
    echo "### ⚠️ Breaking Changes"
    echo ""
    printf '%s\n' "${breaking[@]}"
    echo ""
fi

# Print features
if [ ${#features[@]} -gt 0 ]; then
    echo "### ✨ Features"
    echo ""
    printf '%s\n' "${features[@]}"
    echo ""
fi

# Print fixes
if [ ${#fixes[@]} -gt 0 ]; then
    echo "### 🐛 Bug Fixes"
    echo ""
    printf '%s\n' "${fixes[@]}"
    echo ""
fi

# Print documentation
if [ ${#docs[@]} -gt 0 ]; then
    echo "### 📝 Documentation"
    echo ""
    printf '%s\n' "${docs[@]}"
    echo ""
fi

# Print other changes
if [ ${#chores[@]} -gt 0 ]; then
    echo "### 🔧 Maintenance"
    echo ""
    printf '%s\n' "${chores[@]}"
    echo ""
fi

# Print other commits
if [ ${#other[@]} -gt 0 ]; then
    echo "### Other Changes"
    echo ""
    printf '%s\n' "${other[@]}"
    echo ""
fi

# Contributors
echo "## Contributors"
echo ""
echo "Thank you to all contributors who made this release possible:"
echo ""
git log $COMMIT_RANGE --format="%an" | sort -u | while read -r contributor; do
    echo "- @$contributor"
done
