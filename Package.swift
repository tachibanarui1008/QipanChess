// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "QipanChessCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "GameCore", targets: ["GameCore"]), .library(name: "Analysis", targets: ["Analysis"])],
    targets: [
        .target(name: "GameCore", path: "QipanChessApp/GameCore"),
        .target(name: "Engine", dependencies: ["GameCore"], path: "QipanChessApp/Engine"),
        .target(name: "Analysis", dependencies: ["GameCore", "Engine"], path: "QipanChessApp/Analysis"),
        .testTarget(name: "QipanChessTests", dependencies: ["GameCore", "Engine", "Analysis"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
