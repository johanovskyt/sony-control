#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."

version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
tag="v$version"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Commit your changes before you make a release." >&2
    exit 1
fi

if gh release view "$tag" >/dev/null 2>&1; then
    echo "Release $tag exists. Increase CFBundleShortVersionString in Resources/Info.plist." >&2
    exit 1
fi

./Scripts/build-app.sh --zip

install_notes='## Install

Paste this command in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/johanovskyt/sony-control/main/install.sh | sh
```

To install without Terminal, see the [README](https://github.com/johanovskyt/sony-control#install-without-terminal).'

gh release create "$tag" build/SonyControl.zip \
    --target "$(git rev-parse HEAD)" \
    --title "Sony Control $version" \
    --notes "$install_notes" \
    --generate-notes
