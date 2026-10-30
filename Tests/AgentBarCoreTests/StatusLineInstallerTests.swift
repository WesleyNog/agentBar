import Foundation
import Testing
@testable import AgentBarCore

@Suite("StatusLineInstaller")
struct StatusLineInstallerTests {
    private static let now = Date(timeIntervalSince1970: 1_793_326_000)

    private func settings(in dir: TempDirectory) throws -> NSDictionary {
        let data = try Data(contentsOf: dir.url.appendingPathComponent("settings.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    private func json(_ string: String) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: Data(string.utf8)) as? NSDictionary)
    }

    @Test func conectaSemSettingsExistente() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let installer = StatusLineInstaller(paths: ClaudePaths(root: dir.url))

        #expect(try installer.state() == .notConfigured)
        try installer.connect(now: Self.now)

        #expect(try installer.state() == .connected)
        #expect(dir.exists("agentbar/statusline.sh"))
        #expect(!dir.exists("agentbar/previous-statusline.json"))
        #expect(!dir.exists("agentbar/backups"))
        let statusLine = try #require(try settings(in: dir)["statusLine"] as? NSDictionary)
        #expect(statusLine["command"] as? String == installer.command)
    }

    @Test func guardaOAnteriorEPreservaOResto() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let original = """
        {
          "model": "opus",
          "permissions": {"allow": ["Bash(git status)"]},
          "statusLine": {"type": "command", "command": "~/.claude/widgets/save.sh", "padding": 2}
        }
        """
        try dir.write(original, to: "settings.json")
        let installer = StatusLineInstaller(paths: ClaudePaths(root: dir.url))

        #expect(try installer.state() == .otherCommand("~/.claude/widgets/save.sh"))
        try installer.connect(now: Self.now)

        let after = try settings(in: dir)
        #expect(after["model"] as? String == "opus")
        #expect(after["permissions"] as? NSDictionary == ["allow": ["Bash(git status)"]])
        let statusLine = try #require(after["statusLine"] as? NSDictionary)
        #expect(statusLine["command"] as? String == installer.command)
        #expect(statusLine["padding"] as? Int == 2)

        let previous = try json(dir.read("agentbar/previous-statusline.json"))
        #expect(previous["command"] as? String == "~/.claude/widgets/save.sh")
        #expect(try dir.read("agentbar/backups/settings-\(backupStamp(Self.now)).json") == original)
    }

    @Test func desconectarRestauraOOriginal() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write(#"{"model":"opus","statusLine":{"type":"command","command":"echo oi","padding":0}}"#, to: "settings.json")
        let before = try settings(in: dir)
        let installer = StatusLineInstaller(paths: ClaudePaths(root: dir.url))

        try installer.connect(now: Self.now)
        try installer.disconnect()

        #expect(try settings(in: dir) == before)
        #expect(try installer.state() == .otherCommand("echo oi"))
        #expect(!dir.exists("agentbar/statusline.sh"))
        #expect(!dir.exists("agentbar/previous-statusline.json"))
    }

    @Test func desconectarSemAnteriorRemoveAChave() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write(#"{"model":"opus"}"#, to: "settings.json")
        let installer = StatusLineInstaller(paths: ClaudePaths(root: dir.url))

        try installer.connect(now: Self.now)
        try installer.disconnect()

        #expect(try settings(in: dir) == ["model": "opus"])
    }

    @Test func conectarDuasVezesNaoGuardaOProprioComandoComoAnterior() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write(#"{"statusLine":{"type":"command","command":"echo oi"}}"#, to: "settings.json")
        let installer = StatusLineInstaller(paths: ClaudePaths(root: dir.url))

        try installer.connect(now: Self.now)
        try installer.connect(now: Self.now.addingTimeInterval(60))
        try installer.disconnect()

        #expect(try installer.state() == .otherCommand("echo oi"))
    }

    @Test func desconectarNaoMexeEmStatusLineDeOutro() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let original = #"{"statusLine":{"type":"command","command":"echo oi"}}"#
        try dir.write(original, to: "settings.json")

