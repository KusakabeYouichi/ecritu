import Foundation
@testable import EcrituConversion

// テスト専用の書き込み補助。本番のキーボード拡張は追加語彙を読むだけ(書くのはコンテナーアプリ)なので、
// KanaKanjiStore+Learning.swift から移した(2822)。テストターゲットは拡張のソースを直接コンパイルするため
// internal メンバー(ajoutVocabulary/withCacheLock/learningPersistQueue)に届く
extension KanaKanjiStore {
    func addUserEntry(reading: String, candidate: String) {
        let normalizedReading = KanaTextNormalizer.normalizedReading(reading)
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedReading.isEmpty,
                !trimmedCandidate.isEmpty else {
            return
        }

        var dictionary = ajoutVocabulary()
        var candidates = dictionary[normalizedReading] ?? []

        if let existingIndex = candidates.firstIndex(of: trimmedCandidate) {
            candidates.remove(at: existingIndex)
        }

        candidates.insert(trimmedCandidate, at: 0)
        dictionary[normalizedReading] = Array(candidates.prefix(32))
        withCacheLock { cachedAjoutVocabulary = dictionary }
        saveAjoutVocabulary(dictionary)
    }

    func saveAjoutVocabulary(_ dictionary: [String: [String]]) {
        guard let defaults,
                let encoded = try? JSONEncoder().encode(dictionary) else {
            return
        }

        defaults.set(encoded, forKey: KanaKanjiStorageKeys.ajoutVocabulary)
    }

    // 学習永続化の完了を待つ(フレッシュな store で defaults を読む前に呼ぶ)。デバウンス待ちの分も即時に書き出す
    func waitForPendingLearningPersists() {
        persistDirtyLearningNow()
        learningPersistQueue.sync {}
    }
}

extension KanjiRadicalFileIndex {
    var isEmpty: Bool { data.isEmpty }
}

// テストで KeyboardRootView を作る共通の入口。4 か所で同じ値を並べていたのをまとめ、違う値だけ引数にする(3829)
@MainActor
func makeTestKeyboardRootView(
    showsNextKeyboardKey: Bool = false,
    containerFrame: CGRect = .zero,
    kanaLayoutMode: KanaLayoutMode = .threeByThreePlusWa,
    leftModeSwitchNumberKeyRightFlickActionRawValue: String = "formattedNumber",
    leftModeSwitchLatinKeyRightFlickActionRawValue: String = "emoji",
    leftModeSwitchKanaKeyRightFlickActionRawValue: String = "kanjiRadical",
    kanaModeSwitcherTapActionRawValue: String = "symbols",
    kanaModeSwitcherRightFlickActionRawValue: String = "kaomoji",
    compactKeyboardSwitchKeyRightFlickActionRawValue: String = "kaomoji",
    compactKeyboardSwitchKeyUpFlickActionRawValue: String = "emoji",
    candidateBarModel: KeyboardCandidateBarModel = KeyboardCandidateBarModel()
) -> KeyboardRootView {
    KeyboardRootView(
        onTextInput: { _ in },
        onDeleteBackward: {},
        onLookupRadicalEntries: { _ in [] },
        onSpace: {},
        onReturn: {},
        onAdvanceKeyboard: {},
        onApplyKanaPostModifier: { _, _ in .ignored },
        onToggleParenthesesWrapper: {},
        onSelectConversionCandidate: { _ in },
        onCommitComposingText: {},
        onCommitComposingTextAsKatakana: {},
        onUpgradeRecentKanaCommitToKatakana: { false },
        onInputModeChanged: { _, _ in },
        showsNextKeyboardKey: showsNextKeyboardKey,
        containerFrame: containerFrame,
        directionProfile: .littlebear,
        kanaLayoutMode: kanaLayoutMode,
        kanaModifierPlacementMode: .postfix,
        numberLayoutMode: .calculette,
        latinLayoutMode: .flick,
        accentPaletteRawValue: "emeraude",
        isSystemDictionaryFallback: false,
        hasFullAccess: true,
        basicSymbolOrderRawValue: "ascii",
        temperatureUnitRawValue: TemperatureUnitPreference.celsius.rawValue,
        radicalStrokeCountStyleRawValue: "",
        spaceToastTrigger: 0,
        returnKeySystemImageName: nil,
        returnKeyTitleOverride: nil,
        isReturnKeyEnabled: true,
        kanaFlickGuideDisplayMode: .fourDirections,
        latinFlickGuideDisplayMode: .fourDirections,
        numberFlickGuideDisplayMode: .fourDirections,
        modifierFlickGuideDisplayMode: .off,
        keyRepeatInitialDelay: 0.5,
        keyRepeatInterval: 0.1,
        leftModeSwitchNumberKeyRightFlickActionRawValue: leftModeSwitchNumberKeyRightFlickActionRawValue,
        leftModeSwitchLatinKeyRightFlickActionRawValue: leftModeSwitchLatinKeyRightFlickActionRawValue,
        leftModeSwitchKanaKeyRightFlickActionRawValue: leftModeSwitchKanaKeyRightFlickActionRawValue,
        kanaModeSwitcherTapActionRawValue: kanaModeSwitcherTapActionRawValue,
        kanaModeSwitcherRightFlickActionRawValue: kanaModeSwitcherRightFlickActionRawValue,
        compactKeyboardSwitchKeyRightFlickActionRawValue: compactKeyboardSwitchKeyRightFlickActionRawValue,
        compactKeyboardSwitchKeyUpFlickActionRawValue: compactKeyboardSwitchKeyUpFlickActionRawValue,
        kanaPostModifierEmptyTapActionRawValue: "kaomoji",
        kanaPostModifierEmptyTapKaomojiCategoryID: "existing",
        kanaPostModifierEmptyTapEmojiCategoryID: "0",
        kanaPostModifierEmptyTapSymbolCategoryID: "0",
        kanaPostModifierFlickDakutenEnabled: true,
        landscapeCandidateSideRawValue: "left",
        landscapeNumberPaneSideRawValue: "left",
        landscapeLatinSuggestionModeRawValue: "sidebar",
        shortcutVocabulary: [],
        candidateBarModel: candidateBarModel,
        showsParenthesesWrapper: false,
        initialSpaceToastText: nil,
        initialInputMode: .kana
    )
}
