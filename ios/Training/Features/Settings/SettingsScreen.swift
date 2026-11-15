import SwiftUI

/// Server address and API token. Shown full screen on first launch and inside Settings afterwards.
struct ConnectionForm: View {
    var onSaved: () -> Void = {}
    @State private var url = API.shared.baseURL
    @State private var token = ""
    @State private var status: String?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            LabeledField(label: "Server address") {
                TextField(API.defaultBaseURL, text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            LabeledField(label: API.shared.hasToken ? "API token (saved in the Keychain, type to replace)" : "API token") {
                // oneTimeCode keeps iOS from offering to save the token in the Passwords app.
                SecureField("Paste the API token", text: $token).textContentType(.oneTimeCode).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Text("The token is the Worker's API_TOKEN secret. It is kept in the iOS Keychain on this phone only.").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
            if let status { Text(status).font(Theme.Typography.callout).foregroundStyle(status.hasPrefix("Connected") ? Theme.Palette.ok : Theme.Palette.danger) }
            Button(checking ? "Checking" : "Save and test connection") { Task { await save() } }.buttonStyle(.primary).disabled(checking || (token.isEmpty && !API.shared.hasToken))
        }
    }

    private func save() async {
        checking = true
        defer { checking = false }
        API.shared.baseURL = url.trimmingCharacters(in: .whitespaces)
        if !token.isEmpty { API.shared.setToken(token) }
        do {
            try await API.shared.send("GET", "/api/whoami")
            status = "Connected"
            token = ""
            await AppModel.shared.load()
            onSaved()
        } catch { status = error.localizedDescription }
    }
}

struct SettingsScreen: View {
    @State private var maps = MapChoice.preferred
    @State private var values: [String: String] = [:]
    @State private var error: String?
    @State private var toast: String?
    @State private var confirmSignOut = false

