import Foundation
import SonyKit

let usage = """
    Usage: sonyctl <command>

      status            Show the current mode, ambient level, and battery
      nc                Turn on noise cancelling
      ambient [1-20]    Turn on ambient sound, with an optional level
      wind              Turn on wind noise reduction
      off               Turn off noise cancelling and ambient sound
      voice on|off      Turn focus on voice on or off
      selftest          Check the message encoder without Bluetooth

    Quit the Sony Control menu bar app before you use this tool.
    """

func pumpRunLoop(for seconds: TimeInterval, until done: () -> Bool = { false }) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline, !done() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

@MainActor
func describe(_ controller: HeadphoneController) -> String {
    let soundControl = controller.soundControl
    var lines = [
        "Device:          \(controller.deviceName ?? "unknown")",
        "Mode:            \(soundControl.mode.rawValue)",
        "Ambient level:   \(soundControl.ambientLevel)",
        "Focus on voice:  \(soundControl.focusOnVoice ? "on" : "off")",
    ]
    if let battery = controller.battery {
        lines.append("Battery:         \(battery.level)%\(battery.isCharging ? " (charging)" : "")")
    }
    if let speakToChat = controller.speakToChat {
        lines.append("Speak-to-Chat:   \(speakToChat ? "on" : "off")")
    }
    return lines.joined(separator: "\n")
}

func runSelfTest() -> Int32 {
    var failures = 0
    func check(_ name: String, _ condition: Bool) {
        print("\(condition ? "PASS" : "FAIL")  \(name)")
        if !condition { failures += 1 }
    }

    let initFrame = Frame(type: .command1, sequence: 0, payload: SonyCommand.initialize).encoded()
    check("init frame", initFrame == [0x3e, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x0e, 0x3c])

    let ackFrame = Frame(type: .ack, sequence: 1, payload: []).encoded()
    check("ack frame", ackFrame == [0x3e, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x02, 0x3c])

    let markerFrame = Frame(type: .command1, sequence: 0, payload: [0x3c, 0x3d, 0x3e]).encoded()
    check("markers are escaped", markerFrame == [
        0x3e, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x03,
        0x3d, 0x2c, 0x3d, 0x2d, 0x3d, 0x2e, 0xc6, 0x3c,
    ])

    let ambient = SoundControl(mode: .ambient, ambientLevel: 15, focusOnVoice: true)
    let ambientBytes = Frame(type: .command1, sequence: 1, payload: SonyCommand.setSoundControl(ambient)).encoded()
    var decoder = FrameDecoder()
    let firstHalf = decoder.append(Array(ambientBytes.prefix(5)))
    let decoded = decoder.append(Array(ambientBytes.dropFirst(5)) + ackFrame)
    check("decoder waits for a full frame", firstHalf.isEmpty)
    check("decoder splits joined frames", decoded.count == 2 && decoded[1].messageType == .ack)
    check("round trip keeps the payload", decoded.first?.payload == SonyCommand.setSoundControl(ambient))

    check("noise cancelling payload", SonyCommand.setSoundControl(
        SoundControl(mode: .noiseCancelling, ambientLevel: 15, focusOnVoice: false)
    ) == [0x68, 0x02, 0x11, 0x02, 0x02, 0x01, 0x00, 0x00])

    check("parse ambient notification",
          HeadphoneEvent(payload: [0x69, 0x02, 0x01, 0x02, 0x00, 0x01, 0x01, 0x0f]) == .soundControl(ambient))
    check("parse noise cancelling notification",
          HeadphoneEvent(payload: [0x69, 0x02, 0x01, 0x02, 0x02, 0x01, 0x00, 0x00])
          == .soundControl(SoundControl(mode: .noiseCancelling, ambientLevel: 0, focusOnVoice: false)))
    check("parse battery", HeadphoneEvent(payload: [0x11, 0x00, 0x46, 0x00]) == .battery(Battery(level: 70, isCharging: false)))

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
        return controller.isConnected && controller.battery != nil
    }

    if case .unavailable(let reason) = controller.connection {
        print("Error: \(reason)")
        return 1
    }
    guard controller.isConnected else {
        print("Error: The headphones did not send their settings in time.")
        return 1
    }

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
        if let level = arguments.dropFirst().first.flatMap(Int.init) {
            controller.setAmbientLevel(level)
        }
        controller.setMode(.ambient)
    case "voice":
        controller.setFocusOnVoice(arguments.dropFirst().first == "on")
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
