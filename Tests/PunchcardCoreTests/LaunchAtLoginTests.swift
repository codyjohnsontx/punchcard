import Foundation
@testable import PunchcardCore
import Testing

@MainActor
private final class FakeLoginItem: LoginItem {
    let isBundled: Bool
    var status: LoginItemStatus
    var registerCount = 0
    var registerError: Error?

    init(status: LoginItemStatus, isBundled: Bool = true) {
        self.status = status
        self.isBundled = isBundled
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        status = .notRegistered
    }
}

private struct RegisterFailed: Error {}

@MainActor @Suite struct LaunchAtLoginTests {
    let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func firstLaunchRegistersOnceAndRecordsOnboardedAt() throws {
        let store = SettingsStore(database: try .inMemory())
        let item = FakeLoginItem(status: .notRegistered)

        #expect(try LaunchAtLogin.onboardIfNeeded(store: store, loginItem: item, now: t0) == .registered)
        #expect(item.registerCount == 1)
        #expect(item.status == .enabled)
        #expect(try store.onboardedAt == t0)

        // The user turns it off; later launches leave it off.
        try item.unregister()
        for _ in 0..<3 {
            #expect(try LaunchAtLogin.onboardIfNeeded(store: store, loginItem: item, now: t0.addingTimeInterval(60)) == .alreadyOnboarded)
        }
        #expect(item.registerCount == 1)
        #expect(item.status == .notRegistered)
        #expect(try store.onboardedAt == t0)
    }

    @Test func outsideABundleNothingIsRegisteredOrRecorded() throws {
        let store = SettingsStore(database: try .inMemory())
        let item = FakeLoginItem(status: .notFound, isBundled: false)

        #expect(try LaunchAtLogin.onboardIfNeeded(store: store, loginItem: item, now: t0) == .notBundled)
        #expect(item.registerCount == 0)
        #expect(try store.onboardedAt == nil)

        let row = LaunchAtLoginViewModel(status: item.status, isBundled: item.isBundled)
        #expect(!row.isOn && !row.isToggleEnabled && !row.showsOpenSystemSettings)
        #expect(row.message == LaunchAtLoginViewModel.notBundledText)

        // The bundled app, sharing the same database, still onboards.
        let bundled = FakeLoginItem(status: .notRegistered)
        #expect(try LaunchAtLogin.onboardIfNeeded(store: store, loginItem: bundled, now: t0) == .registered)
        #expect(bundled.registerCount == 1)
    }

    @Test func aBundledAppTheOSCannotFindStillRegistersAndCanBeToggled() throws {
        let store = SettingsStore(database: try .inMemory())
        let item = FakeLoginItem(status: .notFound)

        let row = LaunchAtLoginViewModel(status: item.status, isBundled: item.isBundled)
        #expect(!row.isOn && row.isToggleEnabled && row.message == nil && !row.showsOpenSystemSettings)

        #expect(try LaunchAtLogin.onboardIfNeeded(store: store, loginItem: item, now: t0) == .registered)
        #expect(item.registerCount == 1)
        #expect(item.status == .enabled)
        #expect(try store.onboardedAt == t0)
    }

    @Test func aFailedRegistrationIsRetriedNextLaunch() throws {
        let store = SettingsStore(database: try .inMemory())
        let item = FakeLoginItem(status: .notRegistered)
        item.registerError = RegisterFailed()

        #expect(throws: RegisterFailed.self) { try LaunchAtLogin.onboardIfNeeded(store: store, loginItem: item, now: t0) }
        #expect(try store.onboardedAt == nil)

        item.registerError = nil
        #expect(try LaunchAtLogin.onboardIfNeeded(store: store, loginItem: item, now: t0) == .registered)
        #expect(item.registerCount == 2)
    }

    @Test func settingsRowShowsEachStatus() {
        let enabled = LaunchAtLoginViewModel(status: .enabled, isBundled: true)
        #expect(enabled.isOn && enabled.isToggleEnabled && enabled.message == nil && !enabled.showsOpenSystemSettings)

        let off = LaunchAtLoginViewModel(status: .notRegistered, isBundled: true)
        #expect(!off.isOn && off.isToggleEnabled && off.message == nil && !off.showsOpenSystemSettings)

        let approval = LaunchAtLoginViewModel(status: .requiresApproval, isBundled: true)
        #expect(!approval.isOn && approval.isToggleEnabled && approval.showsOpenSystemSettings)
        #expect(approval.message == "Approve Punchcard in System Settings > General > Login Items")

        let notFound = LaunchAtLoginViewModel(status: .notFound, isBundled: true)
        #expect(!notFound.isOn && notFound.isToggleEnabled && notFound.message == nil && !notFound.showsOpenSystemSettings)

        for status in [LoginItemStatus.enabled, .notRegistered, .requiresApproval, .notFound] {
            let notBundled = LaunchAtLoginViewModel(status: status, isBundled: false)
            #expect(!notBundled.isOn && !notBundled.isToggleEnabled && !notBundled.showsOpenSystemSettings)
            #expect(notBundled.message == LaunchAtLoginViewModel.notBundledText)
        }
    }
}
