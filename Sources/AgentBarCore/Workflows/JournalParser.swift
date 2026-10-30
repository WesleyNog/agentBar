import Foundation

/// Estado de um agente segundo o `journal.jsonl` do workflow.
struct JournalAgent: Equatable {
    let id: String
    var label: String?
    var phase: String?
    var state: AgentState
}

enum JournalParser {
    /// Agentes na ordem em que começaram. O último evento de cada agente define o estado.
    /// Linhas inválidas são ignoradas, inclusive a última quando ainda está sendo escrita.
    static func agents(in data: Data) -> [JournalAgent] {
        let decoder = JSONDecoder()
        var order: [String] = []
        var agents: [String: JournalAgent] = [:]

        for line in data.split(separator: 0x0A) {
            guard let event = try? decoder.decode(Event.self, from: Data(line)), let id = event.agentId else {
                continue
            }
            var agent = agents[id] ?? JournalAgent(id: id, state: .running)
            if agents[id] == nil { order.append(id) }
            if let label = event.label { agent.label = label }
            if let phase = event.phase { agent.phase = phase }
            switch event.type {
            case "started": agent.state = .running
            case "result": agent.state = .done
            case "failed", "error": agent.state = .failed
            default: break
            }
            agents[id] = agent
        }
        return order.compactMap { agents[$0] }
    }

    private struct Event: Decodable {
        let type: String?
        let agentId: String?
        let label: String?
        let phase: String?

        enum CodingKeys: String, CodingKey {
            case type, agentId, label, phase
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = container.lenient(.type)
            agentId = container.lenient(.agentId)
            label = container.lenient(.label)
            phase = container.lenient(.phase)
        }
    }
}
