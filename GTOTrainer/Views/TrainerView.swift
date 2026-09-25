import SwiftUI

struct TrainerView: View {
    @State var vm: TrainerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showStrategyGrid = false
    @State private var rangeSheet: RangeSheet?
    @State private var showSummary = false

    enum RangeSheet: Identifiable {
        case hero, opponent
        var id: Int { self == .hero ? 0 : 1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            TableView(vm: vm)
                .frame(maxHeight: .infinity)
            bottomPanel
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .onChange(of: vm.phase) { _, p in if p == .sessionOver { showSummary = true } }
        .sheet(isPresented: $showStrategyGrid) { strategySheet }
        .sheet(item: $rangeSheet) { which in rangeSheetView(which) }
        .sheet(isPresented: $showSummary, onDismiss: { if vm.phase == .sessionOver { dismiss() } }) {
            NavigationStack { SessionSummaryView(session: vm.session) }
                .presentationDetents([.large])
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Button { vm.stop(); dismiss() } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.config.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(vm.spotLabel.isEmpty ? vm.config.summary : vm.spotLabel)
                    .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            if vm.config.showHeroRange {
                Button { rangeSheet = .hero } label: { Image(systemName: "person.crop.square") }
            }
            if vm.config.showOpponentRange {
                Button { rangeSheet = .opponent } label: { Image(systemName: "person.2.crop.square.stack") }
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(vm.config.sessionLength > 0 ? "\(vm.handsPlayed)/\(vm.config.sessionLength)" : "\(vm.handsPlayed) hands")
                    .font(.caption.monospacedDigit())
                Text(vm.stats.decisionCount > 0 ? "Score \(Int(vm.stats.score.rounded()))%" : "Score –")
                    .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.accent)
            }
            .onTapGesture { showSummary = true }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.surface)
    }

    // MARK: Bottom panel

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 10) {
            if let f = vm.feedback, vm.config.showQuickResults || vm.phase == .paused || vm.phase == .handOver {
                FeedbackCard(feedback: f, showStrategy: vm.config.showHeroStrategy) { showStrategyGrid = true }
            }

            switch vm.phase {
            case .heroTurn:
                heroControls
            case .paused:
                Button("Continue") { vm.resume() }.buttonStyle(PrimaryButtonStyle())
            case .handOver:
                handOverControls
            case .noMatch:
                Text("No hands match these drill filters. Widen the hand range or change the spot.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                Button("Close") { dismiss() }.buttonStyle(PrimaryButtonStyle())
            case .sessionOver:
                Button("Session summary") { showSummary = true }.buttonStyle(PrimaryButtonStyle())
            default:
                Text(" ").font(.subheadline).frame(height: 48)
            }
        }
        .padding(12)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .animation(.easeOut(duration: 0.15), value: vm.phase)
    }

    private var heroControls: some View {
        VStack(spacing: 8) {
            HStack {
                if vm.config.showHandInfo, let info = vm.heroHandInfo {
                    Text(info).font(.caption.weight(.semibold))
                    if let eq = vm.analysis?.equity {
                        Text("Equity \(pct(eq))").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                if let roll = vm.rngRoll {
                    Label("\(roll)", systemImage: "dice").font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(hex: 0xE8C547).opacity(0.9)).foregroundStyle(.black)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(.white)

            if vm.config.showHints, let ga = vm.groupedAnalysis {
                StrategyBars(labels: ga.options.map(\.label), colors: vm.choices.map(\.color),
                             frequencies: ga.frequencies, evLoss: ga.evLoss)
            }

            if let left = vm.timeLeft {
                GeometryReader { g in
                    Capsule().fill(Theme.surfaceHigh)
                        .overlay(alignment: .leading) {
                            Capsule().fill(left < 3 ? Theme.betLarge : Theme.accent)
                                .frame(width: g.size.width * left / Double(max(1, vm.config.timebank)))
                        }
                }
                .frame(height: 4)
            }

            HStack(spacing: 8) {
                ForEach(vm.choices) { c in
                    Button { vm.choose(c) } label: {
                        Text(c.label)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(c.color)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var handOverControls: some View {
        VStack(spacing: 8) {
            if let h = vm.lastHand {
                HStack {
                    if let r = h.result {
                        Text(r >= 0 ? "Won \(bb(r)) bb" : "Lost \(bb(-r)) bb")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(r >= 0 ? Theme.call : Theme.betLarge)
                    } else {
                        Text("Spot complete").font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    Text("EV loss \(bb(h.evLoss, decimals: 2)) bb").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .foregroundStyle(.white)
            }
            if vm.sessionComplete {
                Button("Session summary") { vm.finishSession() }.buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Next hand") { vm.nextHand() }.buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    // MARK: Sheets

    private var strategySheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let f = vm.feedback, let chart = f.preflopChart {
                    Text(f.analysis.spot).font(.headline)
                    RangeGridView(mode: .strategy(chart), highlight: f.heroClass)
                        .padding(.horizontal, 8)
                    StrategyLegend()
                } else {
                    Text("Range grid is available for preflop decisions.").foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(.top)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showStrategyGrid = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func rangeSheetView(_ which: RangeSheet) -> some View {
        let seat = which == .hero ? vm.heroSeat : vm.villainSeat
        let weights = seat.flatMap { vm.rangeWeights(seat: $0) }
        let title = which == .hero ? "Hero range (\(vm.heroPosition.name))"
            : "Opponent range (\(seat.map { Position(rawValue: $0)!.name } ?? "–"))"
        return NavigationStack {
            VStack(spacing: 12) {
                Text(title).font(.headline)
                if let weights {
                    RangeGridView(mode: .weights(weights, which == .hero ? Theme.accent : Theme.betMedium),
                                  highlight: which == .hero ? vm.engine?.players[vm.heroSeat].hole.handClass : nil)
                        .padding(.horizontal, 8)
                    Text("Brighter = more of that hand remains in the range.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                } else {
                    Text("No range yet.").foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(.top)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { rangeSheet = nil } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Feedback

struct FeedbackCard: View {
    let feedback: Feedback
    let showStrategy: Bool
    let onShowGrid: () -> Void
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                GradeBadge(grade: feedback.grade)
                Text(feedback.analysis.options[feedback.chosen].label).font(.subheadline.weight(.semibold))
                if feedback.timedOut { Text("(time)").font(.caption).foregroundStyle(Theme.textSecondary) }
                Spacer()
                Text(feedback.evLoss < 0.005 ? "EV loss 0" : "EV loss \(bb(feedback.evLoss, decimals: 2)) bb")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                if showStrategy {
                    Button { expanded.toggle() } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.up").font(.caption)
                    }
                }
            }
            if showStrategy && expanded {
                StrategyBars(labels: feedback.analysis.options.map(\.label), colors: feedback.colors,
                             frequencies: feedback.analysis.frequencies, evLoss: feedback.analysis.evLoss,
                             chosen: feedback.chosen)
                HStack {
                    Text(feedback.analysis.spot).font(.caption2).foregroundStyle(Theme.textSecondary)
                    if let roll = feedback.rngRoll {
                        Text("· RNG \(roll)").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if feedback.preflopChart != nil {
                        Button("Range grid", action: onShowGrid).font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(Theme.surfaceHigh.opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.color(for: feedback.grade).opacity(0.7), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
