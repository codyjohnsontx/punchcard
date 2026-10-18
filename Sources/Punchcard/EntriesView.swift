import PunchcardCore
import SwiftUI

/// The Entries tab: Day | Week, previous/next/Today, a date picker and Add Entry in the
/// toolbar; the Day table or the Week grid below.
struct EntriesView: View {
    @State private var history: HistoryModel

    init(app: AppModel) {
        _history = State(initialValue: HistoryModel(app: app))
    }

    var body: some View {
        Group {
            switch history.mode {
            case .day: DayView(history: history)
            case .week: WeekView(history: history)
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .sheet(item: $history.editing) { editing in
            EntryEditorView(history: history, editing: editing)
        }
        .confirmationDialog(
            "Delete this entry?", isPresented: isDeleting, titleVisibility: .visible, presenting: history.deleting
        ) { row in
            Button("Delete", role: .destructive) { history.delete(row) }
        } message: { row in
            Text("\(row.clientName), \(row.entry.startedAt.formatted(date: .abbreviated, time: .shortened)). This can't be undone.")
        }
        .overlay(alignment: .bottom) {
            if let error = history.error {
                Text(error)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
        .onAppear { history.reload() }
        .onChange(of: history.mode) { history.reload() }
        .onChange(of: history.date) { history.reload() }
        // External edits are not observed; the app model's snapshot changes after every write
        // it makes, when the dropdown opens, and once a second while a clock runs.
        .onChange(of: history.app.snapshot) { history.reload() }
        .frame(minWidth: 560, minHeight: 320)
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { history.deleting != nil }, set: { if !$0 { history.deleting = nil } })
    }

    private var title: String {
        switch history.mode {
        case .day:
            return history.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        case .week:
            guard let week = history.week else { return "Week" }
            // The interval's end is the next week's first midnight; show the last day instead.
            return (week.interval.start..<(week.interval.end - 1)).formatted(.interval.month(.abbreviated).day().year())
        }
    }

    private var subtitle: String {
        let seconds = history.mode == .day ? history.day?.totalSeconds : history.week?.totalSeconds
        return seconds.map { "Total \(DurationFormatter.hoursMinutes($0))" } ?? ""
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Picker("View", selection: $history.mode) {
                ForEach(HistoryModel.Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        ToolbarItemGroup {
            Button { history.showPrevious() } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .help(history.mode == .day ? "Previous day" : "Previous week")
            Button("Today") { history.showToday() }
                .keyboardShortcut("t", modifiers: .command)
            Button { history.showNext() } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .help(history.mode == .day ? "Next day" : "Next week")
            DatePicker("Date", selection: $history.date, displayedComponents: .date)
                .labelsHidden()
            Button { history.addEntry() } label: {
                Label("Add Entry", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("Add an entry on this day")
        }
    }
}

/// One day's entries: client, start, end, duration, note, and a warning badge on an entry
/// that overlaps another. Double-click or the context menu edits; delete asks first.
private struct DayView: View {
    let history: HistoryModel
    @State private var selection: DayViewModel.Row.ID?

    var body: some View {
        if let day = history.day {
            if day.rows.isEmpty {
                ContentUnavailableView(
                    "No entries", systemImage: "clock",
                    description: Text("Nothing was tracked on this day. Add Entry records time by hand."))
            } else {
                table(day)
            }
        } else {
            Color.clear
        }
    }

    private func table(_ day: DayViewModel) -> some View {
        Table(day.rows, selection: $selection) {
            TableColumn("Client") { row in
                Text(row.clientName).fontWeight(row.isRunning ? .semibold : .regular)
            }
            TableColumn("Start") { row in
                time(row.entry.startedAt, outside: row.startsBeforeDay)
            }
            .width(min: 90, ideal: 130)
            TableColumn("End") { row in
                if let end = row.entry.endedAt {
                    time(end, outside: row.endsAfterDay)
                } else {
                    Text("Running").foregroundStyle(.secondary)
                }
            }
            .width(min: 90, ideal: 130)
            TableColumn("Duration") { row in
                HStack(spacing: 4) {
                    Text(DurationFormatter.hoursMinutes(row.secondsInDay))
                    if row.isPartial {
                        Text("of \(DurationFormatter.hoursMinutes(row.seconds))")
                            .foregroundStyle(.secondary)
                            .help("Only part of this entry falls on this day")
                    }
                }
                .monospacedDigit()
            }
            .width(min: 80, ideal: 110)
            TableColumn("Note") { row in
                Text(row.entry.note).lineLimit(1).foregroundStyle(.secondary)
            }
            TableColumn("") { row in
                if row.overlaps {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help("Overlaps another entry")
                        .accessibilityLabel("Overlaps another entry")
                }
            }
            .width(24)
        }
        .contextMenu(forSelectionType: DayViewModel.Row.ID.self) { ids in
            if let row = row(ids, in: day) {
                Button("Edit…") { history.edit(row) }
                Button("Delete…", role: .destructive) { history.deleting = row }
            }
        } primaryAction: { ids in
            if let row = row(ids, in: day) { history.edit(row) }
        }
        .onDeleteCommand {
            if let id = selection, let row = day.rows.first(where: { $0.id == id }) {
                history.deleting = row
            }
        }
    }

    private func row(_ ids: Set<DayViewModel.Row.ID>, in day: DayViewModel) -> DayViewModel.Row? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return day.rows.first { $0.id == id }
    }

    /// A clock time, with the date in front when it falls on another day.
    private func time(_ date: Date, outside: Bool) -> Text {
        let time = Text(date, format: .dateTime.hour().minute())
        return outside ? Text(date, format: .dateTime.month(.abbreviated).day()) + Text(", ") + time : time
    }
}

/// One week: a column per day, a row per client unless only one client exists, and the
/// week's totals. Clicking a day shows it in the Day view.
private struct WeekView: View {
    let history: HistoryModel

    var body: some View {
        if let week = history.week {
            let showsClientRows = week.showsClientRows(singleClient: history.app.snapshot.isSingleClient)
            ScrollView {
                Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        ForEach(week.days) { day in
                            dayHeader(day, now: week.now)
                        }
                        Text("Week").font(.headline)
                    }
                    Divider()
                    if showsClientRows {
                        ForEach(week.rows) { row in
                            GridRow {
                                Text(row.name).lineLimit(1).gridColumnAlignment(.leading)
                                ForEach(Array(row.seconds.enumerated()), id: \.offset) { _, seconds in
                                    cell(seconds)
                                }
                                cell(row.total)
                            }
                        }
                        Divider()
                    }
                    GridRow {
                        Text(showsClientRows ? "All" : "Total").gridColumnAlignment(.leading)
                        ForEach(week.days) { day in
                            cell(day.seconds)
                        }
                        cell(week.totalSeconds)
                    }
                    .fontWeight(.semibold)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Color.clear
        }
    }

    private func dayHeader(_ day: WeekViewModel.Day, now: Date) -> some View {
        let isToday = day.interval.contains(now)
        return Button {
            history.show(day: day.interval.start)
        } label: {
            VStack(spacing: 2) {
                Text(day.interval.start, format: .dateTime.weekday(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(day.interval.start, format: .dateTime.day())
                    .font(.title3.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
            }
            .frame(minWidth: 44)
        }
        .buttonStyle(.plain)
        .help("Show this day")
    }

    private func cell(_ seconds: Int) -> some View {
        Text(seconds == 0 ? "–" : DurationFormatter.hoursMinutes(seconds))
            .monospacedDigit()
            .foregroundStyle(seconds == 0 ? .tertiary : .primary)
    }
}
