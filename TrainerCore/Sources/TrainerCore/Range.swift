import Foundation

/// A weighted range over all 1326 combos (weights in 0...1).
struct HandRange: Equatable {
    var weights: [Double]

    init(weights: [Double]) { self.weights = weights }
    init(uniform w: Double = 1) { weights = Array(repeating: w, count: Combo.count) }

    /// Build from per-hand-class frequencies (169 entries).
    init(classFrequencies f: [Double]) {
        weights = Combo.classIndex.map { f[$0] }
    }

    subscript(combo: Combo) -> Double {
        get { weights[combo.index] }
        set { weights[combo.index] = newValue }
    }

    /// Zero out combos that use any of the given cards.
    func removing(_ dead: UInt64) -> HandRange {
        var r = self
        for i in 0..<Combo.count where Combo.masks[i] & dead != 0 { r.weights[i] = 0 }
        return r
    }

    var totalWeight: Double { weights.reduce(0, +) }

    /// Fraction of each hand class present (0...1), for drawing the 13x13 grid.
    var classWeights: [Double] {
        var sum = Array(repeating: 0.0, count: 169)
        for i in 0..<Combo.count { sum[Combo.classIndex[i]] += weights[i] }
        return (0..<169).map { sum[$0] / Double(HandClass(index: $0).comboCount) }
    }

    /// Share of all 1326 combos, 0...1.
    var comboFraction: Double { totalWeight / Double(Combo.count) }
}

// MARK: - Range text parsing

/// Parses the compact range notation used by the preflop charts, e.g.
/// `"TT+,A5s-A2s,KJo+,76s:0.5"`. A `:w` suffix sets the frequency.
enum RangeParser {
    static func parse(_ text: String) -> [Double] {
        var f = Array(repeating: 0.0, count: 169)
        for raw in text.split(separator: ",") {
            let token = raw.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty else { continue }
            var body = token
            var weight = 1.0
            if let colon = token.firstIndex(of: ":") {
                body = String(token[..<colon])
                weight = Double(token[token.index(after: colon)...]) ?? 1
            }
            for hc in expand(body) { f[hc.index] = weight }
        }
        return f
    }

    static func expand(_ body: String) -> [HandClass] {
        if body.contains("-") {
            let parts = body.split(separator: "-").map(String.init)
            guard parts.count == 2, let a = HandClass(parts[0]), let b = HandClass(parts[1]) else { return [] }
            return between(a, b)
        }
        if body.hasSuffix("+") {
            guard let base = HandClass(String(body.dropLast())) else { return [] }
            if base.isPair {
                return (base.highRank...12).map { rank in HandClass(row: 12 - rank, col: 12 - rank) }
            }
            // Kicker goes up to one below the high card: ATs+ = ATs, AJs, AQs, AKs.
            return (base.lowRank..<base.highRank).map { make(high: base.highRank, low: $0, suited: base.isSuited) }
        }
        guard let hc = HandClass(body) else { return [] }
        return [hc]
    }

    private static func between(_ a: HandClass, _ b: HandClass) -> [HandClass] {
        if a.isPair && b.isPair {
            let lo = min(a.highRank, b.highRank), hi = max(a.highRank, b.highRank)
            return (lo...hi).map { HandClass(row: 12 - $0, col: 12 - $0) }
        }
        guard a.highRank == b.highRank, a.isSuited == b.isSuited else { return [a, b] }
        let lo = min(a.lowRank, b.lowRank), hi = max(a.lowRank, b.lowRank)
        return (lo...hi).map { make(high: a.highRank, low: $0, suited: a.isSuited) }
    }

    static func make(high: Int, low: Int, suited: Bool) -> HandClass {
        let r = 12 - high, c = 12 - low
        return suited ? HandClass(row: r, col: c) : HandClass(row: c, col: r)
    }
}
