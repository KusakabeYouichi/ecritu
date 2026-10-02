#!/usr/bin/env python3
# App Store スクリーンショット撮影用の一時フックを入れる(コミットしない。撮影後に git checkout -- KeyboardExtension/ で外す)。
# 2026-09-24(take 5)の会話記録から復元し、2026-10-02(take 6)で使ったもの。appstore/screenshots-plan.md「無操作での撮影手順」の 3 節。
# 使い方: python3 appstore/apply-screenshot-hooks.py → シミュレーター向けにビルド → appstore/shoot-screenshot.sh で撮影 → git checkout -- KeyboardExtension/
import sys

import os
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "KeyboardExtension") + "/"


def patch(name, pairs):
    path = ROOT + name
    s = open(path, encoding="utf-8").read()
    for old, new in pairs:
        count = s.count(old)
        if count != 1:
            sys.exit(f"{name}: anchor found {count} times:\n{old[:120]}")
        s = s.replace(old, new)
    open(path, "w", encoding="utf-8").write(s)
    print("patched", name)


def append(name, text):
    path = ROOT + name
    with open(path, "a", encoding="utf-8") as f:
        f.write(text)
    print("appended", name)


# 1. 本文の挿入と読みの打鍵(viewDidAppear から呼ぶ)
append("KeyboardViewController+Diagnostics.swift", '''

// ★撮影用の一時フック(コミットしない。撮影後に git checkout で外す)
extension KeyboardViewController {
    nonisolated(unsafe) private static var lastScreenshotScriptRunAt: CFAbsoluteTime = 0

    func runScreenshotScriptIfNeeded() {
        #if DEBUG
        guard let script = sharedDefaults?.string(forKey: "screenshotScript"),
            !script.isEmpty,
            CFAbsoluteTimeGetCurrent() - Self.lastScreenshotScriptRunAt > 20
        else {
            return
        }
        Self.lastScreenshotScriptRunAt = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            for _ in 0..<80 { self.textDocumentProxy.deleteBackward() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.performScreenshotScript(script)
            }
        }
        #endif
    }

    private func performScreenshotScript(_ script: String) {
        switch script {
        case "01":
            textDocumentProxy.insertText("トカイの土着品種 Hárslevelű と ")
            typeScreenshotReading("くゔぇーるすーるー")
        case "02":
            textDocumentProxy.insertText("トカイの土着品種 Hárslevelű と Kövérszőlő")
        case "03":
            textDocumentProxy.insertText("トカイの土着品種 Hárslevelű と Kövérszőlő🇭🇺")
        case "04":
            textDocumentProxy.insertText("トカイの土着品種 Hárslevelű と Kövérszőlő🇭🇺🇸🇰")
        case "05":
            textDocumentProxy.insertText("フランスの年間のワイン生産量は、フランス農務省の2025年11月1日時点予測値で約")
        default:
            break
        }
    }

    private func typeScreenshotReading(_ reading: String) {
        var delay = 0.0
        for character in reading {
            delay += 0.12
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.handleTextInput(String(character))
            }
        }
    }
}
''')
patch("KeyboardViewController.swift", [(
    "        commitStaleHostMarkedTextOnAppear()\n",
    "        commitStaleHostMarkedTextOnAppear()\n        runScreenshotScriptIfNeeded()\n",
)])

# 2. 面の状態の種
append("KeyboardRootView.swift", '''

// ★撮影用の一時フック(コミットしない。撮影後に git checkout で外す)
enum ScreenshotSeed {
    static let defaults = UserDefaults(suiteName: KeyboardViewController.SharedDefaultsKeys.appGroupID)

    static func string(_ key: String) -> String? {
        guard let value = defaults?.string(forKey: "screenshot_" + key), !value.isEmpty else {
            return nil
        }
        return value
    }

    static var inputMode: KeyboardInputMode? {
        switch string("inputMode") {
        case "emoji": return .emoji
        case "formattedNumber": return .formattedNumber
        case "number": return .number
        case "latin": return .latin
        case "kana": return .kana
        default: return nil
        }
    }

    static var emojiSubmode: EmojiInputSubmode? {
        switch string("emojiSubmode") {
        case "emoji": return .emoji
        case "kaomoji": return .kaomoji
        case "symbols": return .symbols
        case "kanjiRadical": return .kanjiRadical
        default: return nil
        }
    }
}
''')
patch("KeyboardRootView.swift", [
    ('@State var selectedKaomojiCategoryID = "existing"',
     '@State var selectedKaomojiCategoryID = ScreenshotSeed.string("kaomojiCategory") ?? "existing"'),
    ('@State var selectedKaomojiReading: String? = nil',
     '@State var selectedKaomojiReading: String? = ScreenshotSeed.string("kaomojiReading")'),
    ('@State var selectedKaomojiReadingPrefix: String? = nil',
     '@State var selectedKaomojiReadingPrefix: String? = ScreenshotSeed.string("kaomojiPrefix")'),
    ('@State var formattedNumberBuffer: String = ""',
     '@State var formattedNumberBuffer: String = ScreenshotSeed.string("numberBuffer") ?? ""'),
    ('@State var selectedEmojiCategory: EmojiCategory = .people',
     '@State var selectedEmojiCategory: EmojiCategory = (ScreenshotSeed.string("emojiCategory") == "flags" ? .flags : .people)'),
    ("""        .onAppear {
            if inputMode != initialInputMode {
                inputMode = initialInputMode
            }""",
     """        .onAppear {
            if let seededMode = ScreenshotSeed.inputMode {
                inputMode = seededMode
                if let seededSubmode = ScreenshotSeed.emojiSubmode {
                    emojiInputSubmode = seededSubmode
                }
            } else if inputMode != initialInputMode {
                inputMode = initialInputMode
            }"""),
    # でばぐ可視化(削除キーの注記)を写さない
    ("    static let memoryPressureVisualizationEnabled = true",
     "    static let memoryPressureVisualizationEnabled = false  // ★撮影用の一時変更(コミットしない)"),
])

