import Foundation

/// Lê um arquivo JSONL que só cresce, devolvendo a cada chamada apenas as linhas novas.
final class IncrementalLineReader {
    struct Chunk {
        let lines: [Data]
        /// O arquivo encolheu e a leitura recomeçou do início: descarte o que foi acumulado.
        let restarted: Bool
    }

    let url: URL
    private var offset: UInt64 = 0
    private var pending = Data()

    init(url: URL) {
        self.url = url
    }

    /// Linhas completas acrescentadas desde a última leitura. Uma linha sem `\n` no fim
    /// fica guardada até ser completada.
    func readNewLines() -> Chunk {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Chunk(lines: [], restarted: false) }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return Chunk(lines: [], restarted: false) }

        var restarted = false
        if size < offset {
            offset = 0
            pending.removeAll()
            restarted = true
        }
        guard size > offset else { return Chunk(lines: [], restarted: restarted) }

        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: Int(size - offset)) else {
                return Chunk(lines: [], restarted: restarted)
            }
            offset += UInt64(data.count)
            pending.append(data)
        } catch {
            return Chunk(lines: [], restarted: restarted)
        }

        guard let lastNewline = pending.lastIndex(of: 0x0A) else { return Chunk(lines: [], restarted: restarted) }
        let lines = pending[pending.startIndex..<lastNewline]
            .split(separator: 0x0A)
            .map { Data($0) }
        pending = Data(pending[pending.index(after: lastNewline)...])
        return Chunk(lines: lines, restarted: restarted)
    }
}
