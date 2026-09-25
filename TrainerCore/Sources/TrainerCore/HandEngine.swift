import Foundation

struct PlayerState: Codable {
    let position: Position
    var hole: Combo
    var stack: Double
    var streetBet: Double = 0
    var totalIn: Double = 0
    var folded = false

    var isAllIn: Bool { stack <= 1e-9 && !folded }
}

struct LogEntry: Codable, Hashable {
    var street: Street
    var position: Position
    var action: GameAction
    var label: String
}

/// Plays one 6-max hand: blinds, betting rounds, board, showdown and payouts.
/// Seats are indexed by `Position.rawValue`.
///
/// Simplifications (to keep every pot heads-up after the flop):
/// players facing an open plus a cold call may only squeeze or fold, and cold
/// players / cold callers facing a 3bet or bigger fold.
final class HandEngine {
    private(set) var players: [PlayerState]
    private(set) var board: [Card] = []
    private var deck: [Card]
    private(set) var street: Street = .preflop
    private(set) var toAct: Int?
    private(set) var log: [LogEntry] = []
    private var needsToAct: Set<Int> = []
    private(set) var currentBet: Double = 1
    private var lastRaiseSize: Double = 1
    private var aggressionsThisStreet = 0
    /// Seat that made the last bet/raise on the current street, and on the previous one.
    private(set) var streetAggressor: Int?
    private(set) var previousAggressor: Int?

    // Preflop action tracking.
    private(set) var opener: Position?
    private(set) var coldCallers: [Position] = []
    private(set) var threeBettor: Position?
    private(set) var fourBettor: Position?
    private(set) var fiveBettor: Position?
    private var raiseLevel = 0

    /// Each player's range as the other players see it.
    var ranges: [HandRange]

    /// Postflop node solved for the player to act (valid until the next action).
    private var solveCache: (key: Int, seat: Int, solve: PostflopModel.Solve)?

    private(set) var isOver = false
    private(set) var payouts: [Double] = Array(repeating: 0, count: 6)
    private(set) var rakeTaken: Double = 0
    private(set) var wentToShowdown = false

    init(holes: [Combo], deck: [Card]) {
        precondition(holes.count == 6)
        players = Position.allCases.map { PlayerState(position: $0, hole: holes[$0.rawValue], stack: Stakes.startingStack) }
        self.deck = deck
        ranges = Array(repeating: HandRange(uniform: 1), count: 6)
        post(.sb, 0.5)
        post(.bb, 1)
        needsToAct = Set(0..<6)
        toAct = 0
    }

    /// Deal a random hand. `heroCombo` forces the cards of one seat.
    static func deal<G: RandomNumberGenerator>(heroSeat: Int? = nil, heroCombo: Combo? = nil, rng: inout G) -> HandEngine {
        var cards = Card.all
        cards.shuffle(using: &rng)
        if let hc = heroCombo { cards.removeAll { $0 == hc.high || $0 == hc.low } }
        var holes: [Combo] = []
        for seat in 0..<6 {
            if seat == heroSeat, let hc = heroCombo { holes.append(hc); continue }
            holes.append(Combo(cards.removeLast(), cards.removeLast()))
        }
        return HandEngine(holes: holes, deck: cards)
    }

    private func post(_ p: Position, _ amount: Double) {
        players[p.rawValue].stack -= amount
        players[p.rawValue].streetBet = amount
        players[p.rawValue].totalIn = amount
    }

    // MARK: - Queries

    var pot: Double { players.reduce(0) { $0 + $1.totalIn } }
    var activeSeats: [Int] { players.indices.filter { !players[$0].folded } }
    var sawFlop: Bool { board.count >= 3 }

    func toCall(_ seat: Int) -> Double { max(0, min(currentBet - players[seat].streetBet, players[seat].stack)) }

    /// The single remaining opponent of `seat` (postflop pots are heads-up).
    func opponent(of seat: Int) -> Int? { activeSeats.first { $0 != seat } }

    func isInPosition(_ seat: Int) -> Bool {
        guard let o = opponent(of: seat) else { return true }
        return players[seat].position.isInPosition(vs: players[o].position)
    }

    // MARK: - Preflop nodes

    private func openSize(_ p: Position) -> Double { p == .sb ? 3 : 2.5 }

