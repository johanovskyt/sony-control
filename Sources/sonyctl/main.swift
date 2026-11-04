import Foundation
import SonyKit

let usage = """
    Usage: sonyctl <command>

      status                      Show all settings
      nc                          Turn on noise cancelling
      ambient [1-20]              Turn on ambient sound, with an optional level
      wind                        Turn on wind noise reduction
      off                         Turn off noise cancelling and ambient sound
      voice on|off                Turn focus on voice on or off
      eq <preset>                 Select an equalizer preset (\(EqualizerPreset.allCases.map(\.name).joined(separator: ", ")))
      eq-bands <bass> <5 bands>   Set Clear Bass and the 5 bands (-10 to 10)
      set <setting> on|off        Change a setting (\(DeviceSwitch.allCases.map(\.rawValue).joined(separator: ", ")))
      stats                       Show the usage counters that the headphones keep
      selftest                    Check the message encoder and parser without Bluetooth

    Quit the Sony Control menu bar app before you use this tool.
    """

extension EqualizerPreset {
    var name: String { String(describing: self) }
}

func pumpRunLoop(for seconds: TimeInterval, until done: () -> Bool = { false }) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline, !done() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

func onOff(_ value: Bool?) -> String {
    value.map { $0 ? "on" : "off" } ?? "unknown"
}

@MainActor
func describe(_ controller: HeadphoneController) -> String {
    let soundControl = controller.soundControl
    var lines = [
        "Device:              \(controller.deviceName ?? "unknown")",
        "Mode:                \(soundControl.mode.rawValue)",
        "Ambient level:       \(soundControl.ambientLevel)",
        "Focus on voice:      \(onOff(soundControl.focusOnVoice))",
    ]
    if let battery = controller.battery {
        lines.append("Battery:             \(battery.level)%\(battery.isCharging ? " (charging)" : "")")
    }
    for deviceSwitch in DeviceSwitch.allCases {
        lines.append("\(deviceSwitch.rawValue + ":")".padding(toLength: 21, withPad: " ", startingAt: 0) + onOff(controller.switches[deviceSwitch]))
    }
    if let equalizer = controller.equalizer {
        let bands = equalizer.bands.map(String.init).joined(separator: " ")
        lines.append("Equalizer:           \(equalizer.preset.name), Clear Bass \(equalizer.clearBass), bands \(bands)")
    }
    if let config = controller.speakToChatConfig {
        lines.append("Speak-to-Chat setup: sensitivity \(config.sensitivity), timeout \(config.timeout), focus on voice \(onOff(config.focusOnVoice))")
    }
    if let pressure = controller.optimizerPressure {
        lines.append("Optimizer pressure:  \(pressure) atm")
    }
    if let codec = controller.codec {
        lines.append("Codec:               \(codec)")
    }
    if let firmware = controller.firmwareVersion {
        lines.append("Firmware:            \(firmware)")
    }
    return lines.joined(separator: "\n")
}

