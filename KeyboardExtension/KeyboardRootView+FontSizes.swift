import SwiftUI
import UIKit
import CoreFoundation
import Darwin
import Contacts

extension KeyboardRootView {
    var returnActionKeyFontSize: CGFloat {
        isReturnActsAsCommitKey ? 16 : 22
    }

    func kanaThreeByThreeMainLabelFontSize(for displayMode: FlickGuideDisplayMode) -> CGFloat {
        switch displayMode {
        case .off:
            return 26
        case .fourDirections:
            return 24
        case .down:
            return 23
        }
    }

    var kanaThreeByThreeMainLabelFontSize: CGFloat {
        kanaThreeByThreeMainLabelFontSize(for: currentFlickGuideDisplayMode)
    }

    var numberThreeByThreeMainLabelFontSize: CGFloat {
        isLandscapeLayout ? 24 : 28
    }

    var modifierMainLabelFontSize: CGFloat {
        let baseSize: CGFloat = isKanaThreeByThreeMode
            ? kanaThreeByThreeMainLabelFontSize(for: modifierFlickGuideDisplayMode)
            : 28

        let centerLabel = modifierSelectorKey.center

        if inputMode == .kana && centerLabel == "小" {
            return baseSize * 0.6
        }

        let isPostfixKana = inputMode == .kana
            && kanaModifierPlacementMode == .postfix

        if isPostfixKana && centerLabel == "^_^" {
            return baseSize * 0.7
        }

        return baseSize
    }

    // 漢数字(一二三四五六七八九〇)はASCII数字より字幅が広いので少し小さめに描画する。
    func clavierMainKeyFontSize(for text: String) -> CGFloat {
        guard text.count == 1, let scalar = text.unicodeScalars.first else {
            return clavierKeyFontSize
        }
        // CJK統合漢字 (一〜九) と 〇 (U+3007)
        if (0x4E00...0x9FFF).contains(scalar.value) || scalar.value == 0x3007 {
            return clavierKeyFontSize - 4
        }
        return clavierKeyFontSize
    }

    var landscapeLeftModeSwitchFontSize: CGFloat {
        16
    }

    var landscapeLeftModeSwitchKaomojiIconFontSize: CGFloat {
        24
    }

    var portraitLeftModeSwitchFontSize: CGFloat {
        13
    }

    var unifiedLeftModeSwitchFontSize: CGFloat {
        isLandscapeLayout ? landscapeLeftModeSwitchFontSize : portraitLeftModeSwitchFontSize
    }

    var compactKanaModeSwitchButtonFontSize: CGFloat {
        unifiedLeftModeSwitchFontSize
    }

    var standardKanaModeSwitchButtonFontSize: CGFloat {
        unifiedLeftModeSwitchFontSize
    }

    var leftModeSwitchNumberFontSize: CGFloat {
        if usesWideLeftModeSwitchButtons && !isLandscapeLayout {
            return 18
        }

        return unifiedLeftModeSwitchFontSize
    }

    var leftModeSwitchLatinFontSize: CGFloat {
        if usesWideLeftModeSwitchButtons && !isLandscapeLayout {
            return 18
        }

        return unifiedLeftModeSwitchFontSize
    }

    var portraitCompactLeftModeSwitchKaomojiIconFontSize: CGFloat {
        28
    }

    var portraitWideLeftModeSwitchKaomojiIconFontSize: CGFloat {
        20
    }

    var portraitWideLeftModeSwitchEmojiIconFontSize: CGFloat {
        26
    }

    var kaomojiTransitionIconFontSize: CGFloat {
        if isLandscapeLayout {
            return landscapeLeftModeSwitchKaomojiIconFontSize
        }

        if usesWideLeftModeSwitchButtons {
            return portraitWideLeftModeSwitchKaomojiIconFontSize
        }

        return portraitCompactLeftModeSwitchKaomojiIconFontSize
    }

    var symbolTransitionIconFontSize: CGFloat {
        if isLandscapeLayout {
            return unifiedLeftModeSwitchFontSize
        }

        if usesWideLeftModeSwitchButtons {
            return 20
        }

        return 16
    }

    var portraitCompactKanaModeSwitcherIconFontSize: CGFloat {
        portraitCompactLeftModeSwitchKaomojiIconFontSize
    }

    var kanaModeSwitcherEmojiIconFontSize: CGFloat {
        if isLandscapeLayout {
            return landscapeLeftModeSwitchKaomojiIconFontSize
        }

        if !usesWideLeftModeSwitchButtons {
            return portraitCompactKanaModeSwitcherIconFontSize
        }

        return portraitWideLeftModeSwitchKaomojiIconFontSize
    }

    var kanaModeSwitcherFaceEmojiIconFontSize: CGFloat {
        if isLandscapeLayout {
            return landscapeLeftModeSwitchKaomojiIconFontSize
        }

        if !usesWideLeftModeSwitchButtons {
            return portraitCompactKanaModeSwitcherIconFontSize
        }

        return portraitWideLeftModeSwitchEmojiIconFontSize
    }

    var kanaModeSwitcherFaceEmojiMainLabelFontSize: CGFloat {
        if isLandscapeLayout || !usesWideLeftModeSwitchButtons {
            return kanaModeSwitcherFaceEmojiIconFontSize
        }

        return portraitWideLeftModeSwitchEmojiIconFontSize + 1
    }

    var kanaModeSwitcherKaomojiMainLabelFontSize: CGFloat {
        if isLandscapeLayout {
            return landscapeLeftModeSwitchKaomojiIconFontSize
        }

        return max(1, portraitWideLeftModeSwitchKaomojiIconFontSize - 1)
    }

