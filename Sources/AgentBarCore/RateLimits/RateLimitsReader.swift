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

    /// Lê o arquivo salvo pelo status line. O "atualizado em" é a data de modificação do arquivo.
    public static func read(at url: URL) -> RateLimitsSnapshot? {
        guard let data = try? Data(contentsOf: url), let limits = decode(data) else { return nil }
        let modified = FileInfo.modificationDate(of: url) ?? .now
        return RateLimitsSnapshot(limits: limits, updatedAt: modified)
    }
}
