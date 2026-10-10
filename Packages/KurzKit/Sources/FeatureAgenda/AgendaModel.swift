import Domain
import Foundation
import Networking
import Observation

public struct AgendaDay: Equatable, Identifiable, Sendable {
    public let date: String
    public let sessions: [AgendaSession]
    public var id: String { date }
}

public extension AgendaResponse {
    var days: [AgendaDay] {
        let booked = sessions.filter { !$0.appointments.isEmpty }.sorted { $0.startsAt < $1.startsAt }
        return Dictionary(grouping: booked, by: \.date).map { AgendaDay(date: $0.key, sessions: $0.value) }.sorted { $0.date < $1.date }
    }
}

@MainActor @Observable
public final class AgendaModel {
    public enum Phase: Equatable { case idle, loading, loaded(AgendaResponse), failed(String) }

    public private(set) var phase = Phase.idle
    private let load: @Sendable (_ from: String, _ to: String) async throws -> AgendaResponse
    private let daysAhead: Int

    public init(api: APIClient, daysAhead: Int = 30) {
        self.daysAhead = daysAhead
        load = { from, to in
            try await api.send(Endpoint<AgendaResponse>("GET", "api/me/agenda", query: [.init(name: "from", value: from), .init(name: "to", value: to)]))
        }
    }

    public init(daysAhead: Int = 30, load: @escaping @Sendable (String, String) async throws -> AgendaResponse) {
        self.daysAhead = daysAhead
        self.load = load
    }

    public func refresh(today: Date = .now) async {
        if case .loaded = phase {} else { phase = .loading }
        let format = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
        let from = today.formatted(format)
        let to = today.addingTimeInterval(Double(daysAhead) * 86_400).formatted(format)
        do {
            phase = .loaded(try await load(from, to))
        } catch {
            phase = .failed(String(localized: "Couldn't load your agenda. Check your connection and try again."))
        }
    }
}
