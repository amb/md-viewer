#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/swift-module-cache"
swift test --disable-sandbox --cache-path .build/cache
./build_app.sh
python3 scripts/check_diagrams.py
python3 scripts/check_viewer.py
"dist/MD View.app/Contents/MacOS/MDView" --preview "$PWD/examples/demo.md" "$PWD/.build/preview.png"
codesign --verify --strict "dist/MD View.app"
./scripts/check_linkage.sh "dist/MD View.app/Contents/MacOS/MDView"
echo "All checks passed; offscreen preview: .build/preview.png"
