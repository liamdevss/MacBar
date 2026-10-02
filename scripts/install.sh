#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
osascript -e 'tell application id "dev.macbar.launcher" to quit' 2>/dev/null || true
sleep 1
pkill -x MacBar 2>/dev/null || true
bash scripts/build.sh
rm -rf "$HOME/Desktop/MacBar.app"
cp -R build/MacBar.app "$HOME/Desktop/MacBar.app"
open "$HOME/Desktop/MacBar.app"
printf 'Installed %s\n' "$HOME/Desktop/MacBar.app"
