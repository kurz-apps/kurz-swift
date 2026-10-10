import SwiftUI

typealias Login = (URL) async throws -> URL

struct AgendaView: View {
    let model: AgendaModel
    let login: Login

    var body: some View {
        NavigationStack {
            List {
                if let agenda = model.agenda {
                    if !agenda.summary.isEmpty {
                        SummaryCard(text: agenda.summary)
                            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    }
                    ForEach(agenda.days, id: \.day) { day in
                        Section { rows(day.items) } header: { DayHeader(day: day.day) }
                    }
                    if !agenda.undated.isEmpty {
                        Section("Undated") { rows(agenda.undated) }
                    }
                    if !agenda.appointments.isEmpty {
                        Text("Updated at \(agenda.updated.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                } else if model.isLoading {
                    // skeleton while the very first load runs
                    ForEach(0..<5, id: \.self) { _ in
                        AppointmentRow(item: .placeholder).redacted(reason: .placeholder)
                    }
                }
            }
            .listStyle(.inset)
            .overlay { placeholder }
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Account", systemImage: "person.crop.circle") {
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh(login: login) } }
                            .keyboardShortcut("r")
                            .disabled(model.isLoading)
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            Task { await model.signOut() }
                        }
                    }
                }
            }
            .refreshable { await model.refresh(login: login) }
            .sensoryFeedback(.success, trigger: model.agenda?.updated)
        }
    }

    @ViewBuilder private func rows(_ items: [Appointment]) -> some View {
        ForEach(items) { AppointmentRow(item: $0) }
    }

    /// Empty and error states, drawn over the list only when there is nothing to show.
    @ViewBuilder private var placeholder: some View {
        if let error = model.error, model.agenda == nil {
            ContentUnavailableView {
                Label("Couldn't load your schedule", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try again") { Task { await model.refresh(login: login) } }.buttonStyle(.borderedProminent)
            }
        } else if let agenda = model.agenda, agenda.appointments.isEmpty {
            ContentUnavailableView("Nothing scheduled", systemImage: "calendar", description: Text("Your next 7 days are free."))
        }
    }
}

private struct SummaryCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Summary", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(.tint)
            Text(text).font(.body)
            Text("Generated on device with Apple Intelligence").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct DayHeader: View {
    let day: Date

    var body: some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day)
        let relative: String? = isToday ? String(localized: "Today") : cal.isDateInTomorrow(day) ? String(localized: "Tomorrow") : nil
        HStack(spacing: 6) {
            Text(relative ?? day.formatted(.dateTime.weekday(.wide)).capitalized).fontWeight(.semibold)
            Text(day.formatted(.dateTime.day().month(.wide))).foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .foregroundStyle(isToday ? Color.accentColor : .primary)
        .accessibilityAddTraits(.isHeader)
    }
}

struct AppointmentRow: View {
    let item: Appointment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                if let start = item.start {
                    Text(start, format: .dateTime.hour().minute())
                    if let end = item.end { Text(end, format: .dateTime.hour().minute()).foregroundStyle(.secondary) }
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.monospacedDigit())
            .frame(width: 48, alignment: .trailing)

            Capsule().fill(item.isHappeningNow ? Color.red : Color.accentColor).frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline)
                if !item.person.isEmpty { Label(item.person, systemImage: "person") }
                if !item.location.isEmpty { Label(item.location, systemImage: "mappin.and.ellipse") }
                if item.isHappeningNow { Text("Now").font(.caption.bold()).foregroundStyle(.red) }
            }
            .font(.subheadline).foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

extension Appointment {
    static let placeholder = Appointment(
        title: "Placeholder appointment", start: .now, end: .now.addingTimeInterval(3600), person: "Placeholder name", location: "Placeholder place")
}
