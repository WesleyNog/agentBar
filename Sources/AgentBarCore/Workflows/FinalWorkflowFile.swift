import Foundation

/// O `workflows/<runId>.json` que o Claude Code grava quando o workflow termina.
/// Só os campos que o AgentBar usa; o resto (script, result, logs) é ignorado.
struct FinalWorkflowFile: Decodable {
    let workflowName: String?
    let status: String?
    let startTime: Double?
    let durationMs: Double?
    let timestamp: String?
    let phases: [Phase]
    let progress: [Progress]
    let script: String?

    struct Phase: Decodable {
        let title: String?
        let detail: String?

        enum CodingKeys: String, CodingKey { case title, detail }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = container.lenient(.title)
            detail = container.lenient(.detail)
        }
    }

    /// Item de `workflowProgress`: uma fase (`workflow_phase`) ou um agente (`workflow_agent`).
    struct Progress: Decodable {
        let type: String?
        let agentId: String?
        let label: String?
        let phaseTitle: String?
        let model: String?
        let state: String?
        let tokens: Int?
        let startedAt: Double?
        let durationMs: Double?
        let lastProgressAt: Double?

        enum CodingKeys: String, CodingKey {
            case type, agentId, label, phaseTitle, model, state, tokens, startedAt, durationMs, lastProgressAt
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = container.lenient(.type)
            agentId = container.lenient(.agentId)
            label = container.lenient(.label)
            phaseTitle = container.lenient(.phaseTitle)
            model = container.lenient(.model)
            state = container.lenient(.state)
            tokens = container.lenient(.tokens)
            startedAt = container.lenient(.startedAt)
            durationMs = container.lenient(.durationMs)
            lastProgressAt = container.lenient(.lastProgressAt)
        }
    }

    enum CodingKeys: String, CodingKey {
        case workflowName, status, startTime, durationMs, timestamp, phases, script
        case progress = "workflowProgress"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workflowName = container.lenient(.workflowName)
        status = container.lenient(.status)
        startTime = container.lenient(.startTime)
        durationMs = container.lenient(.durationMs)
        timestamp = container.lenient(.timestamp)
        phases = container.lenient(.phases, as: LossyArray<Phase>.self)?.elements ?? []
        progress = container.lenient(.progress, as: LossyArray<Progress>.self)?.elements ?? []
        script = container.lenient(.script)
    }
}
