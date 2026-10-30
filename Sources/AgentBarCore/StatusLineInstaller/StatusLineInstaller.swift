import Foundation

/// Conecta o AgentBar ao status line do Claude Code e desfaz a conexão.
///
/// Só mexe na chave `statusLine` do `settings.json`, sempre com backup antes.
/// O status line anterior fica guardado e continua rodando, encadeado pelo script.
public struct StatusLineInstaller: Sendable {
    public enum State: Sendable, Equatable {
        case connected
        /// Outro status line configurado (o comando vem como está no settings.json).
        case otherCommand(String)
        case notConfigured
    }

    public enum InstallError: Error, Equatable {
        /// O `settings.json` existe, mas não é um objeto JSON. Nada é alterado.
        case invalidSettings
    }

    public let paths: ClaudePaths

    public init(paths: ClaudePaths) {
        self.paths = paths
    }

    /// Comando gravado em `statusLine.command`.
    public var command: String {
        "'" + paths.statusLineScript.path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    public func state() throws -> State {
        let statusLine = try readSettings()["statusLine"] as? [String: Any]
        if isOurs(statusLine) { return .connected }
        if let command = statusLine?["command"] as? String, !command.isEmpty {
            return .otherCommand(command)
        }
        return .notConfigured
    }

    /// Instala o script e aponta o status line para ele. Se já estiver conectado,
    /// só regrava o script (útil quando uma versão nova do app traz um script novo).
    public func connect(now: Date = .now) throws {
        var settings = try readSettings()
        let current = settings["statusLine"] as? [String: Any]

        try FileManager.default.createDirectory(at: paths.agentBarDirectory, withIntermediateDirectories: true)
        try installScript()
        if isOurs(current) { return }

        try backupSettings(now: now)
        if let current {
            try jsonData(current).write(to: paths.previousStatusLineFile, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: paths.previousStatusLineFile)
        }

        // Mantém as outras opções do status line anterior, como `padding`.
        var statusLine = current ?? [:]
        statusLine["type"] = "command"
        statusLine["command"] = command
        settings["statusLine"] = statusLine
        try writeSettings(settings)
    }

    /// Volta o status line anterior (ou remove a chave, se não havia nenhum).
    /// Não faz nada se o status line atual não for o do AgentBar.
    public func disconnect() throws {
        var settings = try readSettings()
        guard isOurs(settings["statusLine"] as? [String: Any]) else { return }

        if let data = try? Data(contentsOf: paths.previousStatusLineFile),
           let previous = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings["statusLine"] = previous
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try writeSettings(settings)

        try? FileManager.default.removeItem(at: paths.previousStatusLineFile)
        try? FileManager.default.removeItem(at: paths.statusLineScript)
    }

    // MARK: - Detalhes

    private func isOurs(_ statusLine: [String: Any]?) -> Bool {
        guard let command = statusLine?["command"] as? String else { return false }
        return command.contains(paths.statusLineScript.path)
    }

    private func installScript() throws {
        try Data(StatusLineScript.contents.utf8).write(to: paths.statusLineScript, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.statusLineScript.path)
    }

    private func readSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: paths.settingsFile) else { return [:] }
        if data.allSatisfy({ [0x20, 0x09, 0x0A, 0x0D].contains($0) }) { return [:] }
        guard let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw InstallError.invalidSettings
        }
        return settings
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        // Grava no destino do link, para não trocar um settings.json linkado (dotfiles) por um arquivo comum.
        let target = paths.settingsFile.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jsonData(settings).write(to: target, options: .atomic)
    }

    private func backupSettings(now: Date) throws {
        guard FileInfo.exists(paths.settingsFile) else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = paths.backupsDirectory.appendingPathComponent("settings-\(formatter.string(from: now)).json")

        try FileManager.default.createDirectory(at: paths.backupsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.copyItem(at: paths.settingsFile.resolvingSymlinksInPath(), to: backup)
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        return data
    }
}
