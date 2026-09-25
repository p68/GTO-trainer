import Foundation

/// Allocation-free 5-to-7 card hand evaluator working on a 64-bit card mask
/// (16 bits per suit, see `Card.bit`). Higher score = better hand.
enum Evaluator {
    enum Category: Int, CaseIterable {
        case highCard, pair, twoPair, trips, straight, flush, fullHouse, quads, straightFlush

        var name: String {
            switch self {
            case .highCard: return "High card"
            case .pair: return "Pair"
            case .twoPair: return "Two pair"
            case .trips: return "Three of a kind"
            case .straight: return "Straight"
            case .flush: return "Flush"
            case .fullHouse: return "Full house"
            case .quads: return "Four of a kind"
            case .straightFlush: return "Straight flush"
            }
        }
    }

    static func category(of score: UInt32) -> Category { Category(rawValue: Int(score >> 20)) ?? .highCard }

    @inline(__always)
    static func evaluate(_ m: UInt64) -> UInt32 {
        let s0 = UInt32(m & 0x1FFF), s1 = UInt32((m >> 16) & 0x1FFF)
        let s2 = UInt32((m >> 32) & 0x1FFF), s3 = UInt32((m >> 48) & 0x1FFF)
        let all = s0 | s1 | s2 | s3

        var flushMask: UInt32 = 0
        if s0.nonzeroBitCount >= 5 { flushMask = s0 }
        else if s1.nonzeroBitCount >= 5 { flushMask = s1 }
        else if s2.nonzeroBitCount >= 5 { flushMask = s2 }
        else if s3.nonzeroBitCount >= 5 { flushMask = s3 }

        if flushMask != 0 {
            let sf = straightHigh(flushMask)
            if sf >= 0 { return 8 << 20 | UInt32(sf) << 16 }
        }

        let four = s0 & s1 & s2 & s3
        if four != 0 {
            let q = top(four)
            let k = top(all & ~(1 << q))
            return 7 << 20 | q << 16 | k << 12
        }

        let threePlus = (s0 & s1 & s2) | (s0 & s1 & s3) | (s0 & s2 & s3) | (s1 & s2 & s3)
        let twoPlus = (s0 & s1) | (s0 & s2) | (s0 & s3) | (s1 & s2) | (s1 & s3) | (s2 & s3)

        if threePlus != 0 {
            let t = top(threePlus)
            let rest = twoPlus & ~(1 << t)
            if rest != 0 { return 6 << 20 | t << 16 | top(rest) << 12 }
        }

        if flushMask != 0 { return 5 << 20 | kickers(flushMask, 5) }

        let st = straightHigh(all)
        if st >= 0 { return 4 << 20 | UInt32(st) << 16 }

        if threePlus != 0 {
            let t = top(threePlus)
            return 3 << 20 | t << 16 | kickers(all & ~(1 << t), 2) >> 4
        }

        if twoPlus.nonzeroBitCount >= 2 {
            let p1 = top(twoPlus)
            let p2 = top(twoPlus & ~(1 << p1))
            let k = top(all & ~(1 << p1) & ~(1 << p2))
            return 2 << 20 | p1 << 16 | p2 << 12 | k << 8
        }

        if twoPlus != 0 {
            let p = top(twoPlus)
            return 1 << 20 | p << 16 | kickers(all & ~(1 << p), 3) >> 4
        }

        return kickers(all, 5)
    }

    @inline(__always)
    private static func top(_ x: UInt32) -> UInt32 { UInt32(31 - x.leadingZeroBitCount) }

    /// Encodes the top `n` ranks of `mask` into nibbles starting at bit 16.
    @inline(__always)
    private static func kickers(_ mask: UInt32, _ n: Int) -> UInt32 {
        var m = mask, out: UInt32 = 0, shift: UInt32 = 16
        for _ in 0..<n {
            guard m != 0 else { break }
            let t = top(m)
            out |= t << shift
            m &= ~(1 << t)
            shift = shift &- 4
        }
        return out
    }

    /// Rank of the highest card of the best straight in `mask`, or -1.
    @inline(__always)
    private static func straightHigh(_ mask: UInt32) -> Int {
        let ext = (mask << 1) | ((mask >> 12) & 1) // ace also plays low
        var h = 13
        while h >= 4 {
            if (ext >> UInt32(h - 4)) & 0x1F == 0x1F { return h - 1 }
            h -= 1
        }
        return -1
    }

    /// Human readable description ("Two pair", "Flush" ...).
    static func describe(_ cards: [Card]) -> String {
        guard cards.count >= 5 else { return "" }
        return category(of: evaluate(cards.mask)).name
    }
}
