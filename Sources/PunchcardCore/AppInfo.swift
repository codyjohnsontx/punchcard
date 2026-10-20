import Foundation

/// App identity used by the app target. The bundle identifier lives in Packaging/Info.plist.
public enum AppInfo {
    public static let name = "Punchcard"

    /// The version `scripts/build-app.sh` stamped into the bundle's Info.plist, or nil when
    /// not running from a bundle, as under `swift run`.
    public static func version(of bundle: Bundle = .main) -> String? {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}
