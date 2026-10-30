import Foundation

extension KeyedDecodingContainer {
    /// Campo opcional que vira `nil` se vier com outro tipo, em vez de derrubar o arquivo inteiro.
    func lenient<T: Decodable>(_ key: Key, as type: T.Type = T.self) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }
}

/// Array que pula os elementos que não decodificam.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        self.elements = elements
    }

    private struct Skip: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}

enum Timestamps {
    /// Datas ISO 8601 do Claude Code, com ou sem frações de segundo.
    static func parseISO8601(_ text: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(text)
    }

    /// Milissegundos desde 1970, como nos arquivos finais dos workflows.
    static func fromMilliseconds(_ milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
