#!/bin/bash
# Builds the TLG Hitchhiker's Guide frontend and stages its dist/ output for
# bundling into the launcher app. Reproducible: pinned Yarn 1, frozen lockfile.
#
# Usage: Scripts/build-guide.sh [path-to-tlg-guide]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUIDE_REPO="${1:-$REPO_ROOT/../tlg-guide}"
STAGED="$REPO_ROOT/GuideDist"

if [[ ! -f "$GUIDE_REPO/package.json" ]]; then
    echo "error: tlg-guide repository not found at $GUIDE_REPO" >&2
    exit 1
fi

echo "Building guide in $GUIDE_REPO..."
(
    cd "$GUIDE_REPO"
    npx --yes yarn@1.22.22 install --frozen-lockfile
    npx --yes yarn@1.22.22 build
)

if [[ ! -f "$GUIDE_REPO/dist/index.html" ]]; then
    echo "error: guide build produced no dist/index.html" >&2
    exit 1
fi

rm -rf "$STAGED"
mkdir -p "$STAGED"
ditto "$GUIDE_REPO/dist" "$STAGED"
echo "Guide staged at $STAGED ($(du -sh "$STAGED" | cut -f1))"
