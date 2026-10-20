import Foundation
@testable import PunchcardCore
import Testing

@Suite struct SettingsViewModelTests {
    @Test func defaultsMatchTheStore() throws {
        let vm = SettingsViewModel()
        #expect(vm == (try SettingsViewModel.load(from: SettingsStore(database: try .inMemory()))))
        #expect(vm.menuBarStyle == .time)
        #expect(vm.weekStartDay == 1)
        #expect(vm.idleThresholdMinutes == 10)
        #expect(vm.idleThresholdSeconds == SettingsStore.defaultIdleThresholdSeconds)
    }

    @Test(arguments: [(0, 1), (-5, 1), (1, 1), (45, 45), (120, 120), (121, 120), (500, 120)])
    func thresholdIsClampedToOneThrough120Minutes(assigned: Int, stored: Int) {
        var vm = SettingsViewModel()
        vm.idleThresholdMinutes = assigned
        #expect(vm.idleThresholdMinutes == stored)
        #expect(SettingsStore.idleThresholdRange.contains(vm.idleThresholdSeconds))
        #expect(SettingsViewModel(menuBarStyle: .time, weekStartDay: 1, idleThresholdMinutes: assigned).idleThresholdMinutes == stored)
    }

    @Test(arguments: [(1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7), (7, 1)])
    func weekStartMapsToCalendarFirstWeekday(weekStartDay: Int, firstWeekday: Int) {
        var vm = SettingsViewModel()
        vm.weekStartDay = weekStartDay
        #expect(vm.firstWeekday == firstWeekday)
        #expect(Calendar.firstWeekday(weekStartDay: weekStartDay) == firstWeekday)
    }

    @Test func weekdaysRunMondayToSundayInTheCalendarsLocale() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        let weekdays = SettingsViewModel.weekdays(calendar: calendar)
        #expect(weekdays.map(\.day) == [1, 2, 3, 4, 5, 6, 7])
        #expect(weekdays.map(\.name) == ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"])
    }

    @Test func loadsWhatTheStoreHoldsAndRoundsSecondsToMinutes() throws {
        let store = SettingsStore(database: try .inMemory())
        try store.setMenuBarStyle(.icon)
        try store.setWeekStartDay(7)
        try store.setIdleThresholdSeconds(90)

        let vm = try SettingsViewModel.load(from: store)
        #expect(vm.menuBarStyle == .icon)
        #expect(vm.weekStartDay == 7)
        #expect(vm.firstWeekday == 1)
        #expect(vm.idleThresholdMinutes == 2)
    }

    @Test func savedThresholdFeedsTheSameStoreTheDetectorReads() throws {
        let store = SettingsStore(database: try .inMemory())
        var vm = try SettingsViewModel.load(from: store)
        vm.idleThresholdMinutes = 1000
        try store.setIdleThresholdSeconds(vm.idleThresholdSeconds)
        #expect(try store.idleThresholdSeconds == 7200)
        #expect(try SettingsViewModel.load(from: store).idleThresholdMinutes == 120)
    }
}

@Test func appVersionIsNilOutsideAStampedBundle() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("punchcard-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(AppInfo.version(of: try #require(Bundle(url: folder))) == nil)
}

@Suite struct ShortcutRecordingTests {
    @Test(arguments: [
        (ShortcutRecording.Key.escape, ShortcutRecording.Action.cancel),
        (.tab, .cancelAndPassOn),
        (.delete, .clear),
        (.other, .reject(message: ShortcutRecording.needsModifierMessage)),
        (.functionKey, .record),
    ])
    func keysWithoutModifiers(key: ShortcutRecording.Key, action: ShortcutRecording.Action) {
        #expect(ShortcutRecording.action(key: key, modifiers: [], isTakenBySystem: false) == action)
    }

    @Test func controlOptionPIsRecorded() {
        #expect(ShortcutRecording.action(key: .other, modifiers: [.control, .option], isTakenBySystem: false) == .record)
    }

    @Test(arguments: [ShortcutRecording.Modifiers.command, .control, .option, [.command, .shift]])
    func aCommandControlOrOptionModifierIsEnough(modifiers: ShortcutRecording.Modifiers) {
        #expect(ShortcutRecording.action(key: .other, modifiers: modifiers, isTakenBySystem: false) == .record)
    }

    @Test(arguments: [ShortcutRecording.Modifiers.shift, .function, [.shift, .function]])
    func shiftOrFunctionAloneIsRejected(modifiers: ShortcutRecording.Modifiers) {
        #expect(ShortcutRecording.action(key: .other, modifiers: modifiers, isTakenBySystem: false)
            == .reject(message: ShortcutRecording.needsModifierMessage))
        #expect(ShortcutRecording.action(key: .functionKey, modifiers: modifiers, isTakenBySystem: false) == .record)
    }

    @Test func modifiedEscapeAndDeleteAreShortcutsLikeAnyOtherKey() {
        #expect(ShortcutRecording.action(key: .escape, modifiers: [.command], isTakenBySystem: false) == .record)
        #expect(ShortcutRecording.action(key: .delete, modifiers: [.control, .option], isTakenBySystem: false) == .record)
    }

    @Test func aShortcutMacOSUsesIsRejected() {
        #expect(ShortcutRecording.action(key: .other, modifiers: [.command], isTakenBySystem: true)
            == .reject(message: ShortcutRecording.takenBySystemMessage))
        // Escape still cancels and an unmodified key still needs a modifier first.
        #expect(ShortcutRecording.action(key: .escape, modifiers: [], isTakenBySystem: true) == .cancel)
        #expect(ShortcutRecording.action(key: .other, modifiers: [.shift], isTakenBySystem: true)
            == .reject(message: ShortcutRecording.needsModifierMessage))
    }
}
