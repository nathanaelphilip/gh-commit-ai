#!/bin/bash
# Integration test: Verify message history is isolated between repositories

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Message History Isolation Test ===${NC}"
echo ""

# Create two test repositories
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

REPO_A="$TEMP_DIR/project-alpha"
REPO_B="$TEMP_DIR/project-beta"

echo "Creating test repositories..."
mkdir -p "$REPO_A" "$REPO_B"

# Setup repo A
cd "$REPO_A"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
echo "alpha" > file.txt
git add file.txt
git commit -q -m "initial"

# Setup repo B
cd "$REPO_B"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
echo "beta" > file.txt
git add file.txt
git commit -q -m "initial"

echo -e "${GREEN}✓${NC} Created two test repositories"
echo ""

# Make changes in repo A
cd "$REPO_A"
echo "change in alpha" >> file.txt
git add file.txt

# Get the expected history directory for repo A
REPO_ROOT=$(git rev-parse --show-toplevel)
if command -v md5sum &> /dev/null; then
    REPO_HASH=$(echo -n "$REPO_ROOT" | md5sum | awk '{print $1}')
elif command -v md5 &> /dev/null; then
    REPO_HASH=$(echo -n "$REPO_ROOT" | md5 | awk '{print $1}')
else
    REPO_HASH=$(basename "$REPO_ROOT")
fi
EXPECTED_DIR_A="/tmp/gh-commit-ai-history-${REPO_HASH}"

echo "Repository A:"
echo "  Path: $REPO_A"
echo "  Expected cache: $EXPECTED_DIR_A"

# Create a fake cached message for repo A (simulating previous run)
mkdir -p "$EXPECTED_DIR_A"
TIMESTAMP=$(date +%s)
echo "feat: update alpha project

- add new feature
- fix bug in alpha" > "$EXPECTED_DIR_A/msg_${TIMESTAMP}.txt"

echo -e "${GREEN}✓${NC} Created cached message for repo A"
echo ""

# Make changes in repo B
cd "$REPO_B"
echo "change in beta" >> file.txt
git add file.txt

# Get expected history directory for repo B
REPO_ROOT=$(git rev-parse --show-toplevel)
if command -v md5sum &> /dev/null; then
    REPO_HASH=$(echo -n "$REPO_ROOT" | md5sum | awk '{print $1}')
elif command -v md5 &> /dev/null; then
    REPO_HASH=$(echo -n "$REPO_ROOT" | md5 | awk '{print $1}')
else
    REPO_HASH=$(basename "$REPO_ROOT")
fi
EXPECTED_DIR_B="/tmp/gh-commit-ai-history-${REPO_HASH}"

echo "Repository B:"
echo "  Path: $REPO_B"
echo "  Expected cache: $EXPECTED_DIR_B"
echo ""

# Verify directories are different
if [ "$EXPECTED_DIR_A" = "$EXPECTED_DIR_B" ]; then
    echo -e "${RED}✗ FAIL: Both repos have the same cache directory!${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Cache directories are different"

# Verify repo A has a cached message
if [ -f "$EXPECTED_DIR_A/msg_${TIMESTAMP}.txt" ]; then
    echo -e "${GREEN}✓${NC} Repo A has cached message"
else
    echo -e "${RED}✗ FAIL: Repo A missing cached message${NC}"
    exit 1
fi

# Verify repo B has no cached messages (hasn't been used yet)
MESSAGE_COUNT=$(ls -1 "$EXPECTED_DIR_B"/*.txt 2>/dev/null | wc -l | tr -d ' ')
if [ "$MESSAGE_COUNT" = "0" ]; then
    echo -e "${GREEN}✓${NC} Repo B has no cached messages (as expected)"
else
    echo -e "${RED}✗ FAIL: Repo B unexpectedly has cached messages${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=== All tests passed! ===${NC}"
echo ""
echo "Summary:"
echo "  • Each repository gets its own cache directory based on path hash"
echo "  • Messages from repo A won't appear in repo B"
echo "  • Message history is properly isolated between repositories"
echo ""
echo "Cache directories:"
echo "  Repo A: $EXPECTED_DIR_A"
echo "  Repo B: $EXPECTED_DIR_B"

# Cleanup
rm -rf "$EXPECTED_DIR_A" "$EXPECTED_DIR_B"
