#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE_APP="$ROOT/outputs/Codex Monitor.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/Codex Monitor.app"

"$ROOT/scripts/build-app.sh"

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP"
ditto "$SOURCE_APP" "$INSTALLED_APP"

pkill -x CodexMenuBar 2>/dev/null || true
open "$INSTALLED_APP"

sleep 2
if pgrep -x CodexMenuBar >/dev/null; then
    echo "Codex Monitor installed and running: $INSTALLED_APP"
else
    echo "Codex Monitor was installed but did not start: $INSTALLED_APP" >&2
    exit 1
fi
