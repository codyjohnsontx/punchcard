import Foundation
import Observation
import PunchcardCore

/// State of the Settings window: the General tab's values, each written to the `settings`
/// table as it changes and followed by an app model refresh, so the menu bar label, the
/// totals and the away detector pick the change up at once.
@MainActor @Observable
final class SettingsModel {
    let app: AppModel
    private(set) var values = SettingsViewModel()
    /// The last failed read or write, cleared by the next one that succeeds.
    private(set) var error: String?

    /// The login item's status as the OS last reported it; the OS, not the database, holds
    /// the launch at login setting.
    private(set) var loginItemStatus: LoginItemStatus = .notRegistered
    /// The last failed register or unregister, cleared by the next one that succeeds.
    private(set) var loginItemError: String?
    private let loginItem = SystemLoginItem()

    init(app: AppModel) {
        self.app = app
    }

    private var store: SettingsStore? { app.database.map { SettingsStore(database: $0) } }

    /// Re-reads the settings. Called when the window appears, since edits made outside the app
    /// (sqlite3, another copy) are not observed.
    func reload() {
        reloadLoginItem()
        guard let store else { return }
        do {
            values = try SettingsViewModel.load(from: store)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    var menuBarStyle: SettingsStore.MenuBarStyle {
        get { values.menuBarStyle }
        set {
            values.menuBarStyle = newValue
            write { try $0.setMenuBarStyle(newValue) }
        }
    }

    var weekStartDay: Int {
        get { values.weekStartDay }
        set {
            values.weekStartDay = newValue
            write { try $0.setWeekStartDay(newValue) }
        }
    }

    var idleThresholdMinutes: Int {
        get { values.idleThresholdMinutes }
        set {
            values.idleThresholdMinutes = newValue
            let seconds = values.idleThresholdSeconds
            write { try $0.setIdleThresholdSeconds(seconds) }
        }
    }

    /// Re-reads the login item's status. Called when the window appears and whenever the app
    /// becomes active, since the user may have changed it in System Settings.
    func reloadLoginItem() {
        loginItemStatus = loginItem.status
    }

    var launchAtLogin: LaunchAtLoginViewModel { LaunchAtLoginViewModel(status: loginItemStatus, isBundled: loginItem.isBundled) }

    var launchesAtLogin: Bool {
        get { launchAtLogin.isOn }
        set {
            do {
                if newValue { try loginItem.register() } else { try loginItem.unregister() }
                loginItemError = nil
            } catch {
                loginItemError = error.localizedDescription
            }
            reloadLoginItem()
        }
    }

    func openLoginItemsSettings() {
        loginItem.openSystemSettings()
    }

    private func write(_ change: (SettingsStore) throws -> Void) {
        guard let store else { return }
        do {
            try change(store)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        // The label re-reads its style and the totals their week start on refresh; the away
        // detector reads the threshold from the store on every tick.
        app.refresh()
    }
}
