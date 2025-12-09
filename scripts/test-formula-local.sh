#!/bin/bash
# Script to test the Homebrew formula locally
# This simulates the installation process without creating an actual tap

set -e

echo "=== Testing gh-commit-ai Homebrew Formula ==="
echo ""

FORMULA_PATH="Formula/gh-commit-ai.rb"

if [ ! -f "$FORMULA_PATH" ]; then
    echo "Error: Formula not found at $FORMULA_PATH"
    exit 1
fi

echo "1. Checking Ruby syntax..."
if ruby -c "$FORMULA_PATH" > /dev/null 2>&1; then
    echo "   ✓ Syntax OK"
else
    echo "   ✗ Syntax error"
    exit 1
fi

echo ""
echo "2. Verifying formula structure..."

# Check for required fields
missing_fields=()

grep -q 'class GhCommitAi < Formula' "$FORMULA_PATH" || missing_fields+=("class definition")
grep -q 'desc "' "$FORMULA_PATH" || missing_fields+=("desc")
grep -q 'homepage "' "$FORMULA_PATH" || missing_fields+=("homepage")
grep -q 'url "' "$FORMULA_PATH" || missing_fields+=("url")
grep -q 'license "' "$FORMULA_PATH" || missing_fields+=("license")
grep -q 'def install' "$FORMULA_PATH" || missing_fields+=("install method")
grep -q 'test do' "$FORMULA_PATH" || missing_fields+=("test block")

if [ ${#missing_fields[@]} -eq 0 ]; then
    echo "   ✓ All required fields present"
else
    echo "   ✗ Missing fields: ${missing_fields[*]}"
    exit 1
fi

echo ""
echo "3. Checking dependencies..."
if command -v gh &> /dev/null; then
    echo "   ✓ GitHub CLI (gh) is installed"
else
    echo "   ⚠ GitHub CLI (gh) not found - formula requires it"
fi

echo ""
echo "4. Verifying file structure..."

REQUIRED_FILES=(
    "gh-commit-ai"
    "completions/gh-commit-ai.bash"
    "completions/_gh-commit-ai"
    ".gh-commit-ai.example.yml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -e "$file" ]; then
        echo "   ✓ $file exists"
    else
        echo "   ✗ $file missing"
        exit 1
    fi
done

echo ""
echo "5. Testing main script..."
if bash -n gh-commit-ai; then
    echo "   ✓ Script syntax OK"
else
    echo "   ✗ Script syntax error"
    exit 1
fi

echo ""
echo "=== All checks passed! ==="
echo ""
echo "To test installation locally:"
echo "  1. Create a local tap: brew tap-new $USER/local-test"
echo "  2. Extract formula: brew extract gh-commit-ai $USER/local-test"
echo "  3. Install: brew install $USER/local-test/gh-commit-ai"
echo ""
echo "Note: Full installation testing requires a GitHub release with tarball."
echo ""
echo "Next steps:"
echo "  1. Create a git tag: git tag -a v1.0.0 -m 'Release v1.0.0'"
echo "  2. Push tag: git push origin v1.0.0"
echo "  3. Update formula SHA: ./scripts/update-formula-sha.sh 1.0.0"
echo "  4. Create tap repository: github.com/$USER/homebrew-gh-commit-ai"
echo "  5. Copy Formula/ directory to tap repository"
