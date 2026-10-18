import SwiftUI

/// The Settings window; its controls arrive in a later release. This is the empty window
/// the dropdown's Settings… item opens.
struct SettingsView: View {
    var body: some View {
        ContentUnavailableView(
            "Settings",
            systemImage: "gearshape",
            description: Text("Menu bar style, week start and more arrive in a later release."))
            .frame(width: 420, height: 240)
    }
}
