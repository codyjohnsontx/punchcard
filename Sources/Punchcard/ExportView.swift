import PunchcardCore
import SwiftUI

/// The Export tab: pick a range and a kind, see how many rows the file will have, and
/// save it as CSV.
struct ExportView: View {
    @State private var export: ExportModel

    init(app: AppModel) {
        _export = State(initialValue: ExportModel(app: app))
    }

    var body: some View {
        Form {
            Section {
                Picker("Range", selection: $export.range) {
                    ForEach(ExportModel.Range.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                if export.range == .custom {
                    DatePicker("From", selection: $export.customStart, displayedComponents: .date)
                    DatePicker("Through", selection: $export.customEnd, displayedComponents: .date)
                }
                Picker("Kind", selection: $export.kind) {
                    Text("Entries").tag(CSVExport.Kind.entries)
                    Text("Daily summary").tag(CSVExport.Kind.dailySummary)
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text(kindDescription)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                LabeledContent("File") {
                    if let document = export.document {
                        VStack(alignment: .trailing) {
                            Text(document.fileName).textSelection(.enabled)
                            Text(rowsDescription(document.rowCount)).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(export.problem ?? "Database unavailable").foregroundStyle(.red)
                    }
                }
                HStack {
                    if let saved = export.savedTo {
                        Text("Saved to \(saved.lastPathComponent).")
                            .foregroundStyle(.secondary)
                        Button("Show in Finder") { export.revealSaved() }
                    } else if let error = export.saveError {
                        Text(error).foregroundStyle(.red)
                    }
                    Spacer()
                    Button("Export…") { export.export() }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(export.document == nil)
                        .help("Save the file as CSV")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Export")
        .onAppear { export.reload() }
        .onChange(of: export.range) { export.reload() }
        .onChange(of: export.kind) { export.reload() }
        .onChange(of: export.customStart) { export.reload() }
        .onChange(of: export.customEnd) { export.reload() }
        .onChange(of: export.app.snapshot.running) { export.reload() }
        .frame(minWidth: 480, minHeight: 320)
    }

    private var kindDescription: String {
        switch export.kind {
        case .entries:
            "One row per entry with client, start, end, duration and note. Times carry your "
                + "time zone's offset; an entry that crosses midnight stays one row."
        case .dailySummary:
            "One row per day and client with the hours tracked that day. An entry that crosses "
                + "midnight is split between its days."
        }
    }

    private func rowsDescription(_ count: Int) -> String {
        switch (export.kind, count) {
        case (_, 0): "No rows, header only"
        case (.entries, 1): "1 entry"
        case (.entries, _): "\(count) entries"
        case (.dailySummary, 1): "1 row"
        case (.dailySummary, _): "\(count) rows"
        }
    }
}
