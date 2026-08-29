import Combine
import SwiftUI

/// フェーズ1: ファイルを選んで Dropbox にアップロードする画面。
struct BackupView: View {
    @EnvironmentObject private var auth: DropboxAuthService
    @EnvironmentObject private var coordinator: BackupCoordinator

    /// 設定画面を開くよう親に依頼する。
    var onOpenSettings: () -> Void

    @State private var authErrorMessage: String?
    @State private var isShowingAuthAlert = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alert("Dropbox の認証が必要です", isPresented: $isShowingAuthAlert) {
                Button("再認証") { Task { await signIn() } }
                Button("閉じる", role: .cancel) {}
            } message: {
                Text(authErrorMessage ?? "Dropbox に再度サインインしてください。")
            }
            .onReceive(coordinator.$authenticationErrorMessage.compactMap { $0 }) { message in
                authErrorMessage = message
                isShowingAuthAlert = true
            }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.phase {
        case .idle:
            startView
        case .uploading:
            UploadProgressView()
        case .review:
            BackupResultsView()
        }
    }

    // MARK: - 開始画面

    @ViewBuilder
    private var startView: some View {
        ScrollView {
            VStack(spacing: Metrics.block) {
                Card(padding: 24) {
                    VStack(spacing: Metrics.block) {
                        heroMark
                        heroText
                        heroActions
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }

    /// 中央の丸い記号。ストレージ画面のリングと大きさを揃える。
    private var heroMark: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.border.opacity(0.45), lineWidth: 26)
            Circle()
                .fill(heroTint.opacity(0.12))
                .padding(26)
            Image(systemName: heroSymbol)
                .font(.system(size: 62, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(heroTint)
        }
        .frame(width: 220, height: 220)
    }

    private var heroText: some View {
        VStack(spacing: Metrics.tight) {
            Text(heroTitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(heroMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
    }

    @ViewBuilder
    private var heroActions: some View {
        switch auth.state {
        case .signedIn:
            VStack(spacing: Metrics.stack) {
                Button {
                    let urls = FilePicker.selectFiles()
                    if !urls.isEmpty { coordinator.start(urls: urls) }
                } label: {
                    Text("ファイルを選択")
                        .font(.headline)
                        .frame(minWidth: 190)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                destinationChip
            }

        case .notConfigured:
            Button("設定を開く", action: onOpenSettings)
                .controlSize(.large)

        case .authenticating:
            ProgressView()
                .controlSize(.small)

        case .signedOut, .needsReauthentication:
            Button(auth.state.isSignedIn ? "Dropbox に再サインイン" : "Dropbox にサインイン") {
                Task { await signIn() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var heroSymbol: String {
        switch auth.state {
        case .signedIn: return "arrow.up.circle"
        case .notConfigured: return "key.slash"
        case .authenticating: return "arrow.triangle.2.circlepath"
        case .needsReauthentication: return "exclamationmark.triangle"
        case .signedOut: return "person.crop.circle.badge.plus"
        }
    }

    private var heroTint: Color {
        switch auth.state {
        case .notConfigured, .needsReauthentication: return .orange
        default: return .accentColor
        }
    }

    private var heroTitle: String {
        switch auth.state {
        case .signedIn: return "バックアップするファイルを選ぶ"
        case .notConfigured: return "Dropbox の App key が未設定です"
        case .authenticating: return "Dropbox にサインインしています"
        case .needsReauthentication: return "再認証が必要です"
        case .signedOut: return "Dropbox に接続する"
        }
    }

    private var heroMessage: String {
        switch auth.state {
        case .signedIn:
            return "写真や音楽制作のファイルを Dropbox に退避します。複数まとめて選べます。"
        case .notConfigured:
            return "Dropbox Developer Console で取得した App key を、環境変数か設定ファイルから読み込ませてください。"
        case .authenticating:
            return "ブラウザで認証を済ませてください。"
        case .needsReauthentication(let reason):
            return reason
        case .signedOut:
            return "バックアップ先の Dropbox アカウントにサインインしてください。"
        }
    }

    /// アップロード先を示す小さな表示。
    private var destinationChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .symbolRenderingMode(.hierarchical)
            Text("アップロード先")
                .foregroundStyle(.secondary)
            Text("\(coordinator.remoteFolder)/")
                .monospaced()
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Palette.surface)
        )
        .overlay(
            Capsule().strokeBorder(Palette.border, lineWidth: 1)
        )
    }

    private func signIn() async {
        do {
            try await auth.signIn()
        } catch DropboxError.cancelled {
            // ユーザーが自分で閉じた場合は何も出さない。
        } catch {
            authErrorMessage = error.localizedDescription
            isShowingAuthAlert = true
        }
    }
}
