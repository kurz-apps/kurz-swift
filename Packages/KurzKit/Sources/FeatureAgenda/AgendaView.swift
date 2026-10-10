import DesignSystem
import Domain
import SwiftUI

public struct AgendaView: View {
    @Bindable var model: AgendaModel
    let userEmail: String
    let signOut: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var focusedDay: String?

    public init(model: AgendaModel, userEmail: String, signOut: @escaping () -> Void) {
        self.model = model
        self.userEmail = userEmail
        self.signOut = signOut
    }

    private var compact: Bool { sizeClass == .compact }

    public var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
                .safeAreaBar(edge: .top) { controls }
                .navigationTitle("Agenda")
                .navigationSubtitle(subtitle)
                .searchable(text: $model.query, prompt: Text("Search session or client"))
                .refreshable { await model.refresh() }
                .toolbar { toolbar }
                .inspector(isPresented: Binding { model.selectedSession != nil } set: { if !$0 { model.selection = nil } }) {
                    if let selected = model.selectedSession, case .loaded(let agenda) = model.phase {
                        SessionDetail(session: selected, timeZone: agenda.timeZone) { model.selection = nil }
                    }
                }
        }
        .focusedSceneValue(model)
        .onChange(of: compact, initial: true) { model.rollingWeek = compact }
        .task(id: model.range.from + model.range.to) { await model.refresh() }
    }

    private var subtitle: String {
        let label = model.periodLabel
        guard case .loaded = model.phase, !model.isStale else { return label }
        let count = model.days.reduce(0) { $0 + $1.sessions.count }
        return label + " · " + String(localized: "\(count) sessions")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Go to date", systemImage: "calendar") { model.isChoosingDate = true }
            filterMenu
            if compact {
                Menu("Account", systemImage: "person.crop.circle") {
                    Text(userEmail)
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: signOut)
                        .accessibilityIdentifier("sign-out-button")
                }
                .menuIndicator(.hidden)
                .accessibilityIdentifier("account-menu")
            }
        }
    }

    private var filterMenu: some View {
        let filtering = model.isFiltering
        return Menu("Filters", systemImage: filtering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") {
            Toggle("Only pending", systemImage: "clock", isOn: $model.onlyPending)
            if !model.forms.isEmpty {
                Section("Forms") {
                    ForEach(model.forms) { form in
                        Toggle(isOn: visible(form.id, in: \.hiddenForms)) {
                            Text(form.name)
                            Text("\(form.count) sessions")
                        }
                    }
                }
            }
            if !model.categories.isEmpty {
                Section("Categories") {
                    ForEach(model.categories) { category in
                        Toggle(isOn: visible(category.id, in: \.hiddenCategories)) {
                            Label {
                                Text(category.name)
                                Text("\(category.count) sessions")
                            } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(Color.appCategory(id: category.id, name: category.name))
                            }
                        }
                    }
                }
            }
            if filtering {
                Button("Show all", systemImage: "arrow.uturn.backward", action: model.clearFilters)
            }
        }
        .menuIndicator(.hidden)
    }

    private func visible(_ id: String, in set: ReferenceWritableKeyPath<AgendaModel, Set<String>>) -> Binding<Bool> {
        Binding { !model[keyPath: set].contains(id) } set: { if $0 { model[keyPath: set].remove(id) } else { model[keyPath: set].insert(id) } }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("Period", selection: $model.period) {
                    Text("Day").tag(AgendaModel.Period.day)
                    Text("Week").tag(AgendaModel.Period.week)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if model.isRefreshing {
                    ProgressView().controlSize(.small).accessibilityLabel("Updating")
                }
                Spacer()
                GlassEffectContainer {
                    HStack(spacing: 6) {
                        Button("Previous", systemImage: "chevron.left", action: model.previous)
                            .labelStyle(.iconOnly)
                        Button("Today") { model.goToToday() }
                        Button("Next", systemImage: "chevron.right", action: model.next)
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.glass)
                    .tint(Color.appPrimary)
                }
                .popover(isPresented: $model.isChoosingDate, arrowEdge: .top) {
                    DatePicker("Go to date", selection: Binding { model.anchor } set: { model.show($0); model.isChoosingDate = false }, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Color.appPrimary)
                        .environment(\.timeZone, model.calendar.timeZone)
                        .frame(minWidth: 320)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
            }
            if listLayout, model.period == .week, case .loaded = model.phase {
                WeekStrip(model: model, focusedDay: $focusedDay)
            }
            status
            if let error = model.refreshError {
                RefreshBanner(message: error) { Task { await model.refresh() } } dismiss: { model.refreshError = nil }
                    .transition(.opacity)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .animation(.default, value: model.refreshError)
    }

    @ViewBuilder private var status: some View {
        let note = model.timeZoneNote()
        if model.isFiltering || note != nil {
            HStack(spacing: 8) {
                if model.isFiltering {
                    let hidden = model.hiddenByFilters
                    Label(hidden == 0 ? "Filters on" : "Filters on · \(hidden) hidden", systemImage: "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(Color.appForeground)
                    Button("Clear", action: model.clearFilters)
                        .fontWeight(.semibold)
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear filters")
                }
                Spacer(minLength: 0)
                if let note {
                    Label(note, systemImage: "globe").foregroundStyle(Color.appMutedForeground)
                }
            }
            .font(.footnote)
            .lineLimit(1)
        }
    }

    private var listLayout: Bool { compact && model.period == .week || typeSize.isAccessibilitySize }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView()
        case .failed(let message):
            LoadFailedView("Couldn't load your agenda", message: message) { Task { await model.refresh() } }
        case .loaded(let agenda):
            let days = model.days
            if model.isStale, listLayout, days.isEmpty {
                ProgressView()
            } else if !model.isStale, days.isEmpty, !model.query.isEmpty {
                noResults
            } else if !model.isStale, days.isEmpty {
                ContentUnavailableView("No sessions", systemImage: "calendar", description: Text(model.period == .day ? "Nothing scheduled for this day." : "Nothing scheduled for this week."))
                    .accessibilityIdentifier("agenda-empty")
            } else if listLayout {
                WeekList(model: model, days: days, timeZone: agenda.timeZone, focusedDay: $focusedDay)
                    .opacity(model.isStale ? 0.45 : 1)
                    .accessibilityIdentifier("agenda-list")
            } else {
                TimeGrid(model: model, days: days, timeZone: TimeZone(identifier: agenda.timeZone) ?? .current)
                    .accessibilityIdentifier("agenda-list")
            }
        }
    }

    private var noResults: some View {
        ContentUnavailableView {
            Label("No results for “\(model.query)”", systemImage: "magnifyingglass")
        } description: {
            Text("Search only looks at \(model.periodLabel). Go to another date to search there.")
        } actions: {
            if model.hiddenByFilters > 0 {
                Button("Show hidden matches", action: model.clearFilters)
            }
        }
    }
}

