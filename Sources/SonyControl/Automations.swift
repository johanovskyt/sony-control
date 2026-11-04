import Carbon.HIToolbox
import CoreAudio
import Foundation
import Observation
import SonyKit
import UserNotifications

@MainActor
final class Automations {
    private static let callStartDelay: TimeInterval = 2
    private static let callEndDelay: TimeInterval = 3
    private static let lowBatteryLevel = 20
    private static let lowBatteryResetLevel = 25

    private let controller: HeadphoneController
    private let settings: AppSettings
    private var microphoneTask: Task<Void, Never>?
    private var microphoneActiveSince: Date?
    private var microphoneIdleSince: Date?
    private var modeBeforeCall: NoiseMode?
    private var cycleHotKey: GlobalHotKey?
    private var hasSentLowBatteryAlert = false

    init(controller: HeadphoneController, settings: AppSettings) {
        self.controller = controller
        self.settings = settings
        settings.onChange = { [weak self] in self?.apply() }
        apply()
        observeBattery()
    }

    private func apply() {
        updateMicrophoneMonitor()
        updateCycleHotKey()
        if settings.lowBatteryAlert {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    private func updateMicrophoneMonitor() {
        guard settings.ambientDuringCalls else {
            microphoneTask?.cancel()
            microphoneTask = nil
            modeBeforeCall = nil
            return
        }
        guard microphoneTask == nil else { return }
        microphoneTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.checkMicrophone()
            }
        }
    }

    private func checkMicrophone() {
        let now = Date()
        if Microphone.isInUse() {
            microphoneIdleSince = nil
            let activeSince = microphoneActiveSince ?? now
            microphoneActiveSince = activeSince
            guard modeBeforeCall == nil,
                  now.timeIntervalSince(activeSince) >= Self.callStartDelay,
                  controller.isConnected,
                  controller.soundControl.mode != .ambient
            else { return }
            modeBeforeCall = controller.soundControl.mode
            controller.setMode(.ambient)
        } else {
            microphoneActiveSince = nil
            let idleSince = microphoneIdleSince ?? now
            microphoneIdleSince = idleSince
            guard let previousMode = modeBeforeCall, now.timeIntervalSince(idleSince) >= Self.callEndDelay else { return }
            modeBeforeCall = nil
            if controller.soundControl.mode == .ambient {
                controller.setMode(previousMode)
            }
        }
    }

    private func updateCycleHotKey() {
        if settings.cycleShortcut, cycleHotKey == nil {
            cycleHotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey | cmdKey)) { [weak self] in
                self?.controller.cycleMode()
            }
        } else if !settings.cycleShortcut {
            cycleHotKey?.unregister()
            cycleHotKey = nil
        }
    }

    private func observeBattery() {
        withObservationTracking {
            _ = controller.battery
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.batteryChanged()
                self?.observeBattery()
            }
        }
    }

    private func batteryChanged() {
        guard let battery = controller.battery else { return }
        if battery.isCharging || battery.level >= Self.lowBatteryResetLevel {
            hasSentLowBatteryAlert = false
            return
        }
        guard settings.lowBatteryAlert, !hasSentLowBatteryAlert, battery.level <= Self.lowBatteryLevel else { return }
        hasSentLowBatteryAlert = true

        let content = UNMutableNotificationContent()
        content.title = "Headphone battery is low"
        content.body = "\(controller.deviceName ?? "Your headphones") has \(battery.level)% battery left."
        let request = UNNotificationRequest(identifier: "low-battery", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum Microphone {
    static func isInUse() -> Bool {
        audioProcesses().contains { process in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var isRunning: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &isRunning) == noErr && isRunning != 0
        }
    }

    private static func audioProcesses() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return [] }
        return processes
    }
}

@MainActor
final class GlobalHotKey {
    static let cycleShortcutTitle = "⌃⌥⌘N"

    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        let hotKeyID = EventHotKeyID(signature: OSType(0x534F_4E59), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        hotKeyRef = nil
        handlerRef = nil
    }
}
