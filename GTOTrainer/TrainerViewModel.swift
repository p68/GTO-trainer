import Foundation
import Observation
import SwiftUI

/// A button hero can press (one or more engine options, depending on difficulty).
struct ChoiceOption: Identifiable {
    let id: Int
    let label: String
    let color: Color
    let members: [Int]
}

struct SeatSnapshot: Identifiable {
    let id: Int
    let position: Position
    let stack: Double
    let bet: Double
    let folded: Bool
    let isHero: Bool
    let isToAct: Bool
    let cards: [Card]
    let showCards: Bool
    let lastAction: String?
}

struct Feedback {
    let grade: Grade
    let evLoss: Double
    let score: Double
    let analysis: DecisionAnalysis
    let colors: [Color]
    let chosen: Int
    let preflopChart: PreflopChart?
    let heroClass: HandClass
    let timedOut: Bool
    let rngRoll: Int?
}

@MainActor
@Observable
final class TrainerViewModel {
    enum Phase: Equatable { case idle, villainActing, heroTurn, paused, handOver, sessionOver, noMatch }

    let config: DrillConfig
    private let store: AppStore
    @ObservationIgnored private var rng = SystemRandomNumberGenerator()

    private(set) var engine: HandEngine?
    private(set) var heroSeat = 0
    private(set) var phase: Phase = .idle
    private(set) var seats: [SeatSnapshot] = []
    private(set) var board: [Card] = []
    private(set) var pot: Double = 0
    private(set) var street: Street = .preflop

    private(set) var analysis: DecisionAnalysis?
    private(set) var choices: [ChoiceOption] = []
    private(set) var groupedAnalysis: DecisionAnalysis?
    private(set) var currentChart: PreflopChart?
    private(set) var rngRoll: Int?
    private(set) var feedback: Feedback?
    private(set) var timeLeft: Double?

    private(set) var session: SessionRecord
    private(set) var lastHand: HandRecord?
    @ObservationIgnored private var decisions: [DecisionRecord] = []
    @ObservationIgnored private var handToken = 0
    @ObservationIgnored private var handNumber = 0
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var pendingTask: Task<Void, Never>?

    init(config: DrillConfig, store: AppStore) {
        self.config = config
        self.store = store
        session = SessionRecord(drillName: config.name)
    }

    var stats: SessionStats { session.stats }
    var heroCards: [Card] { engine?.players[heroSeat].hole.cards ?? [] }
    var heroPosition: Position { Position(rawValue: heroSeat) ?? .utg }
    var handsPlayed: Int { session.hands.count }
    var sessionComplete: Bool { config.sessionLength > 0 && session.hands.count >= config.sessionLength }

    var spotLabel: String { analysis?.spot ?? feedback?.analysis.spot ?? "" }

    var heroHandInfo: String? {
        guard let e = engine else { return nil }
        let hc = e.players[heroSeat].hole.handClass.description
        if e.board.count >= 3 { return "\(hc) · \(e.handDescription(heroSeat))" }
        return hc
    }

    /// Opponent relevant to hero's current decision.
    var villainSeat: Int? {
        guard let e = engine else { return nil }
        if e.street == .preflop, let node = e.preflopNode(heroSeat), let v = node.villain { return v.rawValue }
        return e.opponent(of: heroSeat)
    }

    func rangeWeights(seat: Int) -> [Double]? {
        guard let e = engine else { return nil }
        let w = e.ranges[seat].removing(e.board.mask).classWeights
        let m = w.max() ?? 0
        return m > 0 ? w.map { $0 / m } : nil
    }

    // MARK: - Flow

    func start() {
        guard phase == .idle else { return }
        nextHand()
    }

    func stop() {
        cancelTasks()
        store.save(session: session)
    }

    func nextHand() {
        cancelTasks()
        if sessionComplete { phase = .sessionOver; return }
        handToken += 1
        feedback = nil
        analysis = nil
        choices = []
        decisions = []
        guard let dealt = Dealer.deal(config, handNumber: handNumber, rng: &rng) else {
            engine = nil
            phase = .noMatch
            return
        }
        handNumber += 1
        engine = dealt.engine
        heroSeat = dealt.heroSeat
        proceed()
    }

