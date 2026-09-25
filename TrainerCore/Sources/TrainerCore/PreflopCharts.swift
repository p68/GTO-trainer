import Foundation

/// Frequencies for one preflop decision node, per hand class.
/// `aggressive` = open / 3bet / 4bet / 5bet-jam, `passive` = call. Fold is the remainder.
struct PreflopChart {
    let aggressive: [Double]
    let passive: [Double]

    init(aggressive: String, passive: String = "") {
        let a = RangeParser.parse(aggressive)
        var p = RangeParser.parse(passive)
        // Aggressive frequencies win; calls fill whatever is left.
        for i in 0..<169 { p[i] = max(0, min(p[i], 1 - a[i])) }
        self.aggressive = a
        self.passive = p
    }

    init(aggressive: [Double], passive: [Double]) {
        self.aggressive = aggressive
        self.passive = passive
    }

    func frequencies(_ hc: HandClass) -> (raise: Double, call: Double, fold: Double) {
        let r = aggressive[hc.index], c = passive[hc.index]
        return (r, c, max(0, 1 - r - c))
    }
}

/// Approximate 6-max 100bb cash ranges (2.5x opens, SB 3x, cold calls allowed),
/// hand-authored to resemble published NL25/NL50 GTO solutions.
/// Replace these strings with your own solver output to sharpen the trainer.
enum PreflopCharts {
    // MARK: Raise first in

    static let rfi: [Position: PreflopChart] = [
        .utg: PreflopChart(aggressive: "55+,44:0.5,33:0.3,22:0.3,A2s+,K9s+,K8s:0.5,K7s:0.2,Q9s+,J9s+,T9s,T8s:0.5,98s:0.7,87s:0.5,76s:0.5,65s:0.5,ATo+,KJo+,KTo:0.3,QJo:0.5"),
        .hj: PreflopChart(aggressive: "22+,A2s+,K6s+,K5s:0.5,Q9s+,Q8s:0.5,J9s+,J8s:0.5,T8s+,98s,97s:0.5,87s,76s,65s:0.7,54s:0.3,A9o+,A8o:0.3,KTo+,QJo,QTo:0.5,JTo:0.3"),
        .co: PreflopChart(aggressive: "22+,A2s+,K2s+,Q6s+,Q5s:0.5,J7s+,T7s+,97s+,86s+,75s+,65s,64s:0.3,54s,43s:0.2,A8o+,A7o:0.5,A5o:0.5,KTo+,K9o:0.5,QTo+,JTo,T9o:0.3"),
        .btn: PreflopChart(aggressive: "22+,A2s+,K2s+,Q2s+,J4s+,T6s+,96s+,95s:0.3,85s+,74s+,64s+,53s+,43s,A2o+,K8o+,K7o:0.5,K6o:0.3,Q9o+,Q8o:0.3,J8o+,T8o+,98o,87o:0.3"),
        .sb: PreflopChart(aggressive: "22+,A2s+,K2s+,Q2s+,J3s+,T5s+,95s+,84s+,74s+,63s+,53s+,43s,A2o+,K7o+,K6o:0.5,K5o:0.5,Q8o+,J8o+,T8o+,98o,97o:0.3,87o,76o:0.5,65o:0.3"),
    ]

    // MARK: Facing an open (3bet / call)

