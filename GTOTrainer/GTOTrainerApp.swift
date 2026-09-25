import SwiftUI

@main
struct GTOTrainerApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                HomeView()
                    .tabItem { Label("Practice", systemImage: "suit.spade.fill") }
                StatsView()
                    .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
            }
            .environment(store)
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
        }
    }
}
