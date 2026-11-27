import AppKit
import SwiftUI

/// 設定のウインドウ。プロセスで1つだけ作り、閉じても捨てずに使い回す。
/// 入力メソッドは LSUIElement のアプリで、NSApplication に delegate を置いていないので、
/// 最後のウインドウを閉じてもプロセスは終わらない(applicationShouldTerminateAfterLastWindowClosed の初期値は false)
final class SettingsWindowController {
    static let shared = SettingsWindowController(conversionService: conversionService)

    private let model: ConversionSettingsModel
    private let window: NSWindow

    private init(conversionService: ConversionService) {
        model = ConversionSettingsModel(conversionService: conversionService)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.title = "écritu の設定"
        // 閉じたときに解放されると、次に開くときに解放済みのウインドウを触ってしまう
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.contentView = NSHostingView(rootView: ConversionSettingsView(model: model))
        window.center()
    }

    /// 開いて手前に出す。LSUIElement のアプリは自分からは前に出ないので、アプリごと前に出す
    func show() {
        model.reload()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

/// 設定画面が触る値。変えるたびにすぐ ConversionService へ渡す(エンジンへ入れて保存する)
final class ConversionSettingsModel: ObservableObject {
    private let conversionService: ConversionService

    @Published var settings: ConversionSettings {
        didSet {
            guard settings != oldValue, !isReloading else {
                return
            }
            conversionService.updateSettings(settings)
        }
    }

    /// reload の間は ConversionService へ書き戻さない(読んだ値をそのまま書くだけになる)
    private var isReloading = false

    init(conversionService: ConversionService) {
        self.conversionService = conversionService
        settings = conversionService.settings
    }

    /// 開くたびに ConversionService の今の値を読み直す
    func reload() {
        isReloading = true
        settings = conversionService.settings
        isReloading = false
    }
}