    private static let vsOpenTable: [String: PreflopChart] = [
        "UTG-HJ": PreflopChart(aggressive: "QQ+,AKs,AKo:0.6,AQs:0.4,A5s:0.5,A4s:0.4,KQs:0.2,76s:0.15,65s:0.15",
                               passive: "JJ-66,AQs,AJs,ATs:0.6,KQs,KJs:0.5,QJs:0.5,JTs:0.5,T9s:0.3,AKo,AQo:0.4"),
        "UTG-CO": PreflopChart(aggressive: "QQ+,AKs,AKo:0.7,AQs:0.4,A5s:0.6,A4s:0.4,KQs:0.3,KJs:0.1,76s:0.2,65s:0.2",
                               passive: "JJ-55,AQs,AJs,ATs:0.7,A9s:0.3,KQs,KJs:0.7,KTs:0.3,QJs:0.6,JTs:0.6,T9s:0.4,98s:0.3,AKo,AQo:0.5"),
        "UTG-BTN": PreflopChart(aggressive: "QQ+,JJ:0.3,AKs,AKo:0.8,AQs:0.4,AJs:0.2,A5s:0.6,A4s:0.5,KQs:0.3,KJs:0.2,76s:0.25,65s:0.25,AJo:0.1",
                                passive: "JJ-22,AQs,AJs,ATs,A9s:0.5,A8s:0.3,KQs,KJs,KTs:0.7,QJs,QTs:0.5,JTs,T9s,98s:0.6,87s:0.5,76s:0.6,65s:0.4,AKo,AQo,AJo:0.4,KQo:0.5"),
        "UTG-SB": PreflopChart(aggressive: "JJ+,TT:0.4,AKs,AQs,AJs:0.5,ATs:0.3,A5s:0.6,A4s:0.5,KQs:0.7,KJs:0.3,QJs:0.2,AKo,AQo:0.5",
                               passive: "TT,99:0.3,88:0.3,AJs,KQs"),
        "UTG-BB": PreflopChart(aggressive: "QQ+,JJ:0.4,AKs,AQs:0.6,AJs:0.2,A5s:0.5,A4s:0.4,A3s:0.2,KQs:0.3,K5s:0.1,76s:0.1,AKo:0.8,AQo:0.1",
                               passive: "JJ-22,A2s+,K6s+,Q8s+,J8s+,T8s+,97s+,86s+,75s+,65s,64s:0.3,54s,K5s:0.5,AKo,AQo:0.9,AJo,ATo:0.7,KQo,KJo:0.7,KTo:0.3,QJo:0.5"),

        "HJ-CO": PreflopChart(aggressive: "QQ+,JJ:0.4,AKs,AQs:0.6,AJs:0.3,A5s:0.7,A4s:0.5,A3s:0.2,KQs:0.5,KJs:0.2,76s:0.2,65s:0.2,AKo,AQo:0.3",
                              passive: "JJ-55,AQs,AJs,ATs,A9s:0.4,KQs,KJs:0.8,KTs:0.5,QJs:0.8,QTs:0.3,JTs:0.8,T9s:0.5,98s:0.3,AQo:0.5,AJo:0.2"),
        "HJ-BTN": PreflopChart(aggressive: "QQ+,JJ:0.5,TT:0.2,AKs,AQs:0.6,AJs:0.3,ATs:0.2,A5s:0.7,A4s:0.6,A3s:0.3,KQs:0.5,KJs:0.3,K9s:0.1,76s:0.3,65s:0.3,54s:0.2,AKo,AQo:0.4,AJo:0.1,KQo:0.1",
                               passive: "JJ-22,AQs,AJs,ATs,A9s:0.7,A8s:0.4,KQs,KJs,KTs:0.8,QJs,QTs:0.7,JTs,J9s:0.3,T9s,98s:0.7,87s:0.6,76s:0.7,65s:0.5,AQo,AJo:0.6,KQo:0.6"),
        "HJ-SB": PreflopChart(aggressive: "TT+,99:0.4,AKs,AQs,AJs,ATs:0.5,A9s:0.2,A5s:0.8,A4s:0.6,A3s:0.3,KQs,KJs:0.6,KTs:0.3,QJs:0.4,JTs:0.3,AKo,AQo:0.8,AJo:0.3,KQo:0.3",
                              passive: "99,88:0.3,77:0.2"),
        "HJ-BB": PreflopChart(aggressive: "QQ+,JJ:0.5,AKs,AQs:0.6,AJs:0.3,A5s:0.6,A4s:0.5,A3s:0.3,KQs:0.4,KJs:0.1,K5s:0.1,76s:0.1,65s:0.1,AKo,AQo:0.2",
                              passive: "JJ-22,A2s+,K4s+,Q8s+,J8s+,T8s+,97s+,86s+,75s+,64s+,54s,53s:0.3,AQo,AJo,ATo,A9o:0.3,KQo,KJo,KTo:0.6,QJo:0.8,QTo:0.4,JTo:0.4"),

        "CO-BTN": PreflopChart(aggressive: "JJ+,TT:0.4,AKs,AQs:0.7,AJs:0.4,ATs:0.3,A5s:0.8,A4s:0.7,A3s:0.4,A2s:0.2,KQs:0.6,KJs:0.4,KTs:0.2,K9s:0.2,QJs:0.2,T9s:0.2,76s:0.3,65s:0.3,54s:0.3,AKo,AQo:0.6,AJo:0.3,KQo:0.3",
                               passive: "TT-22,AQs,AJs,ATs,A9s:0.8,A8s:0.6,A7s:0.3,KQs,KJs,KTs:0.8,K9s:0.4,QJs:0.8,QTs:0.8,Q9s:0.3,JTs,J9s:0.5,T9s:0.8,T8s:0.3,98s:0.8,87s:0.7,76s:0.7,65s:0.6,AQo,AJo:0.6,ATo:0.3,KQo:0.6,KJo:0.3"),
        "CO-SB": PreflopChart(aggressive: "99+,88:0.5,AKs,AQs,AJs,ATs,A9s:0.5,A8s:0.3,A5s,A4s:0.8,A3s:0.5,A2s:0.3,KQs,KJs,KTs:0.6,K9s:0.3,QJs:0.7,QTs:0.4,JTs:0.5,T9s:0.3,98s:0.2,76s:0.2,65s:0.2,AKo,AQo,AJo:0.6,ATo:0.2,KQo:0.6,KJo:0.2",
                              passive: "88,77:0.3,66:0.2"),
        "CO-BB": PreflopChart(aggressive: "QQ+,JJ:0.6,TT:0.2,AKs,AQs:0.7,AJs:0.4,ATs:0.2,A5s:0.6,A4s:0.5,A3s:0.3,A2s:0.2,KQs:0.4,KJs:0.3,K9s:0.1,K5s:0.2,Q9s:0.1,J9s:0.1,65s:0.2,54s:0.2,AKo,AQo:0.4,AJo:0.1,KQo:0.1",
                              passive: "JJ-22,A2s+,K2s+,Q5s+,J6s+,T6s+,96s+,85s+,74s+,64s+,53s+,43s:0.5,A2o+,K9o+,K8o:0.3,Q9o+,J9o+,T8o+,98o,87o:0.5,76o:0.2,A7o:0.6,A6o:0.4,A5o:0.6,A4o:0.4,A3o:0.2,A2o:0.1"),

        "BTN-SB": PreflopChart(aggressive: "88+,77:0.6,66:0.4,A2s+,K8s+,K7s:0.5,K6s:0.4,K5s:0.4,Q9s+,Q8s:0.4,J9s+,J8s:0.3,T8s+,98s,97s:0.3,87s,76s:0.8,65s:0.7,54s:0.5,ATo+,A9o:0.4,A5o:0.3,KJo+,KTo:0.5,QJo:0.6,QTo:0.3,JTo:0.3",
                               passive: "77-22:0.4,K9s,Q9s"),
        "BTN-BB": PreflopChart(aggressive: "TT+,99:0.3,AKs,AQs,AJs:0.6,ATs:0.4,A5s:0.6,A4s:0.6,A3s:0.4,A2s:0.3,KQs:0.7,KJs:0.5,KTs:0.3,K9s:0.2,K6s:0.2,K5s:0.3,K4s:0.2,Q9s:0.2,Q6s:0.2,J8s:0.2,T7s:0.2,86s:0.2,75s:0.3,64s:0.3,53s:0.3,AKo,AQo:0.8,AJo:0.4,ATo:0.2,A5o:0.2,KQo:0.4,KJo:0.2,K9o:0.1,Q9o:0.1,J9o:0.1",
                               passive: "22+,A2s+,K2s+,Q2s+,J2s+,T2s+,92s+,82s+,73s+,62s+,52s+,42s+,32s,A2o+,K2o+,Q4o+,Q3o:0.5,Q2o:0.3,J6o+,J5o:0.4,T6o+,T5o:0.2,96o+,86o+,75o+,64o:0.3,65o,54o:0.6"),

        "SB-BB": PreflopChart(aggressive: "99+,88:0.5,A9s+,A5s:0.8,A4s:0.7,A3s:0.5,A2s:0.4,KTs+,K9s:0.5,K5s:0.3,K4s:0.3,QTs+,Q9s:0.5,J9s+,T9s:0.6,T8s:0.4,98s:0.4,87s:0.4,76s:0.4,65s:0.4,54s:0.3,ATo+,A9o:0.5,A5o:0.4,A4o:0.3,KJo+,KTo:0.5,K9o:0.2,QJo:0.5,Q9o:0.2,J9o:0.2,T9o:0.2",
                              passive: "22+,A2s+,K2s+,Q2s+,J2s+,T3s+,94s+,84s+,73s+,63s+,52s+,42s+,32s,A2o+,K3o+,Q5o+,J6o+,T6o+,96o+,86o+,75o+,65o,54o"),
    ]

