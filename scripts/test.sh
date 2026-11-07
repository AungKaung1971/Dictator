#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache .build/cache .build/checks
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
# A standalone runner works with Command Line Tools; XCTest requires full Xcode.
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache"
BIN_PATH=$(swift build -c release --show-bin-path --disable-sandbox --cache-path "$PWD/.build/cache")
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$PWD/.build/module-cache" \
    -I "$BIN_PATH/Modules" "$BIN_PATH"/DictatorCore.build/*.swift.o \
    Sources/Dictator/ShortcutMonitor.swift Tests/Checks.swift -o .build/checks/DictatorChecks
.build/checks/DictatorChecks
