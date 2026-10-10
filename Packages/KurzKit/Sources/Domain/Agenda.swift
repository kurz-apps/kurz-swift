import Foundation

public struct AgendaResponse: Codable, Sendable, Equatable {
    public var timeZone: String
    public var sessions: [AgendaSession]

    public init(timeZone: String, sessions: [AgendaSession]) {
        self.timeZone = timeZone
        self.sessions = sessions
    }
}

public struct AgendaSession: Codable, Sendable, Equatable, Identifiable {
    public struct Category: Codable, Sendable, Equatable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
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

    public init(formId: Int, formTitle: String, serviceId: String, serviceName: String?, category: Category?, duration: Int?, startsAt: Date, date: String, capacity: Int?, booked: Int, pending: Int, appointments: [AgendaAppointment]) {
        self.formId = formId
        self.formTitle = formTitle
        self.serviceId = serviceId
        self.serviceName = serviceName
        self.category = category
        self.duration = duration
        self.startsAt = startsAt
        self.date = date
        self.capacity = capacity
        self.booked = booked
        self.pending = pending
        self.appointments = appointments
    }

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

    public init(id: Int, series: Bool, status: String, clientName: String?, clientEmail: String?, groupKey: String?) {
        self.id = id
        self.series = series
        self.status = status
        self.clientName = clientName
        self.clientEmail = clientEmail
        self.groupKey = groupKey
    }
}