    var body: some View {
        let program = AppModel.shared.program
        Screen(title: "Settings") {
            if let error { ErrorCard(message: error) { await load() } }

            // Uploads, Garmin and Apple Health sync, exports and reports.
            NavigationLink { DataScreen() } label: {
                Row(title: "Data and sync", subtitle: "Garmin, Apple Health, uploads, exports and reports") {
                    EmptyView()
                }
            }
            .buttonStyle(.plain).card()

            AppearanceCard()

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                CardTitle("Maps", note: "for runs you have not set by hand")
                LabeledField(label: "Map") {
                    Picker("Map", selection: $maps.look) { ForEach(MapLook.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                }
                LabeledField(label: "View") {
                    Picker("View", selection: $maps.threeD) { Text("2D").tag(false); Text("3D").tag(true) }.pickerStyle(.segmented)
                }
                LabeledField(label: "Graph under the map") {
                    Picker("Graph", selection: $maps.graph) { ForEach(RunGraph.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                }
            }
            .card()
            .onChange(of: maps) { _, new in MapChoice.preferred = new }

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                CardTitle("Plan")
                LabeledField(label: "Week 1 starts on (Monday)") {
                    DatePicker("", selection: Binding(get: { Day.date(values["program_start_date"] ?? Day.today()) }, set: { values["program_start_date"] = Day.string($0) }), displayedComponents: .date)
                        .labelsHidden().environment(\.timeZone, TimeZone(identifier: "UTC")!).frame(maxWidth: .infinity, alignment: .leading)
                }
                LabeledField(label: "Jump phase") {
                    Picker("Jump phase", selection: field("phase_override")) {
                        Text("Follow the plan").tag("")
                        Text("Phase 1: Tune-up").tag("1"); Text("Phase 2: Power").tag("2"); Text("Phase 3: Reactive").tag("3")
                    }
                    .pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                }
                LabeledField(label: "Lift order") {
                    Picker("Lift order", selection: Binding(get: { values["lift_rotation"] == "0" ? "0" : "1" }, set: { values["lift_rotation"] = $0 })) {
                        Text("Continue where I left off (a skipped lift comes next)").tag("1")
                        Text("Fixed: A on Monday, B on Wednesday, C on Friday").tag("0")
                    }
                    .pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.card()

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                CardTitle("Targets")
                HStack(spacing: Theme.Space.s) {
                    number("Goal weight (kg)", "goal_weight_kg", program.map { Fmt.number($0.body.goalWeightKg) }, .decimalPad)
                    number("Calories per day", "calorie_target", program.map { Fmt.number($0.nutrition.calories) })
                }
                HStack(spacing: Theme.Space.s) {
                    number("Protein per day (g)", "protein_target", program.map { Fmt.number($0.nutrition.proteinG) })
                    number("Fun budget per week", "fun_budget_kcal", program.map { Fmt.number($0.nutrition.funBudgetWeekKcal) })
                }
                HStack(spacing: Theme.Space.s) {
                    number("Max heart rate", "max_hr", program.map { String($0.heartRate.maxBpm) })
                    LabeledField(label: "5 km target (mm:ss)") {
                        TextField(program.map { Fmt.time($0.running.fiveKTargetSec) } ?? "", text: Binding(get: { values["five_k_target"] ?? "" }, set: { values["five_k_target"] = $0 })).keyboardType(.numbersAndPunctuation)
                    }
                }
                Button("Save settings") { Task { await save() } }.buttonStyle(.primary)
            }.card()

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                CardTitle("Connection", note: API.shared.pendingWrites > 0 ? "\(API.shared.pendingWrites) changes waiting to sync" : nil)
                ConnectionForm { Task { await load() } }
                Button("Remove the token from this phone") { confirmSignOut = true }.font(Theme.Typography.callout).foregroundStyle(Theme.Palette.danger)
            }.card()
        }
        .navigationTitle("Settings")
        .toast($toast)
        .task { await load() }
        .confirmationDialog("Remove the API token from this phone?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Remove token", role: .destructive) { API.shared.setToken(nil) }
        }
    }

    private func field(_ key: String) -> Binding<String> { Binding(get: { values[key] ?? "" }, set: { values[key] = $0 }) }

    private func number(_ label: String, _ key: String, _ fallback: String?, _ keyboard: UIKeyboardType = .numberPad) -> some View {
        LabeledField(label: label) { TextField(fallback ?? "", text: field(key)).keyboardType(keyboard) }
    }

    private func load() async {
        do {
            let s: Settings = try await API.shared.get("/api/settings")
            values = s.values
            values["five_k_target"] = s.number("five_k_target_sec").map { Fmt.time($0) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        var body: [String: Any?] = [:]
        for key in ["program_start_date", "phase_override", "lift_rotation", "goal_weight_kg", "calorie_target", "protein_target", "fun_budget_kcal", "max_hr"] {
            let v = (values[key] ?? "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            body[key] = v.isEmpty ? nil : v
        }
        body["five_k_target_sec"] = Fmt.parseTime(values["five_k_target"] ?? "")
        do {
            try await API.shared.send("PUT", "/api/settings", body)
            await AppModel.shared.load()
            toast = "Settings saved"
        } catch { toast = error.localizedDescription }
    }
}

/// Choice of colour theme. The colourful one is built from a single colour picked here.
private struct AppearanceCard: View {
    @Bindable private var store = ThemeStore.shared
    /// The six main colours of the colourful theme, as positions on the colour wheel.
    private static let mains: [(name: String, hue: Double)] = [("Blue", 0.60), ("Green", 0.40), ("Red", 0.0), ("Yellow", 0.14), ("Orange", 0.08), ("Purple", 0.73)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            CardTitle("Appearance")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 3), spacing: Theme.Space.s) {
                ForEach(ThemeKind.allCases) { kind in
                    Button { store.kind = kind } label: { swatch(kind) }.buttonStyle(.plain)
                        .accessibilityLabel("\(kind.title) theme").accessibilityAddTraits(store.kind == kind ? .isSelected : [])
                }
            }
            if store.kind == .colorful {
                LabeledField(label: "Main colour") {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(Self.mains, id: \.name) { main in
                            let on = abs(store.hue - main.hue) < 0.005
                            Button { store.hue = main.hue } label: {
                                Circle().fill(Color(hue: main.hue, saturation: 0.7, brightness: 1)).frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(Theme.Palette.text, lineWidth: on ? 2.5 : 0).padding(-4))
                            }
                            .buttonStyle(.plain).frame(maxWidth: .infinity)
                            .accessibilityLabel(main.name).accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
                Text("The whole app uses this colour and its close neighbours, in lighter and darker shades.")
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
            }
        }
        .card()
    }

    /// A small picture of a theme: its ground, a card, and three of its colours.
    private func swatch(_ kind: ThemeKind) -> some View {
        let colors = ThemeColors.make(kind, hue: store.hue)
        return VStack(spacing: Theme.Space.xs) {
            VStack(alignment: .leading, spacing: 5) {
                LinearGradient(colors: colors.fills[0], startPoint: .topLeading, endPoint: .bottomTrailing).frame(height: 16).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                HStack(spacing: 4) { ForEach([colors.accent, colors.energy, colors.calm], id: \.self) { Circle().fill($0).frame(width: 9, height: 9) } }
            }
            .padding(Theme.Space.s).frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(6)
            .background(colors.background, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(store.kind == kind ? Theme.Palette.accent : Theme.Palette.separator, lineWidth: store.kind == kind ? 2.5 : 1))
            Text(kind.title).font(Theme.Typography.label).foregroundStyle(store.kind == kind ? Theme.Palette.text : Theme.Palette.muted)
        }
    }
}