struct RefreshBanner: View {
    let message: String
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.appDestructive).accessibilityHidden(true)
            Text(message).foregroundStyle(Color.appForeground)
            Spacer(minLength: 0)
            Button("Try again", action: retry).fontWeight(.semibold).buttonStyle(.borderless)
            Button("Dismiss", systemImage: "xmark", action: dismiss).labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(Color.appMutedForeground)
        }
        .font(.footnote)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.appBorder) }
        .onAppear { AccessibilityNotification.Announcement(message).post() }
    }
}

struct WeekStrip: View {
    let model: AgendaModel
    @Binding var focusedDay: String?

    var body: some View {
        let booked = Set(model.days.map(\.date))
        HStack(spacing: 0) {
            ForEach(model.dates, id: \.self) { date in
                let key = model.key(date)
                Button {
                    focusedDay = key
                } label: {
                    VStack(spacing: 4) {
                        Text(date.formatted(model.dateStyle.weekday(.narrow))).font(.caption2).foregroundStyle(Color.appMutedForeground)
                        DayNumber(text: date.formatted(model.dateStyle.day()), today: model.isToday(date))
                        Circle().fill(booked.contains(key) ? Color.appPrimary : .clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!booked.contains(key))
                .accessibilityLabel(date.formatted(model.dateStyle.weekday(.wide).day().month(.wide).year()))
            }
        }
    }
}

struct DayNumber: View {
    let text: String
    let today: Bool
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 30

    var body: some View {
        Text(text)
            .font(.subheadline.weight(today ? .bold : .regular).monospacedDigit())
            .foregroundStyle(today ? Color.appDestructiveForeground : Color.appForeground)
            .frame(width: size, height: size)
            .background(today ? Color.appDestructive : .clear, in: Circle())
    }
}

struct WeekList: View {
    @Bindable var model: AgendaModel
    let days: [AgendaDay]
    let timeZone: String
    @Binding var focusedDay: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $model.selection) {
                ForEach(days) { day in
                    Section {
                        ForEach(day.sessions) { session in
                            SessionRow(session: session, timeZone: timeZone)
                                .tag(session.id)
                                .sessionMenu(session, timeZone: timeZone) { model.selection = session.id }
                        }
                    } header: {
                        Text(model.dayTitle(day.date))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.appPrimary)
                            .textCase(nil)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .id(day.date)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .onChange(of: focusedDay) {
                guard let day = focusedDay else { return }
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(day, anchor: .top) }
                focusedDay = nil
            }
        }
    }
}

