import Foundation

/// O que interessa do transcript de um agente (`agent-<id>.jsonl`).
public struct AgentTranscriptSummary: Sendable, Equatable {
    public var model: String?
    /// Tamanho do contexto na última resposta: `input + cache_creation + cache_read`.
    /// É o número que o Claude Code mostra como "tok" de cada agente.
    public var contextTokens: Int?
    public var firstTimestamp: Date?
    public var lastTimestamp: Date?
    public var cwd: String?

    public init() {}
}

/// Mantém o resumo de um transcript em dia, lendo só as linhas novas a cada `refresh()`.
final class AgentTranscriptReader {
    private let lines: IncrementalLineReader
    private let decoder = JSONDecoder()
    private(set) var summary = AgentTranscriptSummary()

    init(url: URL) {
        lines = IncrementalLineReader(url: url)
    }

    @discardableResult
    func refresh() -> AgentTranscriptSummary {
        let chunk = lines.readNewLines()
        if chunk.restarted { summary = AgentTranscriptSummary() }
        for line in chunk.lines { apply(line) }
        return summary
    }

    private func apply(_ line: Data) {
        guard let entry = try? decoder.decode(Line.self, from: line) else { return }

        if let timestamp = entry.timestamp.flatMap(Timestamps.parseISO8601) {
            if summary.firstTimestamp == nil { summary.firstTimestamp = timestamp }
            summary.lastTimestamp = timestamp
        }
        if summary.cwd == nil, let cwd = entry.cwd { summary.cwd = cwd }

        // Respostas sintéticas (`<synthetic>`) não vêm da API e trazem uso zerado.
        guard entry.type == "assistant", let message = entry.message,
              let model = message.model, !model.hasPrefix("<")
        else { return }
        summary.model = model
        if let usage = message.usage {
            summary.contextTokens = usage.input + usage.cacheCreation + usage.cacheRead
        }
    }

    private struct Line: Decodable {
        let type: String?
        let timestamp: String?
        let cwd: String?
        let message: Message?

        enum CodingKeys: String, CodingKey { case type, timestamp, cwd, message }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = container.lenient(.type)
            timestamp = container.lenient(.timestamp)
            cwd = container.lenient(.cwd)
            message = container.lenient(.message)
        }
    }

    private struct Message: Decodable {
        let model: String?
        let usage: Usage?

        enum CodingKeys: String, CodingKey { case model, usage }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            model = container.lenient(.model)
            usage = container.lenient(.usage)
        }
    }

    private struct Usage: Decodable {
        let input: Int
        let cacheCreation: Int
        let cacheRead: Int

        enum CodingKeys: String, CodingKey {
            case input = "input_tokens"
            case cacheCreation = "cache_creation_input_tokens"
            case cacheRead = "cache_read_input_tokens"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            input = container.lenient(.input) ?? 0
            cacheCreation = container.lenient(.cacheCreation) ?? 0
            cacheRead = container.lenient(.cacheRead) ?? 0
        }
    }
}
