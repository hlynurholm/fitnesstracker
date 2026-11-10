import SwiftUI

@main
struct TrainingApp: App {
    init() { LiveWorkout.endLeftovers() }

    var body: some Scene {
        WindowGroup {
            RootView().tint(Theme.Palette.accent)
        }
    }
}

private struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let api = API.shared, app = AppModel.shared
        Group {
            if !api.hasToken {
                connect
            } else if app.program != nil {
                tabs
            } else if let error = app.error {
                NavigationStack {
                    Screen {
                        ErrorCard(message: error) { await app.load() }
                        VStack(alignment: .leading, spacing: Theme.Space.m) { CardTitle("Connection"); ConnectionForm() }.card()
                    }
                    .navigationTitle("Training")
                }
            } else {
                ProgressView()
            }
        }
        .task(id: api.hasToken) { if api.hasToken { await app.load() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await api.flush() } } }
    }

    private var connect: some View {
        NavigationStack {
            Screen {
                Text("Connect the app to your training tracker. Everything is read from and saved to the same server as the web app.")
                    .font(Theme.Typography.callout).foregroundStyle(Theme.Palette.muted)
                ConnectionForm().card()
            }
            .navigationTitle("Training")
        }
    }

    private var tabs: some View {
        TabView {
            Tab("Today", systemImage: "calendar.day.timeline.left") { NavigationStack { DayScreen(date: Day.today(), isRoot: true) } }
            Tab("Calendar", systemImage: "calendar") { NavigationStack { CalendarScreen() } }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis") { NavigationStack { ProgressScreen() } }
            Tab("Diet", systemImage: "fork.knife") { NavigationStack { DietScreen() } }
            Tab("Data", systemImage: "square.and.arrow.up") { NavigationStack { DataScreen() } }
        }
    }
}