    private var handShouldEnd: Bool {
        guard let e = engine else { return true }
        if e.isOver || e.players[heroSeat].folded { return true }
        if config.gameMode == .street && e.street != .preflop { return true }
        if config.gameMode == .spot && !decisions.isEmpty { return true }
        return false
    }

    private func proceed() {
        guard let e = engine else { return }
        refresh()
        if handShouldEnd { endHand(); return }
        guard let seat = e.toAct else { endHand(); return }
        if seat == heroSeat {
            if e.legalOptions(seat).count == 1 { e.apply(e.legalOptions(seat)[0]); proceed(); return }
            beginHeroTurn()
            return
        }
        phase = .villainActing
        let token = handToken
        pendingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.config.speed.delay ?? 0.5) * 1_000_000_000))
            guard let self, !Task.isCancelled, token == self.handToken else { return }
            self.engine?.playStrategy(seat, rng: &self.rng)
            self.proceed()
        }
    }

    private func beginHeroTurn() {
        guard let e = engine else { return }
        let a = e.analyze(heroSeat, quality: .hero, rng: &rng)
        analysis = a
        currentChart = e.preflopNode(heroSeat)?.chart
        let grouped = group(a)
        choices = grouped.choices
        groupedAnalysis = grouped.analysis
        rngRoll = config.rngMode ? Int.random(in: 1...100) : nil
        phase = .heroTurn
        refresh()
        startTimebank()
    }

    func choose(_ choice: ChoiceOption, timedOut: Bool = false) {
        guard phase == .heroTurn, let e = engine, let a = analysis, let ga = groupedAnalysis else { return }
        timerTask?.cancel()
        timeLeft = nil
        let result = Grader.grade(ga, chosen: choice.id, rngRoll: rngRoll)
        // Execute the most frequent member of the chosen group.
        let member = choice.members.max { a.frequencies[$0] < a.frequencies[$1] } ?? choice.members[0]
        let option = a.options[member]

        let record = DecisionRecord(street: a.street, spot: a.spot, board: e.board, pot: a.pot,
                                    options: ga.options.map(\.label), frequencies: ga.frequencies, evLoss: ga.evLoss,
                                    chosen: choice.id, grade: result.grade, score: result.score,
                                    preflopNode: a.preflopNode, equity: a.equity, timedOut: timedOut)
        decisions.append(record)
        feedback = Feedback(grade: result.grade, evLoss: result.evLoss, score: result.score, analysis: ga,
                            colors: choices.map(\.color), chosen: choice.id, preflopChart: currentChart,
                            heroClass: e.players[heroSeat].hole.handClass, timedOut: timedOut, rngRoll: rngRoll)
        e.take(option, seat: heroSeat, rng: &rng)
        analysis = nil
        choices = []
        let pause = config.pauseAfter == .action || (config.pauseAfter == .mistake && result.grade.isMistake)
        if pause {
            phase = .paused
            refresh()
        } else {
            proceed()
        }
    }

    func resume() {
        guard phase == .paused else { return }
        proceed()
    }

    private func endHand() {
        guard let e = engine else { return }
        timerTask?.cancel()
        timeLeft = nil
        let complete = e.isOver || e.players[heroSeat].folded
        let result: Double? = complete ? e.net(heroSeat) : nil
        if !e.isOver { e.abandon() }
        let opp = villainSeatForRecord(e)
        let reveal = e.wentToShowdown
        let hand = HandRecord(heroPosition: heroPosition, heroCards: heroCards, board: e.board,
                              actions: e.log.map { "\($0.street.name): \($0.position.name) \($0.label)" },
                              decisions: decisions, result: result,
                              opponentPosition: opp.map { Position(rawValue: $0)! },
                              opponentCards: reveal ? opp.map { e.players[$0].hole.cards } : nil)
        lastHand = hand
        session.hands.append(hand)
        store.save(session: session)
        phase = .handOver
        refresh(revealShowdown: reveal)
        scheduleAutoNewHand()
    }

    private func villainSeatForRecord(_ e: HandEngine) -> Int? {
        let others = e.activeSeats.filter { $0 != heroSeat }
        return others.count == 1 ? others[0] : nil
    }

    private func scheduleAutoNewHand() {
        guard !sessionComplete, config.autoNewHand != .off else { return }
        let delay = config.autoNewHand == .instant ? 0.6 : 3.0
        let token = handToken
        pendingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled, token == self.handToken, self.phase == .handOver else { return }
            self.nextHand()
        }
    }

    func finishSession() {
        cancelTasks()
        phase = .sessionOver
    }

    private func startTimebank() {
        guard config.timebank > 0 else { return }
        let total = Double(config.timebank)
        timeLeft = total
        let token = handToken
        timerTask = Task { [weak self] in
            let start = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, token == self.handToken, self.phase == .heroTurn else { return }
                let left = total - Date().timeIntervalSince(start)
                self.timeLeft = max(0, left)
                if left <= 0 {
                    // Out of time: check if possible, otherwise fold.
                    let pick = self.choices.first { c in
                        c.members.contains { self.analysis?.options[$0].action.kind == .check }
                    } ?? self.choices.first
                    if let pick { self.choose(pick, timedOut: true) }
                    return
                }
            }
        }
    }

    private func cancelTasks() {
        timerTask?.cancel()
        pendingTask?.cancel()
        timerTask = nil
        pendingTask = nil
    }

    // MARK: - Display

    private func refresh(revealShowdown: Bool = false) {
        guard let e = engine else { return }
        board = e.board
        pot = e.pot
        street = e.street
        var last: [Int: String] = [:]
        for entry in e.log where entry.street == e.street || e.isOver {
            last[entry.position.rawValue] = entry.label
        }
        if e.street != .preflop && !e.isOver {
            // Show only this street's actions after the flop.
            last = [:]
            for entry in e.log where entry.street == e.street { last[entry.position.rawValue] = entry.label }
        }
        seats = e.players.indices.map { i in
            let p = e.players[i]
            let reveal = i == heroSeat || (revealShowdown && !p.folded)
            return SeatSnapshot(id: i, position: p.position, stack: p.stack, bet: p.streetBet, folded: p.folded,
                                isHero: i == heroSeat, isToAct: e.toAct == i && !e.isOver, cards: p.hole.cards,
                                showCards: reveal, lastAction: last[i])
        }
    }

    // MARK: - Difficulty grouping

    private func group(_ a: DecisionAnalysis) -> (choices: [ChoiceOption], analysis: DecisionAnalysis) {
        var groups: [(label: String, members: [Int])] = []
        func add(_ label: String, _ i: Int) {
            if let k = groups.firstIndex(where: { $0.label == label }) { groups[k].members.append(i) }
            else { groups.append((label, [i])) }
        }
        for (i, o) in a.options.enumerated() {
            switch config.difficulty {
            case .standard:
                groups.append((o.label, [i]))
            case .simple:
                if o.isAggressive { add(a.toCall > 0 ? "Raise" : "Bet", i) } else { groups.append((o.label, [i])) }
            case .grouped:
                if o.isAggressive && a.street != .preflop {
                    let big = o.action.kind == .allIn || o.potFraction > 0.6
                    add(big ? (a.toCall > 0 ? "Big raise" : "Big bet") : (a.toCall > 0 ? "Small raise" : "Small bet"), i)
                } else { groups.append((o.label, [i])) }
            }
        }
        var choices: [ChoiceOption] = []
        var options: [ActionOption] = []
        var freqs: [Double] = [], losses: [Double] = []
        for (k, g) in groups.enumerated() {
            let rep = g.members.max { a.frequencies[$0] < a.frequencies[$1] } ?? g.members[0]
            var opt = a.options[rep]
            opt.label = g.label
            options.append(opt)
            freqs.append(g.members.reduce(0) { $0 + a.frequencies[$1] })
            losses.append(g.members.map { a.evLoss[$0] }.min() ?? 0)
            let color = g.members.count > 1 ? Theme.color(for: a.options[g.members.last!]) : Theme.color(for: a.options[rep])
            choices.append(ChoiceOption(id: k, label: g.label, color: color, members: g.members))
        }
        var ga = a
        ga.options = options
        ga.frequencies = freqs
        ga.evLoss = losses
        return (choices, ga)
    }
}
