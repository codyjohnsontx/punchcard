import AppKit
import PunchcardCore
import SwiftUI

@main
struct PunchcardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        // `.window` because the dropdown holds buttons, client rows and live totals, which
        // the `.menu` style cannot render.
        MenuBarExtra {
            DropdownView(model: model)
        } label: {
            MenuBarLabelView(label: model.label)
        }
        .menuBarExtraStyle(.window)

        Window("History", id: HistoryView.windowID) {
            HistoryView(model: model)
        }
        .defaultSize(width: 720, height: 480)

        Settings {
            SettingsView()
        }
    }
}

struct MenuBarLabelView: View {
    let label: MenuBarLabel

    var body: some View {
        switch label {
        case .icon(let systemName):
            Image(systemName: systemName)
        case .text(let text):
            Text(text).monospacedDigit()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Info.plist sets LSUIElement for the bundle; `swift run` has no Info.plist,
        // so set the policy in code to keep the Dock icon away in both modes.
        NSApp.setActivationPolicy(.accessory)
    }

    // Nothing stops on quit: a running entry is a row with a NULL end and keeps running
    // across a relaunch.
}
