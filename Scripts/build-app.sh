#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."

swift build -c release --product SonyControl
binary_dir="$(swift build -c release --show-bin-path)"

app="build/Sony Control.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary_dir/SonyControl" "$app/Contents/MacOS/SonyControl"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --identifier dev.local.SonyControl "$app"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Sony Control.app"
    cp -R "$app" "$HOME/Applications/"
    echo "Installed: $HOME/Applications/Sony Control.app"
else
    echo "Built: $PWD/$app"
fi
