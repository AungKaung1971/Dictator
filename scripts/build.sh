#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--universal" ) ]]; then
    echo "Usage: $0 [--universal]" >&2
    exit 2
fi
mkdir -p .build/module-cache .build/cache build
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
# Sign outside Desktop/iCloud: File Provider metadata can invalidate loose bundles.
STAGING_DIR=$(mktemp -d /private/tmp/dictator-build.XXXXXX)
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/Dictator.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
if [[ "${1:-}" == "--universal" ]]; then
    for ARCH in x86_64 arm64; do
        TRIPLE="$ARCH-apple-macosx13.0"
        swift build -c release --triple "$TRIPLE" --disable-sandbox --cache-path "$PWD/.build/cache"
        BIN_PATH=$(swift build -c release --triple "$TRIPLE" --show-bin-path --disable-sandbox --cache-path "$PWD/.build/cache")
        cp -X "$BIN_PATH/Dictator" "$STAGING_DIR/Dictator-$ARCH"
    done
    xcrun lipo -create "$STAGING_DIR/Dictator-x86_64" "$STAGING_DIR/Dictator-arm64" -output "$STAGED_APP/Contents/MacOS/Dictator"
    xcrun lipo -verify_arch x86_64 arm64 "$STAGED_APP/Contents/MacOS/Dictator"
else
    swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache"
    BIN_PATH=$(swift build -c release --show-bin-path --disable-sandbox --cache-path "$PWD/.build/cache")
    cp -X "$BIN_PATH/Dictator" "$STAGED_APP/Contents/MacOS/Dictator"
fi
xcrun strip -S "$STAGED_APP/Contents/MacOS/Dictator"
cp -X Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
if [[ -n "${DICTATOR_SIGNING_IDENTITY:-}" ]]; then
    codesign --force --sign "$DICTATOR_SIGNING_IDENTITY" --options runtime --entitlements Resources/Dictator.entitlements "$STAGED_APP"
else
    python3 scripts/sign-local.py "$STAGED_APP"
fi
codesign --verify --strict "$STAGED_APP"
ditto -c -k --keepParent --noextattr --norsrc "$STAGED_APP" "$PWD/build/Dictator.zip"
echo "Built and verified: $PWD/build/Dictator.zip"
