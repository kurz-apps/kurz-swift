import DesignSystem
import Domain
import FeatureAgenda
import SwiftUI

struct PendingView: View {
    let model: AgendaModel

    var body: some View {
        NavigationStack {
            content
                .background(Color.appBackground)
                .navigationTitle("Pending approval")
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
            let days = pendingDays(in: agenda)
            if days.isEmpty {
                ContentUnavailableView("No pending approvals", systemImage: "checkmark.circle", description: Text("Nothing is waiting for your approval."))
                    .accessibilityIdentifier("pending-empty")
            } else {
                List(days) { day in
                    Section {
                        ForEach(day.items) { PendingRow(item: $0, timeZone: agenda.timeZone) }
                    } header: {
                        Text(header(day.date)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.appPrimary).textCase(nil)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .refreshable { await model.refresh() }
                .accessibilityIdentifier("pending-list")
            }
        }
    }

    private func header(_ date: String) -> String {
        guard let day = try? Date(date, strategy: .iso8601.year().month().day()) else { return date }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized
    }
}

struct PendingRow: View {
    let item: PendingItem
    let timeZone: String

    var body: some View {
        HStack(spacing: 12) {
            Text(item.startsAt.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: timeZone) ?? .current).hour().minute()))
                .font(.subheadline.monospacedDigit()).foregroundStyle(Color.appMutedForeground)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.clientName ?? "—").font(.headline).foregroundStyle(Color.appForeground)
                Text(item.serviceName).font(.subheadline).foregroundStyle(Color.appMutedForeground)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
