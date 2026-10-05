#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
build_options=(--cache-path .build/package-cache --config-path .build/config --security-path .build/security)
build_options+=("$@")
configuration="${DOCKTOGGLE_CONFIGURATION:-release}"
swift build "${build_options[@]}" -c "$configuration" --product DockToggle
bin_dir=$(swift build "${build_options[@]}" -c "$configuration" --show-bin-path)
app_path="$PWD/build/DockToggle.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_dir/DockToggle" "$app_path/Contents/MacOS/DockToggle"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
# Set DOCKTOGGLE_SIGN_IDENTITY to a local Apple Development identity to keep
# a certificate-backed signing identity across rebuilds. Ad-hoc is the default.
codesign --force --sign "${DOCKTOGGLE_SIGN_IDENTITY:--}" --identifier dev.nojusl.DockToggle "$app_path"
codesign --verify --strict "$app_path"
printf 'Built %s\n' "$app_path"
