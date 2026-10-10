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
}