    static func vsOpen(opener: Position, hero: Position) -> PreflopChart? {
        vsOpenTable["\(opener.name)-\(hero.name)"]
    }

    // MARK: Opener facing a 3bet (4bet / call)

    private static let vs3betTable: [String: PreflopChart] = [
        "UTG-OOP": PreflopChart(aggressive: "KK+,QQ:0.4,AKs,AKo:0.5,A5s:0.3,A4s:0.2",
                                passive: "QQ-77,66:0.4,AQs,AJs,ATs:0.6,KQs,KJs:0.6,QJs:0.5,JTs:0.5,T9s:0.3,AKo,AQo:0.3"),
        "UTG-IP": PreflopChart(aggressive: "KK+,QQ:0.3,AKs,AKo:0.4,A5s:0.3",
                               passive: "QQ-55,AQs,AJs,ATs,A9s:0.3,KQs,KJs,KTs:0.6,QJs,QTs:0.4,JTs,T9s,98s:0.6,87s:0.5,76s:0.5,65s:0.4,AKo,AQo:0.7,AJo:0.2,KQo:0.3"),
        "HJ-OOP": PreflopChart(aggressive: "KK+,QQ:0.5,AKs,AQs:0.2,AKo:0.6,A5s:0.4,A4s:0.3",
                               passive: "QQ-66,AQs,AJs,ATs:0.7,A9s:0.2,KQs,KJs:0.7,KTs:0.3,QJs:0.6,JTs:0.6,T9s:0.4,98s:0.2,AKo,AQo:0.4"),
        "HJ-IP": PreflopChart(aggressive: "KK+,QQ:0.4,AKs,AKo:0.5,A5s:0.4,A4s:0.3",
                              passive: "QQ-44,AQs,AJs,ATs,A9s:0.5,A8s:0.3,KQs,KJs,KTs:0.8,K9s:0.3,QJs,QTs:0.6,JTs,J9s:0.3,T9s,98s:0.7,87s:0.6,76s:0.5,65s:0.5,AKo,AQo:0.8,AJo:0.3,KQo:0.4"),
        "CO-OOP": PreflopChart(aggressive: "QQ+,JJ:0.3,AKs,AQs:0.3,AKo,AQo:0.2,A5s:0.5,A4s:0.4,A3s:0.2,KQs:0.1,K9s:0.1",
                               passive: "JJ-55,44:0.5,AQs,AJs,ATs,A9s:0.5,A8s:0.3,KQs,KJs,KTs:0.7,K9s:0.2,QJs,QTs:0.6,JTs,J9s:0.3,T9s:0.8,98s:0.6,87s:0.5,76s:0.4,65s:0.3,AQo:0.6,AJo:0.3,KQo:0.4"),
        "CO-IP": PreflopChart(aggressive: "QQ+,JJ:0.2,AKs,AQs:0.2,AKo:0.8,A5s:0.4,A4s:0.4,A3s:0.2",
                              passive: "JJ-22,AQs,AJs,ATs,A9s:0.7,A8s:0.5,A7s:0.3,KQs,KJs,KTs,K9s:0.5,QJs,QTs,Q9s:0.4,JTs,J9s:0.6,T9s,T8s:0.3,98s,87s:0.8,76s:0.7,65s:0.6,54s:0.3,AKo,AQo,AJo:0.6,ATo:0.2,KQo:0.7,KJo:0.2"),
        "BTN-IP": PreflopChart(aggressive: "QQ+,JJ:0.3,AKs,AQs:0.3,AJs:0.1,AKo,AQo:0.3,A5s:0.5,A4s:0.5,A3s:0.3,A2s:0.2,K9s:0.1,K8s:0.1,Q9s:0.1,J9s:0.1,65s:0.1",
                               passive: "JJ-22,AQs,AJs,ATs,A6s+,A5s,A4s,K9s+,K8s:0.6,K7s:0.3,QTs+,Q9s:0.7,J9s+,T8s+,98s,97s:0.5,87s,86s:0.3,76s,75s:0.3,65s,54s:0.6,AQo,AJo,ATo:0.6,A9o:0.2,KQo,KJo:0.7,KTo:0.4,QJo:0.5,QTo:0.2,JTo:0.3"),
        "SB-OOP": PreflopChart(aggressive: "QQ+,JJ:0.4,AKs,AQs:0.4,AJs:0.2,AKo,AQo:0.4,A5s:0.6,A4s:0.5,A3s:0.4,A2s:0.3,KTs:0.2,K9s:0.2,K8s:0.2,Q9s:0.1",
                               passive: "JJ-22,AQs,AJs,A6s+,A5s,A4s,KJs+,KTs:0.8,K9s:0.6,QTs+,Q9s:0.5,J9s+,T8s+,98s,87s,76s,65s,54s:0.5,AQo,AJo,ATo:0.6,A9o:0.2,KQo,KJo:0.6,KTo:0.3,QJo:0.5"),
    ]

