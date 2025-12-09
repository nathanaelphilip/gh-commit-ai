#!/usr/bin/env bash

# Performance benchmarking script for gh-commit-ai
# Measures time spent in various git operations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== gh-commit-ai Performance Benchmark ===${NC}\n"

# Check if we're in a git repo
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: Not in a git repository"
    exit 1
fi

# Function to measure time (using time command)
measure() {
    local label="$1"
    shift
    echo -n "  $label: "
    local result=$( (time "$@" >/dev/null 2>&1) 2>&1 | grep real | awk '{print $2}' | sed 's/0m//' | sed 's/s//' | awk '{printf "%.0f", $1 * 1000}')
    echo -e "${GREEN}${result}ms${NC}"
    echo "$result"
}

# Create test scenario
echo -e "${YELLOW}Setting up test scenario...${NC}"

# Save current state
STASH_OUTPUT=$(git stash push -m "benchmark-temp" 2>&1 || echo "")

# Create a test file
TEST_FILE=".benchmark_test_$$"
cat > "$TEST_FILE" << 'EOF'
# Test file for benchmarking
This file will be deleted after benchmarking

function test1() {
    console.log("Test function 1");
}

function test2() {
    console.log("Test function 2");
}

EOF

git add -f "$TEST_FILE" 2>&1 >/dev/null || true

echo -e "${GREEN}Test scenario ready${NC}\n"

# Benchmark individual git operations
echo -e "${YELLOW}1. Individual Git Operations${NC}"

t1=$(measure "git status --short" git status --short)
t2=$(measure "git diff --cached" git diff --cached)
t3=$(measure "git diff --cached --numstat" git diff --cached --numstat)
t4=$(measure "git diff --cached --stat" git diff --cached --stat)
t5=$(measure "git rev-parse --abbrev-ref HEAD" git rev-parse --abbrev-ref HEAD)
t6=$(measure "git log -n 50 --pretty=format:%s" git log -n 50 --pretty=format:'%s')

echo ""

# Simulate current workflow
echo -e "${YELLOW}2. Current Workflow (Multiple Git Calls)${NC}"
echo -n "  Running workflow... "
start=$(perl -MTime::HiRes=time -e 'print time()' 2>/dev/null)
{
    git diff --cached --numstat >/dev/null 2>&1
    git status --short >/dev/null 2>&1
    git diff --cached >/dev/null 2>&1
    git rev-parse --abbrev-ref HEAD >/dev/null 2>&1
}
end=$(perl -MTime::HiRes=time -e 'print time()' 2>/dev/null)
current_total=$(perl -e "printf '%.0f', ($end - $start) * 1000" 2>/dev/null)
echo -e "${GREEN}${current_total}ms${NC}"

echo ""

# Simulate optimized workflow
echo -e "${YELLOW}3. Optimized Workflow (Reduced Git Calls)${NC}"
echo -n "  Running optimized... "
start=$(perl -MTime::HiRes=time -e 'print time()' 2>/dev/null)
{
    # Single git diff call with parsing
    git diff --cached --numstat >/dev/null 2>&1
    # Branch name
    git rev-parse --abbrev-ref HEAD >/dev/null 2>&1
}
end=$(perl -MTime::HiRes=time -e 'print time()' 2>/dev/null)
optimized_total=$(perl -e "printf '%.0f', ($end - $start) * 1000" 2>/dev/null)
echo -e "${GREEN}${optimized_total}ms${NC}"

echo ""

# Calculate savings
savings=$((current_total - optimized_total))
if [ "$current_total" -gt 0 ]; then
    percentage=$((savings * 100 / current_total))
else
    percentage=0
fi

# Cleanup
echo -e "${YELLOW}Cleaning up...${NC}"
git reset HEAD "$TEST_FILE" >/dev/null 2>&1 || true
rm -f "$TEST_FILE"

# Restore stash if we created one
if [[ "$STASH_OUTPUT" != "No local changes to save" ]] && [[ -n "$STASH_OUTPUT" ]]; then
    git stash pop >/dev/null 2>&1 || true
fi

echo -e "${GREEN}Done!${NC}\n"

# Summary
echo -e "${BLUE}=== Performance Summary ===${NC}"
echo ""
echo "Individual operations:"
echo "  git status:          ${t1}ms"
echo "  git diff (full):     ${t2}ms"
echo "  git diff --numstat:  ${t3}ms"
echo "  git diff --stat:     ${t4}ms"
echo "  git branch:          ${t5}ms"
echo "  git log (50):        ${t6}ms"
echo ""
echo "Workflow comparison:"
echo "  Current workflow:    ${current_total}ms"
echo "  Optimized workflow:  ${optimized_total}ms"
echo "  Improvement:         ${GREEN}${savings}ms (${percentage}% faster)${NC}"
echo ""
echo "Key optimizations:"
echo "  - Eliminate redundant git diff --cached call"
echo "  - Eliminate git status --short (parse from diff)"
echo "  - Keep only essential: numstat + branch name"
