import Foundation

/// Monte Carlo (and exact on the river) equity calculations.
enum Equity {
    /// Weighted sampler over the combos of a range that are compatible with `dead` cards.
    struct Sampler {
        var indices: [Int] = []
        var cumulative: [Double] = []
        var total: Double { cumulative.last ?? 0 }

        init(range: Range, dead: UInt64, minWeight: Double = 1e-6) {
            var acc = 0.0
            for i in 0..<Combo.count {
                let w = range.weights[i]
                guard w > minWeight, Combo.masks[i] & dead == 0 else { continue }
                acc += w
                indices.append(i)
                cumulative.append(acc)
            }
        }

        var isEmpty: Bool { indices.isEmpty }

        @inline(__always)
        func sample<G: RandomNumberGenerator>(_ rng: inout G) -> Int {
            let r = rng.unit() * total
            var lo = 0, hi = cumulative.count - 1
            while lo < hi {
                let mid = (lo + hi) >> 1
                if cumulative[mid] > r { hi = mid } else { lo = mid + 1 }
            }
            return indices[lo]
        }
    }

    /// Fill the board up to five cards with random cards avoiding `used`.
    @inline(__always)
    static func runout<G: RandomNumberGenerator>(boardMask: UInt64, missing: Int, used: UInt64, rng: inout G) -> UInt64 {
        var m = boardMask, u = used, need = missing
        while need > 0 {
            let c = Card(raw: UInt8(rng.below(52)))
            if u & c.bit != 0 { continue }
            u |= c.bit; m |= c.bit; need -= 1
        }
        return m
    }

    /// Equity of `hero` against a weighted `range` (1 = always wins). Exact on the river.
    static func vsRange<G: RandomNumberGenerator>(hero: Combo, board: [Card], range: Range,
                                                  samples: Int, rng: inout G) -> Double {
        let boardMask = board.mask
        let heroMask = hero.mask
        let sampler = Sampler(range: range, dead: boardMask | heroMask)
        guard !sampler.isEmpty else { return 0.5 }

        if board.count == 5 {
            let heroScore = Evaluator.evaluate(boardMask | heroMask)
            var won = 0.0, total = 0.0
            for (k, i) in sampler.indices.enumerated() {
                let w = sampler.cumulative[k] - (k > 0 ? sampler.cumulative[k - 1] : 0)
                let v = Evaluator.evaluate(boardMask | Combo.masks[i])
                won += w * (heroScore > v ? 1 : (heroScore == v ? 0.5 : 0))
                total += w
            }
            return total > 0 ? won / total : 0.5
        }

        let missing = 5 - board.count
        var won = 0.0
        for _ in 0..<samples {
            let vi = sampler.sample(&rng)
            let vMask = Combo.masks[vi]
            let full = runout(boardMask: boardMask, missing: missing, used: boardMask | heroMask | vMask, rng: &rng)
            let h = Evaluator.evaluate(full | heroMask), v = Evaluator.evaluate(full | vMask)
            won += h > v ? 1 : (h == v ? 0.5 : 0)
        }
        return won / Double(samples)
    }

    /// Equity of every combo in `range` (weight > `minWeight`) against `opponent`.
    /// Returns a 1326-long array; combos not in the range get -1.
    static func comboEquities<G: RandomNumberGenerator>(range: Range, vs opponent: Range, board: [Card],
                                                        samples: Int, rng: inout G,
                                                        minWeight: Double = 0.002) -> [Double] {
        var out = Array(repeating: -1.0, count: Combo.count)
        let boardMask = board.mask
        let oppSampler = Sampler(range: opponent, dead: boardMask)
        guard !oppSampler.isEmpty else { return out }
        let missing = 5 - board.count

        // River: exact comparison against every opponent combo.
        var oppScores: [UInt32] = []
        if missing == 0 { oppScores = oppSampler.indices.map { Evaluator.evaluate(boardMask | Combo.masks[$0]) } }

        for i in 0..<Combo.count {
            guard range.weights[i] > minWeight, Combo.masks[i] & boardMask == 0 else { continue }
            let myMask = Combo.masks[i]
            if missing == 0 {
                let mine = Evaluator.evaluate(boardMask | myMask)
                var won = 0.0, total = 0.0
                for (k, j) in oppSampler.indices.enumerated() where Combo.masks[j] & myMask == 0 {
                    let w = oppSampler.cumulative[k] - (k > 0 ? oppSampler.cumulative[k - 1] : 0)
                    won += w * (mine > oppScores[k] ? 1 : (mine == oppScores[k] ? 0.5 : 0))
                    total += w
                }
                out[i] = total > 0 ? won / total : 0.5
                continue
            }
            var won = 0.0, n = 0
            var attempts = 0
            while n < samples && attempts < samples * 4 {
                attempts += 1
                let j = oppSampler.sample(&rng)
                let oMask = Combo.masks[j]
                if oMask & myMask != 0 { continue }
                let full = runout(boardMask: boardMask, missing: missing, used: boardMask | myMask | oMask, rng: &rng)
                let a = Evaluator.evaluate(full | myMask), b = Evaluator.evaluate(full | oMask)
                won += a > b ? 1 : (a == b ? 0.5 : 0)
                n += 1
            }
            out[i] = n > 0 ? won / Double(n) : 0.5
        }
        return out
    }

    /// Preflop all-in equity of each of the 169 hand classes against a random hand.
    /// Computed once (deterministic seed) and used for hand ranking.
    static let preflopVsRandom: [Double] = {
        var rng = SplitMix64(seed: 0xC0FFEE)
        let random = Range(uniform: 1)
        return HandClass.all.map { hc in
            vsRange(hero: hc.combos[0], board: [], range: random, samples: 2500, rng: &rng)
        }
    }()
}
