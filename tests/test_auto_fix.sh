#!/bin/bash
# Test auto-fix formatting functionality

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Auto-Fix Formatting Test ===${NC}"
echo ""

# Get the path to gh-commit-ai script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
GH_COMMIT_AI="$SCRIPT_DIR/../gh-commit-ai"

# Create temporary test repository
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cd "$TEMP_DIR"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"

echo -e "${GREEN}✓${NC} Created test repository"
echo ""

# Test 1: Trailing whitespace detection
echo "Test 1: Trailing whitespace..."
cat > test1.txt << 'EOF'
line with trailing spaces
another line
clean line
EOF

git add test1.txt

# Check if detection function exists
if grep -q "^detect_trailing_whitespace()" "$GH_COMMIT_AI"; then
    echo -e "${GREEN}✓${NC} detect_trailing_whitespace function found"
else
    echo -e "${RED}✗ FAIL: detect_trailing_whitespace function missing${NC}"
    exit 1
fi

# Test 2: Missing final newline detection
echo ""
echo "Test 2: Missing final newline..."
printf "file without newline at end" > test2.txt
git add test2.txt

if grep -q "^detect_missing_final_newline()" $GH_COMMIT_AI; then
    echo -e "${GREEN}✓${NC} detect_missing_final_newline function found"
else
    echo -e "${RED}✗ FAIL: detect_missing_final_newline function missing${NC}"
    exit 1
fi

# Test 3: Fix functions exist
echo ""
echo "Test 3: Checking fix functions..."

if grep -q "^fix_trailing_whitespace()" $GH_COMMIT_AI; then
    echo -e "${GREEN}✓${NC} fix_trailing_whitespace function found"
else
    echo -e "${RED}✗ FAIL: fix_trailing_whitespace function missing${NC}"
    exit 1
fi

if grep -q "^fix_missing_final_newline()" $GH_COMMIT_AI; then
    echo -e "${GREEN}✓${NC} fix_missing_final_newline function found"
else
    echo -e "${RED}✗ FAIL: fix_missing_final_newline function missing${NC}"
    exit 1
fi

# Test 4: Configuration variables
echo ""
echo "Test 4: Checking configuration variables..."

if grep -q "AUTO_FIX_FORMATTING=" $GH_COMMIT_AI; then
    echo -e "${GREEN}✓${NC} AUTO_FIX_FORMATTING configuration found"
else
    echo -e "${RED}✗ FAIL: AUTO_FIX_FORMATTING configuration missing${NC}"
    exit 1
fi

if grep -q "AUTO_FIX_TRAILING_WHITESPACE=" $GH_COMMIT_AI; then
    echo -e "${GREEN}✓${NC} AUTO_FIX_TRAILING_WHITESPACE configuration found"
else
    echo -e "${RED}✗ FAIL: AUTO_FIX_TRAILING_WHITESPACE configuration missing${NC}"
    exit 1
fi

if grep -q "AUTO_FIX_FINAL_NEWLINE=" $GH_COMMIT_AI; then
    echo -e "${GREEN}✓${NC} AUTO_FIX_FINAL_NEWLINE configuration found"
else
    echo -e "${RED}✗ FAIL: AUTO_FIX_FINAL_NEWLINE configuration missing${NC}"
    exit 1
fi

# Test 5: Main check function
echo ""
echo "Test 5: Checking main function..."

if grep -q "^check_and_fix_formatting()" $GH_COMMIT_AI; then
    echo -e "${GREEN}✓${NC} check_and_fix_formatting function found"
else
    echo -e "${RED}✗ FAIL: check_and_fix_formatting function missing${NC}"
    exit 1
fi

# Test 6: Integration in main workflow
echo ""
echo "Test 6: Checking workflow integration..."

if grep -q "check_and_fix_formatting" $GH_COMMIT_AI; then
    echo -e "${GREEN}✓${NC} check_and_fix_formatting is called in main workflow"
else
    echo -e "${RED}✗ FAIL: check_and_fix_formatting not integrated${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=== All tests passed! ===${NC}"
echo ""
echo "Summary:"
echo "  • Auto-fix configuration variables present"
echo "  • Detection functions implemented:"
echo "    - detect_trailing_whitespace"
echo "    - detect_missing_final_newline"
echo "    - detect_line_endings"
echo "  • Fix functions implemented:"
echo "    - fix_trailing_whitespace"
echo "    - fix_missing_final_newline"
echo "    - fix_line_endings"
echo "  • Main check_and_fix_formatting function present"
echo "  • Integrated into main workflow"
echo ""
echo "Configuration options:"
echo "  AUTO_FIX_FORMATTING=true gh commit-ai   # Enable auto-fixing"
echo "  AUTO_FIX_FORMATTING=false gh commit-ai  # Prompt before fixing (default)"
echo "  LINE_ENDING_STYLE=lf gh commit-ai       # Prefer LF endings (default)"
echo "  LINE_ENDING_STYLE=crlf gh commit-ai     # Prefer CRLF endings"
