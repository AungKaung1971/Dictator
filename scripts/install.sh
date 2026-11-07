#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if pgrep -x Dictator >/dev/null 2>&1; then
    echo "Quit Dictator from its menu bar icon, then run this script again."
    exit 1
fi
if [[ ! -f build/Dictator.zip ]]; then
    echo "Run ./scripts/build.sh first."
    exit 1
fi
INSTALL_DIR="${1:-$HOME/Applications}"
mkdir -p "$INSTALL_DIR"
ditto -x -k build/Dictator.zip "$INSTALL_DIR"
codesign --verify --strict "$INSTALL_DIR/Dictator.app"
echo "Installed: $INSTALL_DIR/Dictator.app"
