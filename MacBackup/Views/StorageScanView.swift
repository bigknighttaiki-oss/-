import AppKit
import SwiftUI

/// フェーズ2: ストレージのスキャンと可視化。
struct StorageScanView: View {
    @EnvironmentObject private var model: StorageScanViewModel
    @State private var highlighted: FileCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                model.chooseFolderAndScan()
            } label: {
                Label("フォルダをスキャン", systemImage: "magnifyingglass")
            }
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
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            placeholder
        case .scanning(let progress):
            scanning(progress)
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(message)
                    .multilineTextAlignment(.center)
                Button("もう一度スキャン") { model.rescan() }
                    .disabled(model.lastRoot == nil)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .finished(let result):
            results(result)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("フォルダを選ぶと、種別ごとの使用容量を集計します。")
                .foregroundStyle(.secondary)
            Text("ホームフォルダ全体を選ぶと時間がかかります。まずは「ピクチャ」や「ミュージック」から試すのがおすすめです。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scanning(_ progress: StorageScanner.Progress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 総数が事前に分からないので、進捗率ではなく実績値を出す。
            ProgressView()
                .progressViewStyle(.linear)
            Text("\(progress.filesScanned) 件 / \(ByteFormatting.string(progress.bytesScanned)) を集計しました")
                .font(.callout)
                .monospacedDigit()
            Text(progress.currentPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding()
    }

    private func results(_ result: ScanResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(result)

                if let volume = result.volume {
                    VolumeCapacityBar(volume: volume)
                }

                HStack(alignment: .top, spacing: 24) {
                    CategoryShareChart(usages: result.usages, highlighted: $highlighted)
                        .frame(width: 260)
                    CategorySizeChart(usages: result.usages, highlighted: $highlighted)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("内訳")
                        .font(.headline)
                    CategoryLegendTable(usages: result.usages, highlighted: $highlighted)
                }

                largestFiles(result)

                if !result.unreadablePaths.isEmpty {
                    skipped(result)
                }
            }
            .padding()
        }
    }

    private func header(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ByteFormatting.string(result.totalBytes))
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
            Text("\(result.root.path) · \(result.fileCount) ファイル")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(result.scannedAt.formatted(date: .abbreviated, time: .shortened) + " 時点")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func largestFiles(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("容量の大きいファイル")
                .font(.headline)
            Text("削除の判断はここから。フェーズ1の「バックアップ」で Dropbox に退避してから消せます。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(result.largestFiles.prefix(20)) { file in
                    HStack(spacing: 8) {
                        Image(systemName: file.category.symbolName)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
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
                        Spacer()
                        Text(ByteFormatting.string(file.byteSize))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    }
                    .help("Finder で表示")
                    Divider()
                }
            }
        }
    }

    private func skipped(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("読み取れなかった項目 (\(result.unreadablePaths.count))")
                .font(.headline)
            Text("アクセス権が無いなどの理由で集計から外れています。")
                .font(.caption)
                .foregroundStyle(.secondary)
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
