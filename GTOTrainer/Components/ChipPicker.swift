import SwiftUI

/// Row of pill buttons, like GTO Wizard's segmented settings.
struct ChipPicker<T: Hashable>: View {
    let title: String
    var help: String? = nil
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(Theme.textSecondary)
            FlowLayout(spacing: 6) {
                ForEach(options.indices, id: \.self) { i in
                    let value = options[i].0
                    Button { selection = value } label: {
                        Text(options[i].1)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(selection == value ? Theme.stroke : Theme.surfaceHigh.opacity(0.6))
                            .foregroundStyle(selection == value ? .white : Theme.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            if let help { Text(help).font(.caption).foregroundStyle(Theme.textSecondary.opacity(0.8)) }
        }
    }
}

/// Simple wrapping layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowH = max(rowH, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var color: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct GradeBadge: View {
    let grade: Grade

    var body: some View {
        Text(grade.name)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.color(for: grade))
            .foregroundStyle(.black.opacity(0.85))
            .clipShape(Capsule())
    }
}

/// Horizontal frequency bars for each option of a decision.
struct StrategyBars: View {
    let labels: [String]
    let colors: [Color]
    let frequencies: [Double]
    let evLoss: [Double]
    var chosen: Int?

    var body: some View {
        VStack(spacing: 6) {
            ForEach(labels.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    Text(labels[i]).font(.caption.weight(i == chosen ? .bold : .regular))
                        .frame(width: 92, alignment: .leading)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surfaceHigh)
                            Capsule().fill(colors[i]).frame(width: max(2, g.size.width * frequencies[i]))
                        }
                    }
                    .frame(height: 8)
                    Text(pct(frequencies[i])).font(.caption.monospacedDigit()).frame(width: 40, alignment: .trailing)
                    Text(evLoss[i] < 0.005 ? "–" : "-\(bb(evLoss[i], decimals: 2))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.vertical, 2)
                .background(i == chosen ? Color.white.opacity(0.06) : .clear)
            }
        }
    }
}
