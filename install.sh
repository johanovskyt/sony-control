#!/bin/sh
set -eu

app_name="Sony Control.app"
download_url="${SONY_CONTROL_DOWNLOAD_URL:-https://github.com/johanovskyt/sony-control/releases/latest/download/SonyControl.zip}"

fail() {
    echo "Error: $1" >&2
    exit 1
}

check_system() {
    [ "$(uname -s)" = "Darwin" ] || fail "Sony Control runs only on macOS."
    macos_version="$(sw_vers -productVersion)"
    [ "${macos_version%%.*}" -ge 26 ] || fail "Sony Control needs macOS 26 or later. This Mac has macOS $macos_version."
}

choose_install_dir() {
    if [ -d "$HOME/Applications/$app_name" ]; then
        echo "$HOME/Applications"
    elif [ -w /Applications ]; then
        echo "/Applications"
    else
        echo "$HOME/Applications"
    fi
}

quit_running_app() {
    pgrep -xq SonyControl || return 0
    echo "Quitting the running app..."
    pkill -x SonyControl || true
    attempts=0
    while pgrep -xq SonyControl && [ "$attempts" -lt 50 ]; do
        sleep 0.1
        attempts=$((attempts + 1))
    done
}

main() {
    check_system
    install_dir="$(choose_install_dir)"

    work_dir="$(mktemp -d)"
    trap 'rm -rf "$work_dir"' EXIT

    echo "Downloading Sony Control..."
    curl -fsSL "$download_url" -o "$work_dir/SonyControl.zip" \
        || fail "The download failed. Check your internet connection, then try again."
    ditto -x -k "$work_dir/SonyControl.zip" "$work_dir"
    [ -d "$work_dir/$app_name" ] || fail "The download does not contain $app_name."

    quit_running_app
    mkdir -p "$install_dir"
    rm -rf "$install_dir/$app_name"
    mv "$work_dir/$app_name" "$install_dir/"
    xattr -dr com.apple.quarantine "$install_dir/$app_name" 2>/dev/null || true

    open "$install_dir/$app_name"
    echo "Installed Sony Control in $install_dir."
    echo "Click the headphones icon in the menu bar."
    echo "If macOS asks for Bluetooth access, click Allow."
}

main "$@"
