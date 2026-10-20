import Foundation

/// Whether the app opens at login, as the OS reports it. Mirrors `SMAppService.Status`, which
/// the app target maps into this so the logic below can be tested without the OS.
public enum LoginItemStatus: Equatable, Sendable {
    /// Registered and allowed to open at login.
    case enabled
    /// Not registered, or turned off.
    case notRegistered
    /// Registered, but the user turned it off in System Settings > General > Login Items.
    case requiresApproval
    /// The OS cannot find the login item: under `swift run`, where there is no app bundle, or
    /// for a bundled app that was moved or renamed, or removed from Login Items.
    case notFound
}

/// The OS login item for the app: `SMAppService.mainApp` in the app, a fake in tests.
@MainActor
public protocol LoginItem {
    /// Whether the app runs from an app bundle; under `swift run` it does not.
    var isBundled: Bool { get }
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// Launch at login is on by default: the first launch from an app bundle registers the login
/// item and records `onboarded_at`, and no later launch registers again, so a user who turns it
/// off, here or in System Settings, stays off. The OS is the source of truth for the setting
/// itself, so nothing about it is stored beyond `onboarded_at`.
public enum LaunchAtLogin {
    public enum FirstLaunchOutcome: Equatable, Sendable {
        /// `onboarded_at` was already set; nothing was done.
        case alreadyOnboarded
        /// Not running from an app bundle; nothing was done, so the bundled app still onboards.
        case notBundled
        /// The login item was registered and `onboarded_at` recorded.
        case registered
    }

    /// Runs the first-launch tasks unless they already ran. A failed registration throws and
    /// leaves `onboarded_at` unset, so the next launch tries again.
    @MainActor @discardableResult
    public static func onboardIfNeeded(store: SettingsStore, loginItem: LoginItem, now: Date = Date()) throws -> FirstLaunchOutcome {
        guard try store.onboardedAt == nil else { return .alreadyOnboarded }
        guard loginItem.isBundled else { return .notBundled }
        try loginItem.register()
        try store.setOnboardedAt(now)
        return .registered
    }

    /// Turns launch at login on or off from Settings. A change that succeeds is the user's own
    /// choice, so it also records `onboarded_at` when a failed first launch left it unset;
    /// otherwise the next launch would register again over a user who turned it off. `store`
    /// is nil when the database could not be opened.
    @MainActor
    public static func setEnabled(_ enabled: Bool, store: SettingsStore?, loginItem: LoginItem, now: Date = Date()) throws {
        if enabled { try loginItem.register() } else { try loginItem.unregister() }
        if let store, try store.onboardedAt == nil {
            try store.setOnboardedAt(now)
        }
    }
}

/// What the Settings window's launch at login row shows for a login item status.
public struct LaunchAtLoginViewModel: Equatable, Sendable {
    public static let approvalText = "Approve Punchcard in System Settings > General > Login Items"
    public static let notBundledText = "Only available when Punchcard runs from its app bundle, not from swift run."

    /// Whether the toggle shows on.
    public let isOn: Bool
    /// Whether the toggle can be changed.
    public let isToggleEnabled: Bool
    /// The explanation under the toggle, if any.
    public let message: String?
    /// Whether to offer the button that opens System Settings > General > Login Items.
    public let showsOpenSystemSettings: Bool

    public init(status: LoginItemStatus, isBundled: Bool) {
        guard isBundled else {
            (isOn, isToggleEnabled, message, showsOpenSystemSettings) = (false, false, Self.notBundledText, false)
            return
        }
        switch status {
        case .enabled:
            (isOn, isToggleEnabled, message, showsOpenSystemSettings) = (true, true, nil, false)
        case .notRegistered, .notFound:
            (isOn, isToggleEnabled, message, showsOpenSystemSettings) = (false, true, nil, false)
        case .requiresApproval:
            (isOn, isToggleEnabled, message, showsOpenSystemSettings) = (false, true, Self.approvalText, true)
        }
    }
}
