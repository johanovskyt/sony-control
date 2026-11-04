import ServiceManagement
import SonyKit
import SwiftUI

@MainActor
@Observable
final class PanelState {
    var ambientLevel: Double = 10
    var opensAtLogin = SMAppService.mainApp.status == .enabled
}

struct ControlPanel: View {
    let controller: HeadphoneController
    let state: PanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DeviceHeader(controller: controller)

            if controller.isConnected {
                ModePicker(selection: controller.soundControl.mode, onSelect: controller.setMode)

                if controller.soundControl.mode == .ambient {
                    AmbientSettings(controller: controller, state: state)
                        .transition(.blurReplace)
                }

                if let speakToChat = controller.speakToChat {
                    GlassCard {
                        SwitchRow(
                            title: "Speak-to-Chat",
                            symbol: "bubble.left.and.bubble.right",
                            isOn: Binding(get: { speakToChat }, set: controller.setSpeakToChat)
                        )
                    }
                }
            } else {
                ConnectionStatus(controller: controller)
            }

            PanelFooter(state: state)
        }
        .padding(16)
        .frame(width: 320)
        .animation(.smooth(duration: 0.3), value: controller.soundControl.mode)
        .onAppear(perform: controller.reconnectIfNeeded)
    }
}

private struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

private struct DeviceHeader: View {
    let controller: HeadphoneController

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.deviceName ?? "Sony Headphones")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            if let battery = controller.battery {
                BatteryLabel(battery: battery)
            }
        }
    }

    private var subtitle: String {
        switch controller.connection {
        case .connected: controller.soundControl.mode.title
        case .searching, .connecting: "Connecting…"
        case .unavailable: "Not connected"
        }
    }
}

private struct BatteryLabel: View {
    let battery: Battery

    var body: some View {
        Label("\(battery.level)%", systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
            .help(battery.isCharging ? "Charging" : "Battery level")
    }

    private var symbol: String {
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.level {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

private struct ModePicker: View {
    let selection: NoiseMode
    let onSelect: (NoiseMode) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(NoiseMode.allCases) { mode in
                    ModeButton(mode: mode, isSelected: mode == selection) { onSelect(mode) }
                }
            }
        }
    }
}

private struct ModeButton: View {
    let mode: NoiseMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(width: 50, height: 50)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor.gradient)
                        }
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                Text(mode.shortTitle)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(mode.title)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AmbientSettings: View {
    let controller: HeadphoneController
    let state: PanelState

    var body: some View {
        GlassCard {
            HStack {
                Label("Ambient level", systemImage: "ear")
                Spacer()
                Text("\(Int(state.ambientLevel))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: state.ambientLevel))
            }

            Slider(
                value: Binding(get: { state.ambientLevel }, set: { state.ambientLevel = $0.rounded() }),
                in: Double(SoundControl.ambientLevels.lowerBound)...Double(SoundControl.ambientLevels.upperBound)
            ) { isEditing in
                if !isEditing {
                    controller.setAmbientLevel(Int(state.ambientLevel))
                }
            }

            SwitchRow(
                title: "Focus on voice",
                symbol: "person.wave.2",
                isOn: Binding(get: { controller.soundControl.focusOnVoice }, set: controller.setFocusOnVoice)
            )
        }
        .onAppear { state.ambientLevel = Double(controller.soundControl.ambientLevel) }
        .onChange(of: controller.soundControl.ambientLevel) { _, newLevel in
            state.ambientLevel = Double(newLevel)
        }
    }
}

private struct SwitchRow: View {
    let title: String
    let symbol: String
    let isOn: Binding<Bool>

    var body: some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

private struct ConnectionStatus: View {
    let controller: HeadphoneController

    var body: some View {
        GlassCard {
            switch controller.connection {
            case .searching, .connecting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to the headphones…")
                        .foregroundStyle(.secondary)
                }
            case .unavailable(let reason):
                Text(reason)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again", action: controller.connect)
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
            case .connected:
                EmptyView()
            }
        }
        .font(.callout)
    }
}

private struct PanelFooter: View {
    let state: PanelState

    var body: some View {
        HStack {
            Toggle("Open at login", isOn: Binding(get: { state.opensAtLogin }, set: updateLoginItem))
                .toggleStyle(.checkbox)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.glass)
        }
        .controlSize(.small)
        .padding(.top, 2)
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {}
        state.opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}
