#if DEBUG
import Domain
import Foundation

public extension AgendaModel {
    enum PreviewState: Sendable { case sample, empty, failing, loading, refreshing, refreshFailing, otherTimeZone }

    static func preview(_ state: PreviewState = .sample, period: Period = .week) -> AgendaModel {
        let model = AgendaModel { _, _ in
            switch state {
            case .sample: return AgendaResponse.preview
            case .empty: return AgendaResponse(timeZone: TimeZone.current.identifier, sessions: [])
            case .failing, .refreshFailing: throw URLError(.notConnectedToInternet)
            case .otherTimeZone:
                var response = AgendaResponse.preview
                response.timeZone = TimeZone.current.identifier == "Atlantic/Azores" ? "Europe/Lisbon" : "Atlantic/Azores"
                return response
            case .loading, .refreshing:
                try await Task.sleep(for: .seconds(3600))
                return AgendaResponse.preview
            }
        }
        model.period = period
        if state == .refreshing || state == .refreshFailing {
            model.phase = .loaded(.preview)
            model.loadedKeys = Set(AgendaResponse.preview.sessions.map(\.date))
        }
        return model
    }
}

public extension AgendaResponse {
    static var preview: AgendaResponse {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let iso = Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day()
        let names = ["Ana Ribeiro", "Bruno Costa", "Carla Mendes", "Diogo Faria", "Inês Matos", "João Pires", "Marta Lopes", "Rui Teixeira"]
        let spa = AgendaSession.Category(id: "spa", name: "Spa")
        let nails = AgendaSession.Category(id: "nails", name: "Unhas")
        let dance = AgendaSession.Category(id: "dance", name: "Dança")
        let music = AgendaSession.Category(id: "music", name: "Música")
        let templates: [(service: String, form: String, category: AgendaSession.Category?, hour: Int, minute: Int, duration: Int, capacity: Int, clients: [(Int, String)])] = [
            ("Massagem relaxante", "Massagens", spa, 8, 0, 60, 1, [(0, "confirmed")]),
            ("Manicure gel", "Unhas de gel", nails, 10, 0, 45, 1, [(1, "pending")]),
            ("Pedicure", "Unhas de gel", nails, 10, 0, 60, 1, []),
            ("Ballet adultos", "Aulas de dança", dance, 10, 0, 90, 8, [(2, "confirmed"), (3, "confirmed"), (4, "pending")]),
            ("Piano iniciação", "Aulas de música", music, 11, 30, 45, 2, [(5, "confirmed"), (6, "confirmed")]),
            ("Yoga em grupo", "Bem-estar", nil, 14, 0, 60, 0, [(0, "confirmed"), (3, "confirmed"), (5, "unverified"), (7, "confirmed")]),
            ("Zumba", "Aulas de dança", dance, 17, 30, 60, 12, [(1, "confirmed"), (2, "confirmed"), (6, "pending"), (7, "confirmed")]),
            ("Massagem de pedras quentes", "Massagens", spa, 19, 0, 90, 1, [(4, "confirmed")]),
            ("Canto", "Aulas de música", music, 16, 0, 30, 1, []),
            ("Violino", "Aulas de música", music, 10, 15, 45, 1, [(7, "pending")])
        ]
        var sessions: [AgendaSession] = []
        for offset in -7...7 {
            for (index, template) in templates.enumerated() where offset == 0 || offset == 1 || (index + offset) % 2 == 0 {
                guard let date = calendar.date(byAdding: .day, value: offset, to: today),
                      let start = calendar.date(bySettingHour: template.hour, minute: template.minute, second: 0, of: date) else { continue }
                let appointments = template.clients.enumerated().map { position, client in
                    AgendaAppointment(id: index * 1000 + offset * 10 + position + 5000, series: position % 2 == 1, status: client.1, clientName: names[client.0], clientEmail: nil, groupKey: nil)
                }
                sessions.append(AgendaSession(
                    formId: index / 2 + 1, formTitle: template.form, serviceId: "s\(index)", serviceName: template.service,
                    category: template.category, duration: template.duration, startsAt: start, date: date.formatted(iso),
                    capacity: template.capacity, booked: appointments.count, pending: appointments.filter { $0.status == "pending" }.count,
                    appointments: appointments))
            }
        }
        return AgendaResponse(timeZone: calendar.timeZone.identifier, sessions: sessions)
    }
}
#endif
