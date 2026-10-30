import AgentBarCore
import SwiftUI

/// Workflows rodando e os que terminaram nas últimas 24 horas.
struct WorkflowListSection: View {
    let workflows: [WorkflowRun]
    let onSelect: (WorkflowRun) -> Void

    private static let rowHeight: CGFloat = 44
    private static let maxListHeight: CGFloat = 308

    var body: some View {
        let running = workflows.filter { $0.status == .running }.count

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Workflows")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(running) running · \(workflows.count - running) finished (24h)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)

            if workflows.isEmpty {
                Text("No workflows in the last 24 hours")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(workflows) { run in
                            WorkflowRow(run: run) { onSelect(run) }
                                .frame(height: Self.rowHeight)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(height: min(CGFloat(workflows.count) * Self.rowHeight, Self.maxListHeight))
            }
        }
    }
}

private struct WorkflowRow: View {
    let run: WorkflowRun
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                WorkflowStatusIcon(status: run.status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: run.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    WorkflowSummaryLine(run: run)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