struct TimeGrid: View {
    let model: AgendaModel
    let days: [AgendaDay]
    let timeZone: TimeZone
    @ScaledMetric(relativeTo: .caption2) private var hourHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .caption2) private var gutter: CGFloat = 48
    private let minLaneWidth: CGFloat = 52
    private let chipWidth: CGFloat = 32
    static let minimumBlockHeight: CGFloat = 28

    var body: some View {
        let byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0.sessions) })
        VStack(spacing: 0) {
            if model.dates.count > 1 {
                HStack(spacing: 0) {
                    Color.clear.frame(width: gutter, height: 1)
                    ForEach(model.dates, id: \.self) { date in
                        Button {
                            model.show(date, period: .day)
                        } label: {
                            VStack(spacing: 2) {
                                Text(date.formatted(model.dateStyle.weekday(.abbreviated))).font(.caption).foregroundStyle(Color.appMutedForeground)
                                DayNumber(text: date.formatted(model.dateStyle.day()), today: model.isToday(date))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 6)
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(Date(timeIntervalSince1970: Double(hour) * 3600).formatted(Date.FormatStyle(timeZone: .gmt).hour()))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Color.appMutedForeground)
                                    .opacity(hour == 0 ? 0 : 1)
                                    .offset(y: -7)
                                    .frame(width: gutter - 6, height: hourHeight, alignment: .topTrailing)
                                    .id(hour)
                            }
                        }
                        ForEach(model.dates, id: \.self) { date in
                            column(date: date, sessions: byDate[model.key(date)] ?? [])
                        }
                    }
                    .background(alignment: .top) {
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { _ in
                                Rectangle().fill(Color.appBorder).frame(height: 0.5).frame(height: hourHeight, alignment: .top)
                            }
                        }
                        .padding(.leading, gutter)
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: model.range.from + model.range.to + String(model.isStale), initial: true) {
                    let earliest = model.isStale ? nil : days.flatMap(\.sessions).map { minutes($0.startsAt) }.min()
                    let showsToday = model.dates.contains { model.isToday($0) }
                    proxy.scrollTo(Self.initialHour(earliest: earliest, now: showsToday ? minutes(.now) : nil), anchor: .top)
                }
            }
        }
    }

    private func column(date: Date, sessions: [AgendaSession]) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let maxLanes = max(1, Int(width / minLaneWidth))
            let layout = LaneLayout(sessions, maxLanes: maxLanes)
            let overflowWidth = maxLanes == 1 ? width : chipWidth
            ForEach(sessions) { session in
                if let placement = layout.placements[session.id] {
                    let laneWidth = (width - (placement.reservesChip ? chipWidth : 0)) / CGFloat(placement.lanes)
                    let selected = model.selection == session.id
                    Button { model.selection = session.id } label: {
                        SessionBlock(session: session, timeZone: timeZone, compact: laneWidth < 56, selected: selected)
                    }
                    .buttonStyle(SessionButtonStyle())
                    .accessibilityLabel(spokenSummary(session, timeZone: timeZone.identifier))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .sessionMenu(session, timeZone: timeZone.identifier) { model.selection = session.id }
                    .frame(width: laneWidth - 3, height: height(session.startsAt, session.endsAt))
                    .offset(x: CGFloat(placement.lane) * laneWidth + 1.5, y: top(session.startsAt))
                }
            }
            ForEach(layout.overflows) { overflow in
                OverflowChip(sessions: overflow.sessions, timeZone: timeZone, summary: maxLanes == 1, selection: model.selection) { model.selection = $0.id }
                    .frame(width: overflowWidth - 3, height: height(overflow.start, overflow.end))
                    .offset(x: width - overflowWidth + 1.5, y: top(overflow.start))
            }
            TimelineView(.everyMinute) { context in
                if model.isToday(date, now: context.date) {
                    Rectangle().fill(Color.appDestructive).frame(height: 1.5)
                        .overlay(alignment: .leading) { Circle().fill(Color.appDestructive).frame(width: 8, height: 8).offset(x: -4) }
                        .offset(y: minutes(context.date) / 60 * hourHeight)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: 24 * hourHeight)
        .background {
            TimelineView(.everyMinute) { context in
                if model.dates.count > 1, model.isToday(date, now: context.date) {
                    Color.appPrimary.opacity(0.05)
                }
            }
        }
        .overlay(alignment: .leading) { Rectangle().fill(Color.appBorder).frame(width: 0.5) }
    }

    private func top(_ start: Date) -> CGFloat {
        minutes(start) / 60 * hourHeight + 1
    }

    private func height(_ start: Date, _ end: Date?) -> CGFloat {
        let duration = (end ?? start.addingTimeInterval(1800)).timeIntervalSince(start) / 3600 * hourHeight - 2
        return min(max(Self.minimumBlockHeight, duration), 24 * hourHeight - top(start))
    }

    private func minutes(_ date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    static func initialHour(earliest: Double?, now: Double?) -> Int {
        let firstBusy = earliest.map { Int($0 / 60) - 1 }
        let hour = now.map { Int($0 / 60) - 2 }.map { max($0, firstBusy ?? $0) } ?? firstBusy ?? 7
        return min(max(hour, 0), 23)
    }
}

