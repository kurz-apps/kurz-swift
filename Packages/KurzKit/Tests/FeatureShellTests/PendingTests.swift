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
