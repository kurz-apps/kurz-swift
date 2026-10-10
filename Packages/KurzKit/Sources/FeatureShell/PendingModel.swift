import Domain
import FeatureAgenda
import Foundation
import Networking
import Observation

@MainActor @Observable
public final class PendingModel {
    public static let windowDays = 60
    public static let chunkDays = 30

    public private(set) var response: AgendaResponse?
    public private(set) var error: String?
    public private(set) var isLoading = false

    private let calendar: Calendar
    private let today: @Sendable () -> Date
    private let load: @Sendable (_ from: String, _ to: String) async throws -> AgendaResponse
    private var generation = 0

    public convenience init(api: APIClient) {
        self.init { from, to in
            try await api.send(Endpoint<AgendaResponse>("GET", "api/me/agenda", query: [.init(name: "from", value: from), .init(name: "to", value: to)]))
        }
    }

    public init(calendar: Calendar = .current, today: @escaping @Sendable () -> Date = { .now }, load: @escaping @Sendable (String, String) async throws -> AgendaResponse) {
        self.calendar = calendar
        self.today = today
        self.load = load
    }

    public var count: Int { response.map(pendingCount) ?? 0 }
    public var days: [PendingDay] { response.map(pendingDays) ?? [] }

    public var ranges: [(from: String, to: String)] {
        let start = calendar.startOfDay(for: today())
        let style = Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day()
        return stride(from: 0, to: Self.windowDays, by: Self.chunkDays).compactMap { offset in
            guard let from = calendar.date(byAdding: .day, value: offset, to: start),
                  let to = calendar.date(byAdding: .day, value: min(offset + Self.chunkDays, Self.windowDays) - 1, to: start) else { return nil }
            return (from.formatted(style), to.formatted(style))
        }
    }

    public func refresh() async {
        generation += 1
        let mine = generation
        isLoading = true
        let load = load
        let ranges = ranges
        do {
            let chunks = try await withThrowingTaskGroup(of: (Int, AgendaResponse).self) { group in
                for (index, range) in ranges.enumerated() {
                    group.addTask { (index, try await load(range.from, range.to)) }
                }
                var results: [(Int, AgendaResponse)] = []
                for try await result in group { results.append(result) }
                return results
            }
            guard mine == generation else { return }
            response = Self.merge(chunks.sorted { $0.0 < $1.0 }.map(\.1))
            error = nil
        } catch {
            guard mine == generation else { return }
            if !Task.isCancelled {
                self.error = String(localized: "Couldn't load your agenda. Check your connection and try again.")
            }
        }
        isLoading = false
    }

    nonisolated static func merge(_ chunks: [AgendaResponse]) -> AgendaResponse {
        var seen = Set<String>()
        let sessions = chunks.flatMap(\.sessions).filter { seen.insert($0.id).inserted }
        return AgendaResponse(timeZone: chunks.first?.timeZone ?? TimeZone.current.identifier, sessions: sessions)
    }
}

#if DEBUG
public extension PendingModel {
    enum PreviewState: Sendable { case sample, empty, failing, loading }

    static func preview(_ state: PreviewState = .sample) -> PendingModel {
        PendingModel { _, _ in
            switch state {
            case .sample: return AgendaResponse.preview
            case .empty: return AgendaResponse(timeZone: TimeZone.current.identifier, sessions: [])
            case .failing: throw URLError(.notConnectedToInternet)
            case .loading:
                try await Task.sleep(for: .seconds(3600))
                return AgendaResponse.preview
            }
        }
    }
}
#endif
