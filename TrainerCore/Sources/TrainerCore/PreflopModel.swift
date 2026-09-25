import Foundation

/// A preflop decision point: which chart applies and who the main opponent is.
struct PreflopNode {
    let type: PreflopNodeType
    let hero: Position
    /// The player whose action hero is responding to (nil for RFI).
    let villain: Position?
    let chart: PreflopChart

    var label: String {
        switch type {
        case .rfi: return "\(hero.name) RFI"
        case .vsOpen: return "\(hero.name) vs \(villain?.name ?? "") open"
        case .vsRaiseCall: return "\(hero.name) vs \(villain?.name ?? "") open + call"
        case .vs3bet: return "\(hero.name) vs \(villain?.name ?? "") 3bet"
        case .vs4bet: return "\(hero.name) vs \(villain?.name ?? "") 4bet"
        case .vs5bet: return "\(hero.name) vs \(villain?.name ?? "") 5bet"
        }
    }

    /// Rough size of the decision, used to scale EV-loss estimates.
    var evScale: Double {
        switch type {
        case .rfi: return 1.0
        case .vsOpen: return 1.5
        case .vsRaiseCall: return 1.8
        case .vs3bet: return 3.0
        case .vs4bet: return 5.0
        case .vs5bet: return 8.0
        }
    }
}

/// Estimates preflop EV loss from the charts. Actions the strategy uses cost
/// (almost) nothing; unused actions cost more the further the hand sits from
/// the region of the grid where that action is used, and the stronger the hand
/// is when it's being played too passively.
enum PreflopModel {
    /// `action`: 0 = aggressive, 1 = call, 2 = fold.
    static func frequency(_ chart: PreflopChart, _ hc: HandClass, _ action: Int) -> Double {
        let f = chart.frequencies(hc)
        return [f.raise, f.call, f.fold][action]
    }

    static func evLoss(node: PreflopNode, hand hc: HandClass, action: Int) -> Double {
        let chart = node.chart
        let f = frequency(chart, hc, action)
        let freqs = (0..<3).map { frequency(chart, hc, $0) }
        let maxF = freqs.max() ?? 1
        let scale = node.evScale

        if f >= 0.02 {
            // Mixed actions are close to indifferent at equilibrium.
            return 0.03 * scale * (1 - f / max(maxF, 1e-9))
        }

        // Nearest grid cell where this action is used meaningfully.
        let eq = Equity.preflopVsRandom
        var bestDist = Int.max, bestGap = 0.0
        for other in HandClass.all where frequency(chart, other, action) >= 0.25 {
            let d = abs(other.row - hc.row) + abs(other.col - hc.col)
            let gap = abs(eq[other.index] - eq[hc.index])
            if d < bestDist || (d == bestDist && gap < bestGap) { bestDist = d; bestGap = gap }
        }
        if bestDist == Int.max { bestDist = 8; bestGap = 0.2 }

        var loss = 0.06 * Double(bestDist) + 3.0 * bestGap
        // Is this action more passive than what the hand prefers?
        let preferred = freqs.indices.max { freqs[$0] < freqs[$1] } ?? 2
        if action > preferred {
            loss *= max(1, 1 + (eq[hc.index] - 0.6) / 0.25)
        }
        return max(0.02, loss) * scale
    }
}
