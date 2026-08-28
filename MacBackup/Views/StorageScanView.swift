import AppKit
import SwiftUI

/// フェーズ2: ストレージのスキャンと可視化。
struct StorageScanView: View {
    @EnvironmentObject private var model: StorageScanViewModel
    @State private var highlighted: FileCategory?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            RowDivider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var toolbar: some View {
        HStack(spacing: Metrics.stack) {
            Button {
                model.chooseFolderAndScan()
            } label: {
                Label("フォルダをスキャン", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isScanning)

            if model.lastRoot != nil && !model.isScanning {
                Button {
                    model.rescan()
                } label: {
                    Label("再スキャン", systemImage: "arrow.clockwise")
                }
            }

            Toggle("隠しファイルを含める", isOn: $model.includesHiddenFiles)
                .toggleStyle(.checkbox)
                .disabled(model.isScanning)

            Spacer()

            if model.isScanning {
                Button("中断", role: .cancel) { model.cancel() }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, Metrics.stack)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            EmptyState(
                systemImage: "chart.pie",
                title: "使用容量を調べる",
                message: "フォルダを選ぶと、写真・動画・音楽・書類などの種別ごとに容量を集計します。ホームフォルダ全体は時間がかかるので、まずは「ミュージック」や「ピクチャ」から試すのがおすすめです。"
            ) {
                Button {
                    model.chooseFolderAndScan()
                } label: {
                    Label("フォルダを選択", systemImage: "folder")
                        .frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

        case .scanning(let progress):
            scanning(progress)

        case .failed(let message):
            EmptyState(
                systemImage: "exclamationmark.triangle",
                title: "スキャンできませんでした",
                message: message
            ) {
                Button("もう一度スキャン") { model.rescan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.lastRoot == nil)
            }

        case .finished(let result):
            results(result)
        }
    }

    // MARK: - 走査中

    private func scanning(_ progress: StorageScanner.Progress) -> some View {
        VStack(alignment: .leading, spacing: Metrics.block) {
            Card {
                VStack(alignment: .leading, spacing: Metrics.stack) {
                    HStack(spacing: Metrics.stack) {
                        ProgressView()
                            .controlSize(.small)
                        Text("集計しています")
                            .font(.headline)
                        Spacer()
                    }

                    // 総数が事前に分からないので、進捗率ではなく実績値を出す。
                    HStack(spacing: Metrics.block) {
                        metric("見たファイル", "\(progress.filesScanned)")
                        metric("合計サイズ", ByteFormatting.string(progress.bytesScanned))
                    }

                    Text(progress.currentPath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
        .padding(Metrics.gutter)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.medium))
                .monospacedDigit()
        }
    }

    // MARK: - 結果

    private func results(_ result: ScanResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.block) {
                headerCard(result)

                if let volume = result.volume {
                    Card { VolumeCapacityBar(volume: volume) }
                }

                HStack(alignment: .top, spacing: Metrics.block) {
                    Card {
                        CategoryShareChart(usages: result.usages, highlighted: $highlighted)
                    }
                    .frame(width: 250)

                    Card {
                        CategorySizeChart(usages: result.usages, highlighted: $highlighted)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Metrics.stack) {
                        SectionHeader("内訳", subtitle: "行にポインタを合わせるとグラフ側が強調されます")
                        CategoryLegendTable(usages: result.usages, highlighted: $highlighted)
                    }
                }

                largestFilesCard(result)

                if !result.unreadablePaths.isEmpty {
                    skippedCard(result)
                }
            }
            .padding(Metrics.gutter)
        }
    }

    private func headerCard(_ result: ScanResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.tight) {
                Text(ByteFormatting.string(result.totalBytes))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                    Text(result.root.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(result.fileCount) ファイル")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.callout)

                Text(result.scannedAt.formatted(date: .abbreviated, time: .shortened) + " 時点")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                    FileRow(
                        systemImage: file.category.symbolName,
                        name: file.fileName,
                        detail: file.parentPath,
                        symbolTint: file.category.chartColor
                    ) {
                        MonoText(ByteFormatting.string(file.byteSize))
                    }
                    .padding(.horizontal, Metrics.cardPadding)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    }

                    if file.id != files.last?.id {
                        RowDivider().padding(.leading, Metrics.cardPadding + 30)
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
}
