import Foundation

public struct AgendaResponse: Codable, Sendable, Equatable {
    public var timeZone: String
    public var sessions: [AgendaSession]
}

public struct AgendaSession: Codable, Sendable, Equatable, Identifiable {
    public struct Category: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
    }

    public var formId: Int
    public var formTitle: String
    public var serviceId: String
    public var serviceName: String?
    public var category: Category?
    public var duration: Int?
    public var startsAt: Date
    public var date: String
    public var capacity: Int?
    public var booked: Int
    public var pending: Int
    public var appointments: [AgendaAppointment]

    public var id: String { "\(formId)/\(serviceId)/\(Int(startsAt.timeIntervalSince1970))" }
    public var endsAt: Date? { duration.map { startsAt.addingTimeInterval(Double($0) * 60) } }
}

public struct AgendaAppointment: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var series: Bool
    public var status: String
    public var clientName: String?
    public var clientEmail: String?
    public var groupKey: String?
}
