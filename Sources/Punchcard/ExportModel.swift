import AppKit
import Foundation
import Observation
import PunchcardCore
import UniformTypeIdentifiers

/// State of the Export tab: the chosen range and kind, the document they produce, and the
/// result of the last save. The document is rebuilt from the database on every change, so
/// the row count shown is the one the file will have.
@MainActor @Observable
final class ExportModel {
    enum Range: String, CaseIterable, Identifiable {
        case thisWeek = "This week"
        case thisMonth = "This month"
        case lastMonth = "Last month"
        case allTime = "All time"
        case custom = "Custom"

        var id: String { rawValue }
    }

    let app: AppModel
    var range: Range = .thisMonth
    var kind: CSVExport.Kind = .entries
    /// The first and last day of the custom range.
    var customStart: Date
    var customEnd: Date
    private(set) var document: CSVDocument?
    /// Why there is no document: an invalid range or a failed read.
    private(set) var problem: String?
    /// Where the last export was saved, cleared by the next change.
    private(set) var savedTo: URL?
    /// Why the last save failed, cleared by the next change.
    private(set) var saveError: String?

    init(app: AppModel, now: Date = Date()) {
        self.app = app
        let month = Period.month.interval(containing: now, calendar: .current, weekStartDay: 1)
        customStart = month.start
        customEnd = now
    }

    var exportRange: ExportRange {
        switch range {
        case .thisWeek: .thisWeek
        case .thisMonth: .thisMonth
        case .lastMonth: .lastMonth
        case .allTime: .allTime
        case .custom: .days(from: customStart, through: customEnd)
        }
    }

    /// Rebuilds the document. Called on appear, on every change, and whenever the app model's
    /// snapshot changes, so an entry stopped while the tab is open is picked up.
    func reload() {
        savedTo = nil
        saveError = nil
        guard let database = app.database else { return }
        do {
            document = try CSVExport.document(kind: kind, range: exportRange, from: database)
            problem = nil
        } catch {
            document = nil
            problem = error.localizedDescription
        }
    }

    /// Asks where to save and writes the document there.
    func export() {
        reload()
        guard let document else { return }
        let panel = NSSavePanel()
        panel.title = "Export CSV"
        panel.nameFieldStringValue = document.fileName
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let finish = { @Sendable (response: NSApplication.ModalResponse) in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url else { return }
                self.write(document, to: url)
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    private func write(_ document: CSVDocument, to url: URL) {
        do {
            try Data(document.text.utf8).write(to: url, options: .atomic)
            savedTo = url
            saveError = nil
        } catch {
            savedTo = nil
            saveError = error.localizedDescription
        }
    }

    func revealSaved() {
        guard let savedTo else { return }
        NSWorkspace.shared.activateFileViewerSelecting([savedTo])
    }
}
