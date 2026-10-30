import AgentBarCore
import SwiftUI

// Peças compartilhadas pela lista e pelo detalhe dos workflows.

struct WorkflowStatusIcon: View {
    let status: WorkflowStatus

    var body: some View {
        Group {
            switch status {
            case .running:
                ProgressView().controlSize(.mini)
            case .completed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .stopped:
                Image(systemName: "stop.circle.fill").foregroundStyle(.secondary)
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .interrupted:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .other:
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            }
        }
        .frame(width: 16, height: 16)
        .help(status.title)
    }
}

struct AgentStateIcon: View {
    let state: AgentState

    var body: some View {
        Group {
            switch state {
            case .running:
                Image(systemName: "circle.fill").foregroundStyle(.blue).font(.system(size: 6))
            case .done:
                Image(systemName: "checkmark").foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark").foregroundStyle(.red)
            case .stopped:
                Image(systemName: "stop.fill").foregroundStyle(.secondary).font(.system(size: 7))
            }
        }
        .font(.caption.weight(.semibold))
        .frame(width: 14, height: 14)
    }
}

/// `projeto · 23m 49s · 3/6 agentes · 991.8k tok`. O tempo anda sozinho enquanto o workflow roda.
struct WorkflowSummaryLine: View {
    let run: WorkflowRun
    var includeStatus = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: run.status == .running ? 1 : 3600)) { context in
            Text(verbatim: parts(now: context.date).joined(separator: " · "))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func parts(now: Date) -> [String] {
        var parts: [String] = []
        if includeStatus { parts.append(run.status.title) }
        if let project = run.projectName { parts.append(project) }
        if let elapsed = run.elapsed(now: now) { parts.append(DisplayFormat.duration(elapsed)) }
        parts.append(String(localized: "\(run.doneAgentCount)/\(run.agents.count) agents"))
        parts.append("\(DisplayFormat.tokens(run.totalTokens)) tok")
        return parts
    }
}

extension WorkflowStatus {
    var title: String {
        switch self {
        case .running: String(localized: "Running")
        case .completed: String(localized: "Completed")
        case .stopped: String(localized: "Stopped")
        case .failed: String(localized: "Failed")
        case .interrupted: String(localized: "Interrupted")
        case .other(let raw): String(localized: "Unknown status: \(raw)")
        }
    }
}
