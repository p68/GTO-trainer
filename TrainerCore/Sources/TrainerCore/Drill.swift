import Foundation

// MARK: - Drill settings (mirrors GTO Wizard's "New drill" dialog)

enum GameMode: String, Codable, CaseIterable, Identifiable {
    case fullHand, street, spot
    var id: String { rawValue }
    var name: String { ["fullHand": "Full hand", "street": "Preflop only", "spot": "Spot"][rawValue]! }
    var help: String {
        switch self {
        case .fullHand: return "Play the hand to the end, including postflop streets."
        case .street: return "Only preflop decisions; the hand stops at the flop."
        case .spot: return "One decision per hand."
        }
    }
}

enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case standard, grouped, simple
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var help: String {
        switch self {
        case .standard: return "Pick the exact bet size."
        case .grouped: return "Postflop sizes grouped into small / big."
        case .simple: return "Only choose fold, check/call or bet/raise."
        }
    }
}

enum RelativePosition: String, Codable, CaseIterable, Identifiable {
    case any, ip, oop
    var id: String { rawValue }
    var name: String { self == .any ? "Any" : rawValue.uppercased() }
}

enum PauseAfter: String, Codable, CaseIterable, Identifiable {
    case off, mistake, action
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

enum GameSpeed: String, Codable, CaseIterable, Identifiable {
    case normal, fast, turbo
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    /// Delay between opponent actions, seconds.
    var delay: Double { [0.7, 0.35, 0.08][GameSpeed.allCases.firstIndex(of: self)!] }
}

enum AutoNewHand: String, Codable, CaseIterable, Identifiable {
    case off, threeSeconds, instant
    var id: String { rawValue }
    var name: String { ["Off", "3s", "Instant"][AutoNewHand.allCases.firstIndex(of: self)!] }
}

struct DrillConfig: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = "New drill"

    // Game
    /// nil = any preflop action.
    var preflopAction: PreflopNodeType?
    var hero: Position?
    var opponent: Position?
    var relative: RelativePosition = .any
    var alternatePositions = false

    // Hands
    var hands: Set<Int> = Set(0..<169)
    var handFrom: Double = 0
    var handTo: Double = 100

    // Modes
    var gameMode: GameMode = .fullHand
    var difficulty: Difficulty = .standard
    var pauseAfter: PauseAfter = .off
    var speed: GameSpeed = .normal
    var autoNewHand: AutoNewHand = .off
    var rngMode = false
    /// Seconds, 0 = off.
    var timebank = 0
    /// Hands per session, 0 = unlimited.
    var sessionLength = 20

    // Display
    var showHints = false
    var showQuickResults = true
    var showHeroStrategy = true
    var showHeroRange = false
    var showOpponentRange = false
    var showHandInfo = true

    var summary: String {
        var parts = ["Cash", "6max", "cEV", Stakes.name]
        parts.append(preflopAction?.name ?? "Any action")
        if let h = hero { parts.append("Hero \(h.name)") }
        if let o = opponent { parts.append("vs \(o.name)") }
        return parts.joined(separator: " • ")
    }

    var handCount: Int { hands.count }
}

// MARK: - Dealing hands that match a drill

struct DealtHand {
    let engine: HandEngine
    let heroSeat: Int
}

