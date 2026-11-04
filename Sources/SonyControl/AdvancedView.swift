import SonyKit
import SwiftUI

enum AdvancedSection: String, CaseIterable, Identifiable {
    case sound
    case noiseCancelling
    case headphones
    case automations
    case statistics

    var id: Self { self }

    var title: String {
        switch self {
        case .sound: "Sound"
        case .noiseCancelling: "Noise Cancelling"
        case .headphones: "Headphones"
        case .automations: "Automations"
        case .statistics: "Statistics"
        }
    }

    var symbol: String {
        switch self {
        case .sound: "slider.vertical.3"
        case .noiseCancelling: "waveform.slash"
        case .headphones: "headphones"
        case .automations: "wand.and.stars"
        case .statistics: "chart.bar.fill"
        }
    }

    var needsHeadphones: Bool { self != .automations }
}

@MainActor
@Observable
final class AdvancedState {
    var section: AdvancedSection? = .sound
    var clearBass: Double = 0
    var bands = Array(repeating: 0.0, count: Equalizer.bandCount)
    var isConfirmingPowerOff = false
}

struct AdvancedView: View {
    static let windowID = "advanced"

    let controller: HeadphoneController
    let settings: AppSettings
    let state: AdvancedState

    var body: some View {
        NavigationSplitView {
            List(AdvancedSection.allCases, selection: Binding(get: { state.section }, set: { state.section = $0 })) { section in
                Label(section.title, systemImage: section.symbol)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detail
                .navigationTitle(currentSection.title)
        }
        .frame(minWidth: 700, minHeight: 520)
    }

    private var currentSection: AdvancedSection { state.section ?? .sound }

    @ViewBuilder
    private var detail: some View {
        if currentSection.needsHeadphones, !controller.isConnected {
            ContentUnavailableView(
                "Headphones Not Connected",
                systemImage: "headphones.slash",
                description: Text("Connect the headphones in Bluetooth settings. Sony Control connects to them automatically.")
            )
        } else {
            switch currentSection {
            case .sound: SoundSettings(controller: controller, state: state)
            case .noiseCancelling: NoiseCancellingSettings(controller: controller)
            case .headphones: HeadphoneSettings(controller: controller, state: state)
            case .automations: AutomationSettings(settings: settings)
            case .statistics: StatisticsView(controller: controller)
            }
        }
    }
}

extension HeadphoneController {
    func binding(for deviceSwitch: DeviceSwitch) -> Binding<Bool> {
        Binding(get: { self.switches[deviceSwitch] ?? false }, set: { self.setSwitch(deviceSwitch, $0) })
    }
}

private struct SoundSettings: View {
    let controller: HeadphoneController
    let state: AdvancedState