struct LaneLayout {
    struct Placement: Equatable {
        let lane: Int
        let lanes: Int
        let reservesChip: Bool
    }

    struct Overflow: Identifiable {
        let sessions: [AgendaSession]
        var id: String { sessions[0].id }
        var start: Date { sessions.map(\.startsAt).min() ?? .distantPast }
        var end: Date { sessions.map { $0.endsAt ?? $0.startsAt.addingTimeInterval(1800) }.max() ?? start }
    }

    private(set) var placements: [String: Placement] = [:]
    private(set) var overflows: [Overflow] = []

    init(_ sessions: [AgendaSession], maxLanes: Int) {
        var cluster: [(session: AgendaSession, lane: Int)] = []
        var ends: [Date] = []
        var clusterEnd = Date.distantPast
        func flush() {
            let kept = ends.count <= maxLanes ? ends.count : maxLanes - 1
            for item in cluster where item.lane < kept {
                placements[item.session.id] = Placement(lane: item.lane, lanes: kept, reservesChip: kept < ends.count)
            }
            let hidden = cluster.filter { $0.lane >= kept }.map(\.session)
            if !hidden.isEmpty { overflows.append(Overflow(sessions: hidden)) }
            cluster = []
            ends = []
        }
        for session in sessions.sorted(by: { $0.startsAt < $1.startsAt }) {
            let end = session.endsAt ?? session.startsAt.addingTimeInterval(1800)
            if session.startsAt >= clusterEnd { flush() }
            let lane = ends.firstIndex { $0 <= session.startsAt } ?? ends.count
            if lane == ends.count { ends.append(end) } else { ends[lane] = end }
            cluster.append((session, lane))
            clusterEnd = max(clusterEnd, end)
        }
        flush()
    }
}

struct OverflowChip: View {
    let sessions: [AgendaSession]
    let timeZone: TimeZone
    var summary = false
    var selection: AgendaSession.ID?
    let select: (AgendaSession) -> Void
    @State private var showing = false

