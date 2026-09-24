#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/notesmate-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift test --disable-sandbox --scratch-path build/editor-tests --cache-path "${TMPDIR:-/tmp}/notesmate-swift-cache" "$@"
