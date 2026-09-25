import Foundation

enum Street: Int, Codable, CaseIterable, Comparable {
    case preflop, flop, turn, river
    var name: String { ["Preflop", "Flop", "Turn", "River"][rawValue] }
    static func < (a: Street, b: Street) -> Bool { a.rawValue < b.rawValue }
}

enum ActionKind: String, Codable {
    case fold, check, call, bet, raise, allIn

    var isAggressive: Bool { self == .bet || self == .raise || self == .allIn }
}

/// An action; `amount` is the player's total commitment on this street after acting.
struct GameAction: Codable, Hashable {
    var kind: ActionKind
    var amount: Double = 0
}

/// One button the player can press at a decision point.
struct ActionOption: Codable, Hashable {
    var action: GameAction
    /// e.g. "Raise 7.5", "Bet 33%", "Call 2.5".
    var label: String
    /// Bet size as a fraction of the pot, for aggressive actions.
    var potFraction: Double = 0

    var isAggressive: Bool { action.kind.isAggressive }
}

/// Preflop decision categories (mirrors GTO Wizard's "Preflop action" filter).
enum PreflopNodeType: String, Codable, CaseIterable, Identifiable {
    case rfi, vsOpen, vsRaiseCall, vs3bet, vs4bet, vs5bet
    var id: String { rawValue }
    var name: String {
        switch self {
        case .rfi: return "RFI"
        case .vsOpen: return "vs Open"
        case .vsRaiseCall: return "vs Raise-Call"
        case .vs3bet: return "vs 3bet"
        case .vs4bet: return "vs 4bet"
        case .vs5bet: return "vs 5bet"
        }
    }
}

/// The trainer's model of the correct strategy at a decision, for the hand held.
struct DecisionAnalysis: Codable {
    var options: [ActionOption]
    /// Strategy frequency of each option for this exact hand (sums to 1).
    var frequencies: [Double]
    /// EV lost versus the best option, in big blinds (>= 0).
    var evLoss: [Double]
    var street: Street
    /// Pot before the decision, including bets on this street.
    var pot: Double
    var toCall: Double
    /// Short description of the spot, e.g. "BTN vs CO open".
    var spot: String
    var preflopNode: PreflopNodeType?
    /// Hero's equity against the opponent's range (postflop only).
    var equity: Double?

    var bestIndex: Int { frequencies.indices.max { frequencies[$0] < frequencies[$1] } ?? 0 }

    /// The option picked by an RNG roll in 1...100 (aggressive options occupy the low numbers).
    func rngIndex(roll: Int) -> Int {
        let order = options.indices.sorted { a, b in
            let ka = options[a].isAggressive ? 1 : 0, kb = options[b].isAggressive ? 1 : 0
            if ka != kb { return ka > kb }
            if ka == 1 { return options[a].action.amount > options[b].action.amount }
            return options[a].action.kind == .call && options[b].action.kind != .call
        }
        var acc = 0.0
        for i in order {
            acc += frequencies[i] * 100
            if Double(roll) <= acc + 1e-9, frequencies[i] > 0 { return i }
        }
        return bestIndex
    }
}

// MARK: - Grading

enum Grade: String, Codable, CaseIterable, Identifiable {
    case best, correct, inaccuracy, wrong, blunder
    var id: String { rawValue }
    var name: String {
        switch self {
        case .best: return "Best"
        case .correct: return "Correct"
        case .inaccuracy: return "Inaccuracy"
        case .wrong: return "Wrong"
        case .blunder: return "Blunder"
        }
    }
    var isMistake: Bool { self == .wrong || self == .blunder }
}

enum Grader {
    /// Actions played at least this often by the strategy count as correct.
    static let correctFrequency = 0.035

    /// Grades a choice. Returns the grade, the EV loss (bb) and a -100...100 score.
    static func grade(_ a: DecisionAnalysis, chosen: Int, rngRoll: Int? = nil) -> (grade: Grade, evLoss: Double, score: Double) {
        let loss = a.evLoss[chosen]
        let f = a.frequencies[chosen]
        let best = rngRoll.map { a.rngIndex(roll: $0) } ?? a.bestIndex
        // Scale thresholds to the size of the decision.
        let stake = max(1.5, a.pot + a.toCall)
        let grade: Grade
        if chosen == best { grade = .best }
        else if f >= correctFrequency { grade = .correct }
        else if loss <= 0.05 * stake { grade = .inaccuracy }
        else if loss <= 0.25 * stake { grade = .wrong }
        else { grade = .blunder }

        let score: Double
        switch grade {
        case .best, .correct: score = 100
        default: score = 100 - 200 * min(1, loss / (0.5 * stake))
        }
        return (grade, loss, score)
    }
}
