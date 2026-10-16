import AppKit
import PunchcardCore
import SwiftUI

@main
struct PunchcardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(AppInfo.name, systemImage: "clock") {
            Button("Quit \(AppInfo.name)") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Info.plist sets LSUIElement for the bundle; `swift run` has no Info.plist,
        // so set the policy in code to keep the Dock icon away in both modes.
        NSApp.setActivationPolicy(.accessory)
    }
}
