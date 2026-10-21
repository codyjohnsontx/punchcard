import Foundation

/// What the Settings window's shortcut recorder does with a key pressed while it records. The
/// rules follow the KeyboardShortcuts package's own recorder: Escape cancels, Tab cancels and
/// moves focus on, Delete clears the shortcut, and a shortcut needs Command, Control or Option
/// unless its key is a function key, since Shift alone does not register.
public enum ShortcutRecording {
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Self(rawValue: 1 << 0)
        public static let control = Self(rawValue: 1 << 1)
        public static let option = Self(rawValue: 1 << 2)
        public static let shift = Self(rawValue: 1 << 3)
        public static let function = Self(rawValue: 1 << 4)
    }

    /// The key, as far as the rules care.
    public enum Key: Equatable, Sendable {
        case escape
        case tab
        /// Delete (Backspace).
        case delete
        /// F1 through F20.
        case functionKey
        case other
    }

    public enum Action: Equatable, Sendable {
        /// Stop recording and keep the shortcut as it was.
        case cancel
        /// Stop recording, keep the shortcut and let the key move focus on.
        case cancelAndPassOn
        /// Stop recording and remove the shortcut.
        case clear
        /// Keep recording; `message` says why the key was not taken.
        case reject(message: String)
        /// Stop recording and use the key as the shortcut.
        case record
    }

    public static let needsModifierMessage = "Include Command, Control or Option in the shortcut."

    /// The action for `key` pressed with `modifiers`.
    public static func action(key: Key, modifiers: Modifiers) -> Action {
        if modifiers.isEmpty {
            switch key {
            case .escape: return .cancel
            case .tab: return .cancelAndPassOn
            case .delete: return .clear
            case .functionKey, .other: break
            }
        }
        guard !modifiers.subtracting([.shift, .function]).isEmpty || key == .functionKey else {
            return .reject(message: needsModifierMessage)
        }
        return .record
    }
}
