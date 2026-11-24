// swift-tools-version: 5.9
// 入力の論理(UI を持たない部分)。Mac の入力メソッドから使う。
// 変換は ConversionProviding で外から受け取り、EcrituConversion には依存しない(依存は Foundation だけ)。
import PackageDescription

let package = Package(
    name: "EcrituInput",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EcrituInput", targets: ["EcrituInput"]),
    ],
    targets: [
        .target(name: "EcrituInput"),
        .testTarget(name: "EcrituInputTests", dependencies: ["EcrituInput"]),
    ],
    swiftLanguageVersions: [.v5]
)
