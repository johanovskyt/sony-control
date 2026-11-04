import Foundation
@preconcurrency import IOBluetooth
import Observation

@MainActor
@Observable
public final class HeadphoneController {
    public enum Connection: Equatable, Sendable {
        case searching
        case connecting
        case connected
        case unavailable(String)
    }

    public private(set) var connection: Connection = .searching
    public private(set) var deviceName: String?
    public private(set) var soundControl = SoundControl(mode: .noiseCancelling, ambientLevel: 10, focusOnVoice: false)
    public private(set) var battery: Battery?
    public private(set) var speakToChat: Bool?

    @ObservationIgnored private var link: HeadphoneLink?
    @ObservationIgnored private var observer: BluetoothConnectionObserver?
    @ObservationIgnored private var connectTask: Task<Void, Never>?

    private enum PreferenceKey {
        static let ambientLevel = "ambientLevel"
        static let focusOnVoice = "focusOnVoice"
    }

    public init() {
        let defaults = UserDefaults.standard
        let savedLevel = defaults.integer(forKey: PreferenceKey.ambientLevel)
        if SoundControl.ambientLevels.contains(savedLevel) {
            soundControl.ambientLevel = savedLevel
        }
        soundControl.focusOnVoice = defaults.bool(forKey: PreferenceKey.focusOnVoice)
    }

    public var isConnected: Bool { connection == .connected }

    public func start() {
        observer = BluetoothConnectionObserver(
            onConnect: { [weak self] in self?.scheduleConnect(after: .seconds(2)) },
            onDisconnect: { [weak self] in self?.headphonesDisconnected() }
        )
        connection = .connecting
        scheduleConnect(after: .seconds(1))
    }

    public func connect() {
        guard link == nil else { return }
        guard let device = Self.findHeadphones() else {
            connection = .unavailable("Connect your Sony headphones to this Mac in Bluetooth settings.")
            return
        }

        deviceName = device.name
        connection = .connecting
        let link = HeadphoneLink(device: device)
        link.onStatus = { [weak self] status in self?.linkStatusChanged(status) }
        link.onEvent = { [weak self] event in self?.apply(event) }
        self.link = link
        observer?.watchDisconnect(of: device)
        link.open()
    }

    public func reconnectIfNeeded() {
        if link == nil { connect() }
    }

    public func disconnect() {
        link?.close()
        link = nil
        connection = .unavailable("Disconnected.")
    }

    public func setMode(_ mode: NoiseMode) {
        updateSoundControl { $0.mode = mode }
    }

    public func cycleMode() {
        let next: NoiseMode = switch soundControl.mode {
        case .noiseCancelling: .ambient
        case .ambient: .off
        case .windReduction, .off: .noiseCancelling
        }
        setMode(next)
    }

    public func setAmbientLevel(_ level: Int) {
        let range = SoundControl.ambientLevels
        updateSoundControl { $0.ambientLevel = min(max(level, range.lowerBound), range.upperBound) }
    }

    public func setFocusOnVoice(_ enabled: Bool) {
        updateSoundControl { $0.focusOnVoice = enabled }
    }

    public func setSpeakToChat(_ enabled: Bool) {
        guard isConnected, let link else { return }
        speakToChat = enabled
        link.send(SonyCommand.setSpeakToChat(enabled))
    }

    private func updateSoundControl(_ change: (inout SoundControl) -> Void) {
        guard isConnected, let link else {
            reconnectIfNeeded()
            return
        }
        change(&soundControl)
        link.send(SonyCommand.setSoundControl(soundControl))
        if soundControl.mode == .ambient {
            saveAmbientPreferences()
        }
    }

    private func saveAmbientPreferences() {
        UserDefaults.standard.set(soundControl.ambientLevel, forKey: PreferenceKey.ambientLevel)
        UserDefaults.standard.set(soundControl.focusOnVoice, forKey: PreferenceKey.focusOnVoice)
    }

    private func scheduleConnect(after delay: Duration) {
        connectTask?.cancel()
        connectTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.reconnectIfNeeded()
        }
    }

    private func headphonesDisconnected() {
        link?.close()
        link = nil
        battery = nil
        connection = .unavailable("The headphones disconnected from this Mac.")
    }

    private func linkStatusChanged(_ status: HeadphoneLink.Status) {
        switch status {
        case .opening, .open:
            connection = .connecting
        case .closed(let reason):
            link = nil
            connection = .unavailable(reason ?? "The headphones closed the control channel.")
        }
    }

    private func apply(_ event: HeadphoneEvent) {
        if connection != .connected {
            connection = .connected
        }
        switch event {
        case .initialized:
            for request in [SonyCommand.getSoundControl, SonyCommand.getBattery, SonyCommand.getSpeakToChat] {
                link?.send(request)
            }
        case .soundControl(let reported):
            if reported.mode == .ambient, SoundControl.ambientLevels.contains(reported.ambientLevel) {
                soundControl = reported
                saveAmbientPreferences()
            } else {
                soundControl.mode = reported.mode
            }
        case .battery(let battery):
            self.battery = battery
        case .speakToChat(let enabled):
            speakToChat = enabled
        }
    }

    private static func findHeadphones() -> IOBluetoothDevice? {
        let connected = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter { $0.isConnected() }
        return connected.first { SonyService.controlChannelID(of: $0) != nil }
            ?? connected.first { ($0.name ?? "").hasPrefix("WH-1000XM") }
    }
}

@MainActor
final class BluetoothConnectionObserver: NSObject {
    private let onConnect: () -> Void
    private let onDisconnect: () -> Void
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?

    init(onConnect: @escaping () -> Void, onDisconnect: @escaping () -> Void) {
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
        super.init()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    func watchDisconnect(of device: IOBluetoothDevice) {
        disconnectNotification?.unregister()
        disconnectNotification = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )
    }

    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor [weak self] in self?.onConnect() }
    }

    @objc nonisolated private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor [weak self] in self?.onDisconnect() }
    }
}