    static func vs3bet(opener: Position, threeBettor: Position) -> PreflopChart? {
        let openerIP = opener.isInPosition(vs: threeBettor)
        return vs3betTable["\(opener.name)-\(openerIP ? "IP" : "OOP")"]
    }

    // MARK: 3bettor facing a 4bet (jam / call)

    private static let vs4betIPEarly = PreflopChart(aggressive: "KK+,AKs:0.5,AKo:0.3,A5s:0.2",
                                                    passive: "QQ,JJ:0.5,TT:0.2,AKs,AKo:0.5,AQs:0.4,KQs:0.2")
    private static let vs4betIPLate = PreflopChart(aggressive: "KK+,QQ:0.3,AKs:0.6,AKo:0.5,A5s:0.3,A4s:0.2",
                                                   passive: "QQ,JJ,TT:0.5,99:0.2,AKs,AKo,AQs:0.6,AJs:0.3,KQs:0.4")
    private static let vs4betBlindEarly = PreflopChart(aggressive: "KK+,QQ:0.3,AKs:0.6,AKo:0.4,A5s:0.2",
                                                       passive: "QQ,JJ:0.6,TT:0.3,AKs,AKo:0.5,AQs:0.4")
    private static let vs4betBlindLate = PreflopChart(aggressive: "QQ+,JJ:0.3,AKs,AKo:0.7,A5s:0.3,A4s:0.2",
                                                      passive: "JJ,TT:0.7,99:0.3,AKo,AQs:0.7,AJs:0.4,KQs:0.5,AQo:0.3")

    static func vs4bet(threeBettor: Position, opener: Position) -> PreflopChart {
        let late = opener >= .co
        if threeBettor.isBlind { return late ? vs4betBlindLate : vs4betBlindEarly }
        return late ? vs4betIPLate : vs4betIPEarly
    }

    // MARK: 4bettor facing a 5bet jam (call / fold)

    private static let vs5betEarly = PreflopChart(aggressive: "", passive: "QQ+,JJ:0.5,AKs,AKo")
    private static let vs5betLate = PreflopChart(aggressive: "", passive: "JJ+,TT:0.5,AKs,AKo,AQs:0.6")

    static func vs5bet(opener: Position) -> PreflopChart {
        opener >= .co ? vs5betLate : vs5betEarly
    }
}
