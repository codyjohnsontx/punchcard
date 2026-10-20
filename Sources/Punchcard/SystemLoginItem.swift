import Foundation
import PunchcardCore
import ServiceManagement

/// The app's login item through `SMAppService.mainApp`. Under `swift run` there is no app
/// bundle, so `isBundled` is false.
@MainActor
struct SystemLoginItem: LoginItem {
    private var service: SMAppService { .mainApp }

    var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var status: LoginItemStatus {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .notRegistered
        @unknown default: .notRegistered
        }
    }

    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
