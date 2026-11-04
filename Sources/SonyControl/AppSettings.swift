import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let ambientDuringCalls = "ambientDuringCalls"
        static let cycleShortcut = "cycleShortcut"
        static let batteryInMenuBar = "batteryInMenuBar"
        static let lowBatteryAlert = "lowBatteryAlert"
    }

    @ObservationIgnored var onChange: (() -> Void)?

    var ambientDuringCalls = UserDefaults.standard.bool(forKey: Key.ambientDuringCalls) {
        didSet { save(ambientDuringCalls, for: Key.ambientDuringCalls) }
    }

    var cycleShortcut = UserDefaults.standard.bool(forKey: Key.cycleShortcut) {
        didSet { save(cycleShortcut, for: Key.cycleShortcut) }
    }

    var batteryInMenuBar = UserDefaults.standard.bool(forKey: Key.batteryInMenuBar) {
        didSet { save(batteryInMenuBar, for: Key.batteryInMenuBar) }
    }

    var lowBatteryAlert = UserDefaults.standard.bool(forKey: Key.lowBatteryAlert) {
        didSet { save(lowBatteryAlert, for: Key.lowBatteryAlert) }
    }

    private func save(_ value: Bool, for key: String) {
        UserDefaults.standard.set(value, forKey: key)
        onChange?()
    }
}
