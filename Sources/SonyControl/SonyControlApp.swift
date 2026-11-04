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
            MenuBarIcon(controller: appDelegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = HeadphoneController()
    let panelState = PanelState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
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

    var body: some View {
        Image(systemName: controller.isConnected ? controller.soundControl.mode.menuBarSymbol : "headphones.slash")
    }
}
