import SwiftUI

/// 13x13 starting-hand grid.
struct RangeGridView: View {
    enum Mode {
        /// Strategy: raise / call / fold frequency bars in each cell.
        case strategy(PreflopChart)
        /// Range weights (0...1) drawn with a single colour.
        case weights([Double], Color)
        /// Selection (drill hand filter).
        case selection(Set<Int>)
    }

    let mode: Mode
    var highlight: HandClass?
    var onTap: ((HandClass) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) / 13
            VStack(spacing: 0) {
                ForEach(0..<13, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<13, id: \.self) { c in
                            cell(HandClass(row: r, col: c), size: size)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func cell(_ hc: HandClass, size: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Theme.surfaceHigh)
            switch mode {
            case .strategy(let chart):
                let f = chart.frequencies(hc)
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.betMedium).frame(width: size * f.raise)
                    Rectangle().fill(Theme.call).frame(width: size * f.call)
                    Rectangle().fill(Theme.fold.opacity(0.85)).frame(width: size * f.fold)
                }
            case .weights(let w, let color):
                Rectangle().fill(color.opacity(0.25 + 0.75 * w[hc.index]))
                    .frame(width: size * w[hc.index])
            case .selection(let set):
                if set.contains(hc.index) { Rectangle().fill(Color(hex: 0x1F5A3C)) }
            }
            Text(hc.description)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .overlay(Rectangle().stroke(Color.black.opacity(0.5), lineWidth: 0.5))
        .overlay(Rectangle().stroke(Color.white, lineWidth: highlight == hc ? 2 : 0))
        .contentShape(Rectangle())
        .onTapGesture { onTap?(hc) }
    }
}

struct StrategyLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            legend(Theme.betMedium, "Raise")
            legend(Theme.call, "Call")
            legend(Theme.fold, "Fold")
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10); Text(t) }
    }
}
