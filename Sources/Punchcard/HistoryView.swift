import PunchcardCore
import SwiftUI

/// The History window: a sidebar with Entries, Clients and Export. Entries shows past days
/// and weeks and edits entries, Export saves CSV files; Clients arrives in a later release.
struct HistoryView: View {
    static let windowID = "history"

    enum Section: String, CaseIterable, Identifiable {
        case entries = "Entries"
        case clients = "Clients"
        case export = "Export"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .entries: "calendar"
            case .clients: "person.2"
            case .export: "square.and.arrow.up"
            }
        }
    }

    let model: AppModel
    @State private var section: Section? = .entries

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { section in
                Label(section.rawValue, systemImage: section.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 220)
        } detail: {
            if let openError = model.openError {
                ContentUnavailableView(
                    "Database unavailable", systemImage: "exclamationmark.triangle", description: Text(openError))
            } else {
                switch section ?? .entries {
                case .entries:
                    EntriesView(app: model)
                case .clients:
                    ContentUnavailableView(
                        "Clients", systemImage: Section.clients.systemImage,
                        description: Text("Adding, renaming and archiving clients arrives in a later release."))
                case .export:
                    ExportView(app: model)
                }
            }
        }
    }
}
