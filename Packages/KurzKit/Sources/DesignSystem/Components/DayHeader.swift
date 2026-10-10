import SwiftUI

public struct DayHeader: View {
    let date: String
    var relativeNames = true

    public init(date: String, relativeNames: Bool = true) {
        self.date = date
        self.relativeNames = relativeNames
    }

    public var body: some View {
        Text(Self.title(for: date, relativeNames: relativeNames))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.appPrimary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    public static func title(for date: String, relativeNames: Bool = true, calendar: Calendar = .current) -> String {
        guard let day = try? Date(date, strategy: .iso8601.year().month().day()) else { return date }
        let relative = !relativeNames ? nil : calendar.isDateInToday(day) ? String(localized: "Today") : calendar.isDateInTomorrow(day) ? String(localized: "Tomorrow") : nil
        let weekday = relative ?? day.formatted(.dateTime.weekday(.wide)).capitalized
        return [weekday, day.formatted(.dateTime.day().month(.wide))].joined(separator: " · ")
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
