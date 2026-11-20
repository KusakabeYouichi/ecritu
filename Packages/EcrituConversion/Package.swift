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
    // デバッグ版でも変換は最適化する(3856)。⌘R と TestFlight はデバッグ版で、変換が最適化なしだと 1 打鍵 36ms、
    // 長い文の連文節 140ms。最適化すると 16ms / 58ms(Mac。2.3〜2.4 倍)。1 ファイル直した後のビルドは 50〜66 秒で変わらない。
    // 代わりに、デバッガーで変換のコードを 1 行ずつ止めたときに変数が見えにくい(ユーザ判断: その予定は無い)。
    // DEBUG の条件(#if DEBUG のトレース・診断)は別の指定なので、そのまま有効
    .unsafeFlags(["-O"], .when(configuration: .debug)),
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
