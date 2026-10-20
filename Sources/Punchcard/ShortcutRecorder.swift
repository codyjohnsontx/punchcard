import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import Observation
import PunchcardCore

/// Records the global start/stop shortcut for the Settings window. The KeyboardShortcuts
/// package stores the shortcut and registers the hot key, but its own recorder view is not
/// used: it reads its strings through the package's `Bundle.module`, which looks for the
/// resource bundle at the `.app` root or in the build folder, finds neither in the packaged
/// app (the bundle sits in Contents/Resources) and stops the app with a fatal error.
@MainActor @Observable
final class ShortcutRecorder {
    private(set) var shortcut = KeyboardShortcuts.getShortcut(for: .startStop)
    private(set) var isRecording = false
    /// Why the last key pressed while recording was not taken.
    private(set) var rejection: String?
    @ObservationIgnored private var monitor: Any?

    func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    func startRecording() {
        guard !isRecording else { return }
        // Pressing the current shortcut while recording should record it, not start the clock.
        KeyboardShortcuts.disable(.startStop)
        isRecording = true
        rejection = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        KeyboardShortcuts.enable(.startStop)
    }

    func clear() {
        KeyboardShortcuts.setShortcut(nil, for: .startStop)
        shortcut = nil
        rejection = nil
        stopRecording()
    }

    /// Returns the event to let it through, or nil to swallow it.
    private func handle(_ event: NSEvent) -> NSEvent? {
        let candidate = KeyboardShortcuts.Shortcut(event: event)
        let action = ShortcutRecording.action(
            key: Self.key(of: event), modifiers: Self.modifiers(of: event),
            isTakenBySystem: candidate?.isUsedByMacOS ?? false)
        switch action {
        case .cancel:
            stopRecording()
            return nil
        case .cancelAndPassOn:
            stopRecording()
            return event
        case .clear:
            clear()
            return nil
        case .reject(let message):
            rejection = message
            NSSound.beep()
            return nil
        case .record:
            guard let candidate else {
                NSSound.beep()
                return nil
            }
            KeyboardShortcuts.setShortcut(candidate, for: .startStop)
            shortcut = candidate
            rejection = nil
            stopRecording()
            return nil
        }
    }

    private static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static func key(of event: NSEvent) -> ShortcutRecording.Key {
        switch Int(event.keyCode) {
        case kVK_Escape: .escape
        case kVK_Tab: .tab
        case kVK_Delete: .delete
        case let code where functionKeyCodes.contains(code): .functionKey
        default: .other
        }
    }

    private static func modifiers(of event: NSEvent) -> ShortcutRecording.Modifiers {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: ShortcutRecording.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.function) { modifiers.insert(.function) }
        return modifiers
    }
}
