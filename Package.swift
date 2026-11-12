// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Uncomew",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Uncomew", targets: ["Uncomew"])
    ],
    targets: [
        .executableTarget(
            name: "Uncomew",
            path: "Sources/Uncomew"
        )
    ]
)
