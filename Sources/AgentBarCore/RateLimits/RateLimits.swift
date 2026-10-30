import Foundation

/// Uma janela de limite, como o Claude Code entrega no status line.
public struct RateLimitWindow: Decodable, Sendable, Equatable {
    public let usedPercentage: Double
    public let resetsAt: Date

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    public init(usedPercentage: Double, resetsAt: Date) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    /// Depois do reset, o valor salvo deixa de valer: a janela recomeçou do zero.
    public func effectivePercentage(now: Date = .now) -> Double {
        now >= resetsAt ? 0 : usedPercentage
    }
}

/// O objeto `rate_limits` do status line: sessão de 5 horas e semana.
public struct RateLimits: Decodable, Sendable, Equatable {
    public let fiveHour: RateLimitWindow?
    public let sevenDay: RateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    public init(fiveHour: RateLimitWindow?, sevenDay: RateLimitWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    /// Uma janela malformada não derruba a outra.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try? container.decodeIfPresent(RateLimitWindow.self, forKey: .fiveHour)
        sevenDay = try? container.decodeIfPresent(RateLimitWindow.self, forKey: .sevenDay)
    }
}

/// Limites lidos do disco, com a hora em que o status line os gravou.
public struct RateLimitsSnapshot: Sendable, Equatable {
    public let limits: RateLimits
    public let updatedAt: Date

    public init(limits: RateLimits, updatedAt: Date) {
        self.limits = limits
        self.updatedAt = updatedAt
    }
}
