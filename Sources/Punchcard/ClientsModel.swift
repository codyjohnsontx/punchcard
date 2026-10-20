import Foundation
import Observation
import PunchcardCore

/// State of the Clients tab: the rows, the client being named or deleted, and the last error.
/// Every write goes through `ClientEditor` and then refreshes the app model, so the dropdown
/// gains or loses its client rows at once.
@MainActor @Observable
final class ClientsModel {
    /// A client open in the name sheet; `client` is nil when adding a new one.
    struct Naming: Identifiable {
        let id = UUID()
        let client: Client?
        var name: String

        var isNew: Bool { client == nil }
    }

    let app: AppModel
    private(set) var clients: ClientsViewModel?
    var naming: Naming?
    /// The row awaiting the delete confirmation.
    var deleting: ClientsViewModel.Row?
    /// The last failed write, cleared by the next write that succeeds.
    private var writeError: String?
    /// The last failed read, cleared by the next read that succeeds.
    private var readError: String?
    var error: String? { writeError ?? readError }

    init(app: AppModel) {
        self.app = app
    }

    /// Re-reads the rows. Called on appear, after every write, and whenever the app model's
    /// snapshot changes.
    func reload() {
        guard let database = app.database else { return }
        do {
            clients = try ClientsViewModel.load(from: database)
            readError = nil
        } catch {
            readError = error.localizedDescription
        }
    }

    func add() {
        naming = Naming(client: nil, name: "")
    }

    func rename(_ row: ClientsViewModel.Row) {
        naming = Naming(client: row.client, name: row.name)
    }

    /// Adds or renames the client named in the sheet; a blank or duplicate name throws.
    func save(_ naming: Naming) throws {
        guard let database = app.database else { return }
        let editor = ClientEditor(database: database)
        if let id = naming.client?.id {
            try editor.rename(id: id, to: naming.name)
        } else {
            try editor.add(name: naming.name)
        }
        writeError = nil
        didWrite()
    }

    func archive(_ row: ClientsViewModel.Row) {
        perform { try $0.archive(id: row.id) }
    }

    func unarchive(_ row: ClientsViewModel.Row) {
        perform { try $0.unarchive(id: row.id) }
    }

    func delete(_ row: ClientsViewModel.Row) {
        perform { try $0.delete(id: row.id) }
    }

    private func perform(_ action: (ClientEditor) throws -> Void) {
        guard let database = app.database else { return }
        do {
            try action(ClientEditor(database: database))
            writeError = nil
        } catch {
            writeError = error.localizedDescription
        }
        didWrite()
    }

    private func didWrite() {
        // The dropdown re-reads its clients; its snapshot change then reloads this view too.
        app.refresh()
        reload()
    }
}
