import Domain
import Foundation
import Networking
import Observation

public struct AgendaDay: Equatable, Identifiable, Sendable {
    public let date: String
    public let sessions: [AgendaSession]
    public var id: String { date }
}

public struct AgendaFilterOption: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let count: Int
}

public extension AgendaSession {
    var pendingCount: Int { appointments.filter { $0.status == "pending" }.count }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return ([serviceName, formTitle] + appointments.map(\.clientName)).contains { $0?.localizedStandardContains(query) == true }
    }
}

@MainActor @Observable
public final class AgendaModel {
    public enum Phase: Equatable { case idle, loading, loaded(AgendaResponse), failed(String) }
    public enum Period: String, CaseIterable, Sendable { case day, week }

    public private(set) var phase = Phase.idle
    public var period = Period.week
    public var rollingWeek = false
    public private(set) var anchor: Date
    public var query = ""
    public var hiddenForms: Set<String> = []
    public var hiddenCategories: Set<String> = []
    public var onlyPending = false
    public let calendar: Calendar
    private var loadedRange: String?
    private let load: @Sendable (_ from: String, _ to: String) async throws -> AgendaResponse

    public convenience init(api: APIClient) {
        self.init { from, to in
            try await api.send(Endpoint<AgendaResponse>("GET", "api/me/agenda", query: [.init(name: "from", value: from), .init(name: "to", value: to)]))
        }
    }

    public init(calendar: Calendar = .current, today: Date = .now, load: @escaping @Sendable (String, String) async throws -> AgendaResponse) {
        self.calendar = calendar
        anchor = calendar.startOfDay(for: today)
        self.load = load
    }

    public var dates: [Date] {
        let start = period == .week && !rollingWeek ? calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor : anchor
        return (0..<(period == .day ? 1 : 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    public var range: (from: String, to: String) {
        let dates = dates
        return (key(dates[0]), key(calendar.date(byAdding: .day, value: 1, to: dates[dates.count - 1]) ?? dates[0]))
    }

    public func key(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day())
    }

    public func next() { move(1) }
    public func previous() { move(-1) }
    public func goToToday(_ now: Date = .now) { anchor = calendar.startOfDay(for: now) }

    public func show(_ date: Date, period: Period? = nil) {
        anchor = calendar.startOfDay(for: date)
        if let period { self.period = period }
    }

    private func move(_ direction: Int) {
        anchor = calendar.date(byAdding: .day, value: direction * (period == .day ? 1 : 7), to: anchor) ?? anchor
    }

    private var sessionsInRange: [AgendaSession] {
        guard case .loaded(let response) = phase else { return [] }
        let keys = Set(dates.map(key))
        return response.sessions.filter { keys.contains($0.date) }
    }

    public var forms: [AgendaFilterOption] {
        options(sessionsInRange.map { (String($0.formId), $0.formTitle) })
    }

    public var categories: [AgendaFilterOption] {
        options(sessionsInRange.compactMap { $0.category.map { ($0.id, $0.name) } })
    }

    private func options(_ pairs: [(String, String)]) -> [AgendaFilterOption] {
        Dictionary(grouping: pairs, by: \.0).map { AgendaFilterOption(id: $0.key, name: $0.value[0].1, count: $0.value.count) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public var days: [AgendaDay] {
        let visible = sessionsInRange.filter { session in
            !hiddenForms.contains(String(session.formId))
                && !(session.category.map { hiddenCategories.contains($0.id) } ?? false)
                && (!onlyPending || session.pendingCount > 0)
                && session.matches(query)
        }
        return Dictionary(grouping: visible, by: \.date)
            .map { AgendaDay(date: $0.key, sessions: $0.value.sorted { $0.startsAt < $1.startsAt }) }
            .sorted { $0.date < $1.date }
    }

    public func refresh() async {
        let range = range
        let rangeKey = range.from + range.to
        if case .loaded = phase, loadedRange == rangeKey {} else { phase = .loading }
        do {
            let response = try await load(range.from, range.to)
            guard !Task.isCancelled, rangeKey == self.range.from + self.range.to else { return }
            phase = .loaded(response)
            loadedRange = rangeKey
        } catch {
            guard !Task.isCancelled, rangeKey == self.range.from + self.range.to else { return }
            phase = .failed(String(localized: "Couldn't load your agenda. Check your connection and try again."))
        }
    }
}
