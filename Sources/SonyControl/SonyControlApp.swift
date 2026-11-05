import AppKit
import SonyKit
import SwiftUI

@main
struct SonyControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ControlPanel(controller: appDelegate.controller, state: appDelegate.panelState)
        } label: {
            MenuBarIcon(controller: appDelegate.controller, settings: appDelegate.settings)
        }
        .menuBarExtraStyle(.window)

        Window("Sony Control", id: AdvancedView.windowID) {
            AdvancedView(controller: appDelegate.controller, settings: appDelegate.settings, state: appDelegate.advancedState)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = HeadphoneController()
    let settings = AppSettings()
    let panelState = PanelState()
    let advancedState = AdvancedState()
    private var automations: Automations?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
        automations = Automations(controller: controller, settings: settings)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handle(url)
        }
    }

    private func handle(_ url: URL) {
        switch url.host()?.lowercased() {
        case "nc", "noise-cancelling": controller.setMode(.noiseCancelling)
        case "ambient": controller.setMode(.ambient)
        case "wind": controller.setMode(.windReduction)
        case "off": controller.setMode(.off)
        case "cycle": controller.cycleMode()
        default: break
        }
    }
}

struct MenuBarIcon: View {
    let controller: HeadphoneController
    let settings: AppSettings

    var body: some View {
        Image(nsImage: menuBarImage)
        if settings.batteryInMenuBar, controller.isConnected, let battery = controller.battery {
            Text("\(battery.level)%")
        }
    }

    private var menuBarImage: NSImage {
        let name = controller.isConnected ? controller.soundControl.mode.menuBarSymbol : "headphones.slash"
        let size = NSSize(width: 18, height: 18)

        // Render at an explicit size because MenuBarExtra controls SwiftUI symbol sizing.
        let image = NSImage(size: size, flipped: false) { bounds in
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return false }
            let scale = min(bounds.width / symbol.size.width, bounds.height / symbol.size.height)
            let symbolSize = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            symbol.draw(in: NSRect(
                x: bounds.midX - symbolSize.width / 2,
                y: bounds.midY - symbolSize.height / 2,
                width: symbolSize.width,
                height: symbolSize.height
            ))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Sony Control"
        return image
    }
}
