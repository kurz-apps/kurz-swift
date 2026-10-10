#if DEBUG
import DesignSystem
import Domain
import SwiftUI

@MainActor private func agenda(_ state: AgendaModel.PreviewState = .sample, period: AgendaModel.Period = .week, configure: (AgendaModel) -> Void = { _ in }) -> some View {
    let model = AgendaModel.preview(state, period: period)
    configure(model)
    return AgendaView(model: model, userEmail: "ana@kurz.app") {}
}

private var sample: AgendaSession { AgendaResponse.preview.sessions.first { $0.appointments.count > 2 && $0.pendingCount > 0 }! }
private var unlimited: AgendaSession { AgendaResponse.preview.sessions.first { $0.capacity == 0 }! }

#Preview("Week · iPad", traits: .landscapeLeft) {
    agenda().environment(\.horizontalSizeClass, .regular)
}

#Preview("Week · iPad · dark", traits: .landscapeLeft) {
    agenda().environment(\.horizontalSizeClass, .regular).preferredColorScheme(.dark)
}

#Preview("Week · iPad · pt-PT", traits: .landscapeLeft) {
    agenda().environment(\.horizontalSizeClass, .regular).environment(\.locale, Locale(identifier: "pt-PT"))
}

#Preview("Week · iPad portrait · 4 overlapping", traits: .portrait) {
    agenda().environment(\.horizontalSizeClass, .regular)
}

#Preview("Week · iPad portrait · 4 overlapping · dark", traits: .portrait) {
    agenda().environment(\.horizontalSizeClass, .regular).preferredColorScheme(.dark)
}

#Preview("Week · iPhone") {
    agenda().environment(\.horizontalSizeClass, .compact)
}

#Preview("Week · iPhone · dark") {
    agenda().environment(\.horizontalSizeClass, .compact).preferredColorScheme(.dark)
}

#Preview("Week · iPhone · pt-PT") {
    agenda().environment(\.horizontalSizeClass, .compact).environment(\.locale, Locale(identifier: "pt-PT"))
}

#Preview("Day · iPad", traits: .landscapeLeft) {
    agenda(period: .day).environment(\.horizontalSizeClass, .regular)
}

#Preview("Day · iPhone") {
    agenda(period: .day).environment(\.horizontalSizeClass, .compact)
}

#Preview("Search") {
    agenda { $0.query = "Ana" }.environment(\.horizontalSizeClass, .compact)
}

#Preview("Search · no results") {
    agenda { $0.query = "zzz" }
}

#Preview("Filters · only pending") {
    agenda { $0.onlyPending = true }.environment(\.horizontalSizeClass, .compact)
}

#Preview("Filters · hidden category", traits: .landscapeLeft) {
    agenda { $0.hiddenCategories = ["dance", "nails"] }.environment(\.horizontalSizeClass, .regular)
}

#Preview("Empty") {
    agenda(.empty)
}

#Preview("Error") {
    agenda(.failing)
}

#Preview("Error · dark") {
    agenda(.failing).preferredColorScheme(.dark)
}

#Preview("Loading") {
    agenda(.loading)
}

#Preview("Detail") {
    SessionDetail(session: sample, timeZone: TimeZone.current.identifier) {}
}

#Preview("Detail · unlimited · dark") {
    SessionDetail(session: unlimited, timeZone: TimeZone.current.identifier) {}.preferredColorScheme(.dark)
}

#Preview("Session blocks", traits: .sizeThatFitsLayout) {
    VStack(spacing: 8) {
        ForEach(AgendaResponse.preview.sessions.prefix(9)) { SessionBlock(session: $0, timeZone: .current).frame(width: 130, height: 52) }
        HStack(spacing: 3) {
            ForEach(AgendaResponse.preview.sessions.prefix(2)) { SessionBlock(session: $0, timeZone: .current, compact: true).frame(width: 52, height: 52) }
            OverflowChip(sessions: Array(AgendaResponse.preview.sessions.prefix(4)), timeZone: .current) { _ in }.frame(width: 27, height: 52)
        }
    }
    .padding()
}

#Preview("Session rows", traits: .sizeThatFitsLayout) {
    List(AgendaResponse.preview.sessions.prefix(9)) { SessionRow(session: $0, timeZone: TimeZone.current.identifier) }
        .frame(width: 400, height: 900)
}

@MainActor private var headersAndBadges: some View {
    VStack(alignment: .leading, spacing: 12) {
        DayHeader(date: AgendaModel.preview().key(.now))
        DayHeader(date: AgendaModel.preview().key(.now.addingTimeInterval(86400)))
        DayHeader(date: AgendaModel.preview().key(.now.addingTimeInterval(3 * 86400)))
        HStack { StatusBadge(status: "confirmed"); StatusBadge(status: "pending"); StatusBadge(status: "unverified") }
    }
    .padding()
    .background(Color.appBackground)
}

#Preview("Day header and badges", traits: .sizeThatFitsLayout) {
    headersAndBadges.preferredColorScheme(.light)
}

#Preview("Day header and badges · dark", traits: .sizeThatFitsLayout) {
    headersAndBadges.preferredColorScheme(.dark)
}
#endif
