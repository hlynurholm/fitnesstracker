import SwiftUI

/// The landing page: a grid of data widgets from the watch and from training.
///
/// Edit mode (touch and hold a widget, or the Edit Home button at the bottom of the page): widgets wiggle, and can
/// be dragged to a new place, resized by dragging the line round their bottom right corner, and set up or removed
/// from the button in their top left corner. Widgets are added back with the Add widget button.
/// The layout is saved on the phone.
struct HomeScreen: View {
    let openToday: () -> Void
    @State private var model = HomeModel()
    @State private var editing = false
    @State private var adding = false
    @State private var dragging: CardKind?
    /// For resizing by the corner: the grid's width, each widget's size on screen, and the size of the widget being
    /// resized as it was when the drag began.
    @State private var gridWidth: CGFloat = 0
    @State private var sizes: [CardKind: CGSize] = [:]
    @State private var resizeStart: CGSize?
    /// "Use this range for all widgets" asks twice: first this dialog, then an alert.
    @State private var askApply: ApplyAll?
    @State private var confirmApply: ApplyAll?
    @State private var openDay: String?
    @State private var openRun: Int?
    @State private var openAll = false
    @State private var openDetail: CardKind?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Screen(title: "Home") {
            Text(editing ? "Drag a widget to move it, or its corner to resize it. The button in its top left corner has its settings." : Day.label(model.today, year: true))
                .font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted).padding(.horizontal, Theme.Space.xs)
            if let error = model.error, model.dash == nil { ErrorCard(message: error) { await model.load() } }
            if model.loaded, !model.hasWatchData, !editing { waiting }
            WidgetGrid(spacing: Theme.Space.m) {
                ForEach(model.visible) { setting in card(setting).layoutValue(key: WidgetSizeKey.self, value: setting.shape) }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            if !model.loaded { ProgressView().frame(maxWidth: .infinity).padding(.top, 60) }
            // Editing starts from the very end of the page, out of the way.
            if model.loaded, !editing {
                Button { startEditing() } label: {
                    Label("Edit Home", systemImage: "square.grid.2x2").font(Theme.Typography.label).foregroundStyle(Theme.Palette.text)
                        .padding(.horizontal, Theme.Space.l).frame(height: 40).glass()
                }
                .buttonStyle(.plain).frame(maxWidth: .infinity).padding(.top, Theme.Space.m)
            }
        }
        .navigationTitle("Home")
        // While editing, the two controls sit above the tab bar.
        .safeAreaInset(edge: .bottom) {
            if editing {
                HStack(spacing: Theme.Space.m) {
                    Button { adding = true } label: { Label("Add widget", systemImage: "plus").font(Theme.Typography.label).padding(.horizontal, Theme.Space.l).frame(height: 44).glass() }
                    Button { withAnimation(.snappy) { editing = false; dragging = nil } } label: {
                        Text("Done").font(Theme.Typography.label).foregroundStyle(Theme.Palette.onAccent).padding(.horizontal, Theme.Space.xl).frame(height: 44).background(Theme.Palette.accent, in: Capsule())
                    }
                }
                .buttonStyle(.plain).foregroundStyle(Theme.Palette.text).padding(.bottom, Theme.Space.s)
            }
        }
        .sheet(isPresented: $adding) { AddWidgetSheet(model: model).presentationDetents([.medium, .large]) }
        .confirmationDialog("Use \(askApply?.label ?? "") for all widgets?", isPresented: Binding(get: { askApply != nil }, set: { if !$0 { askApply = nil } }), titleVisibility: .visible, presenting: askApply) { choice in
            Button("Apply to all widgets") {
                // Second check, shown once this dialog has closed.
                Task { try? await Task.sleep(for: .milliseconds(400)); confirmApply = choice }
            }
        } message: { _ in Text("Every widget with a chart will show this range at this resolution.") }
        .alert("Are you sure?", isPresented: Binding(get: { confirmApply != nil }, set: { if !$0 { confirmApply = nil } }), presenting: confirmApply) { choice in
            Button("Yes, change all widgets", role: .destructive) { withAnimation { model.applyToAll(range: choice.range, every: choice.every) } }
            Button("Cancel", role: .cancel) {}
        } message: { choice in
            Text("This sets \(model.layout.filter { $0.kind.hasRange && !$0.hidden }.count) widgets to \(choice.label). Ranges and resolutions you set one by one will be lost.")
        }
        .navigationDestination(item: $openDay) { DayScreen(date: $0) }
        .navigationDestination(item: $openRun) { RunScreen(id: $0) }
        .navigationDestination(isPresented: $openAll) { AllMetricsScreen(model: model) }
        .navigationDestination(item: $openDetail) { WidgetDetailScreen(model: model, kind: $0) }
        .task { await model.load() }
        .refreshable { await model.load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active, model.loaded { Task { await model.load() } } }
    }

    private func startEditing() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy) { editing = true }
    }

    /// Shown until the first import from Garmin has arrived.
    private var waiting: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(kind: .all, title: "Watch data")
            Text("Nothing from your watch yet. The server fetches about four months from Garmin on its first sync, then keeps up every 30 minutes.").font(Theme.Typography.callout)
            if let message = model.syncMessage { Text(message).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
            Button(model.syncing ? "Checking Garmin" : "Check Garmin now") { Task { await model.syncGarmin() } }.buttonStyle(.tinted).disabled(model.syncing)
        }
        .card()
    }

    // MARK: One widget

    @ViewBuilder
    private func card(_ setting: CardSetting) -> some View {
        let size = setting.shape
        let surface = content(setting, size: size)
            .allowsHitTesting(!editing) // while editing, touches move and resize the widget instead
            // The heading sits in the same place at every size; a quarter-height widget only has less room below it.
            .padding([.horizontal, .top], Theme.Space.l).padding(.bottom, size.rows == 1 ? Theme.Space.s : Theme.Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .cardSurface(fill: setting.kind.fill?.colors, lightFill: setting.kind.fill?.light ?? false, glass: !editing)
            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { sizes[setting.kind] = $0 }
        if editing {
            surface
                .opacity(dragging == setting.kind ? 0.4 : 1)
                .overlay(alignment: .topLeading) { menuButton(setting) }
                .overlay(alignment: .bottomTrailing) { resizeHandle(setting) }
                .modifier(Wiggle(size: sizes[setting.kind] ?? .zero))
                .onDrag { dragging = setting.kind; return NSItemProvider(object: setting.id as NSString) }
                .onDrop(of: [.text], delegate: ReorderDrop(target: setting.kind, model: model, dragging: $dragging))
        } else {
            // Touch and hold any widget to start editing, as on the iOS home screen.
            // A tap opens the widget's own page. (The session, last run and watch data widgets open theirs themselves.)
            surface
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .onTapGesture { if !editing, setting.kind.hasPage { openDetail = setting.kind } }
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in startEditing() })
        }
    }

    @ViewBuilder
    private func content(_ setting: CardSetting, size: WidgetSize) -> some View {
        switch setting.kind {
        // A touch that was held long enough to start editing must not also open the widget's page when it lifts.
        case .today: SessionCard(model: model, size: size) { date in if !editing { if date == model.today { openToday() } else { openDay = date } } }
        case .lastRun: LastRunCard(model: model, size: size) { if !editing { openRun = $0 } }
        case .week: WeekCard(model: model, size: size)
        case .weight: WeightWidget(model: model, setting: setting, size: size)
        case .nutrition: NutritionCard(model: model, setting: setting, size: size)
        case .sleep: SleepCard(model: model, setting: setting, size: size)
        case .intensity: IntensityCard(model: model, setting: setting, size: size)
        case .hrv: HRVCard(model: model, setting: setting, size: size)
        case .facts: FactsCard(model: model, size: size)
        case .all: AllMetricsCard(model: model, size: size) { if !editing { openAll = true } }
        default: if let spec = MetricSpec.all[setting.kind] { MetricCard(model: model, setting: setting, spec: spec, size: size) }
        }
    }

    /// Button in the top left corner while editing: opens the widget's settings (size, range, resolution, chart, remove).
    private func menuButton(_ setting: CardSetting) -> some View {
        Menu { menu(setting) } label: {
            Image(systemName: "ellipsis").font(.caption.weight(.heavy)).foregroundStyle(Theme.Palette.background)
                .frame(width: 28, height: 28).background(Theme.Palette.text, in: Circle())
                .overlay(Circle().stroke(Theme.Palette.background, lineWidth: 2))
                .padding(8).contentShape(Rectangle())
        }
        .offset(x: -14, y: -14)
        .accessibilityLabel("Settings for \(setting.kind.title)")
    }

    /// Thick line round the bottom right corner while editing. Dragging it resizes the widget: it takes whichever of
    /// the five sizes is nearest to where the corner has been pulled.
    private func resizeHandle(_ setting: CardSetting) -> some View {
        let radius = Theme.Radius.card
        return Path { $0.addArc(center: CGPoint(x: 44 - radius, y: 44 - radius), radius: radius - 8, startAngle: .degrees(6), endAngle: .degrees(84), clockwise: false) }
            .stroke(Theme.Palette.text.opacity(0.9), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { drag in
                    let start = resizeStart ?? sizes[setting.kind] ?? .zero
                    if resizeStart == nil { resizeStart = start }
                    let spacing = Theme.Space.m, quarter = (gridWidth - 3 * spacing) / 4
                    let wide = start.width + drag.translation.width > gridWidth * 0.75
                    let rows = (start.height + drag.translation.height + spacing) / (quarter + spacing)
                    let choices: [WidgetSize] = wide ? [.strip, .wide, .large] : [.small, .square]
                    guard gridWidth > 0, let size = choices.min(by: { abs(Double($0.rows) - rows) < abs(Double($1.rows) - rows) }), size != setting.shape else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy) { model.update(setting.kind) { $0.size = size; $0.wide = size.isWide } }
                }
                .onEnded { _ in resizeStart = nil })
            .accessibilityLabel("Resize \(setting.kind.title), now \(setting.shape.label)")
            .accessibilityAdjustableAction { direction in
                let all = WidgetSize.allCases, i = all.firstIndex(of: setting.shape) ?? 0
                let size = all[min(max(i + (direction == .increment ? 1 : -1), 0), all.count - 1)]
                model.update(setting.kind) { $0.size = size; $0.wide = size.isWide }
            }
    }

    /// Settings for one widget, behind the button in its top left corner while editing.
    @ViewBuilder
    private func menu(_ setting: CardSetting) -> some View {
        let wide = setting.shape.isWide
        Menu {
            Picker("Size", selection: Binding(get: { setting.shape }, set: { size in withAnimation(.snappy) { model.update(setting.kind) { $0.size = size; $0.wide = size.isWide } } })) {
                ForEach(WidgetSize.allCases.reversed(), id: \.self) { Text($0.label).tag($0) }
            }
        } label: {
            Label("Size: \(setting.shape.label)", systemImage: "rectangle.3.group")
        }
        if setting.kind.hasRange {
            let span = setting.span(wide: wide), every = setting.every(wide: wide), line = setting.chartStyle == .line
            Menu {
                Picker("Range", selection: Binding(get: { span }, set: { days in withAnimation { model.setRange(setting.kind, days) } })) {
                    ForEach(RangeOption.all) { Text("Last \($0.label)").tag($0.days) }
                }
            } label: {
                Label("Range: \(RangeOption.label(span))", systemImage: "calendar")
            }
            Menu {
                Picker("Resolution", selection: Binding(get: { every }, set: { days in withAnimation { model.update(setting.kind) { $0.resolution = days } } })) {
                    ForEach(ResolutionOption.all) { Text($0.label).tag($0.days) }
                }
            } label: {
                Label("Resolution: \(ResolutionOption.label(every))", systemImage: "chart.bar.xaxis")
            }
            if setting.kind != .hrv {
            Menu {
                Picker("Chart", selection: Binding(get: { line ? "line" : "bars" }, set: { kind in withAnimation { model.update(setting.kind) { $0.chart = kind } } })) {
                    Label("Bars", systemImage: "chart.bar.fill").tag("bars")
                    Label("Line", systemImage: "chart.xyaxis.line").tag("line")
                }
            } label: {
                Label("Chart: \(line ? "line" : "bars")", systemImage: line ? "chart.xyaxis.line" : "chart.bar.fill")
            }
            }
            if setting.kind != .hrv, setting.kind != .sleep {
                Menu {
                    Picker("Scale", selection: Binding(get: { setting.isRelative ? "relative" : "absolute" }, set: { scale in withAnimation { model.update(setting.kind) { $0.scale = scale } } })) {
                        Text("Absolute, from zero").tag("absolute")
                        Text("Relative, from the lowest value").tag("relative")
                    }
                } label: {
                    Label("Scale: \(setting.isRelative ? "relative" : "absolute")", systemImage: "arrow.up.and.down")
                }
            }
            Button { askApply = ApplyAll(range: span, every: every) } label: { Label("Use this range and resolution for all widgets", systemImage: "square.on.square") }
        }
        Divider()
        Button(role: .destructive) { withAnimation(.snappy) { model.update(setting.kind) { $0.hidden = true } } } label: { Label("Remove widget", systemImage: "minus.circle") }
    }
}

