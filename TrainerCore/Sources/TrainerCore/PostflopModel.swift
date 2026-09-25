import Foundation

/// Approximate postflop strategy.
///
/// There is no solver on the phone, so each option's chip EV is estimated with a
/// one-step look-ahead against the opponent's (tracked) range:
/// - check:  equity x realisation x pot
/// - call:   equity x realisation x (pot + call) - call
/// - bet/raise: fold-equity x pot + (1 - fold-equity) x (equity vs calling range x final pot - bet)
/// where the opponent continues with combos whose equity beats their pot odds.
/// The strategy is a soft-max over those EVs, so near-equal options get mixed.
/// Ranges are narrowed after every action with the same model, applied to every combo.
enum PostflopModel {
    struct Quality {
        var heroSamples: Int
        var comboSamples: Int
        var calledSamples: Int

        static let hero = Quality(heroSamples: 2500, comboSamples: 50, calledSamples: 1200)
        static let villain = Quality(heroSamples: 600, comboSamples: 50, calledSamples: 300)
    }

    @inline(__always)
    static func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    /// Share of minimum defense frequency the opponent always keeps.
    static let mdfFactor = 0.9

    static func potNet(_ pot: Double) -> Double { pot - Stakes.rake(pot: pot, sawFlop: true) }

    /// Equity realisation: weak hands realise less of their raw equity before showdown,
    /// strong hands more (they get paid on later streets). Out of position realises less.
    static func realization(_ equity: Double, street: Street, inPosition: Bool) -> Double {
        guard street != .river else { return 1 }
        return min(1.15, max(0.35, 0.35 + 1.3 * equity)) * (inPosition ? 1.0 : 0.92)
    }

    /// What happens if `seat` takes an aggressive option: how often the opponent folds,
    /// and which part of their range continues.
    struct AggressionOutcome {
        var foldEquity: Double
        var continuing: Range
        var add: Double
        var finalPot: Double
        var allIn: Bool
    }

    /// Everything about the node that doesn't depend on the exact combo held.
    struct Node {
        let seat: Int
        let oppSeat: Int
        let options: [ActionOption]
        let pot: Double
        let toCall: Double
        let street: Street
        let inPosition: Bool
        let outcomes: [AggressionOutcome?]
        let callAllIn: Bool
        let tau: Double
        /// EV handicap for leading out into the previous street's aggressor
        /// (solvers rarely "donk" bet; the one-step model can't see why).
        let donkPenalty: Double
    }

    /// Fold equity and continuing range for each aggressive option, given the
    /// opponent's equity (per combo) against the range that takes that option.
    static func outcomes(_ engine: HandEngine, seat: Int, oppSeat: Int, options: [ActionOption],
                         oppRange: Range, oppEq: [[Double]?]) -> [AggressionOutcome?] {
        let me = engine.players[seat], opp = engine.players[oppSeat]
        let pot = engine.pot
        let oppIP = !engine.isInPosition(seat)
        let oppCapTotal = opp.streetBet + opp.stack
        return options.enumerated().map { k, option in
            guard option.isAggressive, let eqs = oppEq[k] else { return nil }
            let target = min(option.action.amount, oppCapTotal)          // anything above is refunded
            let add = target - me.streetBet
            let oppAdd = max(0, target - opp.streetBet)
            let finalPot = pot + add + oppAdd
            let req = oppAdd / max(finalPot, 1e-9)
            let allIn = target >= min(me.streetBet + me.stack, oppCapTotal) - 1e-9
            var cont = oppRange
            var total = 0.0, kept = 0.0
            var live: [(i: Int, e: Double)] = []
            for i in 0..<Combo.count where oppRange.weights[i] > 0 {
                let w = oppRange.weights[i]
                total += w
                let e = eqs[i] < 0 ? 0.5 : eqs[i]
                let r = allIn ? 1 : realization(e, street: engine.street, inPosition: oppIP)
                let cp = sigmoid((e * r - req) / 0.04)
                cont.weights[i] = w * cp
                kept += w * cp
                live.append((i, e))
            }
            // Minimum defense: a balanced defender doesn't let a bet profit automatically,
            // so keep at least ~MDF of the range, best hands first.
            let facingPot = pot + add
            let floor = min(0.95, mdfFactor * (facingPot - oppAdd) / max(facingPot, 1e-9)) * total
            if kept < floor {
                live.sort { $0.e > $1.e }
                for (i, _) in live where kept < floor {
                    let w = oppRange.weights[i]
                    kept += w - cont.weights[i]
                    cont.weights[i] = w
                }
            }
            return AggressionOutcome(foldEquity: total > 0 ? 1 - kept / total : 0, continuing: cont,
                                     add: add, finalPot: finalPot, allIn: allIn)
        }
    }

    /// The node solved for `seat`'s whole range.
    struct Solve {
        let node: Node
        /// Per combo equity vs the opponent range.
        let myEq: [Double]
        /// Per aggressive option, per combo equity vs the continuing range.
        let calledEq: [[Double]?]

