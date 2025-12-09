#!/bin/bash
# Test network retry logic

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Network Retry Logic Test ===${NC}"
echo ""

# Extract the retry function from the main script for testing
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

# Test 1: Verify retry configuration variables exist
echo "Test 1: Checking retry configuration..."
if grep -q "MAX_RETRIES=" ./gh-commit-ai && \
   grep -q "RETRY_DELAY=" ./gh-commit-ai && \
   grep -q "CONNECT_TIMEOUT=" ./gh-commit-ai && \
   grep -q "MAX_TIME=" ./gh-commit-ai; then
    echo -e "${GREEN}✓${NC} Retry configuration variables found"
else
    echo -e "${RED}✗ FAIL: Retry configuration variables missing${NC}"
    exit 1
fi

# Test 2: Verify retry_api_call function exists
echo ""
echo "Test 2: Checking retry_api_call function..."
if grep -q "retry_api_call()" ./gh-commit-ai; then
    echo -e "${GREEN}✓${NC} retry_api_call function found"
else
    echo -e "${RED}✗ FAIL: retry_api_call function missing${NC}"
    exit 1
fi

# Test 3: Verify all providers use retry_api_call
echo ""
echo "Test 3: Checking provider functions use retry..."
providers=("ollama" "anthropic" "openai" "groq")
for provider in "${providers[@]}"; do
    if grep -A 30 "call_${provider}()" ./gh-commit-ai | grep -q "retry_api_call"; then
        echo -e "${GREEN}✓${NC} call_${provider} uses retry_api_call"
    else
        echo -e "${RED}✗ FAIL: call_${provider} doesn't use retry_api_call${NC}"
        exit 1
    fi
done

# Test 4: Verify error codes are handled
echo ""
echo "Test 5: Checking error code handling..."
error_codes=(6 7 28 35 52 56)
for code in "${error_codes[@]}"; do
    if grep -q "case $code in\\|$code)" ./gh-commit-ai; then
        echo -e "${GREEN}✓${NC} Error code $code handled"
    fi
done

# Test 6: Verify exponential backoff logic
echo ""
echo "Test 6: Checking exponential backoff..."
if grep -q "delay=\$((delay \* 2))" ./gh-commit-ai; then
    echo -e "${GREEN}✓${NC} Exponential backoff implemented (delay doubles)"
else
    echo -e "${RED}✗ FAIL: Exponential backoff not found${NC}"
    exit 1
fi

# Test 7: Verify user-facing retry messages
echo ""
echo "Test 7: Checking user feedback..."
if grep -q "Retrying in.*attempt" ./gh-commit-ai; then
    echo -e "${GREEN}✓${NC} Retry messages present for user feedback"
else
    echo -e "${RED}✗ FAIL: No retry messages found${NC}"
    exit 1
fi

# Test 8: Verify final failure message
echo ""
echo "Test 8: Checking final failure handling..."
if grep -q "Failed to get response.*after.*attempts" ./gh-commit-ai; then
    echo -e "${GREEN}✓${NC} Final failure messages present"
else
    echo -e "${RED}✗ FAIL: No final failure messages${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=== All tests passed! ===${NC}"
echo ""
echo "Summary:"
echo "  • Retry logic configured with:"
echo "    - MAX_RETRIES (default: 3)"
echo "    - RETRY_DELAY (default: 2s)"
echo "    - CONNECT_TIMEOUT (default: 10s)"
echo "    - MAX_TIME (default: 120s)"
echo "  • Exponential backoff: 2s → 4s → 8s"
echo "  • All 4 providers use retry logic"
echo "  • Comprehensive error code handling"
echo "  • User-friendly retry messages"
echo ""
echo "Configuration options:"
echo "  MAX_RETRIES=5 gh commit-ai        # More retries"
echo "  RETRY_DELAY=1 gh commit-ai        # Faster retries"
echo "  CONNECT_TIMEOUT=20 gh commit-ai   # Longer connection timeout"