    private func threeBetSize(opener o: Position, hero h: Position) -> Double {
        var size: Double
        if h.isBlind { size = o == .sb ? 10 : 11 } else { size = 3 * openSize(o) }
        size += 2.5 * Double(coldCallers.count)
        return size
    }

    private func fourBetSize(opener o: Position, threeBettor t: Position, threeBet: Double) -> Double {
        let ip = o.isInPosition(vs: t)
        return ((ip ? 2.2 : 2.5) * threeBet * 2).rounded() / 2
    }

    func preflopNode(_ seat: Int) -> PreflopNode? {
        guard street == .preflop else { return nil }
        let p = players[seat].position
        switch raiseLevel {
        case 0:
            guard p != .bb, let chart = PreflopCharts.rfi[p] else { return nil }
            return PreflopNode(type: .rfi, hero: p, villain: nil, chart: chart)
        case 1:
            guard let o = opener, o != p, let chart = PreflopCharts.vsOpen(opener: o, hero: p) else { return nil }
            if coldCallers.contains(p) { return nil }
            if coldCallers.isEmpty { return PreflopNode(type: .vsOpen, hero: p, villain: o, chart: chart) }
            // Squeeze or fold: keep the 3bet frequencies only.
            return PreflopNode(type: .vsRaiseCall, hero: p, villain: o,
                               chart: PreflopChart(aggressiveFrequencies: chart.aggressive))
        case 2:
            guard let o = opener, let t = threeBettor, p == o,
                  let chart = PreflopCharts.vs3bet(opener: o, threeBettor: t) else { return nil }
            return PreflopNode(type: .vs3bet, hero: p, villain: t, chart: chart)
        case 3:
            guard let o = opener, let t = threeBettor, p == t else { return nil }
            return PreflopNode(type: .vs4bet, hero: p, villain: o, chart: PreflopCharts.vs4bet(threeBettor: t, opener: o))
        case 4:
            guard let o = opener, let t = threeBettor, p == o else { return nil }
            return PreflopNode(type: .vs5bet, hero: p, villain: t, chart: PreflopCharts.vs5bet(opener: o))
        default:
            return nil
        }
    }

    // MARK: - Legal options

    func legalOptions(_ seat: Int) -> [ActionOption] {
        guard !isOver, toAct == seat else { return [] }
        return street == .preflop ? preflopOptions(seat) : postflopOptions(seat)
    }

    private func allInTotal(_ seat: Int) -> Double { players[seat].streetBet + players[seat].stack }

    private func raiseOption(_ seat: Int, to amount: Double, verb: String) -> ActionOption {
        let cap = allInTotal(seat)
        if amount >= cap - 1e-9 {
            return ActionOption(action: GameAction(kind: .allIn, amount: cap), label: "All-in \(fmt(cap))", potFraction: 0)
        }
        return ActionOption(action: GameAction(kind: .raise, amount: amount), label: "\(verb) \(fmt(amount))")
    }

    private func preflopOptions(_ seat: Int) -> [ActionOption] {
        let fold = ActionOption(action: GameAction(kind: .fold), label: "Fold")
        guard let node = preflopNode(seat) else {
            // BB when everyone limps can't happen (no limping); anything else is a forced fold.
            return [fold]
        }
        let p = players[seat]
        let call = ActionOption(action: GameAction(kind: .call, amount: min(currentBet, allInTotal(seat))),
                                label: "Call \(fmt(min(currentBet, allInTotal(seat)) - p.streetBet))")
        switch node.type {
        case .rfi:
            return [fold, raiseOption(seat, to: openSize(p.position), verb: "Raise")]
        case .vsOpen:
            return [fold, call, raiseOption(seat, to: threeBetSize(opener: opener!, hero: p.position), verb: "3bet")]
        case .vsRaiseCall:
            return [fold, raiseOption(seat, to: threeBetSize(opener: opener!, hero: p.position), verb: "Squeeze")]
        case .vs3bet:
            return [fold, call, raiseOption(seat, to: fourBetSize(opener: opener!, threeBettor: threeBettor!, threeBet: currentBet), verb: "4bet")]
        case .vs4bet:
            return [fold, call, raiseOption(seat, to: allInTotal(seat), verb: "5bet")]
        case .vs5bet:
            return [fold, call]
        }
    }

