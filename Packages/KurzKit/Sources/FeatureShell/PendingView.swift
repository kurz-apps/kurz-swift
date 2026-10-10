import DesignSystem
import Domain
import FeatureAgenda
import SwiftUI

struct PendingView: View {
    let model: PendingModel

    var body: some View {
        NavigationStack {
            content
                .background(Color.appBackground)
                .navigationTitle("Pending approval")
        }
        .task { await model.refresh() }
    }

    @ViewBuilder private var content: some View {
        if let agenda = model.response {
            let days = model.days
            if days.isEmpty {
                ContentUnavailableView("No pending approvals", systemImage: "checkmark.circle", description: Text("Nothing is waiting for your approval."))
                    .accessibilityIdentifier("pending-empty")
            } else {
                List(days) { day in
                    Section {
                        ForEach(day.items) { PendingRow(item: $0, timeZone: agenda.timeZone) }
                    } header: {
                        DayHeader(date: day.date, relativeNames: false, timeZone: TimeZone(identifier: agenda.timeZone) ?? .current)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .refreshable { await model.refresh() }
                .safeAreaInset(edge: .top) {
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red).padding(8).frame(maxWidth: .infinity).background(.bar)
                    }
                }
                .accessibilityIdentifier("pending-list")
            }
        } else if let error = model.error {
            LoadFailedView("Couldn't load your agenda", message: error) { Task { await model.refresh() } }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
