import SwiftUI

/// "New drill" dialog with Game / Hands / Modes / Display tabs.
struct DrillSetupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var config: DrillConfig
    var onStart: (DrillConfig) -> Void

    @State private var tab: Tab = .game
    @State private var askName = false
    @State private var nameDraft = ""

    enum Tab: String, CaseIterable, Identifiable {
        case game = "Game", hands = "Hands", modes = "Modes", display = "Display"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .game: return "suit.spade"
            case .hands: return "square.grid.3x3"
            case .modes: return "gearshape"
            case .display: return "eye"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryChips
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in Label(t.rawValue, systemImage: t.icon).tag(t) }
                }
                .pickerStyle(.segmented)
                .padding(12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch tab {
                        case .game: gameTab
                        case .hands: handsTab
                        case .modes: modesTab
                        case .display: displayTab
                        }
                    }
                    .padding(16)
                }
                bottomBar
            }
            .background(Theme.background)
            .foregroundStyle(.white)
            .navigationTitle(config.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .alert("Save drill", isPresented: $askName) {
                TextField("Name", text: $nameDraft)
                Button("Save") {
                    config.name = nameDraft.isEmpty ? config.name : nameDraft
                    store.save(drill: config)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: Summary

    private var summaryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Cash • 6max • cEV • \(Stakes.name) • 100bb")
                chip("Start spot: Preflop")
                chip("\(config.preflopAction?.name ?? "Any action")")
                chip("Hands \(config.handCount)")
                chip(config.gameMode.name)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .background(Theme.surface)
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(Capsule().stroke(Theme.stroke))
    }

    // MARK: Game

    private var actionOptions: [(PreflopNodeType?, String)] {
        [(nil, "Any")] + PreflopNodeType.allCases.map { (Optional($0), $0.name) }
    }

    private var positionOptions: [(Position?, String)] {
        [(nil, "Any")] + Position.allCases.map { (Optional($0), $0.name) }
    }

    @ViewBuilder
    private var gameTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Solutions").font(.subheadline).foregroundStyle(Theme.textSecondary)
            Text("Cash • 6max • cEV • \(Stakes.name) • 100bb • 2.5x opens with cold calls")
                .font(.subheadline.weight(.medium))
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceHigh).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        ChipPicker(title: "Preflop action", options: actionOptions, selection: $config.preflopAction)
        ChipPicker(title: "Hero", options: positionOptions, selection: $config.hero)
        ChipPicker(title: "GTO – Opponent", help: "The player whose action hero responds to (opener, 3bettor…).",
                   options: positionOptions, selection: $config.opponent)
        ChipPicker(title: "Relative hero position", options: RelativePosition.allCases.map { ($0, $0.name) },
                   selection: $config.relative)
        ChipPicker(title: "Alternate positions", help: "Swap hero and opponent positions every other hand.",
                   options: [(false, "Off"), (true, "On")], selection: $config.alternatePositions)
    }

    // MARK: Hands

    @ViewBuilder
    private var handsTab: some View {
        HStack {
            Text("Hands").font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("\(config.handCount) of 169 · \(pct(comboFraction)) of combos").font(.caption).foregroundStyle(Theme.textSecondary)
        }
        RangeGridView(mode: .selection(config.hands)) { hc in
            if config.hands.contains(hc.index) { config.hands.remove(hc.index) } else { config.hands.insert(hc.index) }
        }
        RangeSlider(from: $config.handFrom, to: $config.handTo)
            .onChange(of: config.handFrom) { _, _ in applySlider() }
            .onChange(of: config.handTo) { _, _ in applySlider() }
        HStack(spacing: 16) {
            stepper("From", value: $config.handFrom)
            Spacer()
            stepper("To", value: $config.handTo)
        }
        HStack {
            Button("All hands") { config.handFrom = 0; config.handTo = 100; applySlider() }
            Spacer()
            Button("Pairs") { config.hands = Set(HandClass.all.filter(\.isPair).map(\.index)) }
            Spacer()
            Button("Suited") { config.hands = Set(HandClass.all.filter(\.isSuited).map(\.index)) }
            Spacer()
            Button("Offsuit") { config.hands = Set(HandClass.all.filter { !$0.isPair && !$0.isSuited }.map(\.index)) }
        }
        .font(.subheadline.weight(.semibold))
        .tint(Theme.accent)
        Text("Tap cells to toggle hands. The slider selects hands by strength (0 = strongest).")
            .font(.caption).foregroundStyle(Theme.textSecondary)
    }

    private var comboFraction: Double {
        Double(config.hands.reduce(0) { $0 + HandClass(index: $1).comboCount }) / 1326
    }

    private func applySlider() {
        config.hands = HandRanking.classes(from: config.handFrom, to: config.handTo)
    }

    private func stepper(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Button { value.wrappedValue = max(0, value.wrappedValue - 1) } label: { Image(systemName: "minus") }
            Text("\(Int(value.wrappedValue))").monospacedDigit().frame(width: 40)
                .padding(.vertical, 6).background(Theme.surfaceHigh).clipShape(RoundedRectangle(cornerRadius: 6))
            Button { value.wrappedValue = min(100, value.wrappedValue + 1) } label: { Image(systemName: "plus") }
        }
        .tint(.white)
    }

    // MARK: Modes

    @ViewBuilder
    private var modesTab: some View {
        ChipPicker(title: "Game mode", help: config.gameMode.help, options: GameMode.allCases.map { ($0, $0.name) },
                   selection: $config.gameMode)
        ChipPicker(title: "Difficulty", help: config.difficulty.help, options: Difficulty.allCases.map { ($0, $0.name) },
                   selection: $config.difficulty)
        ChipPicker(title: "Pause game after", options: PauseAfter.allCases.map { ($0, $0.name) }, selection: $config.pauseAfter)
        ChipPicker(title: "Game speed", options: GameSpeed.allCases.map { ($0, $0.name) }, selection: $config.speed)
        ChipPicker(title: "Auto new hand", options: AutoNewHand.allCases.map { ($0, $0.name) }, selection: $config.autoNewHand)
        ChipPicker(title: "RNG mode", help: "Rolls 1–100 each decision; the action covering that number (aggressive actions take the low numbers) is graded Best.",
                   options: [(false, "Off"), (true, "On")], selection: $config.rngMode)
        ChipPicker(title: "Timebank", options: [(0, "Off"), (7, "7s"), (15, "15s"), (25, "25s")], selection: $config.timebank)
        ChipPicker(title: "Session", options: [(0, "Off"), (20, "20"), (50, "50"), (100, "100"), (200, "200"), (420, "420")],
                   selection: $config.sessionLength)
    }

    // MARK: Display

    @ViewBuilder
    private var displayTab: some View {
        toggle("Show hints", "Show the strategy frequencies before you act.", $config.showHints)
        toggle("Show quick results", "Show the grade right after each decision.", $config.showQuickResults)
        toggle("Show hero strategy", "Show frequencies and EV loss of every option after acting.", $config.showHeroStrategy)
        toggle("Show hero's range", "Button to view your current range.", $config.showHeroRange)
        toggle("Show opponent's range", "Button to view the opponent's current range.", $config.showOpponentRange)
        toggle("Show hand info", "Hand name, made hand and equity vs the opponent's range.", $config.showHandInfo)
    }

    private func toggle(_ title: String, _ help: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(help).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .tint(Theme.accent)
    }

    // MARK: Bottom

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { nameDraft = config.name; askName = true } label: {
                Label("Save", systemImage: "square.and.arrow.down").font(.subheadline.weight(.semibold))
            }
            .tint(.white)
            Spacer()
            Button("Close") { dismiss() }.tint(.white).font(.subheadline.weight(.semibold))
            Button {
                onStart(config)
            } label: {
                Label("Start training", systemImage: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(config.hands.isEmpty ? Theme.stroke : Theme.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(config.hands.isEmpty)
        }
        .padding(12)
        .background(Theme.surface)
    }
}

/// Two-thumb slider for the hand range percentage.
struct RangeSlider: View {
    @Binding var from: Double
    @Binding var to: Double

    var body: some View {
        GeometryReader { g in
            let w = Double(g.size.width) - 24
            let x0 = 12 + w * from / 100, x1 = 12 + w * to / 100
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceHigh).frame(height: 8).padding(.horizontal, 12)
                Capsule().fill(Theme.accent).frame(width: max(0, x1 - x0), height: 8).offset(x: x0)
                thumb(color: Theme.betLarge).position(x: x0, y: g.size.height / 2)
                    .gesture(DragGesture().onChanged { v in from = min(to, max(0, value(v.location.x, width: w))) })
                thumb(color: Theme.accent).position(x: x1, y: g.size.height / 2)
                    .gesture(DragGesture().onChanged { v in to = max(from, min(100, value(v.location.x, width: w))) })
            }
        }
        .frame(height: 32)
    }

    private func value(_ x: CGFloat, width: Double) -> Double {
        ((Double(x) - 12) / width * 100).rounded()
    }

    private func thumb(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 22, height: 22)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white, lineWidth: 2))
    }
}