enum Dealer {
    /// Deal a hand and auto-play it until hero faces a decision matching the drill.
    /// Returns nil if nothing matched after many attempts (filters too narrow).
    static func deal<G: RandomNumberGenerator>(_ config: DrillConfig, handNumber: Int, rng: inout G,
                                               attempts: Int = 6000) -> DealtHand? {
        let handList = Array(config.hands).sorted()
        guard !handList.isEmpty else { return nil }
        let handWeights = handList.map { Double(HandClass(index: $0).comboCount) }

        var heroFilter = config.hero
        var oppFilter = config.opponent
        if config.alternatePositions && handNumber % 2 == 1 { swap(&heroFilter, &oppFilter) }

        for _ in 0..<attempts {
            let heroPos: Position
            if let h = heroFilter { heroPos = h }
            else { heroPos = Position.allCases[rng.below(6)] }
            let hc = HandClass(index: handList[weightedPick(handWeights, using: &rng)])
            let combo = hc.combos[rng.below(hc.combos.count)]
            let engine = HandEngine.deal(heroSeat: heroPos.rawValue, heroCombo: combo, rng: &rng)
            let heroSeat = heroPos.rawValue

            while let seat = engine.toAct, !engine.isOver {
                let options = engine.legalOptions(seat)
                if seat == heroSeat && options.count > 1 {
                    if let node = engine.preflopNode(seat), matches(node, config: config, heroFilter: heroFilter,
                                                                   oppFilter: oppFilter) {
                        return DealtHand(engine: engine, heroSeat: heroSeat)
                    }
                    // Any-action drills start at hero's first real decision.
                    if config.preflopAction == nil { break }
                }
                engine.playStrategy(seat, rng: &rng)
                if engine.players[heroSeat].folded { break }
            }
        }
        return nil
    }

    static func matches(_ node: PreflopNode, config: DrillConfig, heroFilter: Position?, oppFilter: Position?) -> Bool {
        if let h = heroFilter, node.hero != h { return false }
        if let t = config.preflopAction, node.type != t { return false }
        guard let villain = node.villain else {
            // RFI has no opponent; opponent/relative filters only apply to other spots.
            return oppFilter == nil || config.preflopAction == .rfi
        }
        if let o = oppFilter, villain != o { return false }
        switch config.relative {
        case .any: return true
        case .ip: return node.hero.isInPosition(vs: villain)
        case .oop: return !node.hero.isInPosition(vs: villain)
        }
    }
}

// MARK: - Session history

struct DecisionRecord: Codable, Hashable, Identifiable {
    var id = UUID()
    var street: Street
    var spot: String
    var board: [Card]
    var pot: Double
    var options: [String]
    var frequencies: [Double]
    var evLoss: [Double]
    var chosen: Int
    var grade: Grade
    var score: Double
    var preflopNode: PreflopNodeType?
    var equity: Double?
    var timedOut = false

    var chosenLoss: Double { evLoss[chosen] }
}

struct HandRecord: Codable, Hashable, Identifiable {
    var id = UUID()
    var date = Date()
    var heroPosition: Position
    var heroCards: [Card]
    var board: [Card]
    var actions: [String]
    var decisions: [DecisionRecord]
    /// Net result in bb (nil if the hand was stopped before the end).
    var result: Double?
    var opponentPosition: Position?
    var opponentCards: [Card]?

    var evLoss: Double { decisions.reduce(0) { $0 + $1.chosenLoss } }
    var worstGrade: Grade? { decisions.map(\.grade).max { Grade.allCases.firstIndex(of: $0)! < Grade.allCases.firstIndex(of: $1)! } }
}

struct SessionRecord: Codable, Hashable, Identifiable {
    var id = UUID()
    var drillName: String
    var started = Date()
    var hands: [HandRecord] = []

    var decisions: [DecisionRecord] { hands.flatMap(\.decisions) }
    var stats: SessionStats { SessionStats(decisions: decisions, hands: hands) }
}

struct SessionStats {
    var handCount: Int
    var decisionCount: Int
    var score: Double
    var totalEVLoss: Double
    var evLossPerHand: Double
    var net: Double
    var gradeCounts: [Grade: Int]
    var accuracy: Double

    init(decisions: [DecisionRecord], hands: [HandRecord]) {
        handCount = hands.count
        decisionCount = decisions.count
        score = decisions.isEmpty ? 0 : decisions.reduce(0) { $0 + $1.score } / Double(decisions.count)
        totalEVLoss = decisions.reduce(0) { $0 + $1.chosenLoss }
        evLossPerHand = hands.isEmpty ? 0 : totalEVLoss / Double(hands.count)
        net = hands.compactMap(\.result).reduce(0, +)
        var counts: [Grade: Int] = [:]
        for d in decisions { counts[d.grade, default: 0] += 1 }
        gradeCounts = counts
        let good = decisions.filter { $0.grade == .best || $0.grade == .correct }.count
        accuracy = decisions.isEmpty ? 0 : Double(good) / Double(decisions.count)
    }
}
