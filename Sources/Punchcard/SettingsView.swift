import AppKit
import KeyboardShortcuts
import PunchcardCore
import SwiftUI

/// The Settings window: General (menu bar style, week start, away threshold, launch at login,
/// the global shortcut) and Data (where the database is, the app version). Every change applies as soon as it is made.
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.reloadLoginItem()
        }
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
                LaunchAtLoginRow(settings: settings)
                ShortcutRow()
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

private struct LaunchAtLoginRow: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        let row = settings.launchAtLogin
        Toggle("Launch at login", isOn: $settings.launchesAtLogin)
            .disabled(!row.isToggleEnabled)
        if let message = row.message {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if row.showsOpenSystemSettings {
            Button("Open Login Items Settings") { settings.openLoginItemsSettings() }
        }
        if let error = settings.loginItemError {
            Text(error).foregroundStyle(.red)
        }
    }
}

/// The global start/stop shortcut: off until recorded. Click to record, Escape cancels, Delete
/// or the clear button removes it.
private struct ShortcutRow: View {
    @State private var recorder = ShortcutRecorder()

    var body: some View {
        LabeledContent("Start/stop shortcut:") {
            HStack(spacing: 4) {
                Button(action: recorder.toggleRecording) {
                    Text(title)
                        .foregroundStyle(recorder.shortcut == nil && !recorder.isRecording ? .secondary : .primary)
                        .frame(minWidth: 120)
                }
                if recorder.shortcut != nil, !recorder.isRecording {
                    Button("Remove Shortcut", systemImage: "xmark.circle.fill", action: recorder.clear)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Remove the shortcut")
                }
            }
        }
        // Leaving the window, or closing it, ends recording so the shortcut works again.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            recorder.stopRecording()
        }
        .onDisappear { recorder.stopRecording() }
        Text(recorder.isRecording
            ? "Type the shortcut. Escape cancels, Delete removes it."
            : "Stops the running clock, or starts the client you used last, from any app.")
            .font(.callout)
            .foregroundStyle(.secondary)
        if let rejection = recorder.rejection {
            Text(rejection).foregroundStyle(.red)
        }
    }

    private var title: String {
        if recorder.isRecording { return "Type Shortcut…" }
        return recorder.shortcut?.displayName ?? "Suggested: \(KeyboardShortcuts.Shortcut.suggested.displayName)"
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
