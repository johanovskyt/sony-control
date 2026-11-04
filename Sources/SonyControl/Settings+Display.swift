import SonyKit

extension EqualizerPreset {
    var title: String {
        switch self {
        case .off: "Off"
        case .bright: "Bright"
        case .excited: "Excited"
        case .mellow: "Mellow"
        case .relaxed: "Relaxed"
        case .vocal: "Vocal"
        case .trebleBoost: "Treble Boost"
        case .bassBoost: "Bass Boost"
        case .speech: "Speech"
        case .manual: "Manual"
        case .custom1: "Custom 1"
        case .custom2: "Custom 2"
        }
    }
}

extension Equalizer {
    static let bandTitles = ["400 Hz", "1 kHz", "2.5 kHz", "6.3 kHz", "16 kHz"]
}

extension SpeakToChatConfig.Sensitivity {
    var title: String {
        switch self {
        case .auto: "Automatic"
        case .high: "High"
        case .low: "Low"
        }
    }
}

extension SpeakToChatConfig.Timeout {
    var title: String {
        switch self {
        case .short: "Short"
        case .standard: "Standard"
        case .long: "Long"
        case .never: "Never"
        }
    }
}

extension AudioCodec {
    var title: String {
        switch self {
        case .unknown: "Unknown"
        case .sbc: "SBC"
        case .aac: "AAC"
        case .ldac: "LDAC"
        case .aptX: "aptX"
        case .aptXHD: "aptX HD"
        }
    }
}

extension OptimizerStatus {
    var title: String {
        switch self {
        case .notRunning: "Not running"
        case .checkingFit: "Checking the fit…"
        case .measuringPressure: "Measuring the air pressure…"
        case .analyzing: "Analyzing…"
        case .finished: "Finished"
        }
    }
}

struct UsageCounter: Identifiable {
    static let highlights: [UsageCounter] = [
        UsageCounter(key: "pwrOn", title: "Power-ons", symbol: "power"),
        UsageCounter(key: "connectBT", title: "Bluetooth connections", symbol: "dot.radiowaves.left.and.right"),
        UsageCounter(key: "opPlay", title: "Play presses", symbol: "play.fill"),
        UsageCounter(key: "opPause", title: "Pauses", symbol: "pause.fill"),
        UsageCounter(key: "opNext", title: "Next track", symbol: "forward.fill"),
        UsageCounter(key: "opPrev", title: "Previous track", symbol: "backward.fill"),
        UsageCounter(key: "useNcOn", title: "Noise cancelling on", symbol: "waveform.slash"),
        UsageCounter(key: "useAsm", title: "Ambient sound on", symbol: "ear.and.waveform"),
        UsageCounter(key: "opQA", title: "Quick Attention", symbol: "hand.raised.fill"),
        UsageCounter(key: "opVoiceDial", title: "Voice assistant", symbol: "mic.fill"),
        UsageCounter(key: "useHfp", title: "Headset sessions", symbol: "phone.fill"),
        UsageCounter(key: "lowBatt", title: "Low battery warnings", symbol: "battery.25percent"),
    ]

    let key: String
    let title: String
    let symbol: String

    var id: String { key }
}
