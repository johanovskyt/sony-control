public enum NoiseMode: String, CaseIterable, Identifiable, Sendable {
    case noiseCancelling
    case ambient
    case windReduction
    case off

    public var id: String { rawValue }
}

public struct SoundControl: Equatable, Sendable {
    public static let ambientLevels = 1...20

    public var mode: NoiseMode
    public var ambientLevel: Int
    public var focusOnVoice: Bool

    public init(mode: NoiseMode, ambientLevel: Int, focusOnVoice: Bool) {
        self.mode = mode
        self.ambientLevel = ambientLevel
        self.focusOnVoice = focusOnVoice
    }
}

public struct Battery: Equatable, Sendable {
    public var level: Int
    public var isCharging: Bool

    public init(level: Int, isCharging: Bool) {
        self.level = level
        self.isCharging = isCharging
    }
}

public enum HeadphoneEvent: Equatable, Sendable {
    case initialized
    case soundControl(SoundControl)
    case battery(Battery)
    case speakToChat(Bool)

    public init?(payload: [UInt8]) {
        guard let code = payload.first else { return nil }
        switch code {
        case 0x01:
            self = .initialized
        case 0x67, 0x69:
            guard let soundControl = Self.parseSoundControl(payload) else { return nil }
            self = .soundControl(soundControl)
        case 0x11, 0x13:
            guard payload.count >= 4, payload[1] == 0x00 else { return nil }
            self = .battery(Battery(level: Int(payload[2]), isCharging: payload[3] == 0x01))
        case 0xf7, 0xf9:
            guard payload.count == 4, payload[1] == 0x05, payload[2] <= 0x01 else { return nil }
            self = .speakToChat(payload[3] == 0x01)
        default:
            return nil
        }
    }

    private static func parseSoundControl(_ payload: [UInt8]) -> SoundControl? {
        guard payload.count == 8 else { return nil }

        let mode: NoiseMode
        if payload[2] == 0x00 {
            mode = .off
        } else {
            switch (payload[3], payload[4]) {
            case (0x02, 0x02), (0x00, 0x01): mode = .noiseCancelling
            case (0x02, 0x01): mode = .windReduction
            case (_, 0x00): mode = .ambient
            default: return nil
            }
        }

        return SoundControl(mode: mode, ambientLevel: Int(payload[7]), focusOnVoice: payload[6] == 0x01)
    }
}

public enum SonyCommand {
    public static let initialize: [UInt8] = [0x00, 0x00]
    public static let getSoundControl: [UInt8] = [0x66, 0x02]
    public static let getBattery: [UInt8] = [0x10, 0x00]
    public static let getSpeakToChat: [UInt8] = [0xf6, 0x05]

    public static func setSoundControl(_ soundControl: SoundControl) -> [UInt8] {
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
        return [0x68, 0x02, enabled, 0x02, microphoneMode, 0x01, soundControl.focusOnVoice ? 0x01 : 0x00, level]
    }

    public static func setSpeakToChat(_ enabled: Bool) -> [UInt8] {
        [0xf8, 0x05, 0x01, enabled ? 0x01 : 0x00]
    }
}
