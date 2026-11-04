#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."

build_options=(-c release --arch arm64 --arch x86_64)
swift build "${build_options[@]}" --product SonyControl
binary_dir="$(swift build "${build_options[@]}" --show-bin-path)"

app="build/Sony Control.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/SonyControl" "$app/Contents/MacOS/SonyControl"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier dev.local.SonyControl "$app"

case "${1:-}" in
    --install)
        mkdir -p "$HOME/Applications"
        rm -rf "$HOME/Applications/Sony Control.app"
        cp -R "$app" "$HOME/Applications/"
        echo "Installed: $HOME/Applications/Sony Control.app"
        ;;
    --zip)
        rm -f build/SonyControl.zip
        ditto -c -k --keepParent "$app" build/SonyControl.zip
        echo "Packed: $PWD/build/SonyControl.zip"
        ;;
    *)
        echo "Built: $PWD/$app"
        ;;
esac
