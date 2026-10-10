import SwiftUI

public struct DayHeader: View {
    let date: String
    var relativeNames = true
    var timeZone = TimeZone.current

    public init(date: String, relativeNames: Bool = true, timeZone: TimeZone = .current) {
        self.date = date
        self.relativeNames = relativeNames
        self.timeZone = timeZone
    }

    public var body: some View {
        Text(Self.title(for: date, relativeNames: relativeNames, timeZone: timeZone))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.appPrimary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    public static func title(for date: String, relativeNames: Bool = true, timeZone: TimeZone = .current, now: Date = .now, locale: Locale = .current) -> String {
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        let key = Date.ISO8601FormatStyle(timeZone: utc).year().month().day()
        guard let day = try? Date(date, strategy: key) else { return date }
        let today = Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day().format(now)
        let tomorrow = key.format(((try? Date(today, strategy: key)) ?? day).addingTimeInterval(86400))
        let relative = !relativeNames ? nil : date == today ? String(localized: "Today") : date == tomorrow ? String(localized: "Tomorrow") : nil
        let weekday = relative ?? day.formatted(Date.FormatStyle(locale: locale, timeZone: utc).weekday(.wide)).capitalized
        return [weekday, day.formatted(Date.FormatStyle(locale: locale, timeZone: utc).day().month(.wide))].joined(separator: " · ")
    }
}

#Preview("DayHeader") {
    List {
        Section { Text(verbatim: "Session") } header: { DayHeader(date: "2026-10-10") }
        Section { Text(verbatim: "Session") } header: { DayHeader(date: "2026-10-12", relativeNames: false) }
    }
    .listStyle(.inset)
}

#Preview("DayHeader · dark") {
    List {
        Section { Text(verbatim: "Session") } header: { DayHeader(date: "2026-10-10") }
    }
    .listStyle(.inset)
    .preferredColorScheme(.dark)
}
