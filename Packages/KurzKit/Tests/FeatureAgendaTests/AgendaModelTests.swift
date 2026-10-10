import DesignSystem
import Domain
import Foundation
import Synchronization
import SwiftUI
import Testing
@testable import FeatureAgenda

private let saturday = Date(timeIntervalSince1970: 1_791_590_400)

private var utcMondayCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}

private func session(_ date: String, hour: Int, form: Int = 1, category: String? = nil, service: String = "S", clients: [String] = ["Ana"], status: String = "confirmed") -> AgendaSession {
    let appointments = clients.enumerated().map { AgendaAppointment(id: hour * 10 + $0.offset, series: false, status: status, clientName: $0.element, clientEmail: nil, groupKey: nil) }
    return AgendaSession(formId: form, formTitle: "Form \(form)", serviceId: service, serviceName: service, category: category.map { .init(id: $0, name: $0) }, duration: 60, startsAt: saturday.addingTimeInterval(Double(hour) * 3600), date: date, capacity: 2, booked: appointments.count, pending: 0, appointments: appointments)
}

@MainActor private func loadedModel(_ sessions: [AgendaSession]) async -> AgendaModel {
    let model = AgendaModel(calendar: utcMondayCalendar, today: saturday) { _, _ in AgendaResponse(timeZone: "UTC", sessions: sessions) }
    await model.refresh()
    return model
}

@Suite @MainActor struct AgendaModelTests {
    @Test func weekIsTheCalendarWeekAndDayIsTheAnchor() {
        let model = AgendaModel(calendar: utcMondayCalendar, today: saturday) { _, _ in AgendaResponse(timeZone: "UTC", sessions: []) }
        #expect(model.range == ("2026-10-05", "2026-10-12"))
        model.rollingWeek = true
        #expect(model.range == ("2026-10-10", "2026-10-17"))
        model.period = .day
        #expect(model.range == ("2026-10-10", "2026-10-11"))
        #expect(model.dates.count == 1)
    }

    @Test func nextPreviousAndTodayMoveByThePeriod() {
        let model = AgendaModel(calendar: utcMondayCalendar, today: saturday) { _, _ in AgendaResponse(timeZone: "UTC", sessions: []) }
        model.next()
        #expect(model.range.from == "2026-10-12")
        model.period = .day
        model.previous()
        #expect(model.range.from == "2026-10-16")
        model.goToToday(saturday)
        #expect(model.range.from == "2026-10-10")
        model.show(saturday.addingTimeInterval(86_400 * 3), period: .week)
        #expect(model.range.from == "2026-10-12")
    }

    @Test func refreshLoadsOnlyTheVisibleRange() async {
        let requested = Mutex<[String]>([])
        let model = AgendaModel(calendar: utcMondayCalendar, today: saturday) { from, to in
            requested.withLock { $0.append(from + "/" + to) }
            return AgendaResponse(timeZone: "UTC", sessions: [])
        }
        await model.refresh()
        model.period = .day
        await model.refresh()
        #expect(requested.withLock { $0 } == ["2026-10-05/2026-10-12", "2026-10-10/2026-10-11"])
        #expect(model.phase == .loaded(AgendaResponse(timeZone: "UTC", sessions: [])))
    }

    @Test func daysAreGroupedSortedAndLimitedToTheVisibleRange() async {
        let model = await loadedModel([
            session("2026-10-11", hour: 10), session("2026-10-06", hour: 9), session("2026-10-06", hour: 8, clients: []), session("2026-10-13", hour: 9),
        ])
        #expect(model.days.map(\.date) == ["2026-10-06", "2026-10-11"])
        #expect(model.days[0].sessions.map(\.startsAt) == [saturday.addingTimeInterval(8 * 3600), saturday.addingTimeInterval(9 * 3600)])
    }

    @Test func searchMatchesClientServiceOrFormIgnoringCaseAndAccents() async {
        let model = await loadedModel([
            session("2026-10-06", hour: 9, service: "Yoga", clients: ["Bruno Costa"]),
            session("2026-10-07", hour: 9, form: 2, service: "Pilates", clients: ["Ana Silva"]),
        ])
        model.query = "bruno"
        #expect(model.days.flatMap(\.sessions).map(\.serviceName) == ["Yoga"])
        model.query = "PILATES"
        #expect(model.days.flatMap(\.sessions).map(\.serviceName) == ["Pilates"])
        model.query = "form 2"
        #expect(model.days.flatMap(\.sessions).map(\.serviceName) == ["Pilates"])
        model.query = "silvá"
        #expect(model.days.flatMap(\.sessions).map(\.serviceName) == ["Pilates"])
        model.query = "nobody"
        #expect(model.days.isEmpty)
    }

    @Test func filtersByFormCategoryAndPending() async {
        let model = await loadedModel([
            session("2026-10-06", hour: 9, form: 1, category: "spa"),
            session("2026-10-06", hour: 10, form: 2, category: "spa", status: "pending"),
            session("2026-10-07", hour: 9, form: 2),
        ])
        #expect(model.forms.map(\.count) == [1, 2])
        #expect(model.categories == [AgendaFilterOption(id: "spa", name: "spa", count: 2)])
        model.hiddenForms = ["2"]
        #expect(model.days.flatMap(\.sessions).map(\.formId) == [1])
        model.hiddenForms = []
        model.hiddenCategories = ["spa"]
        #expect(model.days.flatMap(\.sessions).map(\.date) == ["2026-10-07"])
        model.hiddenCategories = []
        model.onlyPending = true
        #expect(model.days.flatMap(\.sessions).map(\.startsAt) == [saturday.addingTimeInterval(10 * 3600)])
    }

    @Test func failureShowsAnError() async {
        struct Boom: Error {}
        let model = AgendaModel { _, _ in throw Boom() }
        await model.refresh()
        if case .failed = model.phase {} else { Issue.record("expected failed") }
    }

    @Test func occupancyFollowsCapacity() {
        var group = session("2026-10-06", hour: 9, clients: ["Ana"])
        #expect(occupancy(group) == "1/2")
        group.capacity = 1
        #expect(occupancy(group) == "Ana")
        group.capacity = 0
        #expect(occupancy(group).contains("1"))
        group.appointments = []
        #expect(occupancy(group) == String(localized: "Free"))
    }

    @Test func categoryColorsAreStable() {
        #expect(Color.appCategory(id: nil) == Color.appPrimary)
        #expect(Color.appCategory(id: "x", name: "Dança") == Color.appCategoryPalette[2])
        #expect(Color.appCategory(id: "x", name: "MUSICA") == Color.appCategoryPalette[3])
        #expect(Color.appCategory(id: "cat-1") == Color.appCategoryPalette[2])
        #expect(Color.appCategory(id: "cat-2") == Color.appCategoryPalette[0])
        #expect(Color.appCategory(id: "cat-1", name: "Yoga") == Color.appCategory(id: "cat-1"))
    }

    @Test func overlappingSessionsGetSideBySideLanes() {
        let lanes = TimeGrid.lanes([session("2026-10-06", hour: 9), session("2026-10-06", hour: 9, service: "T"), session("2026-10-06", hour: 10, service: "U")])
        #expect(lanes.count == 2)
    }
}
