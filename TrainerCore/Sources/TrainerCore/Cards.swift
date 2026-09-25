import Foundation

// MARK: - Card

/// A playing card encoded as 0...51: `rank * 4 + suit`, rank 0 = deuce ... 12 = ace.
struct Card: Hashable, Codable, Comparable, CustomStringConvertible {
    let raw: UInt8

    init(raw: UInt8) { self.raw = raw }
    init(rank: Int, suit: Int) { raw = UInt8(rank * 4 + suit) }

    var rank: Int { Int(raw) >> 2 }
    var suit: Int { Int(raw) & 3 }

    /// Bit used by the evaluator's 64-bit card mask (16 bits per suit).
    var bit: UInt64 { 1 << UInt64(suit * 16 + rank) }

    static let rankChars: [Character] = ["2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"]
    static let suitChars: [Character] = ["s", "h", "d", "c"]
    static let suitSymbols = ["♠", "♥", "♦", "♣"]

    var rankChar: Character { Card.rankChars[rank] }
    var suitSymbol: String { Card.suitSymbols[suit] }
    var description: String { "\(rankChar)\(Card.suitChars[suit])" }

    init?(_ text: String) {
        let chars = Array(text)
        guard chars.count == 2,
              let r = Card.rankChars.firstIndex(of: Character(chars[0].uppercased())),
              let s = Card.suitChars.firstIndex(of: Character(chars[1].lowercased())) else { return nil }
        self.init(rank: r, suit: s)
    }

    static func < (a: Card, b: Card) -> Bool { a.raw < b.raw }

    static let all: [Card] = (0..<52).map { Card(raw: UInt8($0)) }
}

extension Array where Element == Card {
    var mask: UInt64 { reduce(0) { $0 | $1.bit } }
    var text: String { map(\.description).joined() }
}

// MARK: - Combo (two specific hole cards)

/// One of the 1326 two-card starting hands.
struct Combo: Hashable, Codable, CustomStringConvertible {
    let high: Card
    let low: Card

    init(_ a: Card, _ b: Card) {
        if a.rank > b.rank || (a.rank == b.rank && a.suit < b.suit) { high = a; low = b } else { high = b; low = a }
    }

    var cards: [Card] { [high, low] }
    var mask: UInt64 { high.bit | low.bit }
    var index: Int { Combo.indexTable[Int(high.raw)][Int(low.raw)] }
    var handClass: HandClass { HandClass(combo: self) }
    var description: String { "\(high)\(low)" }

    func conflicts(_ m: UInt64) -> Bool { mask & m != 0 }

    static let all: [Combo] = {
        var out: [Combo] = []
        out.reserveCapacity(1326)
        for a in 0..<52 { for b in (a + 1)..<52 { out.append(Combo(Card(raw: UInt8(a)), Card(raw: UInt8(b)))) } }
        return out
    }()

    static let count = 1326

    private static let indexTable: [[Int]] = {
        var t = Array(repeating: Array(repeating: -1, count: 52), count: 52)
        var i = 0
        for a in 0..<52 { for b in (a + 1)..<52 { t[a][b] = i; t[b][a] = i; i += 1 } }
        return t
    }()

    static let masks: [UInt64] = all.map(\.mask)
    static let classIndex: [Int] = all.map { $0.handClass.index }
}

// MARK: - HandClass (169 grid cells)

/// A cell of the 13x13 starting-hand grid. Row/column 0 is the ace.
/// Cells above the diagonal are suited, below are offsuit.
struct HandClass: Hashable, Codable, Identifiable, CustomStringConvertible {
    let row: Int
    let col: Int

    init(row: Int, col: Int) { self.row = row; self.col = col }

    init(index: Int) { row = index / 13; col = index % 13 }

    init(combo: Combo) {
        let hi = 12 - combo.high.rank, lo = 12 - combo.low.rank
        if hi == lo { row = hi; col = hi }
        else if combo.high.suit == combo.low.suit { row = hi; col = lo }
        else { row = lo; col = hi }
    }

    /// Parse "AKs", "T9o", "77".
    init?(_ text: String) {
        let c = Array(text)
        guard c.count >= 2,
              let a = Card.rankChars.firstIndex(of: Character(c[0].uppercased())),
              let b = Card.rankChars.firstIndex(of: Character(c[1].uppercased())) else { return nil }
        let hi = 12 - max(a, b), lo = 12 - min(a, b)
        if a == b { guard c.count == 2 else { return nil }; row = hi; col = hi; return }
        guard c.count == 3 else { return nil }
        switch c[2] {
        case "s": row = hi; col = lo
        case "o": row = lo; col = hi
        default: return nil
        }
    }

    var index: Int { row * 13 + col }
    var id: Int { index }
    var isPair: Bool { row == col }
    var isSuited: Bool { row < col }
    var highRank: Int { 12 - min(row, col) }
    var lowRank: Int { 12 - max(row, col) }
    var comboCount: Int { isPair ? 6 : (isSuited ? 4 : 12) }

    var description: String {
        let h = Card.rankChars[highRank], l = Card.rankChars[lowRank]
        return isPair ? "\(h)\(l)" : "\(h)\(l)\(isSuited ? "s" : "o")"
    }

    var combos: [Combo] { HandClass.combosByClass[index] }

    static let all: [HandClass] = (0..<169).map { HandClass(index: $0) }

    static let combosByClass: [[Combo]] = {
        var out = Array(repeating: [Combo](), count: 169)
        for c in Combo.all { out[c.handClass.index].append(c) }
        return out
    }()
}

// MARK: - Random numbers

/// Small, fast, seedable generator (SplitMix64) so the engine is reproducible in tests.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

extension RandomNumberGenerator {
    mutating func unit() -> Double { Double(next() >> 11) * 0x1.0p-53 }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

/// Draw an index with probability proportional to `weights`.
func weightedPick<G: RandomNumberGenerator>(_ weights: [Double], using rng: inout G) -> Int {
    let total = weights.reduce(0, +)
    guard total > 0 else { return 0 }
    var r = rng.unit() * total
    for (i, w) in weights.enumerated() {
        r -= w
        if r < 0 { return i }
    }
    return weights.lastIndex(where: { $0 > 0 }) ?? 0
}
