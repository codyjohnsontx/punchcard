import AppKit
import PunchcardCore

/// The "keep or drop?" alert shown when the user comes back after being away.
@MainActor
enum AwayAlert {
    enum Choice {
        case keep, dropAndContinue, dropAndStop
    }

    /// Runs the alert modally and returns the choice, or nil when it was aborted with
    /// `NSApp.abortModal()` because the prompt changed and should be asked again.
    static func ask(_ prompt: AwayPrompt) -> Choice? {
        let alert = NSAlert()
        alert.messageText = prompt.message()
        alert.informativeText = "The clock kept running. Keep that time, or drop it?"
        alert.addButton(withTitle: "Keep")
        alert.addButton(withTitle: "Drop & Continue")
        alert.addButton(withTitle: "Drop & Stop")
        // An accessory app is never frontmost on its own.
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keep
        case .alertSecondButtonReturn: return .dropAndContinue
        case .alertThirdButtonReturn: return .dropAndStop
        default: return nil
        }
    }
}
