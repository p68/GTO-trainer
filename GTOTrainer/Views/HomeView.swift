import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var setupConfig: DrillConfig?
    @State private var training: TrainingSession?

    struct TrainingSession: Identifiable {
        let id = UUID()
        let config: DrillConfig
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    todayCard
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    Button {
                        setupConfig = DrillConfig()
                    } label: {
                        Label("New drill", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Theme.accent)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section("My drills") {
                    ForEach(store.drills) { drill in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(drill.name).font(.body.weight(.semibold))
                                Text(drill.summary + " • " + drill.gameMode.name)
                                    .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                            }
                            Spacer()
                            Button { setupConfig = drill } label: { Image(systemName: "slider.horizontal.3") }
                                .buttonStyle(.borderless).tint(Theme.textSecondary)
                            Button { training = TrainingSession(config: drill) } label: {
                                Image(systemName: "play.circle.fill").font(.title2)
                            }
                            .buttonStyle(.borderless).tint(Theme.accent)
                        }
                        .listRowBackground(Theme.surface)
                    }
                    .onDelete { store.delete(drills: $0) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Practice")
            .sheet(item: $setupConfig) { cfg in
                DrillSetupView(config: cfg) { started in
                    setupConfig = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        training = TrainingSession(config: started)
                    }
                }
            }
            .fullScreenCover(item: $training) { t in
                TrainerView(vm: TrainerViewModel(config: t.config, store: store))
            }
        }
    }

    private var todayCard: some View {
        let today = store.handsToday
        let decisions = today.flatMap(\.decisions)
        let stats = SessionStats(decisions: decisions, hands: today)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Today").font(.headline)
            HStack(spacing: 8) {
                StatTile(title: "Hands", value: "\(today.count)")
                StatTile(title: "Score", value: decisions.isEmpty ? "–" : "\(Int(stats.score.rounded()))%", color: Theme.accent)
                StatTile(title: "EV loss", value: bb(stats.totalEVLoss, decimals: 2))
            }
            Text("Cash • 6-max • \(Stakes.name) • 100bb • cEV · no daily limit")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }
}
