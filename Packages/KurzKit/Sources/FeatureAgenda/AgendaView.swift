import DesignSystem
import Domain
import SwiftUI

public struct AgendaView: View {
    @Bindable var model: AgendaModel
    let userEmail: String
    let signOut: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected: AgendaSession?
    @State private var choosingDate = false
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
                .inspector(isPresented: Binding { selected != nil } set: { if !$0 { selected = nil } }) {
                    if let selected, case .loaded(let agenda) = model.phase {
                        SessionDetail(session: selected, timeZone: agenda.timeZone) { self.selected = nil }
                    }
                }
        }
        .onChange(of: compact, initial: true) { model.rollingWeek = compact }
        .task(id: model.range.from + model.range.to) { await model.refresh() }
    }

    private var subtitle: String {
        let dates = model.dates
        let label = model.period == .day
            ? dates[0].formatted(.dateTime.weekday(.wide).day().month(.wide))
            : (dates[0]..<dates[dates.count - 1]).formatted(.interval.day().month(.wide).year())
        guard case .loaded = model.phase else { return label }
        let count = model.days.reduce(0) { $0 + $1.sessions.count }
        return label + " · " + String(localized: "\(count) sessions")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Go to date", systemImage: "calendar") { choosingDate = true }
                .popover(isPresented: $choosingDate) {
                    DatePicker("Go to date", selection: Binding { model.anchor } set: { model.show($0); choosingDate = false }, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Color.appPrimary)
                        .frame(minWidth: 320)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
            filterMenu
            Menu("Account", systemImage: "person.crop.circle") {
                Text(userEmail)
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }.keyboardShortcut("r")
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: signOut)
                    .accessibilityIdentifier("sign-out-button")
            }
            .menuIndicator(.hidden)
            .accessibilityIdentifier("account-menu")
        }
    }

    private var filterMenu: some View {
        let filtering = model.onlyPending || !model.hiddenForms.isEmpty || !model.hiddenCategories.isEmpty
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
                Button("Show all", systemImage: "arrow.uturn.backward") {
                    model.onlyPending = false
                    model.hiddenForms = []
                    model.hiddenCategories = []
                }
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
                Spacer()
                GlassEffectContainer {
                    HStack(spacing: 6) {
                        Button("Previous", systemImage: "chevron.left", action: model.previous)
                            .labelStyle(.iconOnly)
                            .keyboardShortcut(.leftArrow)
                        Button("Today") { model.goToToday() }
                            .keyboardShortcut("t")
                        Button("Next", systemImage: "chevron.right", action: model.next)
                            .labelStyle(.iconOnly)
                            .keyboardShortcut(.rightArrow)
                    }
                    .buttonStyle(.glass)
                    .tint(Color.appPrimary)
                }
            }
            if compact, model.period == .week, case .loaded = model.phase {
                WeekStrip(model: model, focusedDay: $focusedDay)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView()
        case .failed(let message):
            LoadFailedView("Couldn't load your agenda", message: message) { Task { await model.refresh() } }
        case .loaded(let agenda):
            let days = model.days
            if days.isEmpty, !model.query.isEmpty {
                ContentUnavailableView.search(text: model.query)
            } else if days.isEmpty {
                ContentUnavailableView("No sessions", systemImage: "calendar", description: Text(model.period == .day ? "Nothing scheduled for this day." : "Nothing scheduled for this week."))
                    .accessibilityIdentifier("agenda-empty")
            } else if compact, model.period == .week {
                WeekList(days: days, timeZone: agenda.timeZone, focusedDay: $focusedDay) { selected = $0 }
                    .accessibilityIdentifier("agenda-list")
            } else {
                TimeGrid(model: model, days: days, timeZone: TimeZone(identifier: agenda.timeZone) ?? .current) { selected = $0 }
                    .accessibilityIdentifier("agenda-list")
            }
        }
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
                        Text(date.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(Color.appMutedForeground)
                        DayNumber(date: date, today: model.calendar.isDateInToday(date))
                        Circle().fill(booked.contains(key) ? Color.appPrimary : .clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!booked.contains(key))
                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
            }
        }
    }
}

struct DayNumber: View {
    let date: Date
    let today: Bool

    var body: some View {
        Text(date.formatted(.dateTime.day()))
            .font(.subheadline.weight(today ? .bold : .regular).monospacedDigit())
            .foregroundStyle(today ? Color.white : Color.appForeground)
            .frame(width: 30, height: 30)
            .background(today ? Color.appDestructive : .clear, in: Circle())
    }
}

struct WeekList: View {
    let days: [AgendaDay]
    let timeZone: String
    @Binding var focusedDay: String?
    let select: (AgendaSession) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(days) { day in
                    Section {
                        ForEach(day.sessions) { session in
                            SessionRow(session: session, timeZone: timeZone)
                                .contentShape(.rect)
                                .onTapGesture { select(session) }
                                .accessibilityAction { select(session) }
                        }
                    } header: {
                        DayHeader(date: day.date)
                    }
                    .id(day.date)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .onChange(of: focusedDay) {
                guard let day = focusedDay else { return }
                withAnimation { proxy.scrollTo(day, anchor: .top) }
                focusedDay = nil
            }
        }
    }
}

