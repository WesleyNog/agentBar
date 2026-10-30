#!/bin/bash
# Gera build/AgentBar.app a partir do Swift Package.
# Uso: ./scripts/bundle.sh                  (release, só a arquitetura deste Mac)
#      CONFIG=debug ./scripts/bundle.sh
#      UNIVERSAL=1 ./scripts/bundle.sh      (Apple Silicon e Intel, para distribuir)
set -euo pipefail
cd "$(dirname "$0")/.."

config="${CONFIG:-release}"
app="build/AgentBar.app"
build_flags=(-c "$config" --product AgentBar)
if [ "${UNIVERSAL:-0}" = "1" ]; then
    build_flags+=(--arch arm64 --arch x86_64)
fi

swift build "${build_flags[@]}"
bin_dir="$(swift build "${build_flags[@]}" --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/AgentBar" "$app/Contents/MacOS/AgentBar"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

# Traduções: o catálogo gera pt-BR.lproj. O en.lproj vazio garante que quem usa o
# sistema em inglês veja o texto original, em vez da única tradução disponível.
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$app/Contents/Resources"
mkdir -p "$app/Contents/Resources/en.lproj"

# Assinatura ad-hoc: sem conta Apple Developer, mas exigida para rodar em Apple Silicon.
codesign --force --sign - --timestamp=none "$app"

echo "$app"
