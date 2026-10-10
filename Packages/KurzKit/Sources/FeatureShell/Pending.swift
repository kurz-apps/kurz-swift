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
    let pending = agenda.sessions.sorted { $0.startsAt < $1.startsAt }.map { session in
        (date: session.date, items: session.appointments.filter { $0.status == "pending" }.map {
            PendingItem(id: $0.id, clientName: $0.clientName, serviceName: session.serviceName ?? session.formTitle, startsAt: session.startsAt)
        })
    }
    let grouped = Dictionary(grouping: pending.filter { !$0.items.isEmpty }, by: \.date)
    return grouped.map { PendingDay(date: $0.key, items: $0.value.flatMap(\.items)) }.sorted { $0.date < $1.date }
}

public func pendingCount(in agenda: AgendaResponse) -> Int {
    pendingDays(in: agenda).reduce(0) { $0 + $1.items.count }
}
