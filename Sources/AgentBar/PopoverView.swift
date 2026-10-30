import SwiftUI

/// Conteúdo do popover. Por enquanto só um marcador; uso e workflows entram no T9 e no T10.
struct PopoverView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AgentBar")
                .font(.headline)
            Text("Em construção")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }
}
