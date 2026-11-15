import SwiftUI

/// The landing page: a grid of data widgets from the watch and from training.
///
/// Normal mode: touch and hold a widget for its settings (size, range of days shown, remove).
/// Edit mode (the Edit Home button at the bottom of the page): widgets can be dragged to a new place, resized with the handle in their bottom
/// right corner, removed with the minus in their top left corner, and added with the plus button.
/// The layout is saved on the phone.
struct HomeScreen: View {
    let openToday: () -> Void
    @State private var model = HomeModel()
    @State private var editing = false
    @State private var adding = false
    @State private var dragging: CardKind?
    /// "Use this range for all widgets" asks twice: first this dialog, then an alert.
    @State private var askApply: ApplyAll?
    @State private var confirmApply: ApplyAll?
    @State private var openDay: String?
    @State private var openRun: Int?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Screen {
            Text(editing ? "Drag to move. Use the corner handle to resize." : Day.label(model.today, year: true))
                .font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted).padding(.horizontal, Theme.Space.xs)
            if let error = model.error, model.dash == nil { ErrorCard(message: error) { await model.load() } }
            if model.loaded, !model.hasWatchData, !editing { waiting }
            WidgetGrid(spacing: Theme.Space.m) {
                ForEach(model.visible) { setting in card(setting).layoutValue(key: WidgetSizeKey.self, value: setting.shape) }
            }
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
                        Text("Done").font(Theme.Typography.label).foregroundStyle(.white).padding(.horizontal, Theme.Space.xl).frame(height: 44).background(Theme.Palette.accent, in: Capsule())
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
            .padding(size.rows == 1 ? Theme.Space.m : Theme.Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .cardSurface(fill: setting.kind.fill?.colors, lightFill: setting.kind.fill?.light ?? false)
            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        if editing {
            surface
                .opacity(dragging == setting.kind ? 0.4 : 1)
                .overlay(alignment: .topLeading) { removeButton(setting) }
                .overlay(alignment: .bottomTrailing) { resizeHandle(setting) }
                .modifier(Wiggle())
                .onDrag { dragging = setting.kind; return NSItemProvider(object: setting.id as NSString) }
                .onDrop(of: [.text], delegate: ReorderDrop(target: setting.kind, model: model, dragging: $dragging))
        } else {
            surface.contextMenu { menu(setting) }
        }
    }

    @ViewBuilder
    private func content(_ setting: CardSetting, size: WidgetSize) -> some View {
        switch setting.kind {
        case .today: SessionCard(model: model, size: size) { date in if date == model.today { openToday() } else { openDay = date } }
        case .lastRun: LastRunCard(model: model, size: size) { openRun = $0 }
        case .week: WeekCard(model: model, size: size)
        case .weight: WeightWidget(model: model, setting: setting, size: size)
        case .nutrition: NutritionCard(model: model, setting: setting, size: size)
        case .sleep: SleepCard(model: model, setting: setting, size: size)
        case .intensity: IntensityCard(model: model, setting: setting, size: size)
        case .hrv: HRVCard(model: model, setting: setting, size: size)
        case .facts: FactsCard(model: model, size: size)
        case .all: AllMetricsCard(model: model, size: size)
        default: if let spec = MetricSpec.all[setting.kind] { MetricCard(model: model, setting: setting, spec: spec, size: size) }
        }
    }

    /// Minus in the top left corner: takes the widget off the dashboard. It can be added back with the plus button.
    private func removeButton(_ setting: CardSetting) -> some View {
        Button { withAnimation(.snappy) { model.update(setting.kind) { $0.hidden = true } } } label: {
            Image(systemName: "minus").font(.caption.weight(.heavy)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(Theme.Palette.rest, in: Circle())
                .overlay(Circle().stroke(Theme.Palette.background, lineWidth: 2))
                .padding(8).contentShape(Rectangle())
        }
        .buttonStyle(.plain).offset(x: -14, y: -14)
        .accessibilityLabel("Remove \(setting.kind.title)")
    }

    /// Handle in the bottom right corner: each tap gives the widget the next of the five sizes.
    private func resizeHandle(_ setting: CardSetting) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.snappy) { model.update(setting.kind) { $0.size = setting.shape.next; $0.wide = setting.shape.next.isWide } }
        } label: {
            Text(setting.shape.label).font(Theme.Typography.label).foregroundStyle(.white)
                .padding(.horizontal, Theme.Space.s).frame(height: 30).background(Theme.Palette.accent, in: Capsule())
                .overlay(Capsule().stroke(Theme.Palette.background, lineWidth: 2))
                .padding(8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: 12, y: 12)
        .accessibilityLabel("Size of \(setting.kind.title): \(setting.shape.label). Tap for the next size.")
    }

    /// Settings for one widget, on touch and hold.
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
            Button { askApply = ApplyAll(range: span, every: every) } label: { Label("Use this range and resolution for all widgets", systemImage: "square.on.square") }
        }
        Divider()
        Button { startEditing() } label: { Label("Edit dashboard", systemImage: "square.grid.2x2") }
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

/// The small rocking motion of widgets in edit mode.
private struct Wiggle: ViewModifier {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(reduceMotion ? 0 : on ? 0.45 : -0.45))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
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
            .navigationTitle("Add widgets").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
