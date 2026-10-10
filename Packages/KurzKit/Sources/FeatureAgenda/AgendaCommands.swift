import SwiftUI

public enum AgendaCommand: CaseIterable, Sendable {
    case day, week, today, previous, next, goToDate, refresh

    public var title: LocalizedStringKey {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .today: "Today"
        case .previous: "Previous"
        case .next: "Next"
        case .goToDate: "Go to Date…"
        case .refresh: "Refresh"
        }
    }

    public var shortcut: KeyboardShortcut {
        switch self {
        case .day: KeyboardShortcut("1")
        case .week: KeyboardShortcut("2")
        case .today: KeyboardShortcut("t")
        case .previous: KeyboardShortcut(.leftArrow)
        case .next: KeyboardShortcut(.rightArrow)
        case .goToDate: KeyboardShortcut("t", modifiers: [.command, .shift])
        case .refresh: KeyboardShortcut("r")
        }
    }

    @MainActor public func perform(on model: AgendaModel) {
        switch self {
        case .day: model.period = .day
        case .week: model.period = .week
        case .today: model.goToToday()
        case .previous: model.previous()
        case .next: model.next()
        case .goToDate: model.isChoosingDate = true
        case .refresh: Task { await model.refresh() }
        }
    }
}

public struct AgendaCommands: Commands {
    @FocusedValue(AgendaModel.self) private var model

    public init() {}

    public var body: some Commands {
        CommandMenu("Calendar") {
            item(.day)
            item(.week)
            Divider()
            item(.today)
            item(.previous)
            item(.next)
            item(.goToDate)
            Divider()
            item(.refresh)
        }
    }

    private func item(_ command: AgendaCommand) -> some View {
        Button(command.title) { model.map(command.perform) }
            .keyboardShortcut(command.shortcut)
            .disabled(model == nil)
    }
}
