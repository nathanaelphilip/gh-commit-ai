#!/usr/bin/env bash

set -e

VERSION="1.0.0"

# Colors for output (simplified palette)
RED='\033[38;2;174;32;18m'     # #AE2012 (errors only)
NC='\033[0m' # No Color

# fd 3 = live-progress channel (spinner / streaming arrow). Kept separate from
# stderr (fd 2) so provider error output on fd 2 can be captured and logged
# without hiding the progress indicator. Defaults to the real stderr (terminal).
exec 3>&2

