import Foundation
import Testing
@testable import AgentBarCore

@Suite("JSONTopLevelEditor")
struct JSONTopLevelEditorTests {
    private let ours: [String: Any] = ["type": "command", "command": "'/u/.claude/agentbar/statusline.sh'"]

    @Test func trocaSoOValorEMantemOResto() throws {
        let original = """
        {
          "worktree": {
            "baseRef": "fresh"
          },
          "statusLine": {
            "type": "command",
            "command": "~/.claude/widgets/save.sh"
          },
          "theme": "dark"
        }
        """

        let edited = try #require(JSONTopLevelEditor.setting("statusLine", to: ours, in: original))

        #expect(edited == """
        {
          "worktree": {
            "baseRef": "fresh"
          },
          "statusLine": {
            "type": "command",
            "command": "'/u/.claude/agentbar/statusline.sh'"
          },
          "theme": "dark"
        }
        """)
    }

    @Test func insereERemoveVoltandoAoTextoOriginal() throws {
        let original = "{\n\t\"theme\": \"dark\"\n}\n"

        let inserted = try #require(JSONTopLevelEditor.setting("statusLine", to: ours, in: original))
        #expect(inserted == "{\n\t\"theme\": \"dark\",\n\t\"statusLine\": {\n\t\t\"type\": \"command\",\n\t\t\"command\": \"'/u/.claude/agentbar/statusline.sh'\"\n\t}\n}\n")

        #expect(JSONTopLevelEditor.setting("statusLine", to: nil, in: inserted) == original)
    }

    @Test func removerDoMeioLevaAVirgulaCerta() throws {
        let original = "{\n  \"a\": 1,\n  \"statusLine\": {\"type\": \"command\"},\n  \"b\": [1, 2]\n}"

        #expect(JSONTopLevelEditor.setting("statusLine", to: nil, in: original) == "{\n  \"a\": 1,\n  \"b\": [1, 2]\n}")
    }

    @Test func jsonNumaLinhaSo() throws {
        let original = #"{"model":"opus"}"#

        let inserted = try #require(JSONTopLevelEditor.setting("statusLine", to: ["type": "command"], in: original))
        #expect(inserted == #"{"model":"opus", "statusLine": {"type": "command"}}"#)
        #expect(JSONTopLevelEditor.setting("statusLine", to: nil, in: inserted) == original)
    }

    @Test func objetoVazio() throws {
        #expect(JSONTopLevelEditor.setting("statusLine", to: ["type": "command"], in: "{}") == "{\n  \"statusLine\": {\n    \"type\": \"command\"\n  }\n}")
    }

    @Test func stringsComChavesEAspasNaoConfundemOEditor() throws {
        let original = #"""
        {
          "permissions": {"allow": ["Bash(echo \"}\" {)", "Read(**/*.swift)"]},
          "na\"me": "valor, com vírgula",
          "statusLine": {"type": "command", "command": "echo \"oi\""}
        }
        """#

        let edited = try #require(JSONTopLevelEditor.setting("statusLine", to: nil, in: original))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(edited.utf8)) as? NSDictionary)

        #expect(object["statusLine"] == nil)
        #expect(object["na\"me"] as? String == "valor, com vírgula")
        #expect((object["permissions"] as? NSDictionary)?["allow"] as? [String] == [#"Bash(echo "}" {)"#, "Read(**/*.swift)"])
    }

    @Test(arguments: ["", "[]", "{\"a\": 1,}", "{\"a\" 1}", "{\"a\": 1} lixo", "{\"a\": \"sem fim}"])
    func textoQueNaoSabePercorrerViraNil(text: String) {
        #expect(JSONTopLevelEditor.setting("statusLine", to: ["type": "command"], in: text) == nil)
    }
}

@Suite("StatusLineInstaller · formatação")
struct StatusLineInstallerFormattingTests {
    @Test func conectarEDesconectarDevolvemOTextoOriginal() throws {
        let dir = try TempDirectory()
        defer { dir.remove() }
        let original = """
        {
          "worktree": {
            "baseRef": "fresh"
          },
          "statusLine": {
            "type": "command",
            "command": "~/.claude/widgets/save_rate_limits.sh"
          },
          "enabledPlugins": {
            "agent-skills@addy-agent-skills": true
          },
          "theme": "dark"
        }

        """
        try dir.write(original, to: "settings.json")
        let installer = StatusLineInstaller(paths: ClaudePaths(root: dir.url))

        try installer.connect()
        let connected = try dir.read("settings.json")
        #expect(connected.components(separatedBy: "\n").count == original.components(separatedBy: "\n").count)
        #expect(connected.contains(#""command": "\#(installer.command)""#))

        try installer.disconnect()
        #expect(try dir.read("settings.json") == original)
    }
}
