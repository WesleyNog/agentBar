/// Lê o pedaço de JavaScript usado no `meta` dos workflows: objetos, arrays, strings
/// ('…', "…", `…`), números, true/false/null, vírgulas sobrando e comentários.
/// Não é um parser de JavaScript; só o suficiente para um literal puro.
struct JSLiteralParser {
    enum Value: Equatable {
        case object([String: Value])
        case array([Value])
        case string(String)
        /// Número, booleano, null ou identificador: o AgentBar não usa esses valores.
        case scalar

        var stringValue: String? {
            if case .string(let string) = self { return string }
            return nil
        }

        var arrayValue: [Value]? {
            if case .array(let array) = self { return array }
            return nil
        }

        var objectValue: [String: Value]? {
            if case .object(let object) = self { return object }
            return nil
        }
    }

    struct SyntaxError: Error {}

    private let bytes: [UInt8]
    private var index = 0

    init<S: Sequence>(_ source: S) where S.Element == UInt8 {
        bytes = Array(source)
    }

    mutating func parseValue() throws -> Value {
        skipTrivia()
        guard let byte = peek() else { throw SyntaxError() }
        switch byte {
        case ascii("{"): return try parseObject()
        case ascii("["): return try parseArray()
        case ascii("'"), ascii("\""), ascii("`"): return .string(try parseString())
        default:
            try skipScalar()
            return .scalar
        }
    }

    // MARK: - Estruturas

    private mutating func parseObject() throws -> Value {
        index += 1
        var object: [String: Value] = [:]
        while true {
            skipTrivia()
            guard let byte = peek() else { throw SyntaxError() }
            if byte == ascii("}") {
                index += 1
                return .object(object)
            }
            let key = isQuote(byte) ? try parseString() : try parseIdentifier()
            skipTrivia()
            guard peek() == ascii(":") else { throw SyntaxError() }
            index += 1
            object[key] = try parseValue()
            try skipSeparator(closing: ascii("}"))
        }
    }

    private mutating func parseArray() throws -> Value {
        index += 1
        var array: [Value] = []
        while true {
            skipTrivia()
            guard let byte = peek() else { throw SyntaxError() }
            if byte == ascii("]") {
                index += 1
                return .array(array)
            }
            array.append(try parseValue())
            try skipSeparator(closing: ascii("]"))
        }
    }

    /// Depois de um valor vem `,` ou o fechamento.
    private mutating func skipSeparator(closing: UInt8) throws {
        skipTrivia()
        if peek() == ascii(",") {
            index += 1
        } else if peek() != closing {
            throw SyntaxError()
        }
    }

    // MARK: - Tokens

    private mutating func parseString() throws -> String {
        let quote = bytes[index]
        index += 1
        var output: [UInt8] = []
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == quote {
                return String(decoding: output, as: UTF8.self)
            }
            guard byte == ascii("\\"), index < bytes.count else {
                output.append(byte)
                continue
            }
            let escaped = bytes[index]
            index += 1
            switch escaped {
            case ascii("n"): output.append(0x0A)
            case ascii("t"): output.append(0x09)
            case ascii("r"): output.append(0x0D)
            case ascii("\n"): break // continuação de linha
            case ascii("u"): output.append(contentsOf: parseUnicodeEscape())
            default: output.append(escaped)
            }
        }
        throw SyntaxError()
    }

    /// `\uXXXX` (o `\u` já foi lido). Escape inválido vira U+FFFD.
    private mutating func parseUnicodeEscape() -> [UInt8] {
        let end = index + 4
        guard end <= bytes.count,
              let code = UInt32(String(decoding: bytes[index..<end], as: UTF8.self), radix: 16)
        else { return Array("\u{FFFD}".utf8) }
        index = end
        let scalar = Unicode.Scalar(code) ?? "\u{FFFD}"
        return Array(String(Character(scalar)).utf8)
    }

    private mutating func parseIdentifier() throws -> String {
        let start = index
        while let byte = peek(), isIdentifierByte(byte) {
            index += 1
        }
        guard index > start else { throw SyntaxError() }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func skipScalar() throws {
        let start = index
        while let byte = peek(), !isWhitespace(byte), ![ascii(","), ascii("}"), ascii("]")].contains(byte) {
            index += 1
        }
        guard index > start else { throw SyntaxError() }
    }

    /// Espaços e comentários `//` e `/* */`.
    private mutating func skipTrivia() {
        while let byte = peek() {
            if isWhitespace(byte) {
                index += 1
            } else if byte == ascii("/"), peek(offset: 1) == ascii("/") {
                while let next = peek(), next != ascii("\n") { index += 1 }
            } else if byte == ascii("/"), peek(offset: 1) == ascii("*") {
                index += 2
                while index < bytes.count, !(peek() == ascii("*") && peek(offset: 1) == ascii("/")) { index += 1 }
                index = min(index + 2, bytes.count)
            } else {
                return
            }
        }
    }

    // MARK: - Bytes

    private func peek(offset: Int = 0) -> UInt8? {
        index + offset < bytes.count ? bytes[index + offset] : nil
    }

    private func isQuote(_ byte: UInt8) -> Bool {
        byte == ascii("'") || byte == ascii("\"") || byte == ascii("`")
    }

    private func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private func isIdentifierByte(_ byte: UInt8) -> Bool {
        (ascii("a")...ascii("z")).contains(byte) || (ascii("A")...ascii("Z")).contains(byte)
            || (ascii("0")...ascii("9")).contains(byte) || byte == ascii("_") || byte == ascii("$")
    }
}

private func ascii(_ character: Unicode.Scalar) -> UInt8 {
    UInt8(ascii: character)
}
