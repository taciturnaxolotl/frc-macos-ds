import SwiftUI

@main
struct FRCMacDSApp: App {
    @State private var model = AppModel()

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

        Settings {
            KeybindSettingsView()
                .environment(model.keybindManager)
        }
    }
}
