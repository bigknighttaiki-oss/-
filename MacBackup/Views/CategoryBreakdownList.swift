import SwiftUI

/// 種別ごとの内訳。1 行に色つきアイコン・名前・件数・割合バー・容量を並べる。
///
/// グラフの凡例と数値表を兼ねている。色だけに意味を持たせないよう、
/// どの行にも名前と容量を必ず添える。
struct CategoryBreakdownList: View {
    let usages: [CategoryUsage]
    @Binding var highlighted: FileCategory?

    private var rows: [CategoryUsage] {
        usages.filter { $0.byteSize > 0 }.sorted { $0.byteSize > $1.byteSize }
    }

    private var largest: Int64 {
        max(rows.first?.byteSize ?? 1, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { usage in
                row(usage)
                if usage.id != rows.last?.id {
                    RowDivider().padding(.leading, 52)
                }
            }
        }
    }

    private func row(_ usage: CategoryUsage) -> some View {
        HStack(spacing: Metrics.stack) {
            CategoryBadge(category: usage.category)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(usage.category.displayName)
                        .font(.body.weight(.medium))
                    Text("\(usage.fileCount) 件")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: Metrics.stack)
                    Text(ByteFormatting.string(usage.byteSize))
                        .font(.body)
                        .monospacedDigit()
                    Text("\(Int((usage.share * 100).rounded()))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }

                // 容量の大小がひと目で分かるよう、行の中に比率のバーを引く。
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Palette.border.opacity(0.5))
                            .frame(height: 5)
                        Capsule()
                            .fill(usage.category.chartColor)
                            .frame(
                                width: max(geometry.size.width * CGFloat(Double(usage.byteSize) / Double(largest)), 4),
                                height: 5
                            )
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 5)
            }
        }
        .padding(.horizontal, Metrics.cardPadding)
        .padding(.vertical, 11)
        .background(
            highlighted == usage.category
                ? Color.accentColor.opacity(0.10)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { isHovering in
            highlighted = isHovering ? usage.category : nil
        }
    }
}

/// 種別の色を敷いた丸いアイコン。
struct CategoryBadge: View {
    let category: FileCategory
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .fill(category.chartColor.opacity(0.16))
            Image(systemName: category.symbolName)
                .font(.system(size: size * 0.44, weight: .medium))
                .foregroundStyle(category.chartColor)
        }
        .frame(width: size, height: size)
    }
}
