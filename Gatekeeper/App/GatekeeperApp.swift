import SwiftUI

/// Gatekeeper's Mac helper: a menu-bar app with no Dock icon (LSUIElement). The popup is the Today screen;
/// exam mode hides or quits the listed apps and the other browsers.
@main
struct GatekeeperApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopupView()
                .environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Gatekeeper", id: "settings") {
            SettingsView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// The menu-bar icon. It also runs the first launch: "open at login" on, and the settings window shown once.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: GateMark.menuBarImage(locked: model.examOn))
            .task {
                guard model.takeFirstRun() else { return }
                try? await Task.sleep(for: .milliseconds(400))
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}
