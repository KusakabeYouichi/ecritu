import AppKit
import Carbon
import InputMethodKit

// 入力メソッドの起動。IMKServer を作り、変換をプロセスで 1 つ用意して、起動時の自己検査をログに出す

// インストール直後に pkg の postinstall から呼ぶ。入力ソースの台帳へ登録だけして終わる
// (登録しないと、ログインし直すまで [入力ソース] の一覧に出ない)
if CommandLine.arguments.contains("--register-input-source") {
    let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
    print("TISRegisterInputSource(\(Bundle.main.bundlePath)) = \(status)")
    exit(status == noErr ? 0 : 1)
}

/// UserDefaults の suite 名(学習の置き場)。メインの bundle ID と同名は suite に使えないので別の名前にする
private let conversionSuiteName = "jp.or.pleiades.merope.inputmethod.ecritu.conversion"
/// エンジンが同名の辞書を探す場所(ディレクトリーは作らない。エンジンはここに何も置かない)
private let conversionContainerDirectory = FileManager.default
    .homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ecritu", isDirectory: true)

let conversionService = ConversionService(
    appGroupID: conversionSuiteName,
    containerDirectory: conversionContainerDirectory
)

private let info = Bundle.main.infoDictionary ?? [:]
private let controllerClassName = info["InputMethodServerControllerClass"] as? String ?? ""
private let connectionName = info["InputMethodConnectionName"] as? String ?? ""

NSLog("[ecritu] 自己検査: コントローラーのクラス %@ の解決 = %@",
      controllerClassName, NSClassFromString(controllerClassName) != nil ? "成功" : "失敗")

let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
NSLog("[ecritu] 自己検査: IMKServer(接続名 %@)の作成 = %@", connectionName, server != nil ? "成功" : "失敗")

conversionService.preload()
NSLog("[ecritu] 自己検査: 辞書を開けた = %@", conversionService.isSystemDictionaryOpen ? "成功" : "失敗")

NSApplication.shared.run()
