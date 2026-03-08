import SwiftUI

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            LiveSessionView()
                .tag(AppTab.session)
                .tabItem {
                    Label("Session", systemImage: "figure.run")
                }

            WorkoutsView()
                .tag(AppTab.workouts)
                .tabItem {
                    Label("Workouts", systemImage: "list.bullet.clipboard")
                }

            HistoryView()
                .tag(AppTab.history)
                .tabItem {
                    Label("History", systemImage: "chart.bar")
                }

            RecordingsView()
                .tag(AppTab.recordings)
                .tabItem {
                    Label("Recordings", systemImage: "waveform")
                }

            SettingsView()
                .tag(AppTab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(.teal)
        .deviceBanner()
        .sheet(item: $router.presentedSheet) { sheet in
            switch sheet {
            case .deviceStatus:
                DeviceStatusSheetView()
            }
        }
    }
}
