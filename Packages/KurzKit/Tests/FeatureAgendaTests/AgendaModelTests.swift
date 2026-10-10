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

@MainActor private final class Probe {
    weak var model: AgendaModel?
    var refreshing = false
    var stale = false
    var shownDays: [String] = []

    func capture() {
        guard let model else { return }
        refreshing = model.isRefreshing
        stale = model.isStale
        shownDays = model.days.map(\.date)
    }
}

private func zoned(_ identifier: String) -> Calendar {
    var calendar = utcMondayCalendar
    calendar.timeZone = TimeZone(identifier: identifier)!
    return calendar
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

    @Test func aFailedRefreshKeepsTheLoadedAgendaAndRaisesABanner() async {
        struct Boom: Error {}
        let calls = Mutex(0)
        let model = AgendaModel(calendar: utcMondayCalendar, today: saturday) { _, _ in
            let call = calls.withLock { $0 += 1; return $0 }
            if call > 1 { throw Boom() }
            return AgendaResponse(timeZone: "UTC", sessions: [session("2026-10-06", hour: 9)])
        }
        await model.refresh()
        await model.refresh()
        #expect(model.days.map(\.date) == ["2026-10-06"])
        #expect(model.refreshError != nil)
        #expect(model.isRefreshing == false)
        if case .loaded = model.phase {} else { Issue.record("expected the loaded agenda to stay") }
    }

    @Test func aSuccessfulRefreshClearsTheBanner() async {
        let model = await loadedModel([session("2026-10-06", hour: 9)])
        model.refreshError = "x"
        await model.refresh()
        #expect(model.refreshError == nil)
    }

    @Test func changingTheRangeKeepsThePreviousContentWhileLoading() async {
        let probe = Probe()
        let model = AgendaModel(calendar: utcMondayCalendar, today: saturday) { from, _ in
            if from == "2026-10-12" { await probe.capture() }
            return AgendaResponse(timeZone: "UTC", sessions: from == "2026-10-12" ? [] : [session("2026-10-06", hour: 9)])
        }
        probe.model = model
        await model.refresh()
        model.next()
        #expect(model.isStale)
        await model.refresh()
        #expect(probe.refreshing)
        #expect(probe.stale)
        #expect(probe.shownDays == ["2026-10-06"])
        #expect(model.isStale == false)
        #expect(model.isRefreshing == false)
        #expect(model.days.isEmpty)
    }

    @Test func narrowingToADayInsideTheLoadedWeekIsNotStale() async {
        let model = await loadedModel([session("2026-10-06", hour: 9)])
        model.show(saturday.addingTimeInterval(-4 * 86_400), period: .day)
        #expect(model.isStale == false)
        #expect(model.days.map(\.date) == ["2026-10-06"])
    }

    @Test func theAgendaTimeZoneDrivesDayKeysAndToday() async {
        let model = AgendaModel(calendar: utcMondayCalendar, today: saturday) { _, _ in AgendaResponse(timeZone: "Pacific/Auckland", sessions: []) }
        await model.refresh()
        #expect(model.calendar.timeZone.identifier == "Pacific/Auckland")
        #expect(model.key(model.anchor) == "2026-10-10")
        #expect(model.range == ("2026-10-05", "2026-10-12"))
        let lateSaturdayUTC = saturday.addingTimeInterval(23.5 * 3600)
        let sunday = model.dates[6]
        #expect(model.key(sunday) == "2026-10-11")
        #expect(model.isToday(sunday, now: lateSaturdayUTC))
        #expect(model.isToday(model.dates[5], now: lateSaturdayUTC) == false)
        #expect(model.dayTitle("2026-10-11", now: lateSaturdayUTC).hasPrefix(String(localized: "Today")))
        #expect(model.dayTitle("2026-10-12", now: lateSaturdayUTC).hasPrefix(String(localized: "Tomorrow")))
        #expect(model.dayTitle("2026-10-12", now: lateSaturdayUTC).contains("12"))
        model.goToToday(lateSaturdayUTC)
        #expect(model.key(model.anchor) == "2026-10-11")
    }

    @Test func dayTitlesWestOfUTCKeepTheirDate() async {
        let model = AgendaModel(calendar: zoned("America/Sao_Paulo"), today: saturday) { _, _ in AgendaResponse(timeZone: "America/Sao_Paulo", sessions: []) }
        let title = model.dayTitle("2026-10-14", now: saturday.addingTimeInterval(12 * 3600))
        #expect(title.contains("14"))
        #expect(!title.hasPrefix(String(localized: "Today")))
    }

    @Test func theTimeZoneNoteAppearsOnlyWhenTheDeviceZoneDiffers() async {
        let model = AgendaModel(calendar: zoned("Europe/Lisbon"), today: saturday) { _, _ in AgendaResponse(timeZone: "Europe/Lisbon", sessions: []) }
        #expect(model.timeZoneNote(device: TimeZone(identifier: "Asia/Tokyo")!) == nil)
        await model.refresh()
        #expect(model.timeZoneNote(device: TimeZone(identifier: "Europe/Lisbon")!) == nil)
        #expect(model.timeZoneNote(device: TimeZone(identifier: "Asia/Tokyo")!) != nil)
        let utc = await loadedModel([])
        #expect(utc.timeZoneNote(device: TimeZone(identifier: "Europe/Lisbon")!)?.contains("GMT") == true)
    }

    @Test func activeFiltersCountHiddenSessionsAndClearInOneStep() async {
        let model = await loadedModel([
            session("2026-10-06", hour: 9, form: 1, category: "spa"),
            session("2026-10-06", hour: 10, form: 2, category: "spa", status: "pending"),
            session("2026-10-07", hour: 9, form: 2),
        ])
        #expect(model.isFiltering == false)
        #expect(model.hiddenByFilters == 0)
        model.hiddenCategories = ["spa"]
        model.onlyPending = true
        #expect(model.isFiltering)
        #expect(model.hiddenByFilters == 3)
        model.query = "nobody"
        #expect(model.hiddenByFilters == 0)
        model.clearFilters()
        #expect(model.isFiltering == false)
        #expect(model.hiddenCategories.isEmpty && model.hiddenForms.isEmpty && model.onlyPending == false)
    }

    @Test func categoryHasASecondChannelBesidesColour() {
        var spa = session("2026-10-06", hour: 9, category: "Spa", service: "Massagem")
        #expect(rowSubtitle(spa) == "Spa · Form 1 · 1/2")
        #expect(blockDetails(spa, timeZone: "UTC") == "Spa · 09:00 · 1/2")
        #expect(spokenSummary(spa, timeZone: "UTC") == "Massagem, Spa, 09:00–10:00, 1/2")
        spa.capacity = 1
        #expect(rowSubtitle(spa) == "Spa · Form 1")
        let plain = session("2026-10-06", hour: 9)
        #expect(rowSubtitle(plain) == "Form 1 · 1/2")
        #expect(spokenSummary(plain, timeZone: "UTC") == "S, 09:00–10:00, 1/2")
    }

    @Test func contextMenuCopiesTimeAndClients() {
        let group = session("2026-10-06", hour: 9, clients: ["Ana Silva", "Bruno Costa"])
        #expect(clientList(group) == "Ana Silva\nBruno Costa")
        #expect(sessionWhen(group, timeZone: "UTC").hasSuffix(" · 09:00–10:00"))
    }

    @Test func selectionFollowsTheLatestData() async {
        let first = session("2026-10-06", hour: 9, clients: ["Ana"])
        let calls = Mutex(0)
        let model = AgendaModel(calendar: utcMondayCalendar, today: saturday) { _, _ in
            let call = calls.withLock { $0 += 1; return $0 }
            var updated = first
            if call > 1 { updated.appointments = [] }
            return AgendaResponse(timeZone: "UTC", sessions: [updated])
        }
        await model.refresh()
        #expect(model.selectedSession == nil)
        model.selection = first.id
        #expect(model.selectedSession?.appointments.count == 1)
        await model.refresh()
        #expect(model.selectedSession?.appointments.isEmpty == true)
        model.selection = "missing"
        #expect(model.selectedSession == nil)
    }

    @Test func blocksAreAtLeastTheMinimumTargetSize() {
        #expect(TimeGrid.minimumBlockHeight >= 28)
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

    @Test func overlappingSessionsGetSideBySideLanesPerCluster() {
        let first = session("2026-10-06", hour: 9), second = session("2026-10-06", hour: 9, service: "T")
        let third = session("2026-10-06", hour: 10, service: "U"), alone = session("2026-10-06", hour: 12, service: "V")
        let layout = LaneLayout([first, second, third, alone], maxLanes: 2)
        #expect(layout.placements[first.id] == .init(lane: 0, lanes: 2, reservesChip: false))
        #expect(layout.placements[second.id] == .init(lane: 1, lanes: 2, reservesChip: false))
        #expect(layout.placements[third.id] == .init(lane: 0, lanes: 1, reservesChip: false))
        #expect(layout.placements[alone.id] == .init(lane: 0, lanes: 1, reservesChip: false))
        #expect(layout.overflows.isEmpty)
    }

    @Test func lanesBeyondTheCapCollapseIntoAnOverflowChip() {
        let sessions = ["A", "B", "C", "D"].map { session("2026-10-06", hour: 9, service: $0) }
        let capped = LaneLayout(sessions, maxLanes: 2)
        #expect(capped.placements.count == 1)
        #expect(capped.placements[sessions[0].id] == .init(lane: 0, lanes: 1, reservesChip: true))
        #expect(capped.overflows.map { $0.sessions.map(\.serviceName) } == [["B", "C", "D"]])
        #expect(capped.overflows[0].start == sessions[0].startsAt)
        let narrow = LaneLayout(sessions, maxLanes: 1)
        #expect(narrow.placements.isEmpty)
        #expect(narrow.overflows.map(\.sessions.count) == [4])
        let roomy = LaneLayout(sessions, maxLanes: 4)
        #expect(roomy.placements.count == 4)
        #expect(roomy.overflows.isEmpty)
    }

    @Test func initialHourFollowsNowAndTheFirstSession() {
        #expect(TimeGrid.initialHour(earliest: 8 * 60, now: 12 * 60 + 38) == 10)
        #expect(TimeGrid.initialHour(earliest: 9 * 60 + 30, now: 6 * 60) == 8)
        #expect(TimeGrid.initialHour(earliest: nil, now: 15 * 60) == 13)
        #expect(TimeGrid.initialHour(earliest: nil, now: 60) == 0)
        #expect(TimeGrid.initialHour(earliest: 10 * 60, now: nil) == 9)
        #expect(TimeGrid.initialHour(earliest: 0, now: nil) == 0)
        #expect(TimeGrid.initialHour(earliest: nil, now: nil) == 7)
    }
}
