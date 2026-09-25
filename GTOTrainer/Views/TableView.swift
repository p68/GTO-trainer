import SwiftUI

/// Oval 6-max table with hero at the bottom.
struct TableView: View {
    let vm: TrainerViewModel

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let center = CGPoint(x: w / 2, y: h * 0.47)
            let rx = w * 0.36, ry = h * 0.36
            ZStack {
                // Felt
                Ellipse()
                    .fill(RadialGradient(colors: [Theme.feltEdge, Theme.felt], center: .center,
                                         startRadius: 10, endRadius: max(rx, ry)))
                    .overlay(Ellipse().stroke(Color(hex: 0x0E1F17), lineWidth: 10))
                    .frame(width: rx * 2.05, height: ry * 2.05)
                    .position(center)

                // Board + pot
                VStack(spacing: 8) {
                    Text("Pot \(bb(vm.pot)) bb")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Color.black.opacity(0.35)).clipShape(Capsule())
                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { i in
                            if i < vm.board.count {
                                CardView(card: vm.board[i], width: min(40, w * 0.1))
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.1))
                                    .frame(width: min(40, w * 0.1), height: min(40, w * 0.1) * 1.38)
                            }
                        }
                    }
                    .animation(.easeOut(duration: 0.25), value: vm.board.count)
                }
                .foregroundStyle(.white)
                .position(center)

                ForEach(vm.seats) { seat in
                    let d = Double((seat.id - vm.heroSeat + 6) % 6)
                    let angle = Double.pi / 2 + d * Double.pi / 3
                    let seatPoint = CGPoint(x: center.x + rx * 1.08 * cos(angle), y: center.y + ry * 1.12 * sin(angle))
                    let betPoint = CGPoint(x: center.x + rx * 0.62 * cos(angle), y: center.y + ry * 0.58 * sin(angle))

                    SeatView(seat: seat, compact: !seat.isHero)
                        .position(seatPoint)

                    if seat.bet > 0 {
                        BetChip(amount: seat.bet).position(betPoint)
                    }
                    if seat.position == .btn {
                        let bp = CGPoint(x: center.x + rx * 0.82 * cos(angle + 0.3), y: center.y + ry * 0.8 * sin(angle + 0.3))
                        Text("D").font(.caption2.weight(.heavy)).foregroundStyle(.black)
                            .frame(width: 18, height: 18).background(Circle().fill(.white)).position(bp)
                    }
                }
            }
        }
        .padding(.vertical, 6)
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
