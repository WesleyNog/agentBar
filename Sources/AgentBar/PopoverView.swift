import AgentBarCore
import Observation
import SwiftUI

/// Estado de navegação do popover: a lista ou o detalhe de um workflow.
@MainActor
@Observable
final class PopoverState {
    var selectedRunID: String?
}

struct PopoverActions {
    let openSettings: @MainActor () -> Void
    let quit: @MainActor () -> Void
}

struct PopoverView: View {
    let store: AgentBarStore
    let state: PopoverState
    let actions: PopoverActions

    var body: some View {
        Group {
            if let id = state.selectedRunID, let run = store.snapshot.workflows.first(where: { $0.id == id }) {
                WorkflowDetailView(run: run) { state.selectedRunID = nil }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    UsageSection(snapshot: store.snapshot, onConnect: actions.openSettings)
                        .padding(14)
                    Divider()
                    WorkflowListSection(workflows: store.snapshot.workflows) { state.selectedRunID = $0.id }
                        .padding(.vertical, 10)
                    Divider()
                    footer
                }
            }
        }
        .frame(width: 360)
    }

    private var footer: some View {
        HStack {
            Button("Settings…", action: actions.openSettings)
            Spacer()
            Button("Quit", action: actions.quit)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
