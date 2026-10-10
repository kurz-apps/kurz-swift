import Foundation
import Testing
@testable import Domain

@Suite struct AgendaDecodingTests {
    @Test func decodesTheBackendAgendaShape() throws {
        let json = #"""
        {"time_zone":"Europe/Lisbon","sessions":[{"form_id":3,"form_title":"Massage","service_id":"s1","service_name":"60 min","category":{"id":"c1","name":"Body"},
        "duration":60,"starts_at":"2026-10-12T09:00:00Z","date":"2026-10-12","capacity":1,"booked":1,"pending":1,
        "appointments":[{"id":7,"series":false,"status":"pending","client_name":"Ana","client_email":"ana@example.com","group_key":null}]}]}
        """#
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        let agenda = try d.decode(AgendaResponse.self, from: Data(json.utf8))

        let s = try #require(agenda.sessions.first)
        #expect(agenda.timeZone == "Europe/Lisbon")
        #expect(s.appointments.first?.clientName == "Ana")
        #expect(s.endsAt == s.startsAt.addingTimeInterval(3600))
        #expect(s.id == "3/s1/\(Int(s.startsAt.timeIntervalSince1970))")
    }
}
