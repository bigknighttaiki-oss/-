import SwiftUI

@main
struct MacBackupApp: App {
    @StateObject private var auth: DropboxAuthService
    @StateObject private var coordinator: BackupCoordinator
    @StateObject private var scanModel = StorageScanViewModel()

    @MainActor
    init() {
        let auth = DropboxAuthService()
        _auth = StateObject(wrappedValue: auth)
        _coordinator = StateObject(wrappedValue: BackupCoordinator(auth: auth))
    }

    var body: some Scene {
        WindowGroup("Mac Backup") {
            ContentView()
                .environmentObject(auth)
                .environmentObject(coordinator)
                .environmentObject(scanModel)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
