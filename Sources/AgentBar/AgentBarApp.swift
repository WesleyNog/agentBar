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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // O Info.plist já tira o ícone do Dock; isto cobre o `swift run`, que roda sem bundle.
        NSApp.setActivationPolicy(.accessory)

        let store = AgentBarStore(paths: ClaudePaths.standard())
        store.start()
        self.store = store
        statusItemController = StatusItemController(store: store)
    }
}
