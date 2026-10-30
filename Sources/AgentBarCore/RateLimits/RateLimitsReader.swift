import Foundation

public enum RateLimitsReader {
    /// `nil` quando o JSON é inválido ou não traz nenhuma janela reconhecível.
    public static func decode(_ data: Data) -> RateLimits? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let limits = try? decoder.decode(RateLimits.self, from: data),
              limits.fiveHour != nil || limits.sevenDay != nil
        else { return nil }
        return limits
    }

    /// Lê um arquivo salvo pelo status line. O "atualizado em" é a data de modificação do arquivo.
    public static func read(at url: URL) -> RateLimitsSnapshot? {
        guard let data = try? Data(contentsOf: url), let limits = decode(data) else { return nil }
        let modified = FileInfo.modificationDate(of: url) ?? .now
        return RateLimitsSnapshot(limits: limits, updatedAt: modified)
    }

    /// Lê os arquivos de todas as sessões (e o arquivo único antigo, se existir) e junta.
    public static func readMerged(directory: URL, legacyFile: URL? = nil) -> RateLimitsSnapshot? {
        var files = FileInfo.contents(of: directory).filter { $0.pathExtension == "json" }
        if let legacyFile { files.append(legacyFile) }
        return merge(files.compactMap(read(at:)))
    }

    /// Cada sessão aberta do Claude Code manda os limites da sua última resposta, então
    /// uma sessão parada reenvia números antigos. Como o uso só cresce até o reset, vence
    /// a janela mais nova e, dentro dela, o maior uso.
    public static func merge(_ snapshots: [RateLimitsSnapshot]) -> RateLimitsSnapshot? {
        let fiveHour = freshest(snapshots.compactMap { snapshot in snapshot.limits.fiveHour.map { ($0, snapshot.updatedAt) } })
        let sevenDay = freshest(snapshots.compactMap { snapshot in snapshot.limits.sevenDay.map { ($0, snapshot.updatedAt) } })
        guard let updatedAt = [fiveHour?.updatedAt, sevenDay?.updatedAt].compactMap({ $0 }).max() else { return nil }
        return RateLimitsSnapshot(
            limits: RateLimits(fiveHour: fiveHour?.window, sevenDay: sevenDay?.window),
            updatedAt: updatedAt
        )
    }

    /// Resets com menos de 1 hora de diferença contam como a mesma janela.
    private static func freshest(
        _ candidates: [(window: RateLimitWindow, updatedAt: Date)]
    ) -> (window: RateLimitWindow, updatedAt: Date)? {
        guard let latestReset = candidates.map(\.window.resetsAt).max() else { return nil }
        return candidates
            .filter { latestReset.timeIntervalSince($0.window.resetsAt) < 3600 }
            .max { ($0.window.usedPercentage, $0.updatedAt) < ($1.window.usedPercentage, $1.updatedAt) }
    }
}
