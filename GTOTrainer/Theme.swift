import SwiftUI

enum Theme {
    static let background = Color(hex: 0x141414)
    static let surface = Color(hex: 0x1F1F1F)
    static let surfaceHigh = Color(hex: 0x2A2A2A)
    static let stroke = Color(hex: 0x3A3A3A)
    static let accent = Color(hex: 0xB9F5AE)
    static let textSecondary = Color(hex: 0x9A9A9A)
    static let felt = Color(hex: 0x1E3A2C)
    static let feltEdge = Color(hex: 0x2C5A43)

    // Action colours (GTO Wizard style: fold blue, check/call green, bets warm → dark red).
    static let fold = Color(hex: 0x4F86D9)
    static let call = Color(hex: 0x4FAE62)
    static let betSmall = Color(hex: 0xE8A33D)
    static let betMedium = Color(hex: 0xE0663A)
    static let betLarge = Color(hex: 0xC43A32)
    static let allIn = Color(hex: 0x8C1D2A)

    static func color(for option: ActionOption) -> Color {
        switch option.action.kind {
        case .fold: return fold
        case .check, .call: return call
        case .allIn: return allIn
        case .bet, .raise:
            if option.potFraction == 0 { return betMedium }   // preflop raises
            if option.potFraction <= 0.4 { return betSmall }
            if option.potFraction <= 0.8 { return betMedium }
            return betLarge
        }
    }

    static func color(for grade: Grade) -> Color {
        switch grade {
        case .best: return Color(hex: 0x2FA35B)
        case .correct: return Color(hex: 0x7FD08A)
        case .inaccuracy: return Color(hex: 0xE8C547)
        case .wrong: return Color(hex: 0xE8843D)
        case .blunder: return Color(hex: 0xE04848)
        }
    }

    static func suitColor(_ suit: Int) -> Color {
        [Color(hex: 0x3B3B3B), Color(hex: 0xC8373A), Color(hex: 0x2F6ED3), Color(hex: 0x2E9A4E)][suit]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

func bb(_ x: Double, decimals: Int = 1) -> String {
    String(format: "%.\(decimals)f", x)
}

func pct(_ x: Double) -> String {
    String(format: "%.0f%%", x * 100)
}
