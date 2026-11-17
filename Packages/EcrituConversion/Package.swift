// swift-tools-version: 5.9
// 変換の中核(UI を持たない部分)。拡張・アプリ・テストへ静的にリンクする(ライブラリーの種類は指定しない)。
// EcrituConversionBase はアプリも使う 10 本。アプリの実行ファイルに変換本体(seed・連語表)を入れないために分ける。
// EcrituConversion は残りの変換本体で、EcrituConversionBase を再公開する。
// 資源(辞書・索引)は今まで通り各ターゲットの Copy Bundle Resources にあり、Bundle(for: KanaKanjiStore.self) で引く。
import PackageDescription

// Release では module をまたぐ呼び出し(EcrituConversion → EcrituConversionBase)も畳めるようにする。
// 付けないと 1 打鍵が 2 割ほど遅くなる(切り出し前は拡張の 1 module でまとめて最適化されていた)。
let crossModuleOptimization: [SwiftSetting] = [
    .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release)),
]

let package = Package(
    name: "EcrituConversion",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EcrituConversionBase", targets: ["EcrituConversionBase"]),
        .library(name: "EcrituConversion", targets: ["EcrituConversion"]),
    ],
    targets: [
        .target(name: "EcrituConversionBase", swiftSettings: crossModuleOptimization),
        .target(name: "EcrituConversion", dependencies: ["EcrituConversionBase"], swiftSettings: crossModuleOptimization),
    ],
    swiftLanguageVersions: [.v5]
)
