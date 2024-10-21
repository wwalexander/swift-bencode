import Foundation

enum BencodeValue: Equatable {
    case dictionary([String: BencodeValue])
    case list([BencodeValue])
    case integer(Decimal)
    case string(Data)
}

struct BencodeParser {
    private var bytes: BencodeBytes

    public init(data: consuming Data) {
        self.bytes = BencodeBytes(data: data)
    }

    public mutating func parse() throws(BencodeError) -> BencodeValue {
        let value = try parseValue()

        guard bytes.isAtEnd
        else { throw BencodeError.unexpectedCharacter(location: bytes.currentIndex) }

        return value
    }

    private mutating func parseValue() throws(BencodeError) -> BencodeValue {
        switch try bytes.peek() {
        case UInt8(ascii: "d"):
            try bytes.pop()
            return try .dictionary(parseDictionary())
        case UInt8(ascii: "l"):
            try bytes.pop()
            return try .list(parseList())
        case UInt8(ascii: "i"):
            try bytes.pop()
            return try .integer(parseInteger())
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return try .string(parseString())
        default:
            throw .unexpectedCharacter(location: bytes.currentIndex)
        }
    }

    private mutating func parseDictionary() throws(BencodeError) -> [String: BencodeValue] {
        var dictionary: [String: BencodeValue] = [:]

        while try bytes.peek() != UInt8(ascii: "e") {
            try dictionary[parseString()] = parseValue()
        }

        try bytes.pop()
        return dictionary
    }

    private mutating func parseList() throws(BencodeError) -> [BencodeValue] {
        var list: [BencodeValue] = []

        while try bytes.peek() != UInt8(ascii: "e") {
            try list.append(parseValue())
        }

        try bytes.pop()
        return list
    }

    private mutating func parseInteger<N>() throws(BencodeError) -> N
    where N: SignedNumeric {
        try parseSignum() * parseMagnitude(until: UInt8(ascii: "e"))
    }

    private mutating func parseString() throws(BencodeError) -> Data {
        let length = try parseLength()
        var data = Data(capacity: length)

        while data.count < length {
            try data.append(bytes.pop())
        }

        return data
    }

    private mutating func parseString() throws(BencodeError) -> String {
        let data: Data = try parseString()

        guard let string = String(data: data, encoding: .utf8)
        else { throw .cannotConvertInputStringDataToUTF8(location: bytes.currentIndex) }

        return string
    }

    private mutating func parseLength() throws(BencodeError) -> Int {
        try parseMagnitude(until: UInt8(ascii: ":"))
    }

    private mutating func parseSignum<N>() throws(BencodeError) -> N
    where N: SignedNumeric {
        if case UInt8(ascii: "-") = try bytes.peek() {
            try bytes.pop()
            return -1
        } else {
            return 1
        }
    }

    private mutating func parseMagnitude<N>(until end: UInt8) throws(BencodeError) -> N
    where N: Numeric {
        let hasLeadingZero: Bool = try bytes.peek() == UInt8(ascii: "0")

        if hasLeadingZero {
            try bytes.pop()
        }

        var integer: N = 0

        while try bytes.peek() != end {
            let digit: N = try parseDigit()

            guard !hasLeadingZero
            else { throw .integerWithLeadingZero(location: bytes.currentIndex) }

            integer *= 10
            integer += digit
        }

        try bytes.pop()
        return integer
    }

    private mutating func parseDigit<N>() throws(BencodeError) -> N
    where N: Numeric {
        let byte = try bytes.pop()

        guard case UInt8(ascii: "0")...UInt8(ascii: "9") = byte
        else { throw .unexpectedCharacter(location: bytes.currentIndex) }

        guard let value = N(exactly: byte - UInt8(ascii: "0"))
        else { throw .integerIsNotRepresentableInSwift }

        return value
    }
}

struct BencodeBytes {
    private var data: Data
    private var peekedByte: UInt8?

    public init(data: Data) {
        self.data = data
    }

    public mutating func peek() throws(BencodeError) -> UInt8 {
        guard let byte = data.first
        else { throw .unexpectedEndOfFile }
        return byte
    }

    @discardableResult
    public mutating func pop() throws(BencodeError) -> UInt8 {
        guard let byte = data.popFirst()
        else { throw .unexpectedEndOfFile }
        return byte
    }

    public var currentIndex: Int {
        data.startIndex
    }

    public var isAtEnd: Bool {
        currentIndex == data.endIndex
    }
}

enum BencodeError: Error {
    case cannotConvertInputStringDataToUTF8(location: Int)
    case unexpectedCharacter(location: Int)
    case unexpectedEndOfFile
    case integerWithLeadingZero(location: Int)
    case integerIsNotRepresentableInSwift
}
