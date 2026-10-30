#!/bin/zsh
set -eu
cd "${0:A:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/swift-module-cache"
if [[ ! -f Resources/mermaid.js ]]; then
  npm ci
  npm run bundle
fi
swift build -c release --disable-sandbox --cache-path .build/cache
app="dist/MD View.app/Contents"
mkdir -p "$app/MacOS" "$app/Resources"
cp .build/release/MDView "$app/MacOS/MDView"
cp .build/release/MermaidWorker "$app/MacOS/MermaidWorker"
cp Resources/Info.plist "$app/Info.plist"
cp Resources/diagram.html Resources/mermaid.js "$app/Resources/"
cp Resources/THIRD-PARTY-NOTICES.txt "$app/Resources/"
cp LICENSE "$app/Resources/LICENSE"
codesign --force --sign - "$app/MacOS/MermaidWorker"
codesign --force --sign - "dist/MD View.app"
echo "Built dist/MD View.app"
