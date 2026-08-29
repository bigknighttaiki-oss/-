import AppKit
import SwiftUI

/// フェーズ2: ストレージのスキャンと可視化。
///
/// 画面の中心に大きなリングを置き、その下に種別ごとの内訳を並べる構成。
struct StorageScanView: View {
    @EnvironmentObject private var model: StorageScanViewModel
    @State private var highlighted: FileCategory?

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.block) {
                hero
                detail
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 中央のリング

    private var hero: some View {
        Card(padding: 24) {
            VStack(spacing: Metrics.block) {
                gauge
                    .frame(width: 260, height: 260)

                caption

                controls
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var gauge: some View {
        switch model.state {
        case .finished(let result):
            RadialGauge(segments: segments(for: result)) {
                GaugeReadout(
                    value: ByteFormatting.string(result.totalBytes),
                    caption: "スキャンした容量",
                    note: "\(result.fileCount) ファイル"
                )
            }

        case .scanning(let progress):
            RadialGauge(
                segments: [
                    .init(id: "scanning", value: 1, color: Color.accentColor.opacity(0.55))
                ]
            ) {
                GaugeReadout(
                    value: ByteFormatting.string(progress.bytesScanned),
                    caption: "集計中",
                    note: "\(progress.filesScanned) ファイル"
                )
            }

        default:
            // スキャン前でも、ディスク全体の空き具合だけは先に見せる。
            if let volume = DiskSpace.startupVolume {
                RadialGauge(
                    segments: [
                        .init(id: "used", value: Double(volume.usedBytes), color: .accentColor),
                        .init(id: "free", value: Double(volume.availableBytes),
                              color: Palette.border.opacity(0.9))
                    ]
                ) {
                    GaugeReadout(
                        value: ByteFormatting.string(volume.availableBytes),
                        caption: "空き容量",
                        note: "全体 \(ByteFormatting.string(volume.totalBytes))"
                    )
                }
            } else {
                RadialGauge(
                    segments: [.init(id: "idle", value: 1, color: Palette.border.opacity(0.9))]
                ) {
                    GaugeReadout(value: "—", caption: "未スキャン")
                }
            }
        }
    }

    @ViewBuilder
    private var caption: some View {
        switch model.state {
        case .idle:
            Text("フォルダを選ぶと、写真・動画・音楽・書類などの種別ごとに容量を集計します。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

        case .scanning(let progress):
            Text(progress.currentPath)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 460)

        case .finished(let result):
            VStack(spacing: Metrics.tight) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                    Text(result.root.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(result.scannedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                .font(.callout)

                if let volume = result.volume {
                    Text("ディスクの空き \(ByteFormatting.string(volume.availableBytes)) / 全体 \(ByteFormatting.string(volume.totalBytes))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: 520)

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if model.isScanning {
            VStack(spacing: Metrics.stack) {
                ProgressView()
                    .controlSize(.small)
                Button("中断", role: .cancel) { model.cancel() }
            }
        } else {
            VStack(spacing: Metrics.stack) {
                Button {
                    model.chooseFolderAndScan()
                } label: {
                    Text(model.result == nil ? "スキャン" : "別のフォルダをスキャン")
                        .font(.headline)
                        .frame(minWidth: 190)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                HStack(spacing: Metrics.block) {
                    // フォルダを選ばなくても結果画面を確認できるようにする入口。
                    if model.result == nil {
                        Button("サンプルデータで試す") { model.startDemo() }
                            .buttonStyle(.link)
                    }
                    if model.lastRoot != nil {
                        Button {
                            model.rescan()
                        } label: {
                            Label("同じフォルダを再スキャン", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.link)
                    }
                    Toggle("隠しファイルを含める", isOn: $model.includesHiddenFiles)
                        .toggleStyle(.checkbox)
                        .font(.callout)
                }
                .font(.callout)
            }
        }
    }

    private func segments(for result: ScanResult) -> [GaugeSegment] {
        // 区間の並びは容量順ではなく固定順にする。並び替えると隣り合う色の
        // 組み合わせが毎回変わり、見分けにくい並びが出るため。
        FileCategory.chartOrder.compactMap { category in
            let usage = result.usage(for: category)
            guard usage.byteSize > 0 else { return nil }
            return GaugeSegment(
                id: category.rawValue,
                value: Double(usage.byteSize),
                color: category.chartColor,
                isDimmed: highlighted != nil && highlighted != category
            )
        }
    }

    // MARK: - リングの下

    @ViewBuilder
    private var detail: some View {
        if let result = model.result {
            breakdownCard(result)
            largestFilesCard(result)
            if !result.unreadablePaths.isEmpty {
                skippedCard(result)
            }
        } else if case .idle = model.state {
            hints
        }
    }

    private func breakdownCard(_ result: ScanResult) -> some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("内訳", subtitle: "行にポインタを合わせるとリングが強調されます")
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.top, Metrics.cardPadding)
                    .padding(.bottom, Metrics.tight)

                CategoryBreakdownList(usages: result.usages, highlighted: $highlighted)
                    .padding(.bottom, Metrics.tight)
            }
        }
    }

    private func largestFilesCard(_ result: ScanResult) -> some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(
                    "容量の大きいファイル",
                    subtitle: "行をクリックすると Finder で表示します"
                )
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.top, Metrics.cardPadding)
                .padding(.bottom, Metrics.tight)

                let files = Array(result.largestFiles.prefix(20))
                ForEach(files) { file in
                    HStack(spacing: Metrics.stack) {
                        CategoryBadge(category: file.category, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.fileName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(file.parentPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: Metrics.stack)
                        Text(ByteFormatting.string(file.byteSize))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Metrics.cardPadding)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    }

                    if file.id != files.last?.id {
                        RowDivider().padding(.leading, 52)
                    }
                }
                .padding(.bottom, Metrics.tight)
            }
        }
    }

    private func skippedCard(_ result: ScanResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.tight) {
                SectionHeader(
                    "読み取れなかった項目 (\(result.unreadablePaths.count))",
                    subtitle: "アクセス権が無いなどの理由で集計から外れています"
                )
                ForEach(result.unreadablePaths.prefix(10), id: \.self) { path in
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    /// スキャン前の案内。どこから見るとよいかを示す。
    private var hints: some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.stack) {
                SectionHeader("どこから見る？")
                hint("music.note", "ミュージック", "音楽制作のプロジェクトは 1 つで数 GB になりがちです")
                hint("photo", "ピクチャ", "写真ライブラリは種別ごとの内訳が効きます")
                hint("arrow.down.circle", "ダウンロード", "使い終わったインストーラや書き出しが溜まりがちです")
            }
        }
    }

    private func hint(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: Metrics.stack) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
