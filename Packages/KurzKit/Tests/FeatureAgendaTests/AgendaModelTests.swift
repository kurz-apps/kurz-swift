import Domain
import Foundation
import Synchronization
import Testing
@testable import FeatureAgenda

private func session(_ date: String, hour: Int, booked: Bool) -> AgendaSession {
    let start = Date(timeIntervalSince1970: 1_791_590_400 + Double(hour) * 3600)
    let appointments = booked ? [AgendaAppointment(id: hour, series: false, status: "confirmed", clientName: "Ana", clientEmail: nil, groupKey: nil)] : []
    return AgendaSession(formId: 1, formTitle: "F", serviceId: "s", serviceName: "S", category: nil, duration: 60, startsAt: start, date: date, capacity: 2, booked: appointments.count, pending: 0, appointments: appointments)
}

@Suite @MainActor struct AgendaModelTests {
    @Test func daysKeepOnlyBookedSessionsGroupedAndSorted() {
        let response = AgendaResponse(timeZone: "UTC", sessions: [
            session("2026-10-12", hour: 10, booked: true), session("2026-10-11", hour: 9, booked: true),
            session("2026-10-11", hour: 11, booked: false), session("2026-10-13", hour: 9, booked: false),
        ])
        #expect(response.days.map(\.date) == ["2026-10-11", "2026-10-12"])
        #expect(response.days.map(\.sessions.count) == [1, 1])
    }

    @Test func refreshLoadsTheRequestedRange() async {
        let requested = Mutex<(String, String)?>(nil)
        let model = AgendaModel(daysAhead: 7) { from, to in
            requested.withLock { $0 = (from, to) }
            return AgendaResponse(timeZone: "UTC", sessions: [])
        }
        await model.refresh(today: Date(timeIntervalSince1970: 1_791_590_400))
        let range = requested.withLock { $0 }
        #expect(range?.0 == "2026-10-10")
        #expect(range?.1 == "2026-10-17")
        #expect(model.phase == .loaded(AgendaResponse(timeZone: "UTC", sessions: [])))
    }

    @Test func failureShowsAnErrorAndKeepsNothingStale() async {
        struct Boom: Error {}
        let model = AgendaModel { _, _ in throw Boom() }
        await model.refresh()
        if case .failed = model.phase {} else { Issue.record("expected failed") }
    }
}
