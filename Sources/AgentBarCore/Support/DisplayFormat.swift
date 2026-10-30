import Foundation

/// Formatos curtos no mesmo estilo do painel de workflows do Claude Code.
public enum DisplayFormat {
    /// `512`, `802.6k`, `1m`, `2.4m`.
    public static func tokens(_ count: Int) -> String {
        switch count {
        case ..<1_000: return "\(max(0, count))"
        case ..<999_950: return compact(Double(count) / 1_000) + "k"
        default: return compact(Double(count) / 1_000_000) + "m"
        }
    }

    /// `45s`, `16m 0s`, `3h 45m 43s`.
    public static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let seconds = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m \(seconds)s" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    /// Tempo até um reset, com as duas maiores unidades: `1d 12h`, `3h 35m`, `12m`, `<1m`.
    public static func countdown(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        let days = minutes / 1440
        let hours = minutes % 1440 / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    /// `claude-opus-5-5` → `Opus 5.5`. Formatos desconhecidos voltam como vieram.
    public static func modelName(_ model: String) -> String {
        var parts = model.split(separator: "-").map(String.init)
        guard parts.first == "claude", parts.count >= 3 else { return model }
        parts.removeFirst()
        // Sufixo de data, como em `claude-sonnet-4-5-20250929`.
        if let last = parts.last, last.count == 8, Int(last) != nil { parts.removeLast() }
        let family = parts.removeFirst()
        guard !parts.isEmpty, parts.allSatisfy({ Int($0) != nil }) else { return model }
        return family.prefix(1).uppercased() + family.dropFirst() + " " + parts.joined(separator: ".")
    }

    /// Uma casa decimal, sem `.0` no fim.
    private static func compact(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}
