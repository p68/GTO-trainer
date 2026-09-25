import XCTest
@testable import TrainerCore

final class EvaluatorTests: XCTestCase {
    func score(_ s: String) -> UInt32 {
        let cards = stride(from: 0, to: s.count, by: 2).map { i -> Card in
            let a = s.index(s.startIndex, offsetBy: i)
            return Card(String(s[a...s.index(after: a)]))!
        }
        return Evaluator.evaluate(cards.mask)
    }

    func testCategories() {
        XCTAssertEqual(Evaluator.category(of: score("AsKsQsJsTs2d3c")), .straightFlush)
        XCTAssertEqual(Evaluator.category(of: score("As2s3s4s5s9c9h")), .straightFlush)
        XCTAssertEqual(Evaluator.category(of: score("AhAdAcAs2d3c4h")), .quads)
        XCTAssertEqual(Evaluator.category(of: score("KhKdKc2s2d3c4h")), .fullHouse)
        XCTAssertEqual(Evaluator.category(of: score("Kh9h7h2h3hAcAd")), .flush)
        XCTAssertEqual(Evaluator.category(of: score("Ah2d3c4h5s9c9h")), .straight)
        XCTAssertEqual(Evaluator.category(of: score("7h7d7c2s9d3cKh")), .trips)
        XCTAssertEqual(Evaluator.category(of: score("7h7d9c9s2dKcQh")), .twoPair)
        XCTAssertEqual(Evaluator.category(of: score("7h7d9c3s2dKcQh")), .pair)
        XCTAssertEqual(Evaluator.category(of: score("7h8d9c3s2dKcQh")), .highCard)
    }

    func testOrdering() {
        XCTAssertGreaterThan(score("AhAd2c3s9dTcJh"), score("KhKdAc3s9dTcJh"))
        XCTAssertGreaterThan(score("Kh3d2c2s9d9c7h"), score("Qh3d2c2s9d9c7h"))       // two pair kicker
        XCTAssertEqual(score("AhKd2c2s9d9cTh"), score("AcKh2c2s9d9cTh"))
        XCTAssertGreaterThan(score("6h2d3c4s5d9cKh"), score("Ah2d3c4s5d9cKh"))       // 6-high beats wheel
        XCTAssertGreaterThan(score("KhKdKc2s2d3c4h"), score("QhQdQcAsAd3c4h"))
        XCTAssertGreaterThan(score("2h2d2c2sAdKcQh"), score("AhAdAcKsKdKcQh"))
    }
}

final class RangeTests: XCTestCase {
    func testParser() {
        let f = RangeParser.parse("TT+,A5s-A2s,KJo+,76s:0.5")
        XCTAssertEqual(f[HandClass("AA")!.index], 1)
        XCTAssertEqual(f[HandClass("TT")!.index], 1)
        XCTAssertEqual(f[HandClass("99")!.index], 0)
        XCTAssertEqual(f[HandClass("A3s")!.index], 1)
        XCTAssertEqual(f[HandClass("A6s")!.index], 0)
        XCTAssertEqual(f[HandClass("KQo")!.index], 1)
        XCTAssertEqual(f[HandClass("KTo")!.index], 0)
        XCTAssertEqual(f[HandClass("76s")!.index], 0.5)
        XCTAssertEqual(f.filter { $0 > 0 }.count, 5 + 4 + 2 + 1)
    }

    func testHandClassRoundTrip() {
        for hc in HandClass.all { XCTAssertEqual(HandClass(hc.description), hc) }
        XCTAssertEqual(HandClass.all.reduce(0) { $0 + $1.comboCount }, 1326)
        for hc in HandClass.all { XCTAssertEqual(hc.combos.count, hc.comboCount) }
    }

    func testChartsAreValid() {
        var charts: [PreflopChart] = Array(PreflopCharts.rfi.values)
        for o in Position.allCases { for h in Position.allCases {
            if let c = PreflopCharts.vsOpen(opener: o, hero: h) { charts.append(c) }
            if o < h, let c = PreflopCharts.vs3bet(opener: o, threeBettor: h) { charts.append(c) }
        } }
        XCTAssertEqual(charts.count, 5 + 15 + 15)
        for c in charts { for hc in HandClass.all {
            let f = c.frequencies(hc)
            XCTAssertEqual(f.raise + f.call + f.fold, 1, accuracy: 1e-9)
            XCTAssertGreaterThanOrEqual(f.fold, -1e-9)
        } }
        // Sanity: RFI widths grow with position.
        let widths = [Position.utg, .hj, .co, .btn].map { p in
            HandClass.all.reduce(0.0) { $0 + PreflopCharts.rfi[p]!.frequencies($1).raise * Double($1.comboCount) } / 1326
        }
        print("RFI widths", widths)
        XCTAssertEqual(widths, widths.sorted())
        XCTAssertEqual(PreflopCharts.rfi[.utg]!.frequencies(HandClass("AA")!).raise, 1)
    }
}

final class EquityTests: XCTestCase {
    func testKnownEquities() {
        var rng = SplitMix64(seed: 1)
        let aa = Combo(Card("Ah")!, Card("As")!)
        var kk = Range(uniform: 0)
        kk[Combo(Card("Kh")!, Card("Kd")!)] = 1
        let e = Equity.vsRange(hero: aa, board: [], range: kk, samples: 20000, rng: &rng)
        XCTAssertEqual(e, 0.82, accuracy: 0.02)
        let eqAA = Equity.preflopVsRandom[HandClass("AA")!.index]
        XCTAssertEqual(eqAA, 0.85, accuracy: 0.03)
        XCTAssertLessThan(Equity.preflopVsRandom[HandClass("72o")!.index], 0.38)
    }

