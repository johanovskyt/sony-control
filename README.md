# Sony Control

Sony Control is a macOS menu bar app for Sony WH-1000XM4 headphones. It replaces the Sony phone app for daily settings.

<img src="docs/panel.png" alt="Sony Control panel" width="320">

## Features

- Noise cancelling, ambient sound, wind noise reduction, and off
- Ambient sound level (1–20) and focus on voice
- Speak-to-Chat on and off
- Battery level
- Live updates when you push the NC/AMB button on the headphones
- URL commands for Shortcuts, Raycast, or keyboard tools

## Requirements

- macOS 26 or later (the panel uses Liquid Glass)
- Swift 6. The Xcode Command Line Tools are enough. You do not need full Xcode.
- Sony headphones that use the first Sony control protocol. This app was tested with WH-1000XM4 (firmware 2.9.0). WH-1000XM3 will probably work. WH-1000XM5 and newer models use a different protocol and do not work.

## Build and install

```sh
./Scripts/build-app.sh --install
open ~/Applications/Sony\ Control.app
```

Without `--install`, the script puts the app in `build/`.

At the first start, macOS can ask for Bluetooth access. Click **Allow**. The app has an ad-hoc signature, so macOS can ask again after each rebuild.

## Use

Click the headphones icon in the menu bar. The icon shows the current mode:

| Icon | Mode |
| --- | --- |
| `headphones.circle.fill` | Noise cancelling |
| `ear.and.waveform` | Ambient sound |
| `wind` | Wind noise reduction |
| `headphones` | Off |
| `headphones.slash` | Not connected |

To start the app when you log in, select **Open at login** in the panel.

## URL commands

The app must be running.

```sh
open sonycontrol://nc
open sonycontrol://ambient
open sonycontrol://wind
open sonycontrol://off
open sonycontrol://cycle
```

`cycle` changes the mode in the same order as the button on the headphones: noise cancelling, ambient sound, off.

## Command-line tool

`sonyctl` is a test tool. Quit the menu bar app before you use it, because only one program can use the control channel at a time.

```sh
swift build
.build/debug/sonyctl status
.build/debug/sonyctl ambient 12
.build/debug/sonyctl voice on
.build/debug/sonyctl nc
.build/debug/sonyctl selftest
```

`selftest` checks the message encoder and parser. It does not use Bluetooth.

## How it works

The headphones have a serial control channel (RFCOMM channel "Serial HPC"). The Sony app sends small binary messages on this channel. Sony Control sends the same messages.

| File | Contents |
| --- | --- |
| `Sources/SonyKit/Frame.swift` | Message format: markers, escape bytes, checksum |
| `Sources/SonyKit/Commands.swift` | Command payloads and reply parsing |
| `Sources/SonyKit/HeadphoneLink.swift` | Bluetooth channel, acknowledgements, retries |
| `Sources/SonyKit/HeadphoneController.swift` | Connection state and settings for the UI |
| `Sources/SonyControl/` | Menu bar app |
| `Sources/sonyctl/` | Command-line tool |

To see the messages, run this command while the app runs:

```sh
log stream --level debug --predicate 'subsystem == "dev.local.SonyControl"'
```

## Credits

The protocol details come from [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge) and [SonyHeadphonesClient](https://github.com/Plutoberth/SonyHeadphonesClient).
