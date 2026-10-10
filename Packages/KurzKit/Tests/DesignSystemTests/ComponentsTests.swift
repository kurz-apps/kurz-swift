import Foundation
import Testing
@testable import DesignSystem

@Suite struct ComponentsTests {
    @Test func statusMapsApiValues() {
        #expect(StatusBadge.Status("pending") == .pending)
        #expect(StatusBadge.Status("confirmed") == .confirmed)
        #expect(StatusBadge.Status("unverified") == .unverified)
        #expect(StatusBadge.Status("cancelled") == .other("cancelled"))
    }

    @Test func timeOfDayUsesTimeZone() {
        let noon = Date(timeIntervalSince1970: 12 * 3600)
        let utc = noon.timeOfDay(in: "UTC")
        let tokyo = noon.timeOfDay(in: "Asia/Tokyo")
        #expect(utc != tokyo)
        #expect(utc.contains("12") || utc.contains("00"))
        #expect(tokyo.contains("21") || tokyo.contains("9"))
    }

    @Test func dayHeaderTitles() {
        let today = Date.now.formatted(.iso8601.year().month().day())
        #expect(DayHeader.title(for: today).hasPrefix(String(localized: "Today")))
        #expect(!DayHeader.title(for: today, relativeNames: false).hasPrefix(String(localized: "Today")))
        #expect(DayHeader.title(for: "not-a-date") == "not-a-date")
    }

    private static let zones = ["Pacific/Pago_Pago", "Pacific/Kiritimati", "America/Sao_Paulo", "Europe/Lisbon"]
    private static let en = Locale(identifier: "en")
    private static let pt = Locale(identifier: "pt-PT")

    private func title(_ date: String, _ relative: Bool, _ zone: String, _ now: Date, _ locale: Locale = en) -> String {
        DayHeader.title(for: date, relativeNames: relative, timeZone: TimeZone(identifier: zone)!, now: now, locale: locale)
    }

    @Test(arguments: zones) func namedDayIsIndependentOfZone(zone: String) {
        let now = Date(timeIntervalSince1970: 1791601200)
        #expect(title("2026-10-10", false, zone, now) == "Saturday · October 10")
        #expect(title("2026-10-10", false, zone, now, Self.pt) == "Sábado · 10 de outubro")
        #expect(title("2026-01-01", true, zone, now) == "Thursday · January 1")
    }

    @Test(arguments: zones) func todayAndTomorrowFollowGivenZone(zone: String) throws {
        let now = Date(timeIntervalSince1970: 1791601200)
        let tz = try #require(TimeZone(identifier: zone))
        let key = Date.ISO8601FormatStyle(timeZone: tz).year().month().day()
        let today = key.format(now)
        let tomorrow = key.format(now.addingTimeInterval(86400))
        let later = key.format(now.addingTimeInterval(3 * 86400))
        #expect(title(today, true, zone, now).hasPrefix(String(localized: "Today")))
        #expect(title(tomorrow, true, zone, now).hasPrefix(String(localized: "Tomorrow")))
        #expect(title(later, true, zone, now, Self.pt).hasPrefix(String(localized: "Today")) == false)
        #expect(!title(today, false, zone, now).hasPrefix(String(localized: "Today")))
        #expect(!title(tomorrow, false, zone, now, Self.pt).hasPrefix(String(localized: "Tomorrow")))
    }

    @Test func todayDiffersAcrossZonesAtSameInstant() {
        let now = Date(timeIntervalSince1970: 1791601200)
        #expect(title("2026-10-09", true, "Pacific/Pago_Pago", now).hasPrefix(String(localized: "Today")))
        #expect(title("2026-10-10", true, "Pacific/Pago_Pago", now).hasPrefix(String(localized: "Tomorrow")))
        #expect(title("2026-10-10", true, "Pacific/Kiritimati", now).hasPrefix(String(localized: "Today")))
        #expect(title("2026-10-09", true, "Pacific/Kiritimati", now) == "Friday · October 9")
    }
}