    var body: some View {
        let containsSelection = sessions.contains { $0.id == selection }
        Button { showing = true } label: {
            VStack(alignment: summary ? .leading : .center, spacing: 3) {
                if summary {
                    Text(sessions[0].startsAt.timeOfDay(in: timeZone.identifier)).font(.caption2.weight(.semibold).monospacedDigit())
                    HStack(spacing: 3) {
                        ForEach(sessions.prefix(4)) { session in
                            Circle().fill(Color.appCategory(id: session.category?.id, name: session.category?.name)).frame(width: 7, height: 7)
                        }
                    }
                    Label { Text(sessions.count, format: .number) } icon: { Image(systemName: "rectangle.stack.fill").imageScale(.small) }
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.appMutedForeground)
                } else {
                    Text(verbatim: "+\(sessions.count)").font(.caption.weight(.semibold).monospacedDigit())
                }
            }
            .lineLimit(1)
            .foregroundStyle(Color.appForeground)
            .padding(.horizontal, summary ? 7 : 0)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: summary ? .topLeading : .top)
            .background(Color.appMuted, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(containsSelection ? Color.appForeground : Color.appBorder, lineWidth: containsSelection ? 2 : 1) }
            .contentShape(.rect)
        }
        .buttonStyle(SessionButtonStyle())
        .accessibilityLabel(summary ? Text("\(sessions.count) sessions") : Text("\(sessions.count) more sessions"))
        .accessibilityAddTraits(containsSelection ? .isSelected : [])
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sessions) { session in
                    let selected = session.id == selection
                    Button {
                        showing = false
                        select(session)
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(Color.appCategory(id: session.category?.id, name: session.category?.name)).frame(width: 8, height: 8)
                            Text(session.startsAt.timeOfDay(in: timeZone.identifier)).monospacedDigit().foregroundStyle(Color.appMutedForeground)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(session.serviceName ?? session.formTitle).foregroundStyle(Color.appForeground)
                                if let category = session.category?.name {
                                    Text(category).font(.caption).foregroundStyle(Color.appMutedForeground)
                                }
                            }
                            Spacer(minLength: 12)
                            Text(occupancy(session)).font(.caption).foregroundStyle(Color.appMutedForeground)
                            Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.appPrimary).opacity(selected ? 1 : 0)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(SessionButtonStyle())
                    .accessibilityLabel(spokenSummary(session, timeZone: timeZone.identifier))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .frame(minWidth: 300)
            .presentationCompactAdaptation(.popover)
        }
    }
}

func occupancy(_ session: AgendaSession) -> String {
    let count = session.appointments.count
    let base: String = switch session.capacity ?? 0 {
    case _ where count == 0: String(localized: "Free")
    case 0: String(localized: "\(count) booked")
    case 1: session.appointments[0].clientName ?? "—"
    case let capacity: "\(count)/\(capacity)"
    }
    let pending = session.pendingCount
    return pending == 0 ? base : base + " · " + String(localized: "\(pending) pending")
}

struct SessionBlock: View {
    let session: AgendaSession
    let timeZone: TimeZone
    var compact = false
    var selected = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let color = Color.appCategory(id: session.category?.id, name: session.category?.name)
        let shape = RoundedRectangle(cornerRadius: 6)
        let title = session.serviceName ?? session.formTitle
        let details = blockDetails(session, timeZone: timeZone.identifier)
        let tint = colorScheme == .dark ? Color.appCategoryTintOpacity.dark : Color.appCategoryTintOpacity.light
        VStack(alignment: .leading, spacing: 1) {
            if compact {
                Text(session.startsAt.timeOfDay(in: timeZone.identifier)).font(.caption2.weight(.semibold).monospacedDigit())
                HStack(spacing: 2) {
                    Image(systemName: "person.fill").imageScale(.small)
                    Text(session.appointments.count, format: .number)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.appMutedForeground)
            } else {
                Text(title).font(.caption.weight(.semibold)).lineLimit(2)
                Text(details).font(.caption2).foregroundStyle(Color.appMutedForeground)
            }
        }
        .lineLimit(compact ? 1 : nil)
        .foregroundStyle(Color.appForeground)
        .padding(.leading, 7).padding(.trailing, 3).padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(tint), in: shape)
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .overlay {
            if selected {
                shape.strokeBorder(Color.appForeground, lineWidth: 2)
            } else if session.pendingCount > 0 {
                shape.strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .clipShape(shape)
        .contentShape(shape)
    }
}

struct SessionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Highlight(configuration: configuration)
    }

    private struct Highlight: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.appForeground.opacity(configuration.isPressed ? 0.12 : hovering ? 0.06 : 0))
                        .allowsHitTesting(false)
                }
                .onHover { hovering = $0 }
        }
    }
}

