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
    @State private var values: [String: String] = [:]
    @State private var error: String?
    @State private var toast: String?
    @State private var confirmSignOut = false

    var body: some View {
        let program = AppModel.shared.program
        Screen {
            if let error { ErrorCard(message: error) { await load() } }

            // Uploads, Garmin and Apple Health sync, exports and reports.
            NavigationLink { DataScreen() } label: {
                Row(title: "Data and sync", subtitle: "Garmin, Apple Health, uploads, exports and reports") {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.Palette.muted)
                }
            }
            .buttonStyle(.plain).card()

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
        for key in ["program_start_date", "phase_override", "goal_weight_kg", "calorie_target", "protein_target", "fun_budget_kcal", "max_hr"] {
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
