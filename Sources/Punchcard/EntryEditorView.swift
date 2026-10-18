import PunchcardCore
import SwiftUI

/// The sheet that adds or edits one entry: client, start, end, note. The end must not be
/// before the start; an overlap with another entry only shows a warning.
struct EntryEditorView: View {
    let history: HistoryModel
    @State private var editing: HistoryModel.Editing
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(history: HistoryModel, editing: HistoryModel.Editing) {
        self.history = history
        _editing = State(initialValue: editing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing.entryID == nil ? "Add Entry" : "Edit Entry")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)
            Form {
                Picker("Client", selection: $editing.draft.clientID) {
                    if editing.draft.clientID == nil {
                        Text("Choose…").tag(Int64?.none)
                    }
                    ForEach(history.clientChoices(including: editing.draft.clientID)) { client in
                        Text(client.name).tag(client.id)
                    }
                }
                DatePicker("Start", selection: $editing.draft.startedAt, displayedComponents: [.date, .hourAndMinute])
                if editing.wasRunning {
                    Toggle("Still running", isOn: isRunning)
                }
                if let end = Binding($editing.draft.endedAt) {
                    DatePicker("End", selection: end, displayedComponents: [.date, .hourAndMinute])
                }
                LabeledContent("Duration", value: duration)
                TextField("Note", text: $editing.draft.note, prompt: Text("Optional"))
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            VStack(alignment: .leading, spacing: 6) {
                if overlapCount > 0 {
                    Label(
                        overlapCount == 1 ? "Overlaps another entry" : "Overlaps \(overlapCount) other entries",
                        systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
    }

    private var isRunning: Binding<Bool> {
        Binding(
            get: { editing.draft.isRunning },
            set: { running in
                editing.draft.endedAt = running ? nil : max(Date(), editing.draft.startedAt)
            })
    }

    private var duration: String {
        guard let end = editing.draft.endedAt else { return "Running" }
        return DurationFormatter.hoursMinutes(Int(end.timeIntervalSince(editing.draft.startedAt).rounded(.down)))
    }

    private var overlapCount: Int {
        history.overlapCount(of: editing.draft, excluding: editing.entryID)
    }

    private func save() {
        do {
            try history.save(editing)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
