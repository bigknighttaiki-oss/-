import SwiftUI

/// アプリのシェル。サイドバーで機能を切り替える。
struct ContentView: View {
    @EnvironmentObject private var auth: DropboxAuthService
    @EnvironmentObject private var coordinator: BackupCoordinator
    @EnvironmentObject private var scanModel: StorageScanViewModel

    enum Feature: String, CaseIterable, Identifiable {
        case backup
        case storage

        var id: String { rawValue }

        var title: String {
            switch self {
            case .backup: return "バックアップ"
            case .storage: return "ストレージ"
            }
        }

        var symbolName: String {
            switch self {
            case .backup: return "arrow.up.circle"
            case .storage: return "chart.pie"
            }
        }

        var subtitle: String {
            switch self {
            case .backup: return "Dropbox に退避する"
            case .storage: return "使用容量を調べる"
            }
        }
    }

    @State private var selection: Feature? = .backup
    @State private var isShowingSettings = false

    private var current: Feature { selection ?? .backup }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("機能") {
                    ForEach(Feature.allCases) { feature in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(feature.title)
                                Text(feature.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: feature.symbolName)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .padding(.vertical, 3)
                        .tag(feature)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 196, ideal: 212, max: 260)
            .safeAreaInset(edge: .bottom) {
                // 連携状態はどの画面からでも目に入る場所に置く。
                ConnectionBadge(state: auth.state)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            VStack(spacing: 0) {
                if isDemo {
                    demoBanner
                }
                switch current {
                case .backup:
                    BackupView(onOpenSettings: { isShowingSettings = true })
                case .storage:
                    StorageScanView()
                }
            }
            .background(Palette.ground)
            .navigationTitle(current.title)
            .navigationSubtitle(current.subtitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("設定", systemImage: "gearshape")
                    }
                    .help("Dropbox 連携の状態やアップロード先を確認する")
                }
            }
        }
        .frame(minWidth: 940, minHeight: 600)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .environmentObject(auth)
                .environmentObject(coordinator)
        }
    }
}

/// Dropbox 連携状態。色に加えて記号と文言でも状態が分かるようにする。
struct ConnectionBadge: View {
    let state: DropboxAuthService.State

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .font(.system(size: 13))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var tint: Color {
        switch state {
        case .signedIn: return .green
        case .authenticating: return .accentColor
        case .needsReauthentication: return .orange
        case .signedOut, .notConfigured: return .secondary
        }
    }

    private var symbol: String {
        switch state {
        case .signedIn: return "checkmark.circle.fill"
        case .authenticating: return "arrow.triangle.2.circlepath"
        case .needsReauthentication: return "exclamationmark.triangle.fill"
        case .signedOut: return "person.crop.circle.badge.questionmark"
        case .notConfigured: return "key.slash"
        }
    }

    private var text: String {
        switch state {
        case .signedIn: return "Dropbox 連携済み"
        case .authenticating: return "サインイン中…"
        case .needsReauthentication: return "再認証が必要"
        case .signedOut: return "未サインイン"
        case .notConfigured: return "App key 未設定"
        }
    }
}
