import Domain
import FeatureAgenda
import Foundation

public struct PendingItem: Equatable, Identifiable, Sendable {
    public let id: Int
    public let clientName: String?
    public let serviceName: String
    public let startsAt: Date
}

public struct PendingDay: Equatable, Identifiable, Sendable {
    public let date: String
    public let items: [PendingItem]
    public var id: String { date }
}

public func pendingDays(in agenda: AgendaResponse) -> [PendingDay] {
    agenda.days.compactMap { day in
        let items = day.sessions.flatMap { session in
            session.appointments.filter { $0.status == "pending" }.map {
                PendingItem(id: $0.id, clientName: $0.clientName, serviceName: session.serviceName ?? session.formTitle, startsAt: session.startsAt)
            }
        }
        return items.isEmpty ? nil : PendingDay(date: day.date, items: items)
    }
}

public func pendingCount(in agenda: AgendaResponse) -> Int {
    pendingDays(in: agenda).reduce(0) { $0 + $1.items.count }
}