    func testRiverExact() {
        var rng = SplitMix64(seed: 2)
        let board = ["Ah", "Kd", "7c", "2s", "3h"].map { Card($0)! }
        let hero = Combo(Card("As")!, Card("Ad")!)
        let e = Equity.vsRange(hero: hero, board: board, range: Range(uniform: 1), samples: 0, rng: &rng)
        XCTAssertGreaterThan(e, 0.97)
    }
}

final class EngineTests: XCTestCase {
    func testChipConservationAndCompletion() {
        var rng = SplitMix64(seed: 42)
        var showdowns = 0, flops = 0
        for _ in 0..<400 {
            let engine = HandEngine.deal(rng: &rng)
            var steps = 0
            while engine.toAct != nil && !engine.isOver {
                engine.playStrategy(engine.toAct!, rng: &rng)
                steps += 1
                XCTAssertLessThan(steps, 60)
                XCTAssertLessThanOrEqual(engine.activeSeats.count, 6)
                if engine.street != .preflop && !engine.isOver { XCTAssertEqual(engine.activeSeats.count, 2) }
            }
            XCTAssertTrue(engine.isOver)
            let net = (0..<6).reduce(0.0) { $0 + engine.net($1) }
            XCTAssertEqual(net + engine.rakeTaken, 0, accuracy: 1e-6)
            for p in engine.players { XCTAssertGreaterThanOrEqual(p.stack, -1e-9) }
            if engine.wentToShowdown { showdowns += 1 }
            if engine.sawFlop { flops += 1 }
        }
        print("flops", flops, "showdowns", showdowns)
        XCTAssertGreaterThan(flops, 50)
    }

    func testDealerFilters() {
        var rng = SplitMix64(seed: 7)
        var cfg = DrillConfig()
        cfg.preflopAction = .vs3bet
        cfg.hero = .btn
        for n in 0..<20 {
            guard let d = Dealer.deal(cfg, handNumber: n, rng: &rng) else { return XCTFail("no deal") }
            let node = d.engine.preflopNode(d.heroSeat)!
            XCTAssertEqual(node.type, .vs3bet)
            XCTAssertEqual(node.hero, .btn)
        }
        cfg = DrillConfig()
        cfg.preflopAction = .vsOpen
        cfg.hero = .bb
        cfg.opponent = .btn
        cfg.hands = HandRanking.classes(from: 0, to: 30)
        for n in 0..<20 {
            guard let d = Dealer.deal(cfg, handNumber: n, rng: &rng) else { return XCTFail("no deal") }
            XCTAssertTrue(cfg.hands.contains(d.engine.players[d.heroSeat].hole.handClass.index))
            XCTAssertEqual(d.engine.preflopNode(d.heroSeat)!.villain, .btn)
        }
    }

    func testGrading() {
        var rng = SplitMix64(seed: 9)
        var cfg = DrillConfig()
        cfg.preflopAction = .rfi
        cfg.hero = .utg
        cfg.hands = [HandClass("72o")!.index]
        let d = Dealer.deal(cfg, handNumber: 0, rng: &rng)!
        let a = d.engine.analyze(d.heroSeat, quality: .hero, rng: &rng)
        XCTAssertEqual(a.options.map(\.label), ["Fold", "Raise 2.5"])
        XCTAssertEqual(Grader.grade(a, chosen: 0).grade, .best)
        let raise = Grader.grade(a, chosen: 1)
        print("72o UTG raise loss", raise.evLoss, raise.grade)
        XCTAssertTrue(raise.grade.isMistake)

        cfg.hands = [HandClass("AA")!.index]
        let d2 = Dealer.deal(cfg, handNumber: 0, rng: &rng)!
        let a2 = d2.engine.analyze(d2.heroSeat, quality: .hero, rng: &rng)
        let fold = Grader.grade(a2, chosen: 0)
        print("AA UTG fold loss", fold.evLoss, fold.grade)
        XCTAssertEqual(fold.grade, .blunder)
    }

    func testPostflopAnalysis() {
        var rng = SplitMix64(seed: 11)
        var cfg = DrillConfig()
        cfg.preflopAction = .vsOpen
        cfg.hero = .bb
        cfg.opponent = .btn
        cfg.hands = [HandClass("KQs")!.index]
        var analysed = 0
        for n in 0..<30 {
            guard let d = Dealer.deal(cfg, handNumber: n, rng: &rng) else { continue }
            let e = d.engine
            let callIdx = e.legalOptions(d.heroSeat).firstIndex { $0.action.kind == .call }!
            e.take(e.legalOptions(d.heroSeat)[callIdx], seat: d.heroSeat, rng: &rng)
            while let s = e.toAct, !e.isOver {
                if s == d.heroSeat {
                    let t0 = Date()
                    let a = e.analyze(s, quality: .hero, rng: &rng)
                    let dt = Date().timeIntervalSince(t0)
                    XCTAssertEqual(a.frequencies.reduce(0, +), 1, accuracy: 1e-6)
                    XCTAssertTrue(a.evLoss.allSatisfy { $0 >= 0 })
                    if analysed < 6 {
                        print(e.board.text, a.spot, "eq", String(format: "%.2f", a.equity ?? 0),
                              zip(a.options.map(\.label), a.frequencies).map { "\($0.0)=\(String(format: "%.2f", $0.1))" },
                              String(format: "%.3fs", dt))
                    }
                    analysed += 1
                }
                e.playStrategy(s, rng: &rng)
            }
        }
        XCTAssertGreaterThan(analysed, 10)
    }
}
