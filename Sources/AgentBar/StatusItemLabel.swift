import AgentBarCore
import SwiftUI

/// Rótulo da barra de menus: sessão (5h) em cima e semana (7d) embaixo, no estilo do CPU/MEM.
struct StatusItemLabel: View {
    let session: Double?
    let week: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: -1) {
            row(title: "5h", percentage: session)
            row(title: "7d", percentage: week)
        }
        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
        .padding(.horizontal, 5)
        .frame(maxHeight: .infinity)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func row(title: String, percentage: Double?) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(PercentFormat.short(percentage))
                .foregroundStyle(color(for: percentage))
                .frame(minWidth: 26, alignment: .trailing)
        }
    }

    private func color(for percentage: Double?) -> Color {
        guard let percentage else { return .secondary }
        switch UsageLevel(percentage: percentage) {
        case .normal: return .primary
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
