import Foundation

public enum HeadphoneEvent: Equatable, Sendable {
    case initialized
    case soundControl(SoundControl)
    case battery(Battery)
    case deviceSwitch(DeviceSwitch, Bool)
    case equalizer(Equalizer)
    case speakToChatConfig(SpeakToChatConfig)
    case optimizerStatus(OptimizerStatus)
    case optimizerResult(pressure: Double)
    case codec(AudioCodec)
    case firmware(String)
    case usageStatistics([String: Int])

    public init?(type: MessageType, payload: [UInt8]) {
        let event: HeadphoneEvent? = switch type {
        case .command1: Self.parseCommand1(payload)
        case .command2: Self.parseCommand2(payload)
        case .ack: nil
        }
        guard let event else { return nil }
        self = event
    }

    private static func parseCommand1(_ payload: [UInt8]) -> HeadphoneEvent? {
        guard let code = payload.first else { return nil }
        switch code {
        case 0x01:
            return .initialized
        case 0x05:
            guard payload.count > 3, payload[1] == 0x02 else { return nil }
            return .firmware(String(decoding: payload[3...], as: UTF8.self))
        case 0x11, 0x13:
            guard payload.count >= 4, payload[1] == 0x00 else { return nil }
            return .battery(Battery(level: Int(payload[2]), isCharging: payload[3] == 0x01))
        case 0x19, 0x1b:
            guard payload.count == 3, payload[1] == 0x00 else { return nil }
            return .codec(AudioCodec(rawValue: payload[2]) ?? .unknown)
        case 0x57, 0x59:
            return parseEqualizer(payload)
        case 0x67, 0x69:
            return parseSoundControl(payload)
        case 0x85:
            guard payload.count == 4, let status = OptimizerStatus(rawValue: payload[3]) else { return nil }
            return .optimizerStatus(status)
        case 0x87, 0x89:
            guard payload.count == 6, (1...10).contains(payload[5]) else { return nil }
            return .optimizerResult(pressure: Double(payload[5]) / 10)
        case 0xc9:
            return parseUsageStatistics(payload)
        case 0xe7, 0xe9:
            guard payload.count == 4, payload[1] == 0x02 else { return nil }
            return .deviceSwitch(.dseeExtreme, payload[3] == 0x01)
        case 0xf7, 0xf9:
            return parseSystemSetting(payload)
        case 0xfb, 0xfd:
            return parseSpeakToChatConfig(payload)
        default:
            return nil
        }
    }

    private static func parseCommand2(_ payload: [UInt8]) -> HeadphoneEvent? {
        guard payload.count == 4, payload[0] == 0x47 || payload[0] == 0x49, payload[1] == 0x01, payload[2] == 0x01 else {
            return nil
        }
        return .deviceSwitch(.voiceGuidance, payload[3] == 0x01)
    }

    private static func parseSoundControl(_ payload: [UInt8]) -> HeadphoneEvent? {
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

        return .soundControl(SoundControl(mode: mode, ambientLevel: Int(payload[7]), focusOnVoice: payload[6] == 0x01))
    }

    private static func parseEqualizer(_ payload: [UInt8]) -> HeadphoneEvent? {
        guard payload.count == 4 + 1 + Equalizer.bandCount, let preset = EqualizerPreset(rawValue: payload[2]) else {
            return nil
        }
        let levels = payload[4...].map { Int($0) - 10 }
        return .equalizer(Equalizer(preset: preset, clearBass: levels[0], bands: Array(levels.dropFirst())))
    }

    private static func parseSystemSetting(_ payload: [UInt8]) -> HeadphoneEvent? {
        guard payload.count == 4, payload[2] <= 0x01 else { return nil }
        let enabled = payload[3] == 0x01
        switch payload[1] {
        case 0x03: return .deviceSwitch(.pauseWhenTakenOff, enabled)
        case 0x05: return .deviceSwitch(.speakToChat, enabled)
        default: return nil
        }
    }

    private static func parseSpeakToChatConfig(_ payload: [UInt8]) -> HeadphoneEvent? {
        guard payload.count == 6, payload[1] == 0x05,
              let sensitivity = SpeakToChatConfig.Sensitivity(rawValue: payload[3]),
              let timeout = SpeakToChatConfig.Timeout(rawValue: payload[5])
        else { return nil }
        return .speakToChatConfig(SpeakToChatConfig(sensitivity: sensitivity, focusOnVoice: payload[4] == 0x01, timeout: timeout))
    }

    private static func parseUsageStatistics(_ payload: [UInt8]) -> HeadphoneEvent? {
        guard payload.count > 4,
              let log = try? JSONDecoder().decode(UsageLog.self, from: Data(payload[4...]))
        else { return nil }
        let counters = Dictionary(log.logs.compactMap { entry in Int(entry.val).map { (entry.key, $0) } }) { _, latest in latest }
        return .usageStatistics(counters)
    }
}

private struct UsageLog: Decodable {
    struct Entry: Decodable {
        let key: String
        let val: String
    }

    let logs: [Entry]
}
