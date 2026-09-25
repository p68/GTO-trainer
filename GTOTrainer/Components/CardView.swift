import SwiftUI

/// Four-colour card: coloured face with big rank and suit symbol.
struct CardView: View {
    let card: Card?
    var width: CGFloat = 44
    var faceDown = false

    var body: some View {
        let h = width * 1.38
        ZStack {
            if let card, !faceDown {
                RoundedRectangle(cornerRadius: width * 0.14)
                    .fill(Theme.suitColor(card.suit))
                VStack(spacing: -width * 0.08) {
                    Text(String(card.rankChar))
                        .font(.system(size: width * 0.62, weight: .bold, design: .rounded))
                    Text(card.suitSymbol)
                        .font(.system(size: width * 0.36))
                }
                .foregroundStyle(.white)
            } else {
                RoundedRectangle(cornerRadius: width * 0.14)
                    .fill(LinearGradient(colors: [Color(hex: 0x3D4B5C), Color(hex: 0x222B36)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: width * 0.1)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    .padding(width * 0.08)
            }
        }
        .frame(width: width, height: h)
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }
}

struct CardsView: View {
    let cards: [Card]
    var width: CGFloat = 44
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, c in CardView(card: c, width: width) }
        }
    }
}
