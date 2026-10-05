#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
test_options=(--cache-path .build/package-cache --config-path .build/config --security-path .build/security)
swift run "${test_options[@]}" "$@" DockToggleTests
