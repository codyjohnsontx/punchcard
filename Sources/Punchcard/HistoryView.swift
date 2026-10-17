import SwiftUI

/// The History window: past days and weeks, entry editing, clients and export arrive in
/// later releases. This is the empty window the dropdown's History… item opens.
struct HistoryView: View {
    static let windowID = "history"

    var body: some View {
        ContentUnavailableView(
            "History",
            systemImage: "calendar",
            description: Text("Past entries, editing, clients and export arrive in a later release."))
    }
}
