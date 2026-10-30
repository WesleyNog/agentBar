import AgentBarCore
import AppKit

@main
@MainActor
enum AgentBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: AgentBarStore?
    private var statusItemController: StatusItemController?
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // O Info.plist já tira o ícone do Dock; isto cobre o `swift run`, que roda sem bundle.
        NSApp.setActivationPolicy(.accessory)

        let paths = AppPreferences.claudePaths
        refreshInstalledScript(paths: paths)

        let store = AgentBarStore(paths: paths)
        store.start()
        let settings = SettingsWindowController(store: store)
        let statusItem = StatusItemController(store: store)
        statusItem.openSettings = { settings.show() }

        self.store = store
        settingsController = settings
        statusItemController = statusItem
    }

    /// Se já estiver conectado, regrava o script: uma versão nova do app pode trazer um script novo.
    private func refreshInstalledScript(paths: ClaudePaths) {
        let installer = StatusLineInstaller(paths: paths)
        if (try? installer.state()) == .connected {
            try? installer.connect()
        }
    }
}
