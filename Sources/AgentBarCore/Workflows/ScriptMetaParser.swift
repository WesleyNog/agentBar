import Foundation

/// O `export const meta = {...}` de um script de workflow.
public struct WorkflowScriptMeta: Sendable, Equatable {
    public var name: String?
    public var description: String?
    public var phases: [WorkflowPhase]

    public init(name: String? = nil, description: String? = nil, phases: [WorkflowPhase] = []) {
        self.name = name
        self.description = description
        self.phases = phases
    }
}

public enum ScriptMetaParser {
    /// `nil` se o script não tiver um `meta` legível.
    public static func parse(_ source: String) -> WorkflowScriptMeta? {
        guard let start = source.range(of: #"export\s+const\s+meta\s*=\s*"#, options: .regularExpression) else {
            return nil
        }
        var parser = JSLiteralParser(source[start.upperBound...].utf8)
        guard let meta = (try? parser.parseValue())?.objectValue else { return nil }

        let phases: [WorkflowPhase] = (meta["phases"]?.arrayValue ?? []).compactMap { value in
            guard let phase = value.objectValue, let title = phase["title"]?.stringValue else { return nil }
            return WorkflowPhase(title: title, detail: phase["detail"]?.stringValue)
        }
        return WorkflowScriptMeta(
            name: meta["name"]?.stringValue,
            description: meta["description"]?.stringValue,
            phases: phases
        )
    }

    /// Nome a partir do arquivo `<nome>-<runId>.js`, para quando o `meta` não tem nome.
    static func name(fromScriptFile fileName: String, runId: String) -> String? {
        let suffix = "-\(runId).js"
        guard fileName.hasSuffix(suffix), fileName.count > suffix.count else { return nil }
        return String(fileName.dropLast(suffix.count))
    }
}
