import AppKit
import SwiftUI

@main
struct AgentBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // O app vive na barra de menus; a única janela é a de ajustes (T11).
        Settings {
            Text("Ajustes")
                .padding()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // O Info.plist já tira o ícone do Dock; isto cobre o `swift run`, que roda sem bundle.
        NSApp.setActivationPolicy(.accessory)
        statusItemController = StatusItemController()
    }
}