    /// Bet sizes (fraction of pot) offered on each street.
    static func betSizes(_ street: Street) -> [Double] {
        switch street {
        case .preflop: return []
        case .flop: return [0.33, 0.75]
        case .turn: return [0.5, 1.0]
        case .river: return [0.5, 1.0, 1.5]
        }
    }

    private func postflopOptions(_ seat: Int) -> [ActionOption] {
        let p = players[seat]
        let cap = allInTotal(seat)
        let facing = currentBet - p.streetBet > 1e-9
        var out: [ActionOption] = []
        let oppCap = opponent(of: seat).map { allInTotal($0) } ?? cap
        let effectiveCap = min(cap, oppCap)

        if !facing {
            out.append(ActionOption(action: GameAction(kind: .check), label: "Check"))
            for f in HandEngine.betSizes(street) {
                let amount = (f * pot * 2).rounded() / 2
                guard amount >= 1 else { continue }
                if amount >= 0.85 * effectiveCap { break }
                out.append(ActionOption(action: GameAction(kind: .bet, amount: amount),
                                        label: "Bet \(Int((f * 100).rounded()))%", potFraction: f))
            }
            if effectiveCap <= 2.5 * pot || out.count == 1 {
                out.append(ActionOption(action: GameAction(kind: .allIn, amount: cap), label: "All-in \(fmt(cap))",
                                        potFraction: cap / max(pot, 1)))
            }
            return out
        }

        out.append(ActionOption(action: GameAction(kind: .fold), label: "Fold"))
        let callTotal = min(currentBet, cap)
        out.append(ActionOption(action: GameAction(kind: .call, amount: callTotal),
                                label: "Call \(fmt(callTotal - p.streetBet))"))
        let opponentAllIn = opponent(of: seat).map { players[$0].isAllIn } ?? true
        if cap > currentBet + 1e-9 && !opponentAllIn && aggressionsThisStreet < 3 {
            let raiseTo = (3 * currentBet * 2).rounded() / 2
            if aggressionsThisStreet < 2 && raiseTo < 0.6 * effectiveCap {
                let potAfterCall = pot + (currentBet - p.streetBet)
                out.append(ActionOption(action: GameAction(kind: .raise, amount: raiseTo), label: "Raise \(fmt(raiseTo))",
                                        potFraction: (raiseTo - currentBet) / max(potAfterCall, 1)))
            }
            out.append(ActionOption(action: GameAction(kind: .allIn, amount: cap), label: "All-in \(fmt(cap))",
                                    potFraction: (cap - currentBet) / max(pot, 1)))
        }
        return out
    }

    // MARK: - Applying actions

    func apply(_ option: ActionOption) {
        guard let seat = toAct, !isOver else { return }
        let action = option.action
        let pos = players[seat].position

        // Preflop range narrowing from the chart.
        if street == .preflop, let node = preflopNode(seat) {
            let idx: Int = action.kind == .fold ? 2 : (action.kind == .call ? 1 : 0)
            let f = (0..<169).map { PreflopModel.frequency(node.chart, HandClass(index: $0), idx) }
            for i in 0..<Combo.count { ranges[seat].weights[i] *= f[Combo.classIndex[i]] }
        }

        switch action.kind {
        case .fold:
            players[seat].folded = true
        case .check:
            break
        case .call:
            put(seat, min(currentBet, allInTotal(seat)) - players[seat].streetBet)
            if street == .preflop && raiseLevel == 1 && pos != opener { coldCallers.append(pos) }
        case .bet, .raise, .allIn:
            let target = min(action.amount, allInTotal(seat))
            put(seat, target - players[seat].streetBet)
            if target > currentBet + 1e-9 {
                let raiseSize = target - currentBet
                if raiseSize >= lastRaiseSize { lastRaiseSize = raiseSize }
                currentBet = target
                aggressionsThisStreet += 1
                streetAggressor = seat
                needsToAct = Set(activeSeats.filter { $0 != seat && !players[$0].isAllIn })
                if street == .preflop {
                    raiseLevel += 1
                    switch raiseLevel {
                    case 1: opener = pos
                    case 2: threeBettor = pos
                    case 3: fourBettor = pos
                    default: fiveBettor = pos
                    }
                }
            }
        }
        needsToAct.remove(seat)
        log.append(LogEntry(street: street, position: pos, action: action, label: option.label))
        advance(after: seat)
    }