struct TimeGrid: View {
    let model: AgendaModel
    let days: [AgendaDay]
    let timeZone: TimeZone
    let select: (AgendaSession) -> Void
    private let hourHeight: CGFloat = 52
    private let gutter: CGFloat = 48
    private let minLaneWidth: CGFloat = 52
    private let chipWidth: CGFloat = 30

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
                                Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption).foregroundStyle(Color.appMutedForeground)
                                DayNumber(date: date, today: model.calendar.isDateInToday(date))
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
                .onChange(of: model.dates, initial: true) {
                    let earliest = days.flatMap(\.sessions).map { minutes($0.startsAt) }.min()
                    let showsToday = model.dates.contains { model.calendar.isDateInToday($0) }
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
                    SessionBlock(session: session, timeZone: timeZone, compact: laneWidth < 56)
                        .frame(width: laneWidth - 3, height: height(session.startsAt, session.endsAt))
                        .offset(x: CGFloat(placement.lane) * laneWidth + 1.5, y: top(session.startsAt))
                        .onTapGesture { select(session) }
                        .accessibilityAction { select(session) }
                }
            }
            ForEach(layout.overflows) { overflow in
                OverflowChip(sessions: overflow.sessions, timeZone: timeZone, summary: maxLanes == 1, select: select)
                    .frame(width: overflowWidth - 3, height: height(overflow.start, overflow.end))
                    .offset(x: width - overflowWidth + 1.5, y: top(overflow.start))
            }
            if model.calendar.isDateInToday(date) {
                Rectangle().fill(Color.appDestructive).frame(height: 1.5)
                    .overlay(alignment: .leading) { Circle().fill(Color.appDestructive).frame(width: 8, height: 8).offset(x: -4) }
                    .offset(y: minutes(.now) / 60 * hourHeight)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 24 * hourHeight)
        .overlay(alignment: .leading) { Rectangle().fill(Color.appBorder).frame(width: 0.5) }
    }

    private func top(_ start: Date) -> CGFloat {
        minutes(start) / 60 * hourHeight + 1
    }

    private func height(_ start: Date, _ end: Date?) -> CGFloat {
        let duration = (end ?? start.addingTimeInterval(1800)).timeIntervalSince(start) / 3600 * hourHeight - 2
        return min(max(26, duration), 24 * hourHeight - top(start))
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
    let select: (AgendaSession) -> Void
    @State private var showing = false

    var body: some View {
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
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.appBorder) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(summary ? Text("\(sessions.count) sessions") : Text("\(sessions.count) more sessions"))
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sessions) { session in
                    Button {
                        showing = false
                        select(session)
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(Color.appCategory(id: session.category?.id, name: session.category?.name)).frame(width: 8, height: 8)
                            Text(session.startsAt.timeOfDay(in: timeZone.identifier)).monospacedDigit().foregroundStyle(Color.appMutedForeground)
                            Text(session.serviceName ?? session.formTitle).foregroundStyle(Color.appForeground)
                            Spacer(minLength: 12)
                            Text(occupancy(session)).font(.caption).foregroundStyle(Color.appMutedForeground)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
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

    var body: some View {
        let color = Color.appCategory(id: session.category?.id, name: session.category?.name)
        let shape = RoundedRectangle(cornerRadius: 6)
        let title = session.serviceName ?? session.formTitle
        let details = session.startsAt.timeOfDay(in: timeZone.identifier) + " · " + occupancy(session)
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
        .background(color.opacity(0.22), in: shape)
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .overlay {
            if session.pendingCount > 0 { shape.strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
        }
        .clipShape(shape)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title + ", " + details))
        .accessibilityAddTraits(.isButton)
    }
}

struct SessionRow: View {
    let session: AgendaSession
    let timeZone: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.startsAt.timeOfDay(in: timeZone))
                if let end = session.endsAt { Text(end.timeOfDay(in: timeZone)).foregroundStyle(Color.appMutedForeground) }
            }
            .font(.subheadline.monospacedDigit())
            .frame(width: 52, alignment: .trailing)

            Capsule().fill(Color.appCategory(id: session.category?.id, name: session.category?.name)).frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(session.serviceName ?? session.formTitle).font(.headline).foregroundStyle(Color.appForeground)
                Text(session.capacity == 1 && !session.appointments.isEmpty ? session.formTitle : session.formTitle + " · " + occupancy(session)).font(.caption).foregroundStyle(Color.appMutedForeground)
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
        NavigationStack {
            List {
                Section {
                    LabeledContent("Form", value: session.formTitle)
                    LabeledContent("Category") {
                        Label {
                            Text(session.category?.name ?? "—")
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(Color.appCategory(id: session.category?.id, name: session.category?.name))
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
            .navigationTitle(session.serviceName ?? session.formTitle)
            .navigationSubtitle(when)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: close).keyboardShortcut(.cancelAction)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var when: String {
        let day = session.startsAt.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: timeZone) ?? .current).weekday(.wide).day().month(.wide))
        return [day, [session.startsAt, session.endsAt].compactMap { $0.map { $0.timeOfDay(in: timeZone) } }.joined(separator: "–")].joined(separator: " · ")
    }

    private func initials(_ name: String?) -> String {
        (name ?? "?").split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}
