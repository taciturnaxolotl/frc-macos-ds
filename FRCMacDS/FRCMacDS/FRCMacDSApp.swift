import SwiftUI

@main
struct FRCMacDSApp: App {
    @State private var model = AppModel()
    @State private var updaterViewModel = UpdaterViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model.appState)
                .environment(model.connection)
                .environment(model.hidManager)
                .environment(model.pcDiag)
                .environment(model.keybindManager)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 920, height: 280)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(viewModel: updaterViewModel)
            }
        }

        Settings {
            KeybindSettingsView()
                .environment(model.keybindManager)
        }
    }
}
