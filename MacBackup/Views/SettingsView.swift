import SwiftUI

/// 設定画面。
/// フェーズ1ではアップロード先は固定だが、将来変更できるよう UI の土台だけ用意してある。
struct SettingsView: View {
    @EnvironmentObject private var auth: DropboxAuthService
    @EnvironmentObject private var coordinator: BackupCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    @State private var accountEmail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.block) {
            Text("設定")
                .font(.title2.weight(.semibold))

            connectionCard
            destinationCard

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("閉じる") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Metrics.gutter)
        .frame(width: 560, height: 500)
        .background(Palette.ground)
        .task { await loadAccount() }
    }

    // MARK: - Dropbox 連携

    private var connectionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.stack) {
                SectionHeader("Dropbox 連携")

                ConnectionBadge(state: auth.state)

                if let accountEmail {
                    LabeledContent("アカウント", value: accountEmail)
                        .font(.callout)
                }

                if case .needsReauthentication(let reason) = auth.state {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if case .notConfigured = auth.state {
                    appKeyInstructions
                }

                HStack(spacing: Metrics.stack) {
                    Button("再認証") { Task { await signIn() } }
                        .disabled(auth.state == .notConfigured)
                    Button("サインアウト") { auth.signOut(); accountEmail = nil }
                        .disabled(!auth.state.isSignedIn)
                }
            }
        }
    }

    private var appKeyInstructions: some View {
        VStack(alignment: .leading, spacing: Metrics.tight) {
            Label("App key が見つかりません", systemImage: "key.slash")
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
            Text("次のいずれかに設定してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                instructionRow(1, "環境変数 DROPBOX_APP_KEY")
                instructionRow(2, AppConfig.userConfigURL.path)
                instructionRow(3, "アプリに同梱した DropboxConfig.plist")
            }
        }
        .padding(Metrics.stack)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
    }

    private func instructionRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(number).")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .monospaced()
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - アップロード先

    private var destinationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.stack) {
                SectionHeader("アップロード先", subtitle: "フェーズ1では固定です")

                HStack(spacing: Metrics.stack) {
                    Image(systemName: "folder")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                    // フェーズ1では固定。将来ここを編集可能にする。
                    TextField("", text: .constant(coordinator.remoteFolder))
                        .textFieldStyle(.roundedBorder)
                        .monospaced()
                        .disabled(true)
                }
            }
        }
    }

    // MARK: - 処理

    private func signIn() async {
        errorMessage = nil
        do {
            try await auth.signIn()
            await loadAccount()
        } catch DropboxError.cancelled {
            // 何も出さない。
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadAccount() async {
        guard auth.state.isSignedIn else { return }
        let auth = self.auth
        let client = DropboxAPIClient(tokenProvider: { try await auth.validAccessToken() })
        accountEmail = try? await client.currentAccountEmail()
    }
}