# 3. 顔文字検索の読み行を種の見出しまでスクロール
patch("KeyboardRootView+EmojiKaomojiLayouts.swift", [(
    '''                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    kaomojiSearchPrefixButton(
                                        title: "全",
                                        isSelected: selectedKaomojiReadingPrefix == nil,
                                        action: { selectKaomojiReadingPrefix(nil) }
                                    )

                                    ForEach(KaomojiCatalog.readingIndexHeadings, id: \\.self) { heading in
                                        kaomojiSearchPrefixButton(
                                            title: heading,
                                            isSelected: selectedKaomojiReadingPrefix == heading,
                                            action: { selectKaomojiReadingPrefix(heading) }
                                        )
                                    }
                                }
                            }''',
    '''                            ScrollViewReader { screenshotProxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    kaomojiSearchPrefixButton(
                                        title: "全",
                                        isSelected: selectedKaomojiReadingPrefix == nil,
                                        action: { selectKaomojiReadingPrefix(nil) }
                                    )

                                    ForEach(KaomojiCatalog.readingIndexHeadings, id: \\.self) { heading in
                                        kaomojiSearchPrefixButton(
                                            title: heading,
                                            isSelected: selectedKaomojiReadingPrefix == heading,
                                            action: { selectKaomojiReadingPrefix(heading) }
                                        )
                                        .id(heading)
                                    }
                                }
                            }
                            .onAppear {
                                // ★撮影用の一時フック(コミットしない)
                                if let seeded = ScreenshotSeed.string("kaomojiPrefix") {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                        screenshotProxy.scrollTo(seeded, anchor: .trailing)
                                    }
                                }
                            }
                            }''',
)])

# 4. 国旗の国名吹き出しを出したままにする
path = ROOT + "KeyboardKeyComponents.swift"
s = open(path, encoding="utf-8").read()
anchor = "view.register(EmojiGridCell.self, forCellWithReuseIdentifier: EmojiGridCell.reuseIdentifier)"
i = s.index(anchor)
a = '''        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        context.coordinator.parent = self
        return view
    }'''
j = s.index(a, i)
b = '''        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        context.coordinator.parent = self
        // ★撮影用の一時フック(コミットしない): 指定した絵文字の吹き出しを出したままにする
        if let target = ScreenshotSeed.string("emojiBubble") {
            let screenshotCoordinator = context.coordinator
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak view] in
                guard let view else { return }
                for (sectionIndex, section) in screenshotCoordinator.parent.sections.enumerated() {
                    guard let item = section.emojis.firstIndex(of: target) else { continue }
                    let indexPath = IndexPath(item: item, section: sectionIndex)
                    view.layoutIfNeeded()
                    screenshotCoordinator.collectionView(view, didHighlightItemAt: indexPath)
                    return
                }
            }
        }
        return view
    }'''
s = s[:j] + b + s[j + len(a):]
open(path, "w", encoding="utf-8").write(s)
print("patched KeyboardKeyComponents.swift")

# 5. 上余白の補正(縦画面で 17pt を透明な帯として高く申告する。3264)を切る。実機のホストが付ける灰色の余白を
#    打ち消すためのもので、シミュレーターのホストは余白を付けないので、帯がそのまま空白として写ってしまう(take 6 の失敗)
patch("KeyboardViewController+Layout.swift", [(
    "    static let hostPlaceholderTopInset: CGFloat = 17",
    "    static let hostPlaceholderTopInset: CGFloat = 0  // ★撮影用の一時変更(コミットしない)",
)])

# 6. 指定の面で最初から開く(高さの申告より前に面を決める)。表示直後に かな→絵文字 と切り替えると、
#    iOS が余白(17pt)を足す表示経路に入りやすかった(take 7 の 03 で 8 回連続)
patch("KeyboardViewController+Rendering.swift", [(
    """    func preferredInitialInputMode() -> KeyboardInputMode {
        switch textDocumentProxy.keyboardType {""",
    """    func preferredInitialInputMode() -> KeyboardInputMode {
        if let seeded = ScreenshotSeed.inputMode {  // ★撮影用の一時フック(コミットしない)
            return seeded
        }
        switch textDocumentProxy.keyboardType {""",
)])
patch("KeyboardViewController.swift", [(
    """        super.viewDidLoad()
        MemoryForensics.notePhase("個体の生成(viewDidLoad)")
""",
    """        super.viewDidLoad()
        MemoryForensics.notePhase("個体の生成(viewDidLoad)")
        if let seeded = ScreenshotSeed.inputMode {  // ★撮影用の一時フック(コミットしない)
            currentInputMode = seeded
        }
""",
)])

# 7. 2 段階フリックの吹き出しを出したままにする
patch("FlickKeyView.swift", [(
    """        .contentShape(Rectangle())
        .gesture(flickGesture)""",
    """        .contentShape(Rectangle())
        .gesture(flickGesture)
        // ★撮影用の一時フック(コミットしない): 指定キーの2段階フリックを出したままにする
        .onAppear {
            if let target = ScreenshotSeed.string("flickKey"), kana.center == target {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    isTouching = true
                    secondaryFlickPrimaryDirection = .gauche
                    secondaryFlickVerticalDirection = .haut
                }
            }
        }""",
)])
print("all hooks applied")