    func compactKanaModeSwitcherMainLabelFontSize(for action: KanaModeSwitcherAction) -> CGFloat {
        switch action {
        case .symbols:
            return symbolTransitionIconFontSize
        case .emoji:
            return compactKanaModeSwitcherEmojiMainLabelFontSize
        case .kaomoji:
            return unifiedLeftModeSwitchFontSize
        }
    }

    func wideKanaModeSwitcherMainLabelFontSize(for action: KanaModeSwitcherAction) -> CGFloat {
        switch action {
        case .symbols:
            return symbolTransitionIconFontSize
        case .emoji:
            return kanaModeSwitcherFaceEmojiMainLabelFontSize
        case .kaomoji:
            return kanaModeSwitcherKaomojiMainLabelFontSize
        }
    }

    func compactKanaModeSwitcherActiveLabelFontSize(for action: KanaModeSwitcherAction) -> CGFloat {
        switch action {
        case .symbols:
            return symbolTransitionIconFontSize
        case .emoji:
            return compactKanaModeSwitcherEmojiActiveIconFontSize
        case .kaomoji:
            return compactKanaModeSwitcherPreviewIconFontSize
        }
    }

    func wideKanaModeSwitcherActiveMainLabelFontSize(for action: KanaModeSwitcherAction) -> CGFloat {
        switch action {
        case .symbols:
            return symbolTransitionIconFontSize
        case .emoji:
            return kanaModeSwitcherFaceEmojiIconFontSize
        case .kaomoji:
            return kanaModeSwitcherKaomojiMainLabelFontSize
        }
    }

    func wideKanaModeSwitcherActivePreviewFontSize(for action: KanaModeSwitcherAction) -> CGFloat {
        switch action {
        case .symbols:
            return symbolTransitionIconFontSize
        case .emoji:
            return kanaModeSwitcherFaceEmojiIconFontSize
        case .kaomoji:
            return kanaModeSwitcherEmojiIconFontSize
        }
    }

    var kanaModeSwitcherMainLabelFontSize: CGFloat {
        if !usesWideLeftModeSwitchButtons {
            return compactKanaModeSwitcherMainLabelFontSize(for: kanaModeSwitcherTapAction)
        }

        return wideKanaModeSwitcherMainLabelFontSize(for: kanaModeSwitcherTapAction)
    }

    func kanaModeSwitcherMainLabelFontSizeForDirection(
        _ direction: FlickDirection,
        mainText: String
    ) -> CGFloat {
        if mainText == "🌐" {
            return kaomojiTransitionIconFontSize
        }

        if !usesWideLeftModeSwitchButtons {
            if direction == .milieu {
                return kanaModeSwitcherMainLabelFontSize
            }

            if let action = kanaModeSwitcherAction(for: direction) {
                return compactKanaModeSwitcherActiveLabelFontSize(for: action)
            }

            if mainText == "⌘" {
                return symbolTransitionIconFontSize
            }

            if mainText == "☺︎" {
                return compactKanaModeSwitcherEmojiActiveIconFontSize
            }

            if mainText == "^_^" {
                return compactKanaModeSwitcherPreviewIconFontSize
            }

            return kanaModeSwitcherMainLabelFontSize
        }

        if direction == .milieu {
            return kanaModeSwitcherMainLabelFontSize
        }

        if let action = kanaModeSwitcherAction(for: direction) {
            return wideKanaModeSwitcherActiveMainLabelFontSize(for: action)
        }

        if mainText == "⌘" {
            return symbolTransitionIconFontSize
        }

        if mainText == "☺︎" {
            return kanaModeSwitcherFaceEmojiIconFontSize
        }

        if mainText == "^_^" {
            return kanaModeSwitcherKaomojiMainLabelFontSize
        }

        return kanaModeSwitcherMainLabelFontSize
    }

    var kanaModeSwitcherPreviewFontSize: CGFloat {
        return 14
    }

    var compactKanaModeSwitcherPreviewIconFontSize: CGFloat {
        18
    }

    var compactKanaModeSwitcherEmojiMainLabelFontSize: CGFloat {
        unifiedLeftModeSwitchFontSize + 2
    }

    var compactKanaModeSwitcherEmojiActiveIconFontSize: CGFloat {
        compactKanaModeSwitcherPreviewIconFontSize + 2
    }

    func kanaModeSwitcherPreviewFontSizeForDirection(
        _ direction: FlickDirection,
        previewText: String
    ) -> CGFloat {
        guard !isLandscapeLayout else {
            return kanaModeSwitcherPreviewFontSize
        }

        if !usesWideLeftModeSwitchButtons {
            if let action = kanaModeSwitcherAction(for: direction) {
                return compactKanaModeSwitcherActiveLabelFontSize(for: action)
            }

            if previewText == "⌘" {
                return symbolTransitionIconFontSize
            }

            if previewText == "☺︎" {
                return compactKanaModeSwitcherEmojiActiveIconFontSize
            }

            if previewText == "^_^" {
                return compactKanaModeSwitcherPreviewIconFontSize
            }

            return kanaModeSwitcherPreviewFontSize
        }

        if let action = kanaModeSwitcherAction(for: direction) {
            return wideKanaModeSwitcherActivePreviewFontSize(for: action)
        }

        if previewText == "⌘" {
            return symbolTransitionIconFontSize
        }

        if previewText == "☺︎" {
            return kanaModeSwitcherFaceEmojiIconFontSize
        }

        if previewText == "^_^" {
            return kanaModeSwitcherEmojiIconFontSize
        }

        return kanaModeSwitcherPreviewFontSize
    }
}
