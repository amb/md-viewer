#!/bin/zsh
set -eu
binary="${1:-dist/MD View.app/Contents/MacOS/MDView}"
linked_libraries=$(/usr/bin/otool -L "$binary")
if [[ "$linked_libraries" == *WebKit* || "$linked_libraries" == *JavaScriptCore* ]]; then
  echo "Reader unexpectedly links a browser engine: $binary" >&2
  exit 1
fi