    private func put(_ seat: Int, _ amount: Double) {
        let a = max(0, min(amount, players[seat].stack))
        players[seat].stack -= a
        players[seat].streetBet += a
        players[seat].totalIn += a
    }

    private func advance(after seat: Int) {
        let active = activeSeats
        if active.count == 1 { finish(winners: active); return }

        if needsToAct.isEmpty {
            let canAct = active.filter { !players[$0].isAllIn }
            if street == .river || canAct.count <= 1 {
                while board.count < 5 { board.append(deck.removeLast()) }
                showdown()
                return
            }
            nextStreet()
            return
        }
        let order = street == .preflop ? Array(0..<6) : postflopOrder
        let startIdx = (order.firstIndex(of: seat) ?? 0)
        for k in 1...6 {
            let s = order[(startIdx + k) % 6]
            if needsToAct.contains(s) { toAct = s; return }
        }
        toAct = nil
    }

    private var postflopOrder: [Int] { Position.allCases.sorted { $0.postflopOrder < $1.postflopOrder }.map(\.rawValue) }

    private func nextStreet() {
        street = Street(rawValue: street.rawValue + 1)!
        let n = street == .flop ? 3 : 1
        for _ in 0..<n { board.append(deck.removeLast()) }
        for i in players.indices { players[i].streetBet = 0 }
        currentBet = 0
        lastRaiseSize = 1
        aggressionsThisStreet = 0
        previousAggressor = streetAggressor
        streetAggressor = nil
        let active = activeSeats.filter { !players[$0].isAllIn }
        needsToAct = Set(active)
        toAct = postflopOrder.first { needsToAct.contains($0) }
    }

    /// Return any bet nobody matched.
    private func refundUncalled() {
        let live = activeSeats
        guard let top = live.max(by: { players[$0].totalIn < players[$1].totalIn }) else { return }
        let others = players.indices.filter { $0 != top }.map { players[$0].totalIn }
        let second = others.max() ?? 0
        let excess = players[top].totalIn - second
        if excess > 1e-9 {
            players[top].totalIn -= excess
            players[top].stack += excess
            players[top].streetBet -= excess
        }
    }

    private func finish(winners: [Int]) {
        refundUncalled()
        let rake = Stakes.rake(pot: pot, sawFlop: sawFlop)
        rakeTaken = rake
        let share = (pot - rake) / Double(winners.count)
        for w in winners { payouts[w] += share }
        toAct = nil
        isOver = true
    }

    private func showdown() {
        wentToShowdown = true
        let boardMask = board.mask
        let live = activeSeats
        let scores = live.map { Evaluator.evaluate(boardMask | players[$0].hole.mask) }
        let best = scores.max()!
        let winners = zip(live, scores).filter { $0.1 == best }.map(\.0)
        finish(winners: winners)
    }

    /// Net chips won by `seat` (only meaningful once the hand is over or the seat folded).
    func net(_ seat: Int) -> Double { payouts[seat] - players[seat].totalIn }

    /// Force the hand to end now (used when the trainer stops a hand early).
    func abandon() { toAct = nil; isOver = true }

    func cachedSolve<G: RandomNumberGenerator>(seat: Int, rng: inout G) -> PostflopModel.Solve? {
        if let c = solveCache, c.key == log.count, c.seat == seat { return c.solve }
        guard let s = PostflopModel.solve(self, seat: seat, options: legalOptions(seat),
                                          samples: PostflopModel.Quality.villain.comboSamples, rng: &rng) else { return nil }
        solveCache = (log.count, seat, s)
        return s
    }

    func handDescription(_ seat: Int) -> String {
        Evaluator.describe(players[seat].hole.cards + board)
    }
}

extension PreflopChart {
    /// A raise-or-fold chart using the given raise frequencies.
    init(aggressiveFrequencies: [Double]) {
        self.init(aggressive: aggressiveFrequencies, passive: Array(repeating: 0, count: 169))
    }
}

func fmt(_ x: Double) -> String {
    if abs(x - x.rounded()) < 0.001 { return String(Int(x.rounded())) }
    return String(format: "%.1f", x)
}
