import DesignSystem
import Domain
import SwiftUI

public struct AgendaView: View {
    let model: AgendaModel
    let userEmail: String
    let signOut: () -> Void

    public init(model: AgendaModel, userEmail: String, signOut: @escaping () -> Void) {
        self.model = model
        self.userEmail = userEmail
        self.signOut = signOut
    }

    public var body: some View {
        NavigationStack {
            content
                .background(Color.appBackground)
                .navigationTitle("Agenda")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Account", systemImage: "person.crop.circle") {
                            Text(userEmail)
                            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }.keyboardShortcut("r")
                            Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: signOut)
                                .accessibilityIdentifier("sign-out-button")
                        }
                        .accessibilityIdentifier("account-menu")
                    }
                }
        }
        .task { await model.refresh() }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load your agenda", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.refresh() } }.buttonStyle(.glassProminent).tint(Color.appPrimary)
            }
        case .loaded(let agenda):
            let days = agenda.days
            if days.isEmpty {
                ContentUnavailableView("Nothing booked", systemImage: "calendar", description: Text("Your next 30 days are free."))
                    .accessibilityIdentifier("agenda-empty")
            } else {
                List {
                    ForEach(days) { day in
                        Section { ForEach(day.sessions) { SessionRow(session: $0, timeZone: agenda.timeZone) } } header: { DayHeader(date: day.date) }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .refreshable { await model.refresh() }
                .accessibilityIdentifier("agenda-list")
            }
        }
    }
}

struct DayHeader: View {
    let date: String

    var body: some View {
        let parsed = try? Date(date, strategy: .iso8601.year().month().day())
        let label: String = parsed.map { day in
            let calendar = Calendar.current
            let relative = calendar.isDateInToday(day) ? String(localized: "Today") : calendar.isDateInTomorrow(day) ? String(localized: "Tomorrow") : nil
            return [relative ?? day.formatted(.dateTime.weekday(.wide)).capitalized, day.formatted(.dateTime.day().month(.wide))].joined(separator: " · ")
        } ?? date
        Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Color.appPrimary).textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SessionRow: View {
    let session: AgendaSession
    let timeZone: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(time(session.startsAt))
                if let end = session.endsAt { Text(time(end)).foregroundStyle(Color.appMutedForeground) }
            }
            .font(.subheadline.monospacedDigit())
            .frame(width: 52, alignment: .trailing)

            Capsule().fill(Color.appPrimary).frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(session.serviceName ?? session.formTitle).font(.headline).foregroundStyle(Color.appForeground)
                Text(session.formTitle).font(.caption).foregroundStyle(Color.appMutedForeground)
                ForEach(session.appointments) { appointment in
                    HStack {
                        Label(appointment.clientName ?? "—", systemImage: "person")
                        Spacer()
                        StatusBadge(status: appointment.status)
                    }
                    .font(.subheadline).foregroundStyle(Color.appForeground)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: timeZone) ?? .current).hour().minute())
    }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(label).font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(status == "pending" ? Color.appAccentForeground : Color.appPrimaryForeground)
            .background(status == "pending" ? Color.appAccent : Color.appPrimary, in: Capsule())
    }

    private var label: LocalizedStringKey {
        switch status {
        case "confirmed": "Confirmed"
        case "pending": "Pending"
        case "unverified": "Unverified"
        default: LocalizedStringKey(status.capitalized)
        }
    }
}
