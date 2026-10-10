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
            ContentUnavailableView {
                Label("Couldn't load your agenda", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.refresh() } }.buttonStyle(.glassProminent).tint(Color.appPrimary)
            }
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
                .onAppear { proxy.scrollTo(max(0, Int(minutes(.now) / 60) - 2), anchor: .top) }
            }
        }
    }

    private func column(date: Date, sessions: [AgendaSession]) -> some View {
        let lanes = Self.lanes(sessions)
        return GeometryReader { geometry in
            let width = geometry.size.width / CGFloat(lanes.count)
            ForEach(sessions) { session in
                let top = minutes(session.startsAt) / 60 * hourHeight
                let height = max(26, Double(session.duration ?? 30) / 60 * hourHeight - 2)
                SessionBlock(session: session, timeZone: timeZone)
                    .frame(width: width - 3, height: min(height, 24 * hourHeight - top))
                    .offset(x: CGFloat(lanes.index[session.id] ?? 0) * width + 1.5, y: top + 1)
                    .onTapGesture { select(session) }
                    .accessibilityAction { select(session) }
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

    private func minutes(_ date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    static func lanes(_ sessions: [AgendaSession]) -> (index: [String: Int], count: Int) {
        var ends: [Date] = []
        var index: [String: Int] = [:]
        for session in sessions.sorted(by: { $0.startsAt < $1.startsAt }) {
            let end = session.endsAt ?? session.startsAt.addingTimeInterval(1800)
            if let lane = ends.firstIndex(where: { $0 <= session.startsAt }) {
                ends[lane] = end
                index[session.id] = lane
            } else {
                index[session.id] = ends.count
                ends.append(end)
            }
        }
        return (index, max(ends.count, 1))
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

func time(_ date: Date, _ timeZone: String) -> String {
    date.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: timeZone) ?? .current).hour().minute())
}

struct SessionBlock: View {
    let session: AgendaSession
    let timeZone: TimeZone

    var body: some View {
        let color = Color.appCategory(id: session.category?.id, name: session.category?.name)
        let shape = RoundedRectangle(cornerRadius: 6)
        VStack(alignment: .leading, spacing: 1) {
            Text(session.serviceName ?? session.formTitle).font(.caption.weight(.semibold)).lineLimit(2)
            Text(time(session.startsAt, timeZone.identifier) + " · " + occupancy(session)).font(.caption2).foregroundStyle(Color.appMutedForeground)
        }
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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
                Text(time(session.startsAt, timeZone))
                if let end = session.endsAt { Text(time(end, timeZone)).foregroundStyle(Color.appMutedForeground) }
            }
            .font(.subheadline.monospacedDigit())
            .frame(width: 52, alignment: .trailing)

            Capsule().fill(Color.appCategory(id: session.category?.id, name: session.category?.name)).frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(session.serviceName ?? session.formTitle).font(.headline).foregroundStyle(Color.appForeground)
                Text(session.formTitle + " · " + occupancy(session)).font(.caption).foregroundStyle(Color.appMutedForeground)
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
        return [day, [session.startsAt, session.endsAt].compactMap { $0.map { time($0, timeZone) } }.joined(separator: "–")].joined(separator: " · ")
    }

    private func initials(_ name: String?) -> String {
        (name ?? "?").split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
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
