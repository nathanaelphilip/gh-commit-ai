#!/bin/bash
# Script to update Homebrew formula SHA256 after creating a release

set -e

VERSION="${1:-}"
PROVIDED_SHA256="${2:-}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version> [sha256]"
    echo "Example: $0 1.0.0"
    echo "Example: $0 1.0.0 abc123..."
    exit 1
fi

# Remove 'v' prefix if present
VERSION="${VERSION#v}"

TARBALL_URL="https://github.com/nathanaelphilip/gh-commit-ai/archive/refs/tags/v${VERSION}.tar.gz"
FORMULA_FILE="Formula/gh-commit-ai.rb"

# Calculate SHA256 if not provided
if [ -n "$PROVIDED_SHA256" ]; then
    SHA256="$PROVIDED_SHA256"
    echo "Using provided SHA256: $SHA256"
else
    echo "Downloading release tarball for v${VERSION}..."
    TEMP_FILE=$(mktemp)
    curl -sL "$TARBALL_URL" -o "$TEMP_FILE"

    echo "Calculating SHA256..."
    if command -v shasum &> /dev/null; then
        SHA256=$(shasum -a 256 "$TEMP_FILE" | awk '{print $1}')
    elif command -v sha256sum &> /dev/null; then
        SHA256=$(sha256sum "$TEMP_FILE" | awk '{print $1}')
    else
        echo "Error: Neither shasum nor sha256sum found"
        rm -f "$TEMP_FILE"
        exit 1
    fi

    rm -f "$TEMP_FILE"
fi

echo ""
echo "SHA256: $SHA256"
echo ""

# Update formula file
if [ -f "$FORMULA_FILE" ]; then
    echo "Updating $FORMULA_FILE..."

    # Detect if we're using GNU or BSD sed
    if sed --version 2>&1 | grep -q "GNU"; then
        # GNU sed
        sed -i "s/version \".*\"/version \"${VERSION}\"/" "$FORMULA_FILE"
        sed -i "s|url \".*\"|url \"${TARBALL_URL}\"|" "$FORMULA_FILE"
        sed -i "s/sha256 \".*\"/sha256 \"${SHA256}\"/" "$FORMULA_FILE"
    else
        # BSD sed (macOS)
        sed -i '' "s/version \".*\"/version \"${VERSION}\"/" "$FORMULA_FILE"
        sed -i '' "s|url \".*\"|url \"${TARBALL_URL}\"|" "$FORMULA_FILE"
        sed -i '' "s/sha256 \".*\"/sha256 \"${SHA256}\"/" "$FORMULA_FILE"
    fi

    echo "✓ Formula updated successfully!"
    echo ""
    echo "Changes made:"
    echo "  - Version: ${VERSION}"
    echo "  - URL: ${TARBALL_URL}"
    echo "  - SHA256: ${SHA256}"
    echo ""
    echo "Next steps:"
    echo "  1. Review changes: git diff $FORMULA_FILE"
    echo "  2. Test formula: brew install --build-from-source ./$FORMULA_FILE"
    echo "  3. Commit changes: git add $FORMULA_FILE && git commit -m 'chore: update formula to v${VERSION}'"
else
    echo "Error: Formula file not found at $FORMULA_FILE"
    exit 1
fi
