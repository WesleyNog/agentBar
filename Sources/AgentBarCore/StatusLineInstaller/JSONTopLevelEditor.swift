import Foundation

/// Troca o valor de uma chave de topo de um objeto JSON mexendo só no trecho dessa chave,
/// para não reordenar nem reformatar o resto do arquivo de quem instala.
enum JSONTopLevelEditor {
    /// Texto com `key` trocada por `value` (ou removida, se `value` for `nil`).
    /// `nil` se o texto não for um objeto JSON que o editor saiba percorrer.
    static func setting(_ key: String, to value: [String: Any]?, in text: String) -> String? {
        var bytes = Array(text.utf8)
        guard let layout = ObjectLayout(bytes: bytes) else { return nil }
        let indent = layout.indent(in: bytes)

        if let index = layout.pairs.firstIndex(where: { $0.key == key }) {
            let pair = layout.pairs[index]
            if let value {
                bytes.replaceSubrange(pair.valueStart..<pair.valueEnd, with: serialize(value, indent: indent))
            } else {
                bytes.removeSubrange(layout.removalRange(ofPairAt: index))
            }
        } else if let value {
            let entry = Array("\"\(key)\": ".utf8) + serialize(value, indent: indent)
            if let last = layout.pairs.last {
                let separator = Array(",".utf8) + (indent.map { Array("\n\($0)".utf8) } ?? Array(" ".utf8))
                bytes.insert(contentsOf: separator + entry, at: last.valueEnd)
            } else {
                let opening = indent.map { Array("\n\($0)".utf8) } ?? []
                let closing = indent == nil ? [] : Array("\n".utf8)
                bytes.insert(contentsOf: opening + entry + closing, at: layout.openBrace + 1)
            }
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// Objeto com `type` e `command` primeiro, como o Claude Code escreve.
    /// Com `indent`, uma chave por linha; sem, tudo numa linha só.
    private static func serialize(_ object: [String: Any], indent: String?) -> [UInt8] {
        let preferred = ["type", "command"]
        let keys = preferred.filter { object[$0] != nil } + object.keys.filter { !preferred.contains($0) }.sorted()
        let entries = keys.compactMap { key -> String? in
            guard let value = object[key],
                  let keyData = try? JSONSerialization.data(withJSONObject: key, options: .fragmentsAllowed),
                  let valueData = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
            else { return nil }
            return String(decoding: keyData, as: UTF8.self) + ": " + String(decoding: valueData, as: UTF8.self)
        }
        guard let indent else { return Array("{\(entries.joined(separator: ", "))}".utf8) }
        let inner = indent + indent
        return Array("{\n\(entries.map { inner + $0 }.joined(separator: ",\n"))\n\(indent)}".utf8)
    }
}

/// Posições das chaves de topo de um objeto JSON, em bytes UTF-8.
private struct ObjectLayout {
    struct Pair {
        let key: String
        /// Onde começa o espaço antes da chave (logo depois de `{` ou `,`).
        let leadingStart: Int
        let keyStart: Int
        let valueStart: Int
        let valueEnd: Int
        /// Posição da vírgula depois do valor, se houver.
        let comma: Int?
    }

    let openBrace: Int
    let closeBrace: Int
    let pairs: [Pair]

    init?(bytes: [UInt8]) {
        var scanner = JSONScanner(bytes: bytes)
        scanner.skipWhitespace()
        guard scanner.peek() == UInt8(ascii: "{") else { return nil }
        openBrace = scanner.index
        scanner.index += 1

        var pairs: [Pair] = []
        var closeBrace: Int?
        while closeBrace == nil {
            let leadingStart = scanner.index
            scanner.skipWhitespace()
            if scanner.peek() == UInt8(ascii: "}"), pairs.isEmpty {
                closeBrace = scanner.index
                break
            }
            let keyStart = scanner.index
            guard let key = scanner.scanString() else { return nil }
            scanner.skipWhitespace()
            guard scanner.peek() == UInt8(ascii: ":") else { return nil }
            scanner.index += 1
            scanner.skipWhitespace()
            let valueStart = scanner.index
            guard scanner.skipValue() else { return nil }
            let valueEnd = scanner.index
            scanner.skipWhitespace()

            var comma: Int?
            switch scanner.peek() {
            case UInt8(ascii: ","):
                comma = scanner.index
                scanner.index += 1
            case UInt8(ascii: "}"):
                closeBrace = scanner.index
            default:
                return nil
            }
            pairs.append(Pair(key: key, leadingStart: leadingStart, keyStart: keyStart, valueStart: valueStart, valueEnd: valueEnd, comma: comma))
        }

        guard let closeBrace else { return nil }
        scanner.index = closeBrace + 1
        scanner.skipWhitespace()
        guard scanner.peek() == nil else { return nil }
        self.closeBrace = closeBrace
        self.pairs = pairs
    }

    /// Recuo das chaves de topo (`"  "`, `"\t"`…), ou `nil` se o objeto está numa linha só.
    func indent(in bytes: [UInt8]) -> String? {
        guard let first = pairs.first else { return "  " }
        let leading = bytes[first.leadingStart..<first.keyStart]
        guard let newline = leading.lastIndex(of: UInt8(ascii: "\n")) else { return nil }
        let indent = String(decoding: leading[(newline + 1)...], as: UTF8.self)
        return indent.isEmpty ? "  " : indent
    }

    /// Trecho a apagar para remover um par sem deixar vírgula sobrando.
    func removalRange(ofPairAt index: Int) -> Range<Int> {
        let pair = pairs[index]
        if let comma = pair.comma {
            // Não é o último: vai do espaço antes da chave até a vírgula depois do valor.
            return pair.leadingStart..<(comma + 1)
        }
        if index > 0, let previousComma = pairs[index - 1].comma {
            // É o último: leva junto a vírgula do par anterior.
            return previousComma..<pair.valueEnd
        }
        return pair.leadingStart..<pair.valueEnd
    }
}

private struct JSONScanner {
    let bytes: [UInt8]
    var index = 0

    func peek() -> UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    mutating func skipWhitespace() {
        while let byte = peek(), [0x20, 0x09, 0x0A, 0x0D].contains(byte) {
            index += 1
        }
    }

    /// Lê uma string JSON e devolve o conteúdo já sem escapes.
    mutating func scanString() -> String? {
        let start = index
        guard skipString() else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: .fragmentsAllowed)) as? String
    }

    private mutating func skipString() -> Bool {
        guard peek() == UInt8(ascii: "\"") else { return false }
        index += 1
        while let byte = peek() {
            index += 1
            if byte == UInt8(ascii: "\\") {
                index += 1
            } else if byte == UInt8(ascii: "\"") {
                return true
            }
        }
        return false
    }

    mutating func skipValue() -> Bool {
        guard let byte = peek() else { return false }
        switch byte {
        case UInt8(ascii: "\""):
            return skipString()
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            while let current = peek() {
                switch current {
                case UInt8(ascii: "\""):
                    guard skipString() else { return false }
                    continue
                case UInt8(ascii: "{"), UInt8(ascii: "["):
                    depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                default:
                    break
                }
                index += 1
                if depth == 0 { return true }
            }
            return false
        default:
            let start = index
            while let current = peek(), ![UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"), 0x20, 0x09, 0x0A, 0x0D].contains(current) {
                index += 1
            }
            return index > start
        }
    }
}
