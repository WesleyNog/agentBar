#!/bin/bash
# Gera build/AgentBar.app a partir do Swift Package.
# Uso: ./scripts/bundle.sh            (release)
#      CONFIG=debug ./scripts/bundle.sh
set -euo pipefail
cd "$(dirname "$0")/.."

config="${CONFIG:-release}"
app="build/AgentBar.app"

swift build -c "$config" --product AgentBar
bin_dir="$(swift build -c "$config" --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/AgentBar" "$app/Contents/MacOS/AgentBar"
cp Resources/Info.plist "$app/Contents/Info.plist"

# Assinatura ad-hoc: sem conta Apple Developer, mas exigida para rodar em Apple Silicon.
codesign --force --sign - --timestamp=none "$app"

echo "$app"
