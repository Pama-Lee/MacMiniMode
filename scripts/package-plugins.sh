#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
bash scripts/build-mcp.sh build/macminimode-mcp
codesign --force --sign - build/macminimode-mcp
for client in codex claude-code; do
    mkdir -p "plugins/$client/bin"
    cp build/macminimode-mcp "plugins/$client/bin/macminimode-mcp"
    rm -f "build/macminimode-$client-plugin.zip"
    ditto -c -k --keepParent --norsrc "plugins/$client" "build/macminimode-$client-plugin.zip"
done