        try StatusLineInstaller(paths: ClaudePaths(root: dir.url)).disconnect()

        #expect(try dir.read("settings.json") == original)
    }

    @Test func settingsInvalidoNaoEAlterado() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let original = #"{"model": "opus",,}"#
        try dir.write(original, to: "settings.json")
        let installer = StatusLineInstaller(paths: ClaudePaths(root: dir.url))

        #expect(throws: StatusLineInstaller.InstallError.invalidSettings) {
            try installer.connect(now: Self.now)
        }
        #expect(try dir.read("settings.json") == original)
    }

    @Test func settingsLinkadoContinuaSendoLink() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let real = try dir.write(#"{"model":"opus"}"#, to: "dotfiles/settings.json")
        let root = dir.url.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let installer = StatusLineInstaller(paths: ClaudePaths(root: root))

        try installer.connect(now: Self.now)

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == real.path)
        #expect(try installer.state() == .connected)
    }

    @Test func comandoComAspasNoCaminho() {
        let installer = StatusLineInstaller(paths: ClaudePaths(root: URL(fileURLWithPath: "/tmp/it's here/.claude")))
        #expect(installer.command == #"'/tmp/it'\''s here/.claude/agentbar/statusline.sh'"#)
    }

    private func backupStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

@Suite("StatusLineScript")
struct StatusLineScriptTests {
    private static let input = #"{"session_id":"sessao-1","model":{"id":"claude-opus-5-5"},"rate_limits":{"five_hour":{"used_percentage":27,"resets_at":1793339400}}}"#

    /// Instala o script numa pasta temporária e o executa como o Claude Code faria.
    private func run(previousCommand: String?, input: String = Self.input, in dir: TempDirectory) throws -> String {
        let paths = ClaudePaths(root: dir.url)
        if let previousCommand {
            let previous = try JSONSerialization.data(withJSONObject: ["type": "command", "command": previousCommand])
            try dir.write(#"{"statusLine":\#(String(decoding: previous, as: UTF8.self))}"#, to: "settings.json")
        }
        try StatusLineInstaller(paths: paths).connect()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", StatusLineInstaller(paths: paths).command]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: output, as: UTF8.self)
    }

    @Test func salvaOsLimitesERepassaAEntrada() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }

        let output = try run(previousCommand: "plutil -extract model.id raw -o - -", in: dir)

        #expect(output.trimmingCharacters(in: .newlines) == "claude-opus-5-5")
        let saved = try #require(RateLimitsReader.decode(Data(try dir.read("agentbar/rate_limits/sessao-1.json").utf8)))
        #expect(saved.fiveHour?.usedPercentage == 27)
    }

    @Test func semAnteriorNaoImprimeNada() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }

        let output = try run(previousCommand: nil, in: dir)

        #expect(output.isEmpty)
        #expect(dir.exists("agentbar/rate_limits/sessao-1.json"))
    }

    @Test func entradaSemLimitesMantemOArquivoAnterior() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        _ = try run(previousCommand: nil, in: dir)
        let before = try dir.read("agentbar/rate_limits/sessao-1.json")

        _ = try run(previousCommand: nil, input: #"{"session_id":"sessao-1","model":{"id":"x"}}"#, in: dir)

        #expect(try dir.read("agentbar/rate_limits/sessao-1.json") == before)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.url.appendingPathComponent("agentbar/rate_limits").path)
            .filter { $0.hasPrefix(".tmp") }
        #expect(leftovers.isEmpty)
    }

    @Test func semSessionIdUsaUmNomeFixoEApagaOArquivoAntigo() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        try dir.write("{}", to: "agentbar/rate_limits.json")

        _ = try run(previousCommand: nil, input: #"{"rate_limits":{"seven_day":{"used_percentage":5,"resets_at":1793458800}}}"#, in: dir)

        #expect(dir.exists("agentbar/rate_limits/sem-sessao.json"))
        #expect(!dir.exists("agentbar/rate_limits.json"))
    }
}
