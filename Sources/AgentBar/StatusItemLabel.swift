import AgentBarCore
import SwiftUI

/// Rótulo da barra de menus: sessão (5h) em cima e semana (7d) embaixo, no estilo do CPU/MEM.
struct StatusItemLabel: View {
    let store: AgentBarStore

    var body: some View {
        // A cada minuto, para uma janela que resetou voltar a 0% mesmo sem leitura nova.
        TimelineView(.everyMinute) { context in
            let limits = store.snapshot.rateLimits?.limits
            VStack(alignment: .leading, spacing: -1) {
                row(title: "5h", percentage: limits?.fiveHour?.effectivePercentage(now: context.date))
                row(title: "7d", percentage: limits?.sevenDay?.effectivePercentage(now: context.date))
            }
        }
        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
        .padding(.horizontal, 5)
        .frame(maxHeight: .infinity)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func row(title: String, percentage: Double?) -> some View {
        HStack(spacing: 3) {
            Text(verbatim: title)
                .foregroundStyle(.secondary)
            Text(verbatim: PercentFormat.short(percentage))
                .foregroundStyle(percentage.map { UsageLevel(percentage: $0).color } ?? .secondary)
                .frame(minWidth: 26, alignment: .trailing)
        }
    }
}

extension UsageLevel {
    var color: Color {
        switch self {
        case .normal: .primary
        case .warning: .orange
        case .critical: .red
        }
    }

    /// Cor da barra de progresso no popover, onde `.primary` ficaria apagado demais.
    var tint: Color {
        self == .normal ? .accentColor : color
    }
}
