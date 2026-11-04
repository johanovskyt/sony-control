public struct Request: Equatable, Sendable {
    public var type: MessageType
    public var payload: [UInt8]
    public var coalescingKey: [UInt8]

    public init(_ payload: [UInt8], type: MessageType = .command1, coalescingKey: [UInt8]? = nil) {
        self.type = type
        self.payload = payload
        self.coalescingKey = coalescingKey ?? Array(payload.prefix(2))
    }
}

public enum SonyCommand {
    public static let initialize = Request([0x00, 0x00])
    public static let getFirmware = Request([0x04, 0x02])
    public static let getBattery = Request([0x10, 0x00])
    public static let getCodec = Request([0x18, 0x00])
    public static let getEqualizer = Request([0x56, 0x01])
    public static let getSoundControl = Request([0x66, 0x02])
    public static let getOptimizerResult = Request([0x86, 0x01])
    public static let getSpeakToChatConfig = Request([0xfa, 0x05])
    public static let getUsageStatistics = Request([0xc4, 0x01, 0x00])
    public static let powerOff = Request([0x22, 0x00, 0x01])

    public static func get(_ deviceSwitch: DeviceSwitch) -> Request {
        switch deviceSwitch {
        case .speakToChat: Request([0xf6, 0x05])
        case .dseeExtreme: Request([0xe6, 0x02])
        case .pauseWhenTakenOff: Request([0xf6, 0x03])
        case .voiceGuidance: Request([0x46, 0x01, 0x01], type: .command2)
        }
    }

    public static func set(_ deviceSwitch: DeviceSwitch, _ enabled: Bool) -> Request {
        let value: UInt8 = enabled ? 0x01 : 0x00
        return switch deviceSwitch {
        case .speakToChat: Request([0xf8, 0x05, 0x01, value])
        case .dseeExtreme: Request([0xe8, 0x02, 0x00, value])
        case .pauseWhenTakenOff: Request([0xf8, 0x03, 0x00, value])
        case .voiceGuidance: Request([0x48, 0x01, 0x01, value], type: .command2)
        }
    }

    public static func setSoundControl(_ soundControl: SoundControl) -> Request {
        let enabled: UInt8 = soundControl.mode == .off ? 0x00 : 0x11
        let microphoneMode: UInt8 = switch soundControl.mode {
        case .noiseCancelling: 0x02
        case .windReduction: 0x01
        case .ambient, .off: 0x00
        }
        let level: UInt8 = switch soundControl.mode {
        case .ambient, .off: UInt8(clamping: soundControl.ambientLevel)
        case .noiseCancelling, .windReduction: 0x00
        }
        return Request([0x68, 0x02, enabled, 0x02, microphoneMode, 0x01, soundControl.focusOnVoice ? 0x01 : 0x00, level])
    }

    public static func setEqualizerPreset(_ preset: EqualizerPreset) -> Request {
        Request([0x58, 0x01, preset.rawValue, 0x00], coalescingKey: [0x58, 0x01, 0x00])
    }

    public static func setEqualizerBands(clearBass: Int, bands: [Int]) -> Request {
        let levels = ([clearBass] + bands).map { UInt8(clamping: min(max($0, Equalizer.levels.lowerBound), Equalizer.levels.upperBound) + 10) }
        return Request([0x58, 0x01, 0xff, UInt8(levels.count)] + levels, coalescingKey: [0x58, 0x01, 0xff])
    }

    public static func setSpeakToChatConfig(_ config: SpeakToChatConfig) -> Request {
        Request([0xfc, 0x05, 0x00, config.sensitivity.rawValue, config.focusOnVoice ? 0x01 : 0x00, config.timeout.rawValue])
    }

    public static func runOptimizer(_ start: Bool) -> Request {
        Request([0x84, 0x01, 0x00, start ? 0x01 : 0x00])
    }
}
