import SwiftUI
import UniformTypeIdentifiers

/// Uploads (Garmin, MyFitnessPal), exports for Claude, reports and the list of uploaded files.
struct DataScreen: View {
    @State private var uploads: [Upload] = []
    @State private var reports: [Report] = []
    @State private var error: String?
    @State private var toast: String?
    @State private var importSource: String?
    @State private var busy = false
    @State private var exportFile: URL?
    @State private var deleteUpload: Upload?

    var body: some View {
        Screen {
            if let error { ErrorCard(message: error) { await load() } }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardTitle("Garmin", note: "FIT, TCX, GPX or CSV")
                Text("Runs are matched to the session on the same day. Attach a file to a specific run from its day instead if you prefer.").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
                Button("Upload Garmin files") { importSource = "garmin" }.buttonStyle(.tinted)
            }.card()

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardTitle("MyFitnessPal", note: "CSV export")
                Text("Upload the nutrition summary CSV. Daily calories and protein show up on the Diet tab.").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
                Button("Upload MyFitnessPal export") { importSource = "myfitnesspal" }.buttonStyle(.tinted)
            }.card()

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardTitle("Export for Claude")
                Button("Copy summary for Claude") { Task { await copySummary() } }.buttonStyle(.tinted)
                if let exportFile {
                    ShareLink("Share the JSON export", item: exportFile).buttonStyle(.tinted)
                } else {
                    Button("Prepare full JSON export") { Task { await prepareExport() } }.buttonStyle(.tinted)
                }
            }.card()

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardTitle("Reports", note: "\(reports.count)")
                if reports.isEmpty { Text("Reports Claude posts through the API appear here.").font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted) }
                Divided {
                    ForEach(reports) { r in
                        NavigationLink(value: r) {
                            Row(title: r.title, subtitle: [r.date.map { Day.label($0, year: true) }, r.author, r.section].compactMap { $0 }.joined(separator: " · ")) {
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.Palette.muted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }.card()

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardTitle("Uploaded files", note: "\(uploads.count)")
                Divided {
                    ForEach(uploads) { u in
                        Row(title: u.filename ?? "upload", subtitle: [u.source, u.format, u.workout_date.map { Day.label($0) }, u.parse_error].compactMap { $0 }.joined(separator: " · ")) {
                            Badge(u.parse_status.replacingOccurrences(of: "_", with: " "), tone: u.parse_status == "parsed" ? .ok : u.parse_status == "failed" ? .danger : .neutral)
                        }
                        .contextMenu { Button("Delete upload", role: .destructive) { deleteUpload = u } }
                    }
                }
                if !uploads.isEmpty { Text("Touch and hold a file to delete it.").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted) }
            }.card()
        }
        .navigationTitle("Data")
        .navigationDestination(for: Report.self) { ReportScreen(id: $0.id) { await load() } }
        .overlay { if busy { ProgressView().padding(Theme.Space.xl).background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card)) } }
        .toast($toast)
        .task { await load() }
        .refreshable { await load() }
        .fileImporter(isPresented: Binding(get: { importSource != nil }, set: { if !$0 { importSource = nil } }), allowedContentTypes: [.data], allowsMultipleSelection: true) { [source = importSource] result in
            if case .success(let urls) = result, let source { Task { await upload(urls, source: source) } }
        }
        .confirmationDialog("Delete this upload and its parsed activity?", isPresented: Binding(get: { deleteUpload != nil }, set: { if !$0 { deleteUpload = nil } }), titleVisibility: .visible, presenting: deleteUpload) { u in
            Button("Delete", role: .destructive) { Task { try? await API.shared.send("DELETE", "/api/uploads/\(u.id)"); await load() } }
        }
    }

    private func load() async {
        do {
            uploads = try await API.shared.get("/api/uploads")
            reports = try await API.shared.get("/api/reports")
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func upload(_ urls: [URL], source: String) async {
        busy = true
        defer { busy = false }
        do {
            let r = try await API.shared.upload(files: urls, fields: ["source": source, "tz_offset_min": String(-TimeZone.current.secondsFromGMT() / 60)])
            let failed = r.uploads.first { $0.status == "failed" }
            toast = failed.map { "Stored, but could not parse: \($0.error ?? "")" } ?? "Uploaded \(r.uploads.count) file\(r.uploads.count == 1 ? "" : "s")"
            await load()
        } catch { toast = error.localizedDescription }
    }

    private func copySummary() async {
        do {
            UIPasteboard.general.string = String(decoding: try await API.shared.data("/api/summary.md"), as: UTF8.self)
            toast = "Summary copied. Paste it to Claude."
        } catch { toast = error.localizedDescription }
    }

    private func prepareExport() async {
        busy = true
        defer { busy = false }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fitness-export-\(Day.today()).json")
            try await API.shared.data("/api/export.json").write(to: url)
            exportFile = url
        } catch { toast = error.localizedDescription }
    }
}

private struct ReportScreen: View {
    let id: Int
    let changed: () async -> Void
    @State private var report: Report?
    @State private var error: String?
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Screen {
            if let r = report {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text(r.title).font(Theme.Typography.title)
                    Text([r.date.map { Day.label($0, year: true) }, r.author].compactMap { $0 }.joined(separator: " · ")).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.muted)
                    MarkdownText(r.body_md ?? "")
                }.card()
            } else if let error {
                ErrorCard(message: error) { await load() }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Delete", role: .destructive) { confirmDelete = true } }
        .confirmationDialog("Delete this report?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { try? await API.shared.send("DELETE", "/api/reports/\(id)"); await changed(); dismiss() } }
        }
        .task { await load() }
    }

    private func load() async {
        do { report = try await API.shared.get("/api/reports/\(id)"); error = nil } catch { self.error = error.localizedDescription }
    }
}
