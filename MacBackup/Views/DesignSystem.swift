import AppKit
import SwiftUI

/// 画面をまたいで使う余白・角丸の基準値。
/// 数値を各ビューに散らさず、ここだけを見れば間隔が揃っているか分かるようにする。
enum Metrics {
    /// 画面の外周。
    static let gutter: CGFloat = 20
    /// ブロック同士の間隔。
    static let block: CGFloat = 18
    /// 要素同士の間隔。
    static let stack: CGFloat = 10
    /// ラベルと値のような、近い要素同士の間隔。
    static let tight: CGFloat = 5

    static let cardRadius: CGFloat = 10
    static let cardPadding: CGFloat = 14
    static let controlRadius: CGFloat = 6
}

/// 面と境界の色。macOS のシステムカラーを使い、ライト／ダークとアクセントカラーの
/// 設定変更に自動で追随させる。
enum Palette {
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let ground = Color(nsColor: .windowBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
}

/// 情報のかたまりを載せる面。
struct Card<Content: View>: View {
    var padding: CGFloat = Metrics.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
    }
}

/// カードや一覧の見出し。右側に補助的なコントロールを置ける。
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.stack) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// 状態を色と記号の両方で示す小さなラベル。
/// 色だけに意味を持たせないよう、必ず記号と文言を伴う。
struct StatusChip: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(tint.opacity(0.12))
            )
            .overlay(
                Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 1)
            )
    }
}

/// 何も無い状態の案内。記号・見出し・説明・操作を縦に積む。
struct EmptyState<Actions: View>: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Metrics.block) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 92, height: 92)
                Image(systemName: systemImage)
                    .font(.system(size: 38, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: Metrics.tight) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }

            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Metrics.gutter)
    }
}

/// ファイル 1 行の共通レイアウト。進捗・結果・大きいファイル一覧で使い回す。
struct FileRow<Trailing: View>: View {
    let systemImage: String
    let name: String
    var detail: String? = nil
    /// 補足を注意色で出すか（リネームされた、スキップされた等）。
    var detailTint: Color? = nil
    var symbolTint: Color? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Metrics.stack) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbolTint ?? Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(detailTint ?? Color.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Metrics.stack)
            trailing
        }
        .padding(.vertical, 6)
    }
}

/// 桁を揃えたい数値（容量・パーセント）用。
struct MonoText: View {
    let text: String
    var font: Font = .callout

    init(_ text: String, font: Font = .callout) {
        self.text = text
        self.font = font
    }

    var body: some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

/// 一覧の行の間に引く細い区切り線。
struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 1)
    }
}
