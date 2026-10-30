import AgentBarCore
import SwiftUI

/// Sessão (5h) e semana (7d), cada uma com barra, porcentagem e reset.
struct UsageSection: View {
    let snapshot: AgentBarSnapshot
    let onConnect: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 12) {
                if let rateLimits = snapshot.rateLimits {
                    WindowRow(title: "Current session (5h)", window: rateLimits.limits.fiveHour, now: context.date)
                    WindowRow(title: "This week (all models)", window: rateLimits.limits.sevenDay, now: context.date)
                    Text("Updated \(rateLimits.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch snapshot.statusLine {
        case .connected:
            Label("Waiting for Claude Code. Your limits show up after the next reply in any session.", systemImage: "hourglass")
                .font(.callout)
                .foregroundStyle(.secondary)
        case nil:
            Label("Couldn't read ~/.claude/settings.json. Check that it's valid JSON.", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        case .otherCommand, .notConfigured:
            VStack(alignment: .leading, spacing: 8) {
                Label("Connect AgentBar to Claude Code to see your usage limits.", systemImage: "gauge.with.dots.needle.33percent")
                    .font(.callout)
                Button("Connect…", action: onConnect)
            }
        }
    }
}

private struct WindowRow: View {
    let title: LocalizedStringKey
    let window: RateLimitWindow?
    let now: Date

    var body: some View {
        let percentage = window?.effectivePercentage(now: now)
        let level = UsageLevel(percentage: percentage ?? 0)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: PercentFormat.short(percentage))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(percentage == nil ? .secondary : level.color)
            }
            ProgressView(value: min(max(percentage ?? 0, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .tint(level.tint)
            if let window {
                resetText(window)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func resetText(_ window: RateLimitWindow) -> Text {
        let time = ResetTime.format(window.resetsAt, now: now)
        guard window.resetsAt > now else { return Text("Reset \(time)") }
        return Text("Resets \(time) · in \(DisplayFormat.countdown(window.resetsAt.timeIntervalSince(now)))")
    }
}

enum ResetTime {
    /// Só a hora quando é hoje; senão dia da semana, data e hora.
    static func format(_ date: Date, now: Date) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits).hour().minute())
    }
}
