import SwiftUI

/// リングを構成する区間。値は合計で正規化して描くので、比率でも実数でもよい。
///
/// ジェネリックな `RadialGauge` の入れ子にすると参照のたびに型引数が要るため、
/// トップレベルの型にしてある。
struct GaugeSegment: Identifiable {
    let id: String
    let value: Double
    let color: Color
    /// 強調表示から外れているとき薄くする。
    var isDimmed: Bool = false
}

/// 中央に大きく数値を出すリング型のゲージ。
///
/// Swift Charts の `SectorMark` は macOS 14 以降でしか使えないため、
/// 円は自前で描いている。おかげで macOS 13 でも同じ見た目になる。
struct RadialGauge<Center: View>: View {
    let segments: [GaugeSegment]
    var lineWidth: CGFloat = 26
    /// 区間の間に開ける隙間（角度）。
    var gapDegrees: Double = 2.2
    @ViewBuilder var center: Center

    private var total: Double {
        max(segments.reduce(0) { $0 + $1.value }, .leastNonzeroMagnitude)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.border.opacity(0.45), lineWidth: lineWidth)

            ForEach(Array(offsets.enumerated()), id: \.element.segment.id) { _, item in
                Circle()
                    .trim(from: item.start, to: item.end)
                    .stroke(
                        item.segment.color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .opacity(item.segment.isDimmed ? 0.25 : 1)
                    // 12 時の位置から時計回りに描く。
                    .rotationEffect(.degrees(-90))
            }

            center
                .padding(lineWidth + 12)
        }
        .padding(lineWidth / 2)
        .animation(.easeOut(duration: 0.25), value: segments.map(\.value))
    }

    /// 各区間の開始・終了位置（0.0〜1.0）。隙間のぶんだけ末尾を詰める。
    private var offsets: [(segment: GaugeSegment, start: CGFloat, end: CGFloat)] {
        var result: [(GaugeSegment, CGFloat, CGFloat)] = []
        var cursor: Double = 0
        let gap = gapDegrees / 360

        for segment in segments where segment.value > 0 {
            let share = segment.value / total
            let start = cursor
            // 区間が隙間より短いときは潰さず、最低限の長さを残す。
            let end = max(start + share - gap, start + min(share, 0.004))
            result.append((segment, CGFloat(start), CGFloat(end)))
            cursor += share
        }
        return result
    }
}

extension RadialGauge where Center == EmptyView {
    init(segments: [GaugeSegment], lineWidth: CGFloat = 26, gapDegrees: Double = 2.2) {
        self.init(segments: segments, lineWidth: lineWidth, gapDegrees: gapDegrees) { EmptyView() }
    }
}

/// ゲージの中央に置く、大きな数値と説明。
struct GaugeReadout: View {
    let value: String
    let caption: String
    var note: String?

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
