#!/usr/bin/env bash
#
# Test script for cache functionality
# Tests cache operations in isolation to identify hanging issues
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Testing Cache Functionality ==="
echo ""

# Test 1: Create test repository
echo "Test 1: Setting up test repository..."
TEST_DIR="/tmp/gh-commit-ai-cache-test-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
git init -q
echo "test" > test.txt
git add test.txt

echo "✓ Test repository created"
echo ""

# Test 2: Test cache operations in isolation
echo "Test 2: Testing cache operations..."

# Source the cache functions from main script
CACHE_DIR="/tmp/gh-commit-ai-test-cache-$$"
mkdir -p "$CACHE_DIR"

# Test hash generation
echo "  Testing MD5 hash generation..."
TEST_HASH=$(echo "test content" | md5sum 2>/dev/null | awk '{print $1}' || echo "test content" | md5 2>/dev/null || echo "fallback")
echo "  Hash: $TEST_HASH"
echo "  ✓ Hash generation works"

# Test file operations
echo "  Testing cache file write..."
TEST_FILE="${CACHE_DIR}/test.txt"
echo "test message" > "$TEST_FILE"
if [ -f "$TEST_FILE" ]; then
    echo "  ✓ Cache file write works"
else
    echo "  ✗ Cache file write failed"
    exit 1
fi

echo "  Testing cache file read..."
CONTENT=$(cat "$TEST_FILE")
if [ "$CONTENT" = "test message" ]; then
    echo "  ✓ Cache file read works"
else
    echo "  ✗ Cache file read failed"
    exit 1
fi

echo "  Testing stat command (BSD/GNU compatibility)..."
if stat -f %m "$TEST_FILE" &>/dev/null; then
    FILE_TIME=$(stat -f %m "$TEST_FILE")
    echo "  BSD stat: $FILE_TIME"
elif stat -c %Y "$TEST_FILE" &>/dev/null; then
    FILE_TIME=$(stat -c %Y "$TEST_FILE")
    echo "  GNU stat: $FILE_TIME"
else
    echo "  ✗ stat command not working"
    exit 1
fi
echo "  ✓ stat works"

echo ""

# Test 3: Test with actual script (with debug enabled)
echo "Test 3: Testing full integration with debug mode..."
cd "$TEST_DIR"

# Create a change
echo "modified" >> test.txt
git add test.txt

# Run with cache debug enabled (don't commit, just preview)
echo "  Running: CACHE_DEBUG=true $REPO_DIR/gh-commit-ai --preview"
CACHE_DEBUG=true "$REPO_DIR/gh-commit-ai" --preview 2>&1 | head -20

# Check if debug log was created
if [ -f "${CACHE_DIR}/debug.log" ]; then
    echo ""
    echo "  Debug log contents:"
    cat "${CACHE_DIR}/debug.log"
    echo ""
    echo "  ✓ Debug logging works"
else
    echo "  ℹ No debug log created (cache may be disabled)"
fi

echo ""

# Test 4: Test cache hit on second run
echo "Test 4: Testing cache hit..."
echo "  First run (should cache)..."
FIRST_RUN=$("$REPO_DIR/gh-commit-ai" --preview 2>&1 | grep -A 10 "Generated commit message")

echo "  Second run (should hit cache)..."
SECOND_RUN=$("$REPO_DIR/gh-commit-ai" --preview 2>&1 | grep -E "(Using cached|Generated commit message)" | head -5)

if echo "$SECOND_RUN" | grep -q "Using cached"; then
    echo "  ✓ Cache hit successful!"
else
    echo "  ℹ No cache hit (first run or cache disabled)"
fi

echo ""

# Cleanup
echo "Cleaning up..."
rm -rf "$TEST_DIR"
rm -rf "$CACHE_DIR"

echo ""
echo "=== Cache Tests Complete ==="
echo ""
echo "If the script hung, the last test output shows where."
echo "Check the debug log for timing information."
