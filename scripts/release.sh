#!/bin/bash
# Gera build/AgentBar-<versão>.zip para o GitHub Releases.
#
# Sem conta Apple Developer o app sai com assinatura ad-hoc e sem notarização:
# na primeira abertura o macOS pede liberação manual (o README explica como).
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)"
zip="build/AgentBar-$version.zip"

swift test
UNIVERSAL=1 ./scripts/bundle.sh

rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent build/AgentBar.app "$zip"

echo
echo "$zip"
lipo -archs build/AgentBar.app/Contents/MacOS/AgentBar
shasum -a 256 "$zip"
