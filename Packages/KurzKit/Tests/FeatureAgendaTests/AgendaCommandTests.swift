import Domain
import Foundation
import Synchronization
import SwiftUI
import Testing
@testable import FeatureAgenda

@Suite @MainActor struct AgendaCommandTests {
    private let saturday = Date(timeIntervalSince1970: 1_791_590_400)

    private func model(onLoad: @escaping @Sendable () -> Void = {}) -> AgendaModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return AgendaModel(calendar: calendar, today: saturday) { _, _ in
            onLoad()
            return AgendaResponse(timeZone: "UTC", sessions: [])
        }
    }

    @Test func shortcutsAreCommandModifiedAndUnique() {
        let expected: [AgendaCommand: KeyboardShortcut] = [
            .day: KeyboardShortcut("1", modifiers: .command),
            .week: KeyboardShortcut("2", modifiers: .command),
            .today: KeyboardShortcut("t", modifiers: .command),
            .previous: KeyboardShortcut(.leftArrow, modifiers: .command),
            .next: KeyboardShortcut(.rightArrow, modifiers: .command),
            .goToDate: KeyboardShortcut("t", modifiers: [.command, .shift]),
            .refresh: KeyboardShortcut("r", modifiers: .command),
        ]
        for command in AgendaCommand.allCases {
            #expect(command.shortcut == expected[command])
            #expect(command.shortcut.modifiers.contains(.command))
        }
        #expect(Set(AgendaCommand.allCases.map(\.shortcut)).count == AgendaCommand.allCases.count)
    }

    @Test func commandsDriveTheModel() {
        let model = model()
        AgendaCommand.day.perform(on: model)
        #expect(model.period == .day)
        AgendaCommand.next.perform(on: model)
        #expect(model.range.from == "2026-10-11")
        AgendaCommand.previous.perform(on: model)
        AgendaCommand.previous.perform(on: model)
        #expect(model.range.from == "2026-10-09")
        AgendaCommand.week.perform(on: model)
        #expect(model.period == .week)
        AgendaCommand.today.perform(on: model)
        #expect(model.isToday(model.anchor))
        AgendaCommand.goToDate.perform(on: model)
        #expect(model.isChoosingDate)
    }

    @Test func refreshCommandReloads() async {
        let calls = Mutex(0)
        let model = model { calls.withLock { $0 += 1 } }
        AgendaCommand.refresh.perform(on: model)
        for _ in 0..<100 where calls.withLock({ $0 }) == 0 { await Task.yield() }
        #expect(calls.withLock { $0 } == 1)
    }
}
