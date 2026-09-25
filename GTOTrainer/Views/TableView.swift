import SwiftUI

/// Oval 6-max table with hero at the bottom.
struct TableView: View {
    let vm: TrainerViewModel

    private struct Geometry {
        let center: CGPoint
        let rx: CGFloat
        let ry: CGFloat
        let width: CGFloat

        func point(seatOffset d: Int, radiusX: CGFloat, radiusY: CGFloat, turn: Double = 0) -> CGPoint {
            let angle: Double = Double.pi / 2 + Double(d) * Double.pi / 3 + turn
            let x: CGFloat = center.x + rx * radiusX * CGFloat(cos(angle))
            let y: CGFloat = center.y + ry * radiusY * CGFloat(sin(angle))
            return CGPoint(x: x, y: y)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let g = makeGeometry(geo.size)
            ZStack {
                felt(g)
                centerInfo(g)
                ForEach(vm.seats) { seat in
                    seatLayer(seat, g)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func makeGeometry(_ size: CGSize) -> Geometry {
        Geometry(center: CGPoint(x: size.width / 2, y: size.height * 0.47),
                 rx: size.width * 0.36, ry: size.height * 0.36, width: size.width)
    }

    private func felt(_ g: Geometry) -> some View {
        Ellipse()
            .fill(RadialGradient(colors: [Theme.feltEdge, Theme.felt], center: .center,
                                 startRadius: 10, endRadius: max(g.rx, g.ry)))
            .overlay(Ellipse().stroke(Color(hex: 0x0E1F17), lineWidth: 10))
            .frame(width: g.rx * 2.05, height: g.ry * 2.05)
            .position(g.center)
    }

    private func centerInfo(_ g: Geometry) -> some View {
        let cardWidth: CGFloat = min(40, g.width * 0.1)
        return VStack(spacing: 8) {
            Text("Pot \(bb(vm.pot)) bb")
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Color.black.opacity(0.35)).clipShape(Capsule())
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    boardSlot(i, width: cardWidth)
                }
            }
            .animation(.easeOut(duration: 0.25), value: vm.board.count)
        }
        .foregroundStyle(.white)
        .position(g.center)
    }

    @ViewBuilder
    private func boardSlot(_ i: Int, width: CGFloat) -> some View {
        if i < vm.board.count {
            CardView(card: vm.board[i], width: width)
                .transition(.scale.combined(with: .opacity))
        } else {
            RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1))
                .frame(width: width, height: width * 1.38)
        }
    }

    @ViewBuilder
    private func seatLayer(_ seat: SeatSnapshot, _ g: Geometry) -> some View {
        let d = (seat.id - vm.heroSeat + 6) % 6
        SeatView(seat: seat, compact: !seat.isHero)
            .position(g.point(seatOffset: d, radiusX: 1.08, radiusY: 1.12))
        if seat.bet > 0 {
            BetChip(amount: seat.bet)
                .position(g.point(seatOffset: d, radiusX: 0.62, radiusY: 0.58))
        }
        if seat.position == .btn {
            Text("D").font(.caption2.weight(.heavy)).foregroundStyle(.black)
                .frame(width: 18, height: 18).background(Circle().fill(.white))
                .position(g.point(seatOffset: d, radiusX: 0.82, radiusY: 0.8, turn: 0.3))
        }
    }
}

struct SeatView: View {
    let seat: SeatSnapshot
    var compact: Bool

    var body: some View {
        VStack(spacing: 3) {
            if !seat.folded {
                if seat.isHero {
                    CardsView(cards: seat.cards, width: 46, spacing: 3)
                } else if seat.showCards {
                    CardsView(cards: seat.cards, width: 30, spacing: 2)
                } else {
                    HStack(spacing: -12) {
                        CardView(card: nil, width: 22)
                        CardView(card: nil, width: 22)
                    }
                }
            }
            VStack(spacing: 0) {
                Text(seat.position.name).font(.caption.weight(.bold))
                Text(seat.stack <= 0.001 && !seat.folded ? "All-in" : bb(seat.stack))
                    .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            }
            .frame(minWidth: 58)
            .padding(.vertical, 4).padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(seat.isToAct ? Theme.accent : (seat.isHero ? Theme.stroke : .clear), lineWidth: seat.isToAct ? 2 : 1))
            if let a = seat.lastAction {
                Text(a).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(actionColor(a).opacity(0.9)).clipShape(Capsule())
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .opacity(seat.folded ? 0.4 : 1)
    }

    private func actionColor(_ label: String) -> Color {
        if label.hasPrefix("Fold") { return Theme.fold }
        if label.hasPrefix("Check") || label.hasPrefix("Call") { return Theme.call }
        if label.hasPrefix("All-in") { return Theme.allIn }
        return Theme.betMedium
    }
}

struct BetChip: View {
    let amount: Double
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(Theme.betSmall).frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2])))
            Text(bb(amount)).font(.caption2.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Color.black.opacity(0.35)).clipShape(Capsule())
    }
}
