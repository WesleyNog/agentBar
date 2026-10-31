/// Faixa de consumo de uma janela de limite, usada para colorir os números.
public enum UsageLevel: Sendable, Equatable {
    case normal
    case warning
    case critical

    public init(percentage: Double) {
        switch percentage {
        case 90...: self = .critical
        case 70..<90: self = .warning
        default: self = .normal
        }
    }
}

public enum PercentFormat {
    /// O texto mais largo que `short` produz. A barra de menus reserva espaço para ele.
    public static let widest = "100%"

    /// Texto curto para a barra de menus: `27%`, ou `--` sem dados.
    /// Arredonda para baixo, como o status line do Claude Code, e fica entre 0% e 100%.
    public static func short(_ percentage: Double?) -> String {
        guard let percentage, percentage.isFinite else { return "--" }
        return "\(Int(min(100, max(0, percentage)).rounded(.down)))%"
    }
}
