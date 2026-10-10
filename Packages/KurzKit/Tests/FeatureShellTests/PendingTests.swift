import Domain
import FeatureShell
import Foundation
import Testing

struct PendingTests {
    private func session(_ date: String, _ at: TimeInterval, _ statuses: [String]) -> AgendaSession {
        AgendaSession(formId: 1, formTitle: "Form", serviceId: "s", serviceName: "Cut", category: nil, duration: 30, startsAt: Date(timeIntervalSince1970: at), date: date, capacity: nil, booked: statuses.count, pending: 0,
                      appointments: statuses.enumerated().map { AgendaAppointment(id: Int(at) + $0.offset, series: false, status: $0.element, clientName: "C", clientEmail: nil, groupKey: nil) })
    }

    @Test func countsAndGroupsOnlyPending() {
        let agenda = AgendaResponse(timeZone: "UTC", sessions: [
            session("2026-01-01", 100, ["pending", "confirmed"]),
            session("2026-01-01", 200, ["pending"]),
            session("2026-01-02", 300, ["confirmed"]),
            session("2026-01-03", 400, ["pending"]),
        ])
        #expect(pendingCount(in: agenda) == 3)
        #expect(pendingDays(in: agenda).map(\.date) == ["2026-01-01", "2026-01-03"])
        #expect(pendingDays(in: agenda)[0].items.count == 2)
    }

    @Test func emptyWhenNoPending() {
        #expect(pendingCount(in: AgendaResponse(timeZone: "UTC", sessions: [])) == 0)
    }
}

@MainActor
struct PendingModelTests {
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [(String, String)] = []
        func add(_ from: String, _ to: String) { lock.withLock { stored.append((from, to)) } }
        var all: [(String, String)] { lock.withLock { stored.sorted { $0.0 < $1.0 } } }
    }

    private nonisolated var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private nonisolated func session(_ date: String, _ id: Int, status: String = "pending") -> AgendaSession {
        AgendaSession(formId: 1, formTitle: "Form", serviceId: "s\(id)", serviceName: "Cut", category: nil, duration: 30, startsAt: Date(timeIntervalSince1970: Double(id) * 1000), date: date, capacity: nil, booked: 1, pending: 0,
                      appointments: [AgendaAppointment(id: id, series: false, status: status, clientName: "C", clientEmail: nil, groupKey: nil)])
    }

    private func makeModel(calls: Calls = Calls(), load: @escaping @Sendable (String, String) async throws -> AgendaResponse) -> PendingModel {
        PendingModel(calendar: calendar, today: { Date(timeIntervalSince1970: 1_767_225_600) }, load: { from, to in
            calls.add(from, to)
            return try await load(from, to)
        })
    }

    @Test func windowIsChunkedForwardFromToday() async {
        let calls = Calls()
        let model = makeModel(calls: calls) { _, _ in AgendaResponse(timeZone: "UTC", sessions: []) }
        await model.refresh()
        #expect(calls.all.map(\.0) == ["2026-01-01", "2026-01-31"])
        #expect(calls.all.map(\.1) == ["2026-01-30", "2026-03-01"])
        #expect(PendingModel.chunkDays <= 62)
    }

    @Test func mergesChunksAndDropsDuplicateSessions() async {
        let shared = session("2026-01-30", 1)
        let model = makeModel { from, _ in
            from == "2026-01-01"
                ? AgendaResponse(timeZone: "UTC", sessions: [shared, session("2026-01-02", 2)])
                : AgendaResponse(timeZone: "UTC", sessions: [shared, session("2026-02-05", 3)])
        }
        await model.refresh()
        #expect(model.response?.sessions.count == 3)
        #expect(model.count == 3)
        #expect(model.days.map(\.date) == ["2026-01-02", "2026-01-30", "2026-02-05"])
    }

    @Test func failureKeepsPreviousDataAndSurfacesError() async {
        let fail = Fail()
        let model = makeModel { _, to in
            if fail.on { throw URLError(.notConnectedToInternet) }
            return AgendaResponse(timeZone: "UTC", sessions: to == "2026-01-30" ? [session("2026-01-02", 2)] : [])
        }
        await model.refresh()
        #expect(model.count == 1)
        fail.on = true
        await model.refresh()
        #expect(model.count == 1)
        #expect(model.error != nil)
        fail.on = false
        await model.refresh()
        #expect(model.error == nil)
        #expect(!model.isLoading)
    }

    @Test func failureWithoutDataHasNoResponse() async {
        let model = makeModel { _, _ in throw URLError(.timedOut) }
        await model.refresh()
        #expect(model.response == nil)
        #expect(model.error != nil)
        #expect(model.count == 0)
    }

    @Test func countIgnoresNonPendingAndAgendaPeriod() async {
        let model = makeModel { _, to in
            to == "2026-01-30" ? AgendaResponse(timeZone: "UTC", sessions: [session("2026-01-20", 1), session("2026-01-21", 2, status: "confirmed")]) : AgendaResponse(timeZone: "UTC", sessions: [session("2026-02-20", 3)])
        }
        await model.refresh()
        #expect(model.count == 2)
    }

    final class Fail: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var on: Bool {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }
}
