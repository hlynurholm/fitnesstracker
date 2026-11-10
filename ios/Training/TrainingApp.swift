import SwiftUI

@main
struct TrainingApp: App {
    init() {
        Theme.Typography.applyToNavigationBars()
        LiveWorkout.endLeftovers()
        #if DEBUG
        HealthSync.selfCheck()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView().tint(Theme.Palette.accent)
        }
    }
}

private struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0

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
        // Coming to the front: replay queued writes, then pick up anything new from Apple Health.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { Task { await api.flush(); await HealthSync.shared.sync() } }
        }
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
        TabView(selection: $tab) {
            Tab("Home", systemImage: "square.grid.2x2.fill", value: 0) { NavigationStack { HomeScreen { tab = 1 } } }
            Tab("Today", systemImage: "calendar.day.timeline.left", value: 1) { NavigationStack { DayScreen(date: Day.today()) } }
            Tab("Calendar", systemImage: "calendar", value: 2) { NavigationStack { CalendarScreen() } }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: 3) { NavigationStack { ProgressScreen() } }
            Tab("Diet", systemImage: "fork.knife", value: 4) { NavigationStack { DietScreen() } }
        }
    }
}