    var body: some View {
        Form {
            Section {
                Picker("Preset", selection: Binding(get: { controller.equalizer?.preset ?? .off }, set: controller.setEqualizerPreset)) {
                    ForEach(EqualizerPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                LevelSlider(
                    title: "Clear Bass",
                    value: Binding(get: { state.clearBass }, set: { state.clearBass = $0.rounded() }),
                    onCommit: commitBands
                )
                ForEach(Equalizer.bandTitles.indices, id: \.self) { index in
                    LevelSlider(
                        title: Equalizer.bandTitles[index],
                        value: Binding(get: { state.bands[index] }, set: { state.bands[index] = $0.rounded() }),
                        onCommit: commitBands
                    )
                }
            } header: {
                Text("Equalizer")
            } footer: {
                Text("If you move a slider while the preset is not Manual, Custom 1, or Custom 2, the preset changes to Manual.")
            }

            Section {
                Toggle("DSEE Extreme", isOn: controller.binding(for: .dseeExtreme))
            } header: {
                Text("Sound Quality")
            } footer: {
                Text("DSEE Extreme restores detail in compressed music. It uses more battery.")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadEqualizer)
        .onChange(of: controller.equalizer) { loadEqualizer() }
    }

    private func loadEqualizer() {
        guard let equalizer = controller.equalizer else { return }
        state.clearBass = Double(equalizer.clearBass)
        state.bands = equalizer.bands.map(Double.init)
    }

    private func commitBands() {
        controller.setEqualizerBands(clearBass: Int(state.clearBass), bands: state.bands.map { Int($0) })
    }
}

private struct LevelSlider: View {
    let title: String
    let value: Binding<Double>
    let onCommit: () -> Void

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                Slider(
                    value: value,
                    in: Double(Equalizer.levels.lowerBound)...Double(Equalizer.levels.upperBound)
                ) { isEditing in
                    if !isEditing {
                        onCommit()
                    }
                }
                .frame(width: 260)
                Text(signedLevel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
    }

    private var signedLevel: String {
        let level = Int(value.wrappedValue)
        return level > 0 ? "+\(level)" : "\(level)"
    }
}

private struct NoiseCancellingSettings: View {
    let controller: HeadphoneController

    var body: some View {
        Form {
            Section {
                LabeledContent("Air pressure", value: pressureText)
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        if controller.optimizerStatus.isRunning {
                            ProgressView().controlSize(.small)
                        }
                        Text(controller.optimizerStatus.title)
                    }
                }
                HStack {
                    Spacer()
                    if controller.optimizerStatus.isRunning {
                        Button("Cancel", action: controller.cancelOptimizer)
                            .buttonStyle(.glass)
                    } else {
                        Button("Start Optimizer", action: controller.startOptimizer)
                            .buttonStyle(.glassProminent)
                    }
                }
            } header: {
                Text("Noise Cancelling Optimizer")
            } footer: {
                Text("Put on the headphones and stay still. The headphones play test tones to measure the fit and the air pressure. Then they adjust the noise cancelling.")
            }

            if let config = controller.speakToChatConfig {
                Section {
                    Toggle("Speak-to-Chat", isOn: controller.binding(for: .speakToChat))
                    Picker("Voice detection", selection: Binding(get: { config.sensitivity }, set: { value in updateConfig { $0.sensitivity = value } })) {
                        ForEach(SpeakToChatConfig.Sensitivity.allCases) { sensitivity in
                            Text(sensitivity.title).tag(sensitivity)
                        }
                    }
                    Picker("End after silence", selection: Binding(get: { config.timeout }, set: { value in updateConfig { $0.timeout = value } })) {
                        ForEach(SpeakToChatConfig.Timeout.allCases) { timeout in
                            Text(timeout.title).tag(timeout)
                        }
                    }
                    Toggle("Focus on voice", isOn: Binding(get: { config.focusOnVoice }, set: { value in updateConfig { $0.focusOnVoice = value } }))
                } header: {
                    Text("Speak-to-Chat")
                } footer: {
                    Text("When you talk, the headphones pause the music and let in ambient sound. \"End after silence\" sets how long they wait after you stop talking.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var pressureText: String {
        guard let pressure = controller.optimizerPressure else { return "Not measured" }
        return "\(pressure.formatted(.number.precision(.fractionLength(1)))) atm"
    }

    private func updateConfig(_ change: (inout SpeakToChatConfig) -> Void) {
        guard var config = controller.speakToChatConfig else { return }
        change(&config)
        controller.setSpeakToChatConfig(config)
    }
}

private struct HeadphoneSettings: View {
    let controller: HeadphoneController
    let state: AdvancedState

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Pause when taken off", isOn: controller.binding(for: .pauseWhenTakenOff))
                Toggle("Voice guidance", isOn: controller.binding(for: .voiceGuidance))
            }

            Section("Information") {
                LabeledContent("Model", value: controller.deviceName ?? "Unknown")
                LabeledContent("Firmware", value: controller.firmwareVersion ?? "Unknown")
                LabeledContent("Codec", value: controller.codec?.title ?? "Unknown")
                if let battery = controller.battery {
                    LabeledContent("Battery", value: "\(battery.level)%\(battery.isCharging ? ", charging" : "")")
                }
            }

            Section {
                Button("Turn Off Headphones…", role: .destructive) {
                    state.isConfirmingPowerOff = true
                }
            } footer: {
                Text("To turn them on again, push the power button on the headphones.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Turn off the headphones?",
            isPresented: Binding(get: { state.isConfirmingPowerOff }, set: { state.isConfirmingPowerOff = $0 })
        ) {
            Button("Turn Off", role: .destructive, action: controller.powerOff)
        } message: {
            Text("The headphones disconnect from all your devices.")
        }
    }
}

private struct AutomationSettings: View {
    private static let urlCommands = [
        ("nc", "Noise cancelling"),
        ("ambient", "Ambient sound"),
        ("wind", "Wind noise reduction"),
        ("off", "Off"),
        ("cycle", "Next mode"),
    ]

    let settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Ambient sound during calls", isOn: Binding(get: { settings.ambientDuringCalls }, set: { settings.ambientDuringCalls = $0 }))
            } header: {
                Text("Calls")
            } footer: {
                Text("When an app uses the microphone, for example Zoom, FaceTime, or Teams, the headphones change to ambient sound so you hear your own voice. After the call, they change back.")
            }

            Section {
                Toggle("Cycle modes with \(GlobalHotKey.cycleShortcutTitle)", isOn: Binding(get: { settings.cycleShortcut }, set: { settings.cycleShortcut = $0 }))
            } header: {
                Text("Keyboard")
            } footer: {
                Text("The shortcut works in all apps. It changes the mode in this order: noise cancelling, ambient sound, off.")
            }

            Section {
                Toggle("Show battery level in the menu bar", isOn: Binding(get: { settings.batteryInMenuBar }, set: { settings.batteryInMenuBar = $0 }))
                Toggle("Notify me when the battery is low", isOn: Binding(get: { settings.lowBatteryAlert }, set: { settings.lowBatteryAlert = $0 }))
            } header: {
                Text("Battery")
            } footer: {
                Text("The notification comes when the battery is at 20% or less.")
            }

            Section {
                ForEach(Self.urlCommands, id: \.0) { command, title in
                    LabeledContent {
                        Text(title)
                    } label: {
                        Text("sonycontrol://\(command)")
                            .fontDesign(.monospaced)
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("URL Commands")
            } footer: {
                Text("Use these URLs in Shortcuts, Raycast, or the open command in Terminal. The app must be running.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct StatisticsView: View {
    let controller: HeadphoneController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if controller.usageStatistics.isEmpty {
                    ProgressView("Reading the counters…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    GlassEffectContainer(spacing: 12) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(UsageCounter.highlights) { counter in
                                if let value = controller.usageStatistics[counter.key] {
                                    StatisticTile(counter: counter, value: value)
                                }
                            }
                        }
                    }

                    Text("The headphones count these events for their whole life. Sony does not document the counters, so some names are a best guess.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    DisclosureGroup("All counters") {
                        ForEach(controller.usageStatistics.sorted { $0.key < $1.key }, id: \.key) { key, value in
                            LabeledContent(key, value: value.formatted())
                                .fontDesign(.monospaced)
                        }
                    }
                }
            }
            .padding(20)
        }
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise", action: controller.refreshUsageStatistics)
        }
        .onAppear(perform: controller.refreshUsageStatistics)
    }
}

private struct StatisticTile: View {
    let counter: UsageCounter
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: counter.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
            Text(value.formatted())
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Text(counter.title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}
