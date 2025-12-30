// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-bencode",
    products: [
        .library(
            name: "Bencode",
            targets: ["Bencode"]
        ),
    ],
    targets: [
        .target(name: "Bencode"),
        .testTarget(
            name: "BencodeTests",
            dependencies: ["Bencode"],
            resources: [
                .copy("debian-13.2.0-arm64-netinst.iso.torrent")
            ]
        ),
    ]
)