/// A range and resolution about to be given to every widget.
private struct ApplyAll {
    let range: Int
    let every: Int
    var label: String { "\(RangeOption.label(range)), \(ResolutionOption.label(every))" }
}

/// Moves the dragged widget to the place of the widget it is dragged over.
private struct ReorderDrop: DropDelegate {
    let target: CardKind
    let model: HomeModel
    @Binding var dragging: CardKind?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = model.layout.firstIndex(where: { $0.kind == dragging }), let to = model.layout.firstIndex(where: { $0.kind == target }) else { return }
        withAnimation(.snappy) { model.layout.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

/// The rocking of widgets in edit mode, after the iOS home screen: each widget turns a little about its centre and
/// drifts a fraction of a point, on its own rhythm so that no two move together. The turn is sized so that the edge
/// of every widget travels the same short distance, which means a large widget turns less than a small one.
private struct Wiggle: ViewModifier {
    let size: CGSize
    @State private var phase = Double.random(in: 0..<1)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the edge of a widget travels, in points.
    private static let travel = 0.6

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let angle = Self.travel / (Double(max(size.width, size.height, 80)) / 2)
                content
                    .rotationEffect(.radians(angle * sin((t / (0.27 + phase * 0.05) + phase) * 2 * .pi)))
                    .offset(x: 0.35 * sin((t / 0.43 + phase) * 2 * .pi), y: 0.35 * cos((t / 0.39 + phase) * 2 * .pi))
            }
        }
    }
}

/// The widgets that are not on the dashboard, to add back.
private struct AddWidgetSheet: View {
    let model: HomeModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let hidden = model.layout.filter(\.hidden)
        NavigationStack {
            ScrollView {
                if hidden.isEmpty {
                    Text("Every widget is already on your dashboard.").font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted).padding(.top, 40)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.m), GridItem(.flexible())], spacing: Theme.Space.m) {
                    ForEach(hidden) { card in
                        Button { withAnimation(.snappy) { model.add(card.kind) } } label: {
                            VStack(alignment: .leading, spacing: Theme.Space.s) {
                                HStack {
                                    Image(systemName: card.kind.icon).font(.title3).foregroundStyle(card.kind.tint)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.Palette.ok)
                                }
                                Text(card.kind.title).font(Theme.Typography.headline).foregroundStyle(Theme.Palette.text).multilineTextAlignment(.leading)
                                Text(model.hasData(card.kind) ? " " : "no data yet").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
                            }
                            .padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(card.kind.title)")
                    }
                }
                .padding(Theme.Space.l)
            }
            .screenBackground()
            .inlineTitle("Add widgets")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
