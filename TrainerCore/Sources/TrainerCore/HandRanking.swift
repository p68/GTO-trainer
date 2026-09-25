import Foundation

/// Orders the 169 starting hands from strongest to weakest, used by the
/// "From / To %" range slider in the drill setup.
enum HandRanking {
    /// Hand classes sorted best-first.
    static let ordered: [HandClass] = {
        let eq = Equity.preflopVsRandom
        func value(_ h: HandClass) -> Double {
            var v = eq[h.index]
            if h.isPair { v += 0.03 }
            if h.isSuited { v += 0.025 }
            if !h.isPair {
                let gap = h.highRank - h.lowRank
                v += 0.012 * Double(max(0, 4 - gap))
            }
            return v
        }
        return HandClass.all.sorted { value($0) > value($1) }
    }()

    /// Percentile span (0...100) that each class occupies in the ordering, by combos.
    static let percentile: [ClosedRange<Double>] = {
        var out = Array(repeating: 0.0...0.0, count: 169)
        var acc = 0.0
        for h in ordered {
            let start = acc
            acc += Double(h.comboCount) / 1326 * 100
            out[h.index] = start...acc
        }
        return out
    }()

    /// Classes whose midpoint lies in `from...to` percent.
    static func classes(from: Double, to: Double) -> Set<Int> {
        var s = Set<Int>()
        for h in HandClass.all {
            let p = percentile[h.index]
            let mid = (p.lowerBound + p.upperBound) / 2
            if mid >= from && mid <= to { s.insert(h.index) }
        }
        return s
    }
}