func runSelfTest() -> Int32 {
    var failures = 0
    func check(_ name: String, _ condition: Bool) {
        print("\(condition ? "PASS" : "FAIL")  \(name)")
        if !condition { failures += 1 }
    }

    let initFrame = Frame(type: .command1, sequence: 0, payload: SonyCommand.initialize.payload).encoded()
    check("init frame", initFrame == [0x3e, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x0e, 0x3c])

    let ackFrame = Frame(type: .ack, sequence: 1, payload: []).encoded()
    check("ack frame", ackFrame == [0x3e, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x02, 0x3c])

    let markerFrame = Frame(type: .command1, sequence: 0, payload: [0x3c, 0x3d, 0x3e]).encoded()
    check("markers are escaped", markerFrame == [
        0x3e, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x03,
        0x3d, 0x2c, 0x3d, 0x2d, 0x3d, 0x2e, 0xc6, 0x3c,
    ])

    let ambient = SoundControl(mode: .ambient, ambientLevel: 15, focusOnVoice: true)
    let ambientPayload = SonyCommand.setSoundControl(ambient).payload
    let ambientBytes = Frame(type: .command1, sequence: 1, payload: ambientPayload).encoded()
    var decoder = FrameDecoder()
    let firstHalf = decoder.append(Array(ambientBytes.prefix(5)))
    let decoded = decoder.append(Array(ambientBytes.dropFirst(5)) + ackFrame)
    check("decoder waits for a full frame", firstHalf.isEmpty)
    check("decoder splits joined frames", decoded.count == 2 && decoded[1].messageType == .ack)
    check("round trip keeps the payload", decoded.first?.payload == ambientPayload)

    check("noise cancelling payload", SonyCommand.setSoundControl(
        SoundControl(mode: .noiseCancelling, ambientLevel: 15, focusOnVoice: false)
    ).payload == [0x68, 0x02, 0x11, 0x02, 0x02, 0x01, 0x00, 0x00])

    func event(_ payload: [UInt8], type: MessageType = .command1) -> HeadphoneEvent? {
        HeadphoneEvent(type: type, payload: payload)
    }

    check("parse ambient notification",
          event([0x69, 0x02, 0x01, 0x02, 0x00, 0x01, 0x01, 0x0f]) == .soundControl(ambient))
    check("parse noise cancelling notification",
          event([0x69, 0x02, 0x01, 0x02, 0x02, 0x01, 0x00, 0x00])
          == .soundControl(SoundControl(mode: .noiseCancelling, ambientLevel: 0, focusOnVoice: false)))
    check("parse battery", event([0x11, 0x00, 0x46, 0x00]) == .battery(Battery(level: 70, isCharging: false)))

    check("parse Speak-to-Chat reply", event([0xf7, 0x05, 0x00, 0x01]) == .deviceSwitch(.speakToChat, true))
    check("ignore unknown Speak-to-Chat notification", event([0xf9, 0x05, 0x02, 0x00]) == nil)
    check("parse pause when taken off", event([0xf9, 0x03, 0x00, 0x00]) == .deviceSwitch(.pauseWhenTakenOff, false))
    check("parse DSEE Extreme", event([0xe7, 0x02, 0x00, 0x01]) == .deviceSwitch(.dseeExtreme, true))
    check("parse voice guidance", event([0x47, 0x01, 0x01, 0x01], type: .command2) == .deviceSwitch(.voiceGuidance, true))

    check("parse equalizer preset",
          event([0x59, 0x01, 0x10, 0x06, 0x09, 0x0a, 0x0f, 0x11, 0x11, 0x13])
          == .equalizer(Equalizer(preset: .bright, clearBass: -1, bands: [0, 5, 7, 7, 9])))
    check("equalizer bands payload",
          SonyCommand.setEqualizerBands(clearBass: 3, bands: [0, 0, 0, 0, 2]).payload
          == [0x58, 0x01, 0xff, 0x06, 0x0d, 0x0a, 0x0a, 0x0a, 0x0a, 0x0c])
    check("preset and bands do not replace each other in the queue",
          SonyCommand.setEqualizerPreset(.manual).coalescingKey
          != SonyCommand.setEqualizerBands(clearBass: 0, bands: [0, 0, 0, 0, 0]).coalescingKey)

    check("parse Speak-to-Chat setup",
          event([0xfb, 0x05, 0x00, 0x00, 0x00, 0x01])
          == .speakToChatConfig(SpeakToChatConfig(sensitivity: .auto, focusOnVoice: false, timeout: .standard)))
    check("parse optimizer result", event([0x87, 0x01, 0x01, 0x01, 0x01, 0x09]) == .optimizerResult(pressure: 0.9))
    check("parse codec", event([0x19, 0x00, 0x02]) == .codec(.aac))
    check("parse firmware", event([0x05, 0x02, 0x05] + Array("2.9.0".utf8)) == .firmware("2.9.0"))

    let json = Array(#"{"v":"M6","logs":[{"key":"did","val":"15F2"},{"key":"opPlay","val":"1347"}]}"#.utf8)
    check("parse usage counters", event([0xc9, 0x01, 0x00, UInt8(json.count)] + json) == .usageStatistics(["opPlay": 1347]))

    print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
    return failures == 0 ? 0 : 1
}

@MainActor
func run(_ arguments: [String]) -> Int32 {
    guard let command = arguments.first else {
        print(usage)
        return 2
    }
    if command == "selftest" {
        return runSelfTest()
    }

    let controller = HeadphoneController()
    controller.start()
    pumpRunLoop(for: 15) {
        if case .unavailable = controller.connection { return true }
        return controller.isConnected && controller.firmwareVersion != nil
    }

    if case .unavailable(let reason) = controller.connection {
        print("Error: \(reason)")
        return 1
    }
    guard controller.isConnected else {
        print("Error: The headphones did not send their settings in time.")
        return 1
    }

    let options = Array(arguments.dropFirst())
    switch command {
    case "status":
        break
    case "nc":
        controller.setMode(.noiseCancelling)
    case "wind":
        controller.setMode(.windReduction)
    case "off":
        controller.setMode(.off)
    case "ambient":
        if let level = options.first.flatMap(Int.init) {
            controller.setAmbientLevel(level)
        }
        controller.setMode(.ambient)
    case "voice":
        controller.setFocusOnVoice(options.first == "on")
    case "eq":
        guard let preset = EqualizerPreset.allCases.first(where: { $0.name == options.first }) else {
            print(usage)
            return 2
        }
        controller.setEqualizerPreset(preset)
    case "eq-bands":
        let levels = options.compactMap(Int.init)
        guard levels.count == 1 + Equalizer.bandCount else {
            print(usage)
            return 2
        }
        controller.setEqualizerBands(clearBass: levels[0], bands: Array(levels.dropFirst()))
    case "set":
        guard let deviceSwitch = DeviceSwitch(rawValue: options.first ?? ""), options.count == 2 else {
            print(usage)
            return 2
        }
        controller.setSwitch(deviceSwitch, options[1] == "on")
    case "stats":
        controller.refreshUsageStatistics()
        pumpRunLoop(for: 3)
        for (key, value) in controller.usageStatistics.sorted(by: { $0.key < $1.key }) {
            print(key.padding(toLength: 16, withPad: " ", startingAt: 0) + String(value))
        }
        controller.disconnect()
        pumpRunLoop(for: 0.3)
        return 0
    default:
        print(usage)
        controller.disconnect()
        return 2
    }

    pumpRunLoop(for: command == "status" ? 0.5 : 2)
    print(describe(controller))
    controller.disconnect()
    pumpRunLoop(for: 0.3)
    return 0
}

exit(MainActor.assumeIsolated { run(Array(CommandLine.arguments.dropFirst())) })
