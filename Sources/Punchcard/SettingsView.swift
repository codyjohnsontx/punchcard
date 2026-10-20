import AppKit
import PunchcardCore
import SwiftUI

/// The Settings window: General (menu bar style, week start, away threshold) and Data (where
/// the database is, the app version). Every change applies as soon as it is made.
struct SettingsView: View {
    @State private var settings: SettingsModel

    init(app: AppModel) {
        _settings = State(initialValue: SettingsModel(app: app))
    }

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            DataSettingsView(app: settings.app)
                .tabItem { Label("Data", systemImage: "cylinder") }
        }
        .frame(width: 460)
        .onAppear { settings.reload() }
    }
}

private struct GeneralSettingsView: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            if let openError = settings.app.openError {
                Label(openError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else {
                Picker("Menu bar shows:", selection: $settings.menuBarStyle) {
                    Text("Running time").tag(SettingsStore.MenuBarStyle.time)
                    Text("Icon only").tag(SettingsStore.MenuBarStyle.icon)
                }
                .pickerStyle(.radioGroup)
                Picker("Week starts on:", selection: $settings.weekStartDay) {
                    ForEach(SettingsViewModel.weekdays()) { weekday in
                        Text(weekday.name).tag(weekday.day)
                    }
                }
                LabeledContent("Ask after being away for:") {
                    Stepper(value: $settings.idleThresholdMinutes, in: SettingsViewModel.idleThresholdMinutesRange) {
                        Text(settings.idleThresholdMinutes == 1 ? "1 minute" : "\(settings.idleThresholdMinutes) minutes")
                            .monospacedDigit()
                    }
                }
                Text("While the clock runs, idle or asleep this long asks whether to keep the time when you come back.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let error = settings.error {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DataSettingsView: View {
    let app: AppModel

    var body: some View {
        Form {
            LabeledContent("Database:") {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(app.databaseURL.map { ($0.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath } ?? "Unavailable")
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                    if let url = app.databaseURL {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }
            }
            LabeledContent("Version:", value: AppInfo.version() ?? "Not running from an app bundle")
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}
