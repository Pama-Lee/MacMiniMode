#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT=${1:-build/macminimode-mcp}
mkdir -p "$(dirname "$OUTPUT")" work/mcp-universal
for arch in arm64 x86_64; do
    swift build --package-path MCP -c release --arch "$arch" --force-resolved-versions
    BIN=$(swift build --package-path MCP -c release --arch "$arch" --show-bin-path)
    cp "$BIN/macminimode-mcp" "work/mcp-universal/$arch"
done
lipo -create work/mcp-universal/arm64 work/mcp-universal/x86_64 -output "$OUTPUT"