extension View {
    func sessionMenu(_ session: AgendaSession, timeZone: String, open: @escaping () -> Void) -> some View {
        contextMenu {
            Button("Open", systemImage: "sidebar.right", action: open)
            Button("Copy time", systemImage: "clock") { copyToPasteboard(sessionWhen(session, timeZone: timeZone)) }
            Button("Copy clients", systemImage: "person.2") { copyToPasteboard(clientList(session)) }
                .disabled(session.appointments.isEmpty)
        }
    }
}

func copyToPasteboard(_ text: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = text
    #else
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #endif
}

func sessionWhen(_ session: AgendaSession, timeZone: String) -> String {
    let day = session.startsAt.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: timeZone) ?? .current).weekday(.wide).day().month(.wide))
    return [day, timeRange(session, timeZone: timeZone)].joined(separator: " · ")
}

func timeRange(_ session: AgendaSession, timeZone: String) -> String {
    [session.startsAt, session.endsAt].compactMap { $0?.timeOfDay(in: timeZone) }.joined(separator: "–")
}

func clientList(_ session: AgendaSession) -> String {
    session.appointments.map { $0.clientName ?? "—" }.joined(separator: "\n")
}

func rowSubtitle(_ session: AgendaSession) -> String {
    let occupancyText = session.capacity == 1 && !session.appointments.isEmpty ? nil : occupancy(session)
    return [session.category?.name, session.formTitle, occupancyText].compactMap { $0 }.joined(separator: " · ")
}

func blockDetails(_ session: AgendaSession, timeZone: String) -> String {
    [session.category?.name, session.startsAt.timeOfDay(in: timeZone), occupancy(session)].compactMap { $0 }.joined(separator: " · ")
}

func spokenSummary(_ session: AgendaSession, timeZone: String) -> String {
    [session.serviceName ?? session.formTitle, session.category?.name, timeRange(session, timeZone: timeZone), occupancy(session)].compactMap { $0 }.joined(separator: ", ")
}

struct SessionRow: View {
    let session: AgendaSession
    let timeZone: String
    @ScaledMetric(relativeTo: .subheadline) private var timeWidth: CGFloat = 52

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.startsAt.timeOfDay(in: timeZone))
                if let end = session.endsAt { Text(end.timeOfDay(in: timeZone)).foregroundStyle(Color.appMutedForeground) }
            }
            .font(.subheadline.monospacedDigit())
            .frame(width: timeWidth, alignment: .trailing)

            Capsule().fill(Color.appCategory(id: session.category?.id, name: session.category?.name)).frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(session.serviceName ?? session.formTitle).font(.headline).foregroundStyle(Color.appForeground)
                Text(rowSubtitle(session)).font(.caption).foregroundStyle(Color.appMutedForeground)
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
}

struct SessionDetail: View {
    let session: AgendaSession
    let timeZone: String
    let close: () -> Void

    var body: some View {
        List {
            Section {
                LabeledContent("Form", value: session.formTitle)
                LabeledContent("Category") {
                    HStack(spacing: 6) {
                        Circle().fill(Color.appCategory(id: session.category?.id, name: session.category?.name)).frame(width: 10, height: 10)
                        Text(session.category?.name ?? "—")
                    }
                }
                LabeledContent("Occupancy", value: occupancy(session))
                if let capacity = session.capacity, capacity > 1 {
                    ProgressView(value: Double(min(session.appointments.count, capacity)), total: Double(capacity)).tint(Color.appPrimary)
                }
            }
            Section("Clients · \(session.appointments.count)") {
                ForEach(session.appointments) { appointment in
                    HStack(spacing: 10) {
                        Text(initials(appointment.clientName))
                            .font(.caption.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .background(Color.appAccent, in: Circle())
                            .foregroundStyle(Color.appAccentForeground)
                        Text(appointment.clientName ?? "—").foregroundStyle(Color.appForeground)
                        Spacer()
                        Text(appointment.series ? "Monthly plan" : "Single")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.appMuted, in: Capsule())
                            .foregroundStyle(Color.appMutedForeground)
                        StatusBadge(status: appointment.status)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.serviceName ?? session.formTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.appForeground)
                        .accessibilityAddTraits(.isHeader)
                    Text(sessionWhen(session, timeZone: timeZone))
                        .font(.subheadline)
                        .foregroundStyle(Color.appMutedForeground)
                }
                Spacer(minLength: 0)
                Button("Close", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .presentationDetents([.medium, .large])
    }

    private func initials(_ name: String?) -> String {
        (name ?? "?").split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}
