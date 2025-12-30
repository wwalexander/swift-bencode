import Combine
import Foundation

public class BencodeDecoder: TopLevelDecoder {
    public init() {}

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        var parser = BencodeParser(data: data)
        let value = try parser.parse()
        let decoder = BencodeDecoderImpl(value: value)
        return try decoder.singleValueContainer().decode(type)
    }
}

internal struct BencodeDecoderImpl: Decoder {
    let value: BencodeValue
    let codingPath: [any CodingKey]

    init(value: BencodeValue, codingPath: [any CodingKey] = []) {
        self.value = value
        self.codingPath = codingPath
    }

    var userInfo: [CodingUserInfoKey: Any] { [:] } // TODO

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .dictionary(let dictionary) = value else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Expected dictionary"))
        }

        let container = BencodeKeyedDecodingContainer<Key>(dictionary: dictionary, codingPath: codingPath)
        return KeyedDecodingContainer(container)
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case .list(let list) = value else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Expected list"))
        }

        return BencodeUnkeyedDecodingContainer(list: list, codingPath: codingPath)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        BencodeSingleValueDecodingContainer(value: value, codingPath: codingPath)
    }
}

internal enum BencodeCodingKey: CodingKey {
    case dictionaryKey(String)
    case listIndex(Int)

    init(stringValue: String) {
        self = .dictionaryKey(stringValue)
    }

    init(intValue: Int) {
        self = .listIndex(intValue)
    }

    var stringValue: String {
        switch self {
        case .dictionaryKey(let key): key
        case .listIndex(let index): String(index)
        }
    }

    var intValue: Int? {
        switch self {
        case .dictionaryKey: nil
        case .listIndex(let index): index
        }
    }
}

internal struct BencodeKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let dictionary: [String: BencodeValue]
    let codingPath: [any CodingKey]

    init(dictionary: [String: BencodeValue], codingPath: [any CodingKey]) {
        self.dictionary = dictionary
        self.codingPath = codingPath
    }

    var allKeys: [Key] {
        dictionary.keys.compactMap { key in
            Key(stringValue: key)
        }
    }

    func contains(_ key: Key) -> Bool {
        dictionary.keys.contains(key.stringValue)
    }


    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try with(forKey: key) { decoder in
            try decoder.container(keyedBy: type)
        }
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        try with(forKey: key) { decoder in
            try decoder.unkeyedContainer()
        }
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        try with(forKey: key) { decoder in
            decoder
        }
    }

    func superDecoder() throws -> any Decoder {
        try with(forKey: BencodeCodingKey.dictionaryKey("super")) { decoder in decoder }
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try with(forKey: key) { decoder in
            try decoder.singleValueContainer().decode(type)
        }
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        try with(forKey: key) { decoder in
            try decoder.singleValueContainer().decodeNil()
        }
    }

    @inline(__always)
    private func with<T>(forKey key: any CodingKey, _ body: (BencodeDecoderImpl) throws -> T) throws -> T {
        let codingPath = codingPath + [key]

        guard let value = dictionary[key.stringValue]
        else { throw DecodingError.valueNotFound(T.self, .init(codingPath: codingPath, debugDescription: "Value not found for key \(key)")) }

        let decoder = BencodeDecoderImpl(value: value, codingPath: codingPath) // TODO: UserInfo
        return try body(decoder)
    }
}

internal struct BencodeUnkeyedDecodingContainer : UnkeyedDecodingContainer {
    let list: [BencodeValue]
    let codingPath: [any CodingKey]

    init(list: [BencodeValue], codingPath: [any CodingKey]) {
        self.list = list
        self.codingPath = codingPath
    }

    private(set) var currentIndex: Int = 0
    var count: Int? { list.count }
    var isAtEnd: Bool { currentIndex == list.endIndex }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        try with { decoder in try decoder.container(keyedBy: type) }
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        try with { decoder in try decoder.unkeyedContainer() }
    }

    mutating func superDecoder() throws -> any Decoder {
        try with { decoder in decoder }
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try with { decoder in
            try decoder.singleValueContainer().decode(T.self)
        }
    }

    mutating func decodeNil() throws -> Bool { false }

    @inline(__always)
    private mutating func with<T>(_ body: (BencodeDecoderImpl) throws -> T) throws -> T {
        let codingKey = BencodeCodingKey(intValue: currentIndex)
        let codingPath = codingPath + [codingKey]

        guard !isAtEnd
        else { throw DecodingError.valueNotFound(T.self, .init(codingPath: codingPath, debugDescription: "At end")) }

        defer { list.formIndex(after: &currentIndex) }
        let value = list[currentIndex]
        let decoder = BencodeDecoderImpl(value: value, codingPath: codingPath) // TODO: UserInfo
        return try body(decoder)
    }

}

internal struct BencodeSingleValueDecodingContainer: SingleValueDecodingContainer {
    let value: BencodeValue
    let codingPath: [any CodingKey]

    init(value: BencodeValue, codingPath: [any CodingKey]) {
        self.value = value
        self.codingPath = codingPath
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if type == Data.self {
            guard case .string(let data) = value else {
                throw DecodingError.typeMismatch(type, .init(
                    codingPath: codingPath,
                    debugDescription: "Expected string"
                ))
            }
            return data as! T
        } else if type == URL.self {
            let string = try decode(String.self)
            return URL(string: string)! as! T
        }
        
        let decoder = BencodeDecoderImpl(value: value, codingPath: codingPath)
        return try T(from: decoder)
    }
    
    func decode(_ type: String.Type) throws -> String {
        let data = try decode(Data.self)

        guard let string = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Unable to convert data to a string"))
        }

        return string
    }

    func decode(_ type: Decimal.Type) throws -> Decimal {
        guard case .integer(let decimal) = value else {
            throw DecodingError.typeMismatch(type, .init(codingPath: codingPath, debugDescription: "Expected integer"))
        }

        return decimal
    }

    func decode(_ type: NSDecimalNumber.Type) throws -> NSDecimalNumber {
        let decimal = try decode(Decimal.self)
        return NSDecimalNumber(decimal: decimal)
    }

    func decode(_ type: Int.Type) throws -> Int {
        try decode(NSDecimalNumber.self).intValue
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        try decode(NSDecimalNumber.self).int64Value
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        try decode(NSDecimalNumber.self).int32Value
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        try decode(NSDecimalNumber.self).int16Value
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        try decode(NSDecimalNumber.self).int8Value
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        try decode(NSDecimalNumber.self).uintValue
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        try decode(NSDecimalNumber.self).uint64Value
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        try decode(NSDecimalNumber.self).uint32Value
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        try decode(NSDecimalNumber.self).uint16Value
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        try decode(NSDecimalNumber.self).uint8Value
    }

    func decode(_ type: Double.Type) throws -> Double {
        try decode(NSDecimalNumber.self).doubleValue
    }

    func decode(_ type: Float.Type) throws -> Float {
        try decode(NSDecimalNumber.self).floatValue
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        try decode(NSDecimalNumber.self).boolValue
    }

    func decodeNil() -> Bool { false }
}
