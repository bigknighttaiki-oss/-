import Charts
import SwiftUI

/// 種別ごとの使用容量を円グラフ（macOS 14 以降）または
/// 100% 積み上げ棒（macOS 13）で見せる。
///
/// セグメントの並びは常に `FileCategory.chartOrder` で固定する。
/// 容量順に並べ替えると隣り合う色の組み合わせが毎回変わってしまい、
/// 色覚特性のある人にとって見分けにくい並びが出うるため。
struct CategoryShareChart: View {
    let usages: [CategoryUsage]
    @Binding var highlighted: FileCategory?

    private var ordered: [CategoryUsage] {
        FileCategory.chartOrder
            .compactMap { category in usages.first { $0.category == category } }
            .filter { $0.byteSize > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("種別ごとの割合")
                .font(.headline)

            if #available(macOS 14.0, *) {
                donut
            } else {
                normalizedBar
            }
        }
    }

    @available(macOS 14.0, *)
    private var donut: some View {
        Chart(ordered) { usage in
            SectorMark(
                angle: .value("容量", usage.byteSize),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(usage.category.chartColor)
            .opacity(highlighted == nil || highlighted == usage.category ? 1 : 0.35)
        }
        .chartLegend(.hidden)
        .frame(height: 220)
        .overlay { centerLabel }
    }

    /// macOS 13 には SectorMark が無いので、100% 積み上げ棒で割合を見せる。
    private var normalizedBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(ordered) { usage in
                BarMark(
                    x: .value("容量", usage.byteSize),
                    y: .value("全体", "全体"),
                    stacking: .normalized
                )
                .foregroundStyle(usage.category.chartColor)
                .opacity(highlighted == nil || highlighted == usage.category ? 1 : 0.35)
            }
            .chartLegend(.hidden)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 44)

            centerLabel
        }
    }

    private var centerLabel: some View {
        VStack(spacing: 2) {
            Text(ByteFormatting.string(usages.reduce(Int64(0)) { $0 + $1.byteSize }))
                .font(.title2.bold())
                .monospacedDigit()
            Text("合計")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// 種別ごとの使用容量を横棒グラフで見せる。
/// 容量の大きい順に並べ、軸に種別名、棒の先に容量を直接書く
/// （色だけに意味を持たせない）。
struct CategorySizeChart: View {
    let usages: [CategoryUsage]
    @Binding var highlighted: FileCategory?

    private var sorted: [CategoryUsage] {
        usages.filter { $0.byteSize > 0 }.sorted { $0.byteSize > $1.byteSize }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("種別ごとの使用容量")
                .font(.headline)

            Chart(sorted) { usage in
                BarMark(
                    x: .value("容量", usage.byteSize),
                    y: .value("種別", usage.category.displayName)
                )
                .cornerRadius(4)
                .foregroundStyle(usage.category.chartColor)
                .opacity(highlighted == nil || highlighted == usage.category ? 1 : 0.35)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(ByteFormatting.string(usage.byteSize))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(preset: .aligned, position: .leading) { _ in
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let bytes = value.as(Double.self) {
                            Text(ByteFormatting.string(Int64(bytes)))
                        }
                    }
                }
            }
            // 棒の右に容量ラベルを出すぶん、描画領域に余白を残す。
            .chartPlotStyle { plot in plot.padding(.trailing, 56) }
            .frame(height: CGFloat(max(sorted.count, 1)) * 34 + 32)
        }
    }
}

/// ボリューム全体の使用状況。使用中と空きの 2 色だけで、どちらも直接ラベルを付ける。
struct VolumeCapacityBar: View {
    let volume: VolumeUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("ディスクの空き")
                    .font(.headline)
                Spacer()
                Text("\(ByteFormatting.string(volume.availableBytes)) 空き / 全体 \(ByteFormatting.string(volume.totalBytes))")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                let usedWidth = geometry.size.width * CGFloat(min(1, max(0, volume.usedShare)))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .quaternaryLabelColor))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: NSColor(rgbHex: 0x2A78D6)))
                        .frame(width: usedWidth)
                }
            }
            .frame(height: 14)

            Text("使用中 \(ByteFormatting.string(volume.usedBytes))（\(Int((volume.usedShare * 100).rounded()))%）")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// グラフの凡例と、同じ数字を読める表を兼ねたビュー。
/// ライトモードで背景とのコントラストが 3:1 に届かない色があるため、
/// 色だけに頼らず数値で読めるようにこの表を必ず一緒に出す。
struct CategoryLegendTable: View {
    let usages: [CategoryUsage]
    @Binding var highlighted: FileCategory?

    private var rows: [CategoryUsage] {
        usages.filter { $0.byteSize > 0 }.sorted { $0.byteSize > $1.byteSize }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("種別").frame(width: 120, alignment: .leading)
                Text("容量").frame(width: 90, alignment: .trailing)
                Text("割合").frame(width: 60, alignment: .trailing)
                Text("件数").frame(width: 80, alignment: .trailing)
                Spacer()
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)

            Divider()

            ForEach(rows) { usage in
                HStack {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(usage.category.chartColor)
                            .frame(width: 10, height: 10)
                        Image(systemName: usage.category.symbolName)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(usage.category.displayName)
                    }
                    .frame(width: 120, alignment: .leading)

                    Text(ByteFormatting.string(usage.byteSize))
                        .frame(width: 90, alignment: .trailing)
                    Text("\(Int((usage.share * 100).rounded()))%")
                        .frame(width: 60, alignment: .trailing)
                    Text("\(usage.fileCount)")
                        .frame(width: 80, alignment: .trailing)
                    Spacer()
                }
                .monospacedDigit()
                .font(.callout)
                .padding(.vertical, 3)
                .background(highlighted == usage.category ? Color.accentColor.opacity(0.12) : Color.clear)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    highlighted = isHovering ? usage.category : nil
                }
            }
        }
    }
}