        func frequencies(combo i: Int) -> [Double] {
            let e = myEq[i] < 0 ? 0.5 : myEq[i]
            let c = calledEq.map { arr -> Double in
                guard let arr, arr[i] >= 0 else { return e }
                return arr[i]
            }
            return PostflopModel.strategy(PostflopModel.evs(node, equity: e, calledEquity: c), tau: node.tau)
        }
    }

    /// Solve the node for `seat`'s range with one refinement step: the opponent's
    /// continuing ranges are recomputed against the range that actually takes each
    /// aggressive option (rather than the whole range), so bluffs and calls balance.
    static func solve<G: RandomNumberGenerator>(_ engine: HandEngine, seat: Int, options: [ActionOption],
                                                samples: Int, rng: inout G) -> Solve? {
        guard let oppSeat = engine.opponent(of: seat) else { return nil }
        let me = engine.players[seat]
        let boardMask = engine.board.mask
        let board = engine.board
        let oppRange = engine.ranges[oppSeat].removing(boardMask)
        let myRange = engine.ranges[seat].removing(boardMask)
        let hasAggression = options.contains { $0.isAggressive }

        let isDonk = engine.previousAggressor == oppSeat && engine.streetAggressor == nil
            && !engine.isInPosition(seat)
        func makeNode(_ outs: [AggressionOutcome?]) -> Node {
            let callAllIn = engine.players[oppSeat].isAllIn || engine.currentBet >= me.streetBet + me.stack - 1e-9
            return Node(seat: seat, oppSeat: oppSeat, options: options, pot: engine.pot, toCall: engine.toCall(seat),
                        street: engine.street, inPosition: engine.isInPosition(seat),
                        outcomes: outs, callAllIn: callAllIn, tau: max(0.05, 0.03 * engine.pot),
                        donkPenalty: isDonk ? 0.06 * engine.pot : 0)
        }
        func calledEquities(_ outs: [AggressionOutcome?]) -> [[Double]?] {
            outs.map { o in
                guard let o, o.continuing.totalWeight > 1e-6 else { return nil }
                return Equity.comboEquities(range: myRange, vs: o.continuing, board: board, samples: samples, rng: &rng)
            }
        }

        let myEq = Equity.comboEquities(range: myRange, vs: oppRange, board: board, samples: samples, rng: &rng)
        guard hasAggression else { return Solve(node: makeNode(options.map { _ in nil }), myEq: myEq, calledEq: options.map { _ in nil }) }

        // Pass 1: opponent reacts as if we bet our whole range.
        let base = Equity.comboEquities(range: oppRange, vs: myRange, board: board, samples: samples, rng: &rng)
        let outs1 = outcomes(engine, seat: seat, oppSeat: oppSeat, options: options, oppRange: oppRange,
                             oppEq: options.map { $0.isAggressive ? base : nil })
        let first = Solve(node: makeNode(outs1), myEq: myEq, calledEq: calledEquities(outs1))

        // Pass 2: opponent reacts to the range that actually takes each option.
        var perOption = options.map { _ in myRange }
        for i in 0..<Combo.count where myRange.weights[i] > 0 {
            let f = first.frequencies(combo: i)
            for k in options.indices { perOption[k].weights[i] *= f[k] }
        }
        let oppEq2: [[Double]?] = options.indices.map { k in
            guard options[k].isAggressive else { return nil }
            guard perOption[k].totalWeight > 0.5 else { return base }
            return Equity.comboEquities(range: oppRange, vs: perOption[k], board: board, samples: samples, rng: &rng)
        }
        let outs2 = outcomes(engine, seat: seat, oppSeat: oppSeat, options: options, oppRange: oppRange, oppEq: oppEq2)
        return Solve(node: makeNode(outs2), myEq: myEq, calledEq: calledEquities(outs2))
    }

    /// EV of each option for a hand with `equity` vs the opponent's range and
    /// `calledEquity[k]` vs the continuing range after aggressive option k.
    static func evs(_ n: Node, equity: Double, calledEquity: [Double]) -> [Double] {
        n.options.enumerated().map { k, option in
            switch option.action.kind {
            case .fold:
                return 0
            case .check:
                return equity * realization(equity, street: n.street, inPosition: n.inPosition) * potNet(n.pot)
            case .call:
                let r = n.callAllIn ? 1 : realization(equity, street: n.street, inPosition: n.inPosition)
                return equity * r * potNet(n.pot + n.toCall) - n.toCall
            case .bet, .raise, .allIn:
                guard let o = n.outcomes[k] else { return 0 }
                let r = o.allIn ? 1 : realization(calledEquity[k], street: n.street, inPosition: n.inPosition)
                let penalty = option.action.kind == .bet ? n.donkPenalty : 0
                return o.foldEquity * potNet(n.pot) + (1 - o.foldEquity) * (calledEquity[k] * r * potNet(o.finalPot) - o.add) - penalty
            }
        }
    }

