import AgentBarCore
import Foundation
import ServiceManagement

/// Preferências guardadas no UserDefaults.
enum AppPreferences {
    private static let claudeDirectoryKey = "claudeDirectory"

    /// Pasta escolhida nos ajustes; sem escolha, `CLAUDE_CONFIG_DIR` ou `~/.claude`.
    static var claudePaths: ClaudePaths {
        guard let path = UserDefaults.standard.string(forKey: claudeDirectoryKey), !path.isEmpty else {
            return .standard()
        }
        return ClaudePaths(root: URL(fileURLWithPath: path, isDirectory: true))
    }

    static var hasCustomClaudeDirectory: Bool {
        UserDefaults.standard.string(forKey: claudeDirectoryKey) != nil
    }

    static func setClaudeDirectory(_ url: URL?) {
        if let url {
            UserDefaults.standard.set(url.path, forKey: claudeDirectoryKey)
        } else {
            UserDefaults.standard.removeObject(forKey: claudeDirectoryKey)
        }
    }
}

/// Abrir ao iniciar a sessão do Mac.
enum LoginItem {
    /// Só funciona com o app empacotado; no `swift run` não há bundle para registrar.
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
