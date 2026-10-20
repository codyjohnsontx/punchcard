import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// The global start/stop shortcut. It has no default, so it is off until the user records
    /// one in Settings; the KeyboardShortcuts package keeps it in the app's user defaults.
    static let startStop = Self("startStop")
}

extension KeyboardShortcuts.Shortcut {
    /// The binding the recorder suggests while none is set: Control-Option-P.
    static let suggested = Self(.p, modifiers: [.control, .option])

    /// The shortcut as Settings shows it, such as ⌃⌥P. Space is named here because the
    /// package's `description` reads that name from its `Bundle.module` (see `ShortcutRecorder`).
    @MainActor var displayName: String {
        key == .space ? modifiers.ks_symbolicRepresentation + "Space" : description
    }
}
