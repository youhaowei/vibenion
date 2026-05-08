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
    dependencies: [
        .package(url: "https://github.com/krzysztofzablocki/Inject.git", from: "1.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Vibenion",
            dependencies: [
                .product(name: "Inject", package: "Inject")
            ],
            path: "Sources/Vibenion",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-interposable"], .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "VibenionTests",
            dependencies: ["Vibenion"],
            path: "Tests/VibenionTests"
        )
    ]
)
