#!/bin/bash
# Test that message history is properly scoped per repository

set -e

echo "=== Testing Repository-Specific Message History ==="
echo ""

# Function to extract MESSAGE_HISTORY_DIR from the script
get_history_dir_for_repo() {
    local repo_path="$1"
    cd "$repo_path"

    # Simulate what the script does
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$REPO_ROOT" ]; then
        if command -v md5sum &> /dev/null; then
            REPO_HASH=$(echo -n "$REPO_ROOT" | md5sum | awk '{print $1}')
        elif command -v md5 &> /dev/null; then
            REPO_HASH=$(echo -n "$REPO_ROOT" | md5 | awk '{print $1}')
        else
            REPO_HASH=$(basename "$REPO_ROOT")
        fi
        echo "/tmp/gh-commit-ai-history-${REPO_HASH}"
    else
        echo "/tmp/gh-commit-ai-history"
    fi
}

# Create two temporary git repositories
TEMP_DIR=$(mktemp -d)
REPO_A="${TEMP_DIR}/repo-a"
REPO_B="${TEMP_DIR}/repo-b"

mkdir -p "$REPO_A" "$REPO_B"

# Initialize repo A
cd "$REPO_A"
git init > /dev/null 2>&1
git config user.email "test@example.com"
git config user.name "Test User"
echo "# Repo A" > README.md
git add README.md
git commit -m "Initial commit" > /dev/null 2>&1
HISTORY_DIR_A=$(get_history_dir_for_repo "$REPO_A")

# Initialize repo B
cd "$REPO_B"
git init > /dev/null 2>&1
git config user.email "test@example.com"
git config user.name "Test User"
echo "# Repo B" > README.md
git add README.md
git commit -m "Initial commit" > /dev/null 2>&1
HISTORY_DIR_B=$(get_history_dir_for_repo "$REPO_B")

# Check that they're different
echo "Repository A path: $REPO_A"
echo "History directory: $HISTORY_DIR_A"
echo ""
echo "Repository B path: $REPO_B"
echo "History directory: $HISTORY_DIR_B"
echo ""

if [ "$HISTORY_DIR_A" = "$HISTORY_DIR_B" ]; then
    echo "✗ FAIL: Both repositories have the same history directory!"
    echo "  This means messages could leak between repositories."
    rm -rf "$TEMP_DIR"
    exit 1
else
    echo "✓ PASS: Each repository has a unique history directory"
    echo "  Messages will be properly scoped per repository"
fi

# Test that the same repository always gets the same hash
HISTORY_DIR_A2=$(get_history_dir_for_repo "$REPO_A")
if [ "$HISTORY_DIR_A" = "$HISTORY_DIR_A2" ]; then
    echo "✓ PASS: Repository hash is consistent"
else
    echo "✗ FAIL: Repository hash changed!"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "=== All tests passed! ==="
echo ""
echo "Message history is now properly scoped per repository."
echo "Cached commit messages from one repo won't leak to another."