    static func strategy(_ evs: [Double], tau: Double) -> [Double] {
        let best = evs.max() ?? 0
        var f = evs.map { exp(($0 - best) / tau) }
        var sum = f.reduce(0, +)
        f = f.map { $0 / sum }
        f = f.map { $0 < 0.02 ? 0 : $0 }
        sum = f.reduce(0, +)
        return f.map { $0 / sum }
    }

    // MARK: Single hand (hero grading / villain decisions)

    static func analyze<G: RandomNumberGenerator>(_ engine: HandEngine, seat: Int, options: [ActionOption],
                                                  quality: Quality, rng: inout G) -> DecisionAnalysis {
        guard let solved = engine.cachedSolve(seat: seat, rng: &rng) else {
            return DecisionAnalysis(options: options, frequencies: options.map { _ in 1 / Double(options.count) },
                                    evLoss: options.map { _ in 0 }, street: engine.street, pot: engine.pot,
                                    toCall: 0, spot: "", preflopNode: nil, equity: nil)
        }
        let n = solved.node
        let me = engine.players[seat]
        let dead = engine.board.mask | me.hole.mask
        let oppRange = engine.ranges[n.oppSeat].removing(dead)
        let equity = Equity.vsRange(hero: me.hole, board: engine.board, range: oppRange, samples: quality.heroSamples, rng: &rng)
        let called: [Double] = n.outcomes.map { o in
            guard let o else { return equity }
            let cont = o.continuing.removing(dead)
            return cont.totalWeight > 1e-6
                ? Equity.vsRange(hero: me.hole, board: engine.board, range: cont, samples: quality.calledSamples, rng: &rng)
                : equity
        }
        let ev = evs(n, equity: equity, calledEquity: called)
        let best = ev.max() ?? 0
        let opp = engine.players[n.oppSeat]
        return DecisionAnalysis(options: options, frequencies: strategy(ev, tau: n.tau), evLoss: ev.map { best - $0 },
                                street: engine.street, pot: n.pot, toCall: n.toCall,
                                spot: "\(me.position.name) vs \(opp.position.name) · \(engine.street.name)",
                                preflopNode: nil, equity: equity)
    }

    /// Narrow `seat`'s range after it takes `option` (call before the action is applied):
    /// every combo is weighted by how often the model takes that action with it.
    static func updateRange<G: RandomNumberGenerator>(_ engine: HandEngine, seat: Int, option: ActionOption,
                                                      rng: inout G) {
        let options = engine.legalOptions(seat)
        guard let chosen = options.firstIndex(of: option), let solved = engine.cachedSolve(seat: seat, rng: &rng) else { return }
        var r = engine.ranges[seat].removing(engine.board.mask)
        for i in 0..<Combo.count where r.weights[i] > 0 {
            r.weights[i] *= max(solved.frequencies(combo: i)[chosen], 0.005)
        }
        engine.ranges[seat] = r
    }
}

// MARK: - Unified analysis / sampling for any street

extension HandEngine {
    func analyze<G: RandomNumberGenerator>(_ seat: Int, quality: PostflopModel.Quality, rng: inout G) -> DecisionAnalysis {
        let options = legalOptions(seat)
        if street == .preflop {
            let hc = players[seat].hole.handClass
            guard let node = preflopNode(seat) else {
                return DecisionAnalysis(options: options, frequencies: options.map { _ in 1 }, evLoss: options.map { _ in 0 },
                                        street: .preflop, pot: pot, toCall: toCall(seat), spot: "", preflopNode: nil, equity: nil)
            }
            let idx: [Int] = options.map { $0.action.kind == .fold ? 2 : ($0.action.kind == .call ? 1 : 0) }
            var freqs = idx.map { PreflopModel.frequency(node.chart, hc, $0) }
            let s = freqs.reduce(0, +)
            freqs = s > 0 ? freqs.map { $0 / s } : freqs
            let losses = idx.map { PreflopModel.evLoss(node: node, hand: hc, action: $0) }
            let minLoss = losses.min() ?? 0
            return DecisionAnalysis(options: options, frequencies: freqs, evLoss: losses.map { $0 - minLoss },
                                    street: .preflop, pot: pot, toCall: toCall(seat), spot: node.label,
                                    preflopNode: node.type, equity: nil)
        }
        return PostflopModel.analyze(self, seat: seat, options: options, quality: quality, rng: &rng)
    }

    /// Pick an action for `seat` from the strategy (used for villains and auto-played hero actions).
    @discardableResult
    func playStrategy<G: RandomNumberGenerator>(_ seat: Int, rng: inout G) -> ActionOption? {
        let options = legalOptions(seat)
        guard !options.isEmpty else { return nil }
        if options.count == 1 { apply(options[0]); return options[0] }
        let a = analyze(seat, quality: .villain, rng: &rng)
        let choice = options[weightedPick(a.frequencies, using: &rng)]
        take(choice, seat: seat, rng: &rng)
        return choice
    }

    /// Apply an action, updating the actor's postflop range first.
    func take<G: RandomNumberGenerator>(_ option: ActionOption, seat: Int, rng: inout G) {
        if street != .preflop { PostflopModel.updateRange(self, seat: seat, option: option, rng: &rng) }
        apply(option)
    }
}
