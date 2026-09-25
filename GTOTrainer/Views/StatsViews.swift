import SwiftUI

/// Summary of one session: score, EV loss, grade breakdown and hands sorted by EV loss.
struct SessionSummaryView: View {
    let session: SessionRecord
    @Environment(\.dismiss) private var dismiss
    @State private var sortByLoss = true

    var body: some View {
        let s = session.stats
        List {
            Section {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        StatTile(title: "GTO score", value: s.decisionCount > 0 ? "\(Int(s.score.rounded()))%" : "–", color: Theme.accent)
                        StatTile(title: "Accuracy", value: s.decisionCount > 0 ? pct(s.accuracy) : "–")
                    }
                    HStack(spacing: 8) {
                        StatTile(title: "Hands", value: "\(s.handCount)")
                        StatTile(title: "Decisions", value: "\(s.decisionCount)")
                    }
                    HStack(spacing: 8) {
                        StatTile(title: "EV loss (bb)", value: bb(s.totalEVLoss, decimals: 2))
                        StatTile(title: "EV loss / hand", value: bb(s.evLossPerHand, decimals: 2))
                    }
                    StatTile(title: "Result (bb)", value: bb(s.net), color: s.net >= 0 ? Theme.call : Theme.betLarge)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section("Grades") {
                GradeDistribution(counts: s.gradeCounts)
                    .listRowBackground(Theme.surface)
            }
            Section {
                ForEach(sortedHands) { hand in
                    NavigationLink { HandReviewView(hand: hand) } label: { HandRow(hand: hand) }
                        .listRowBackground(Theme.surface)
                }
            } header: {
                HStack {
                    Text("Hands")
                    Spacer()
                    Button(sortByLoss ? "Biggest mistakes" : "Chronological") { sortByLoss.toggle() }
                        .font(.caption).textCase(nil)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(session.drillName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private var sortedHands: [HandRecord] {
        sortByLoss ? session.hands.sorted { $0.evLoss > $1.evLoss } : session.hands
    }
}

struct GradeDistribution: View {
    let counts: [Grade: Int]

    var body: some View {
        let total = max(1, counts.values.reduce(0, +))
        VStack(spacing: 8) {
            GeometryReader { g in
                HStack(spacing: 0) {
                    ForEach(Grade.allCases) { grade in
                        Rectangle().fill(Theme.color(for: grade))
                            .frame(width: g.size.width * Double(counts[grade] ?? 0) / Double(total))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            HStack {
                ForEach(Grade.allCases) { grade in
                    VStack(spacing: 2) {
                        Text("\(counts[grade] ?? 0)").font(.subheadline.weight(.semibold).monospacedDigit())
                        Text(grade.name).font(.caption2).foregroundStyle(Theme.color(for: grade))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct HandRow: View {
    let hand: HandRecord

    var body: some View {
        HStack(spacing: 10) {
            CardsView(cards: hand.heroCards, width: 22, spacing: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(hand.heroPosition.name)\(hand.opponentPosition.map { " vs \($0.name)" } ?? "")")
                    .font(.subheadline.weight(.semibold))
                Text(hand.decisions.first?.spot ?? "")
                    .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let g = hand.worstGrade { GradeBadge(grade: g) }
                Text("-\(bb(hand.evLoss, decimals: 2)) bb").font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Step-by-step review of a played hand.
struct HandReviewView: View {
    let hand: HandRecord

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hero \(hand.heroPosition.name)").font(.caption).foregroundStyle(Theme.textSecondary)
                        CardsView(cards: hand.heroCards, width: 38)
                    }
                    if let oc = hand.opponentCards, let op = hand.opponentPosition {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(op.name).font(.caption).foregroundStyle(Theme.textSecondary)
                            CardsView(cards: oc, width: 38)
                        }
                    }
                    Spacer()
                    if let r = hand.result {
                        Text("\(r >= 0 ? "+" : "")\(bb(r)) bb").font(.headline.monospacedDigit())
                            .foregroundStyle(r >= 0 ? Theme.call : Theme.betLarge)
                    }
                }
                if !hand.board.isEmpty { CardsView(cards: hand.board, width: 34) }
            }
            .listRowBackground(Theme.surface)

            ForEach(Array(hand.decisions.enumerated()), id: \.element.id) { i, d in
                Section("Decision \(i + 1) · \(d.street.name)") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            GradeBadge(grade: d.grade)
                            Text(d.options[d.chosen]).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("EV loss \(bb(d.chosenLoss, decimals: 2))").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Text(d.spot + (d.equity.map { " · equity \(pct($0))" } ?? "") + " · pot \(bb(d.pot))")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                        if !d.board.isEmpty { CardsView(cards: d.board, width: 24, spacing: 2) }
                        StrategyBars(labels: d.options, colors: d.options.map(color(for:)), frequencies: d.frequencies,
                                     evLoss: d.evLoss, chosen: d.chosen)
                    }
                }
                .listRowBackground(Theme.surface)
            }

            Section("Action") {
                ForEach(Array(hand.actions.enumerated()), id: \.offset) { _, a in
                    Text(a).font(.caption.monospaced())
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Hand review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func color(for label: String) -> Color {
        if label.hasPrefix("Fold") { return Theme.fold }
        if label.hasPrefix("Check") || label.hasPrefix("Call") { return Theme.call }
        if label.hasPrefix("All-in") { return Theme.allIn }
        if label.hasPrefix("Small") { return Theme.betSmall }
        if label.hasPrefix("Big") { return Theme.betLarge }
        return Theme.betMedium
    }
}

/// All-time stats and session history.
struct StatsView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                let hands = store.allHands
                let decisions = hands.flatMap(\.decisions)
                let s = SessionStats(decisions: decisions, hands: hands)
                Section {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            StatTile(title: "GTO score", value: decisions.isEmpty ? "–" : "\(Int(s.score.rounded()))%", color: Theme.accent)
                            StatTile(title: "Hands", value: "\(s.handCount)")
                        }
                        HStack(spacing: 8) {
                            StatTile(title: "EV loss / hand", value: bb(s.evLossPerHand, decimals: 3))
                            StatTile(title: "Result (bb)", value: bb(s.net), color: s.net >= 0 ? Theme.call : Theme.betLarge)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if !decisions.isEmpty {
                    Section("By preflop spot") {
                        ForEach(PreflopNodeType.allCases) { t in
                            breakdownRow(t.name, decisions.filter { $0.preflopNode == t })
                        }
                    }
                    .listRowBackground(Theme.surface)
                    Section("By street") {
                        ForEach(Street.allCases, id: \.self) { st in
                            breakdownRow(st.name, decisions.filter { $0.street == st })
                        }
                    }
                    .listRowBackground(Theme.surface)
                    Section("By position") {
                        ForEach(Position.allCases) { p in
                            let ds = hands.filter { $0.heroPosition == p }.flatMap(\.decisions)
                            breakdownRow(p.name, ds)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }

                Section("Sessions") {
                    ForEach(store.sessions) { session in
                        NavigationLink {
                            SessionSummaryView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.drillName).font(.subheadline.weight(.semibold))
                                let st = session.stats
                                Text("\(session.started.formatted(date: .abbreviated, time: .shortened)) · \(st.handCount) hands · score \(Int(st.score.rounded()))% · EV loss \(bb(st.totalEVLoss, decimals: 2))")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .onDelete { store.delete(sessions: $0) }
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) { confirmClear = true }.disabled(store.sessions.isEmpty)
                }
            }
            .confirmationDialog("Delete all history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { store.clearHistory() }
            }
        }
    }

    @ViewBuilder
    private func breakdownRow(_ title: String, _ ds: [DecisionRecord]) -> some View {
        if !ds.isEmpty {
            let s = SessionStats(decisions: ds, hands: [])
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(ds.count)").font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 44)
                Text("\(Int(s.score.rounded()))%").font(.caption.monospacedDigit()).frame(width: 44)
                Text("-\(bb(s.totalEVLoss / Double(ds.count), decimals: 3))").font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary).frame(width: 56, alignment: .trailing)
            }
        }
    }
}
