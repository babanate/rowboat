#!/bin/sh
# Builds the debug binary and runs it with logs on stderr, for trying the
# modes by hand. Quit Homerow first or the two will fight over ⇧Space.
set -eu
cd "$(dirname "$0")/.."
swift build 2>&1 | grep -E "error|Build complete" | grep -v '^\[' || true
echo
echo "Rowboat is running. In any app:"
echo "  ⇧Space   click labels   (type a label; ⇧ right-click, ⌘ cmd-click, ⌥ double, ⌫ edit, ⎋ leave)"
echo "  ⇧⌘J     scroll         (h j k l / arrows, ⇧ dash, d u half page, gg G ends, 1-9 pick area)"
echo "  ⇧/      search         (type text, 1-9 or ↩ to click)"
echo "Menu bar icon → Settings. Ctrl-C here to quit."
echo
ROWBOAT_DEBUG=1 exec .build/debug/Rowboat
