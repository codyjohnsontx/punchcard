import AppKit
import PunchcardCore
import SwiftUI

/// The menu bar dropdown: the running clock, Start/Stop, today/week/month totals, and the
/// History, Settings and Quit items.
struct DropdownView: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let openError = model.openError {
                Label(openError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                tracker(model.dropdown)
            }
            if let lastError = model.lastError {
                Text(lastError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 300)
        // External edits (another app, sqlite3) are not observed, so re-read on every open.
        .onAppear { model.refresh() }
    }

    @ViewBuilder
    private func tracker(_ dropdown: DropdownViewModel) -> some View {
        headline(dropdown)
        if dropdown.isSingleClient {
            singleClientButton(dropdown)
        } else {
            clientRows(dropdown.clientRows)
        }
        Divider()
        if dropdown.isSingleClient, let totals = dropdown.totalsRows.first {
            singleClientTotals(totals)
        } else {
            totalsGrid(dropdown.totalsRows)
        }
    }

    private func headline(_ dropdown: DropdownViewModel) -> some View {
        Text(dropdown.headline ?? "Not running")
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(dropdown.isRunning ? .primary : .secondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private func singleClientButton(_ dropdown: DropdownViewModel) -> some View {
        if dropdown.isRunning {
            Button("Stop") { model.stop() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
        } else if let clientID = dropdown.singleClientID {
            Button("Start") { model.start(clientID: clientID) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        } else {
            Text("No active clients.")
                .foregroundStyle(.secondary)
        }
    }

    private func clientRows(_ rows: [DropdownViewModel.ClientRow]) -> some View {
        VStack(spacing: 4) {
            ForEach(rows) { row in
                HStack {
                    Text(row.name)
                        .fontWeight(row.isRunning ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer()
                    Text(row.clock ?? "–")
                        .monospacedDigit()
                        .foregroundStyle(row.isRunning ? .primary : .secondary)
                    if row.isRunning {
                        Button("Stop") { model.stop() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Start") { model.start(clientID: row.id) }
                            .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(row.isRunning ? Color.accentColor.opacity(0.15) : .clear))
            }
        }
    }

    private func singleClientTotals(_ totals: DropdownViewModel.TotalsRow) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            totalLine("Today", totals.today)
            totalLine("This week", totals.week)
            totalLine("This month", totals.month)
        }
    }

    private func totalLine(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit().gridColumnAlignment(.trailing)
        }
    }

    private func totalsGrid(_ rows: [DropdownViewModel.TotalsRow]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text("Today").gridColumnAlignment(.trailing)
                Text("Week").gridColumnAlignment(.trailing)
                Text("Month").gridColumnAlignment(.trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(rows) { row in
                let isAll = row.id == DropdownViewModel.TotalsRow.allID
                if isAll {
                    Divider()
                }
                GridRow {
                    Text(row.name).lineLimit(1)
                    Text(row.today)
                    Text(row.week)
                    Text(row.month)
                }
                .monospacedDigit()
                .fontWeight(isAll ? .semibold : .regular)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("History…") {
                openWindow(id: HistoryView.windowID)
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Settings…") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
    }
}
