// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OneTwenty",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OneTwenty", targets: ["OneTwenty"])
    ],
    targets: [
        .executableTarget(
            name: "OneTwenty",
            path: "Sources/OneTwenty"
        ),
        .testTarget(
            name: "OneTwentyTests",
            dependencies: ["OneTwenty"],
            path: "Tests/OneTwentyTests"
        )
    ]
)
