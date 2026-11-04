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

public enum DeviceSwitch: String, CaseIterable, Identifiable, Sendable {
    case speakToChat
    case dseeExtreme
    case pauseWhenTakenOff
    case voiceGuidance

    public var id: String { rawValue }
}

public enum EqualizerPreset: UInt8, CaseIterable, Identifiable, Sendable {
    case off = 0x00
    case bright = 0x10
    case excited = 0x11
    case mellow = 0x12
    case relaxed = 0x13
    case vocal = 0x14
    case trebleBoost = 0x15
    case bassBoost = 0x16
    case speech = 0x17
    case manual = 0xa0
    case custom1 = 0xa1
    case custom2 = 0xa2

    public var id: UInt8 { rawValue }

    public var hasEditableBands: Bool {
        self == .manual || self == .custom1 || self == .custom2
    }
}

public struct Equalizer: Equatable, Sendable {
    public static let levels = -10...10
    public static let bandCount = 5

    public var preset: EqualizerPreset
    public var clearBass: Int
    public var bands: [Int]

    public init(preset: EqualizerPreset, clearBass: Int, bands: [Int]) {
        self.preset = preset
        self.clearBass = clearBass
        self.bands = bands
    }
}

public struct SpeakToChatConfig: Equatable, Sendable {
    public enum Sensitivity: UInt8, CaseIterable, Identifiable, Sendable {
        case auto = 0x00
        case high = 0x01
        case low = 0x02

        public var id: UInt8 { rawValue }
    }

    public enum Timeout: UInt8, CaseIterable, Identifiable, Sendable {
        case short = 0x00
        case standard = 0x01
        case long = 0x02
        case never = 0x03

        public var id: UInt8 { rawValue }
    }

    public var sensitivity: Sensitivity
    public var focusOnVoice: Bool
    public var timeout: Timeout

    public init(sensitivity: Sensitivity, focusOnVoice: Bool, timeout: Timeout) {
        self.sensitivity = sensitivity
        self.focusOnVoice = focusOnVoice
        self.timeout = timeout
    }
}

public enum AudioCodec: UInt8, Sendable {
    case unknown = 0x00
    case sbc = 0x01
    case aac = 0x02
    case ldac = 0x10
    case aptX = 0x20
    case aptXHD = 0x21
}

public enum OptimizerStatus: UInt8, Sendable {
    case notRunning = 0x00
    case checkingFit = 0x01
    case measuringPressure = 0x02
    case analyzing = 0x10
    case finished = 0x11

    public var isRunning: Bool {
        self == .checkingFit || self == .measuringPressure || self == .analyzing
    }
}
