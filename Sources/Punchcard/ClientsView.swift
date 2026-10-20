import PunchcardCore
import SwiftUI

/// The Clients tab: every client with its entry count, Add Client in the toolbar, and Rename,
/// Archive or Unarchive and Delete for the selected one. Delete is only offered to a client
/// without entries; one with entries is archived instead, which hides it from the dropdown and
/// the pickers while its time stays in history.
struct ClientsView: View {
    @State private var model: ClientsModel
    @State private var selection: ClientsViewModel.Row.ID?

    init(app: AppModel) {
        _model = State(initialValue: ClientsModel(app: app))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let clients = model.clients {
                table(clients)
                Divider()
                actionBar(clients.row(id: selection ?? -1))
            } else {
                Color.clear
            }
        }
        .navigationTitle("Clients")
        .navigationSubtitle(subtitle)
        .toolbar {
            Button { model.add() } label: {
                Label("Add Client", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("Add a client")
        }
        .sheet(item: $model.naming) { naming in
            ClientNameSheet(model: model, naming: naming)
        }
        .confirmationDialog(
            "Delete this client?", isPresented: isDeleting, titleVisibility: .visible, presenting: model.deleting
        ) { row in
            Button("Delete", role: .destructive) { model.delete(row) }
        } message: { row in
            Text("\(row.name) has no entries and will be removed. This can't be undone.")
        }
        .overlay(alignment: .bottom) {
            if let error = model.error {
                Text(error)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .padding(.bottom, 36)
            }
        }
        .onAppear { model.reload() }
        // External edits are not observed; the app model's snapshot changes after every write
        // it makes, when the dropdown opens, and once a second while a clock runs.
        .onChange(of: model.app.snapshot) { model.reload() }
        .frame(minWidth: 560, minHeight: 320)
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { model.deleting != nil }, set: { if !$0 { model.deleting = nil } })
    }

    private var subtitle: String {
        guard let clients = model.clients else { return "" }
        let archived = clients.rows.count - clients.activeCount
        let active = clients.activeCount == 1 ? "1 active client" : "\(clients.activeCount) active clients"
        return archived == 0 ? active : "\(active), \(archived) archived"
    }

    private func table(_ clients: ClientsViewModel) -> some View {
        Table(clients.rows, selection: $selection) {
            TableColumn("Name") { row in
                HStack(spacing: 6) {
                    Text(row.name)
                        .fontWeight(row.isRunning ? .semibold : .regular)
                        .foregroundStyle(row.isArchived ? .secondary : .primary)
                    if row.isRunning {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(Color.accentColor)
                            .help("The clock is running for this client")
                            .accessibilityLabel("Running")
                    }
                }
            }
            TableColumn("Status") { row in
                Text(row.isArchived ? "Archived" : "Active")
                    .foregroundStyle(row.isArchived ? .secondary : .primary)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Entries") { row in
                Text(row.entryCount == 0 ? "–" : "\(row.entryCount)")
                    .monospacedDigit()
                    .foregroundStyle(row.entryCount == 0 ? .tertiary : .primary)
            }
            .width(min: 60, ideal: 80)
            TableColumn("") { row in
                if row.suggestsArchive {
                    Text("Archive instead")
                        .foregroundStyle(.secondary)
                        .help("This client has entries and can't be deleted. Archive it instead.")
                }
            }
        }
        .contextMenu(forSelectionType: ClientsViewModel.Row.ID.self) { ids in
            if let row = row(ids, in: clients) {
                rowActions(row)
            }
        } primaryAction: { ids in
            if let row = row(ids, in: clients) { model.rename(row) }
        }
        .onDeleteCommand {
            if let row = clients.row(id: selection ?? -1), row.canDelete {
                model.deleting = row
            }
        }
    }

    @ViewBuilder
    private func rowActions(_ row: ClientsViewModel.Row) -> some View {
        Button("Rename…") { model.rename(row) }
        if row.isArchived {
            Button("Unarchive") { model.unarchive(row) }
        } else {
            Button("Archive") { model.archive(row) }
                .disabled(!row.canArchive)
                .help(row.isRunning ? "Stop the clock before archiving this client" : "Hide this client from the dropdown; its time stays in history")
        }
        Button("Delete…", role: .destructive) { model.deleting = row }
            .disabled(!row.canDelete)
            .help(row.canDelete ? "Remove this client" : row.suggestsArchive ? "This client has entries and can't be deleted. Archive it instead." : "This client has entries and can't be deleted.")
    }

    /// The actions for the selected client, with the reason when one is unavailable.
    private func actionBar(_ row: ClientsViewModel.Row?) -> some View {
        HStack(spacing: 8) {
            if let row {
                rowActions(row)
                if row.isRunning {
                    hint("The clock is running. Stop it before archiving.")
                } else if row.suggestsArchive {
                    hint("Has entries. Archive it instead of deleting.")
                } else if !row.canDelete {
                    hint("Has entries, so it can't be deleted.")
                }
            } else {
                Text("Select a client to rename, archive or delete it.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).lineLimit(1)
    }

    private func row(_ ids: Set<ClientsViewModel.Row.ID>, in clients: ClientsViewModel) -> ClientsViewModel.Row? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return clients.row(id: id)
    }
}

/// The sheet that names a new client or renames one. A blank name, or one that another
/// client already uses in any case, is refused with a message.
private struct ClientNameSheet: View {
    let model: ClientsModel
    @State private var naming: ClientsModel.Naming
    @State private var error: String?
    @FocusState private var isNameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: ClientsModel, naming: ClientsModel.Naming) {
        self.model = model
        _naming = State(initialValue: naming)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(naming.isNew ? "Add Client" : "Rename Client")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)
            Form {
                TextField("Name", text: $naming.name, prompt: Text("Client or project"))
                    .focused($isNameFocused)
                    .onSubmit { save() }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            VStack(alignment: .leading, spacing: 6) {
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(naming.isNew ? "Add" : "Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 380)
        .onAppear { isNameFocused = true }
    }

    private func save() {
        do {
            try model.save(naming)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
