import Foundation

/// 6-max seats. Seat index doubles as preflop acting order.
enum Position: Int, Codable, CaseIterable, Identifiable, Comparable {
    case utg, hj, co, btn, sb, bb

    var id: Int { rawValue }
    var name: String { ["UTG", "HJ", "CO", "BTN", "SB", "BB"][rawValue] }
    var isBlind: Bool { self == .sb || self == .bb }

    /// Postflop acting order: SB first, BTN last.
    var postflopOrder: Int { [2, 3, 4, 5, 0, 1][rawValue] }

    /// True if `self` acts after `other` postflop.
    func isInPosition(vs other: Position) -> Bool { postflopOrder > other.postflopOrder }

    static func < (a: Position, b: Position) -> Bool { a.rawValue < b.rawValue }
}

/// Stakes and rake model. Everything in the engine is measured in big blinds.
enum Stakes {
    static let name = "NL25"
    static let bigBlindDollars = 0.25
    static let startingStack = 100.0
    /// 5% rake capped at 4bb ($1 at NL25), no flop no drop.
    static let rakePercent = 0.05
    static let rakeCapBB = 4.0

    static func rake(pot: Double, sawFlop: Bool) -> Double {
        sawFlop ? min(pot * rakePercent, rakeCapBB) : 0
    }
}
