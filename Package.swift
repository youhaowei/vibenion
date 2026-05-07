// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Vibenion",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Vibenion", targets: ["Vibenion"])
    ],
    targets: [
        .executableTarget(
            name: "Vibenion",
            path: "Sources/Vibenion"
        ),
        .testTarget(
            name: "VibenionTests",
            dependencies: ["Vibenion"],
            path: "Tests/VibenionTests"
        )
    ]
)
