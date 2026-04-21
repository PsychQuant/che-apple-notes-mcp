// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CheAppleNotesMCP",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", .upToNextMinor(from: "0.12.0"))
    ],
    targets: [
        .executableTarget(
            name: "CheAppleNotesMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/CheAppleNotesMCP",
            exclude: ["Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/CheAppleNotesMCP/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "CheAppleNotesMCPTests",
            dependencies: ["CheAppleNotesMCP"],
            path: "Tests/CheAppleNotesMCPTests"
        ),
        .testTarget(
            name: "CheAppleNotesMCPE2ETests",
            dependencies: ["CheAppleNotesMCP"],
            path: "Tests/CheAppleNotesMCPE2ETests"
        )
    ]
)
