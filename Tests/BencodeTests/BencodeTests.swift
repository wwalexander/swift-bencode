import Testing
@testable import Bencode
import Foundation



@Test func example() throws {
    struct Metainfo: Decodable {
        let announce: URL
        let info: Info
        
        struct Info: Decodable {
            let name: String
            let pieceLength: UInt64
            let pieces: Data
            let length: UInt64?
            let files: [File]?
            
            struct File: Decodable {
                let length: UInt64
                let path: [String]
            }
            
            enum CodingKeys: String, CodingKey {
                case name
                case pieceLength = "piece length"
                case pieces
                case length
                case files
            }
        }
    }
    
    let metainfo = try BencodeDecoder().decode(
        Metainfo.self,
        from: .init(contentsOf: #require(#bundle.url(
            forResource: "debian-13.2.0-arm64-netinst.iso",
            withExtension: "torrent"
        )))
    )
    
    #expect(metainfo.announce == URL(string: "http://bttracker.debian.org:6969/announce"))
    #expect(metainfo.info.name == "debian-13.2.0-arm64-netinst.iso")
    #expect(metainfo.info.pieceLength == 262144)
    #expect(metainfo.info.pieces.count == 58920)
    #expect(metainfo.info.length == 772059136)
    #expect(metainfo.info.files == nil)

}
