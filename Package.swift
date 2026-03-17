// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProxyMock",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.2")
    ],
    targets: [
        .executableTarget(
            name: "ProxyMock",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources"
        )
    ]
)
