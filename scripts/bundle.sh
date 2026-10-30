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

# Traduções: o catálogo gera pt-BR.lproj. O en.lproj vazio garante que quem usa o
# sistema em inglês veja o texto original, em vez da única tradução disponível.
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$app/Contents/Resources"
mkdir -p "$app/Contents/Resources/en.lproj"

# Assinatura ad-hoc: sem conta Apple Developer, mas exigida para rodar em Apple Silicon.
codesign --force --sign - --timestamp=none "$app"

echo "$app"
