import AgentBarCore
import SwiftUI

/// Detalhe de um workflow: descrição, fases e cada agente.
struct WorkflowDetailView: View {
    let run: WorkflowRun
    let onBack: () -> Void

    private static let phaseHeaderHeight: CGFloat = 20
    private static let agentRowHeight: CGFloat = 32
    private static let sectionSpacing: CGFloat = 10
    private static let maxListHeight: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            header
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                    ForEach(sections, id: \.title) { section in
                        PhaseSection(section: section, headerHeight: Self.phaseHeaderHeight, rowHeight: Self.agentRowHeight)
                    }
                }
                .padding(14)
            }
            .frame(height: min(listHeight, Self.maxListHeight))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                WorkflowStatusIcon(status: run.status)
                Text(verbatim: run.name)
                    .font(.headline)
                    .lineLimit(2)
            }
            if let description = run.description {
                Text(verbatim: description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            WorkflowSummaryLine(run: run, includeStatus: true)
                .font(.caption)
                .foregroundStyle(.secondary)
            if run.status == .interrupted {
                Text("The session closed before the workflow finished.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if case .paused(let resetsAt) = run.status {
                Group {
                    if let resetsAt, resetsAt > .now {
                        Text("Paused at the usage limit. Resets \(ResetTime.format(resetsAt, now: .now)).")
                    } else {
                        Text("Paused at the usage limit.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Seções por fase

    fileprivate struct Section {
        let number: Int?
        let title: String
        let done: Int
        let agents: [WorkflowAgent]
    }

    private var sections: [Section] {
        var sections = run.phaseProgress.enumerated().map { index, progress in
            Section(
                number: index + 1,
                title: progress.phase.title,
                done: progress.done,
                agents: run.agents.filter { $0.phase == progress.phase.title }
            )
        }
        let withoutPhase = run.agents.filter { $0.phase == nil }
        if !withoutPhase.isEmpty || sections.isEmpty {
            sections.append(Section(
                number: nil,
                title: String(localized: "Agents"),
                done: withoutPhase.filter { $0.state == .done }.count,
                agents: withoutPhase
            ))
        }
        return sections
    }

    /// Altura exata do conteúdo, para o popover não sobrar nem cortar (as linhas têm altura fixa).
    private var listHeight: CGFloat {
        let sections = self.sections
        let rows = sections.reduce(0) { $0 + max($1.agents.count, 1) }
        return 28
            + CGFloat(sections.count) * Self.phaseHeaderHeight
            + CGFloat(rows) * Self.agentRowHeight
            + CGFloat(max(sections.count - 1, 0)) * Self.sectionSpacing
    }
}

private struct PhaseSection: View {
    let section: WorkflowDetailView.Section
    let headerHeight: CGFloat
    let rowHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let number = section.number {
                    Text(verbatim: "\(number)")
                        .foregroundStyle(.tertiary)
                }
                Text(verbatim: section.title)
                    .fontWeight(.semibold)
                Text(verbatim: "\(section.done)/\(section.agents.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
            }
            .font(.caption)
            .frame(height: headerHeight)

            if section.agents.isEmpty {
                Text("No agents yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(height: rowHeight)
            } else {
                ForEach(section.agents) { agent in
                    AgentRow(agent: agent)
                        .frame(height: rowHeight)
                }
            }
        }
    }
}

private struct AgentRow: View {
    let agent: WorkflowAgent

    var body: some View {
        HStack(spacing: 8) {
            AgentStateIcon(state: agent.state)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: agent.label)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                TimelineView(.periodic(from: .now, by: agent.state == .running ? 1 : 3600)) { context in
                    Text(verbatim: details(now: context.date).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func details(now: Date) -> [String] {
        var parts: [String] = []
        if let model = agent.model { parts.append(DisplayFormat.modelName(model)) }
        if let tokens = agent.tokens { parts.append("\(DisplayFormat.tokens(tokens)) tok") }
        if let start = agent.startedAt {
            parts.append(DisplayFormat.duration((agent.endedAt ?? now).timeIntervalSince(start)))
        }
        // Como no painel do Claude Code: "idle" quando o agente está há um tempo sem atividade.
        if agent.state == .running, let last = agent.lastActivityAt, now.timeIntervalSince(last) >= 30 {
            parts.append(String(localized: "idle \(DisplayFormat.duration(now.timeIntervalSince(last)))"))
        }
        return parts
    }
}
