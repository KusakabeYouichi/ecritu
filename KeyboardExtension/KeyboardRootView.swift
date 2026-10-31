import Foundation
import SwiftUI
import UIKit

struct KeyboardRootView: View {
    let onTextInput: (String) -> Void
    let onDeleteBackward: () -> Void
    // 部首ピッカーの字一覧(部首番号→字・部首内画数・区点・読み)。索引は mmap 保持なので
    // 呼ぶたびに引いても常駐コストは無い。ストアはコントローラ側が持つためクロージャで注入する。
    let onLookupRadicalEntries: (Int) -> [KanjiRadicalFileIndex.Entry]
    let onSpace: () -> Void
    let onReturn: () -> Void
    let onAdvanceKeyboard: () -> Void
    let onApplyKanaPostModifier: (KanaPostModifierButtonState, Bool) -> KanaPostModifierApplyOutcome
    let onToggleParenthesesWrapper: () -> Void
    let onSelectConversionCandidate: (Int) -> Void
    let onCommitComposingText: () -> Void
    let onCommitComposingTextAsKatakana: () -> Void
    let onUpgradeRecentKanaCommitToKatakana: () -> Bool
    // 第2引数は調査用ログ(記号面切替 2838): 切替の引き金とサブモード。原因判明後に外す
    let onInputModeChanged: (KeyboardInputMode, String) -> Void
    // でばぐ表示(削除キーの数字と色)を面の切り替え(サブモード含む)でも更新する要求(3304)。引数は切替の内容
    var onMemoryDebugDisplayRefreshRequested: (String) -> Void = { _ in }
    var onFormattedNumberCategoryChanged: () -> Void = {}
    // 絵文字/顔文字パネルで確定した文字列をショートカット語彙の先頭へ足す(3243。ユーザ指定)。
    // ショートカット・カテゴリー自身からの確定は対象外(手で並べた順を崩さない)
    var onShortcutCandidateCommitted: (String) -> Void = { _ in }
    let showsNextKeyboardKey: Bool
    // キーボードビューのウィンドウ座標の枠(KeyboardViewController が view.convert で測る)。
    // width が盤面の幅見積もり、minX/maxX が吹き出しのクランプに使われる。zero=未レイアウト
    let containerFrame: CGRect
    // 枠の外にある下端セーフエリア(ホームインジケーターの帯)。0 のときは従来どおり
    var bottomSafeAreaOutsideFrame: CGFloat = 0
    var containerWidth: CGFloat { containerFrame.width }
    let directionProfile: FlickDirectionProfile
    let kanaLayoutMode: KanaLayoutMode
    let kanaModifierPlacementMode: KanaModifierPlacementMode
    // 『や』キーの左右フリックの括弧(3585)。コンテナーアプリの設定。生成後に代入する(メンバーワイズ初期化の引数を増やさない)
    var kanaYaBracketMode: KanaYaBracketMode = .doubleCorner
    let numberLayoutMode: NumberLayoutMode
    let latinLayoutMode: LatinLayoutMode
    let accentPaletteRawValue: String
    let isSystemDictionaryFallback: Bool
    // フルアクセスの可否。オフだと app group への書き込みが黙って失敗し、学習も設定の保存も
    // 効かないのに見た目は正常なので、ユーザーが気づけない(2026-08-20 に実際に半日気づけず、
    // 読み取りだけは効いていたためテーマは設定どおりに見えていた)。全面の案内で知らせる。
    let hasFullAccess: Bool
    let keyboardBackgroundThemeRawValue: String
    let basicSymbolOrderRawValue: String
    let temperatureUnitRawValue: String
    let radicalStrokeCountStyleRawValue: String
    let spaceToastTrigger: Int
    let returnKeySystemImageName: String?
    let returnKeyTitleOverride: String?
    let isReturnKeyEnabled: Bool
    let kanaFlickGuideDisplayMode: FlickGuideDisplayMode
    let latinFlickGuideDisplayMode: FlickGuideDisplayMode
    let numberFlickGuideDisplayMode: FlickGuideDisplayMode
    let modifierFlickGuideDisplayMode: FlickGuideDisplayMode
    let keyRepeatInitialDelay: TimeInterval
    let keyRepeatInterval: TimeInterval
    // 左端のモード切り替え列の割り当て(設定 E.5。3618 で右フリックを復活)。上 3 段は右フリックだけ、
    // 最下段はタップと右フリック、🌐 キー(ホームボタンのある画面の狭い iPhone の かな 5×2 縦画面)は右と上
    let leftModeSwitchNumberKeyRightFlickActionRawValue: String
    let leftModeSwitchLatinKeyRightFlickActionRawValue: String
    let leftModeSwitchKanaKeyRightFlickActionRawValue: String
    let kanaModeSwitcherTapActionRawValue: String
    let kanaModeSwitcherRightFlickActionRawValue: String
    let compactKeyboardSwitchKeyRightFlickActionRawValue: String
    let compactKeyboardSwitchKeyUpFlickActionRawValue: String
    let kanaPostModifierEmptyTapActionRawValue: String
    let kanaPostModifierEmptyTapKaomojiCategoryID: String
    let kanaPostModifierEmptyTapEmojiCategoryID: String
    let kanaPostModifierEmptyTapSymbolCategoryID: String
    let kanaPostModifierFlickDakutenEnabled: Bool
    let landscapeCandidateSideRawValue: String
    let landscapeNumberPaneSideRawValue: String
    let landscapeLatinSuggestionModeRawValue: String
    let shortcutVocabulary: [String]
    // 候補バー系の状態は ObservableObject 経由で受ける。候補だけが変わる打鍵では
    // rootView を差し替えず(=UIHostingController の同期 layoutIfNeeded も走らせず)、
    // モデルの publish だけで SwiftUI に再評価させるため。既存の消費箇所は
    // computed プロパティで無改修のまま互換にする。
    @ObservedObject var candidateBarModel: KeyboardCandidateBarModel
    var composingText: String { candidateBarModel.composingText }
    // tokushima(3211): 候補欄に出す未確定(下線付き)
    var internalCompositionPreviewText: String { candidateBarModel.internalCompositionPreviewText }
    var conversionCandidates: [String] { candidateBarModel.conversionCandidates }
    var selectedConversionCandidateIndex: Int? { candidateBarModel.selectedConversionCandidateIndex }
    var latinSuggestionQuery: String { candidateBarModel.latinSuggestionQuery }
    var latinSuggestions: [String] { candidateBarModel.latinSuggestions }
    var kanaPostModifierButtonState: KanaPostModifierButtonState { candidateBarModel.kanaPostModifierButtonState }
    let showsParenthesesWrapper: Bool
    let initialSpaceToastText: String?
    // フィールドの keyboardType(数字入力欄等)に合わせた初期入力モード(4.4.1 準拠)。
    // onAppear で inputState.inputMode に反映する
    let initialInputMode: KeyboardInputMode

    // 入力の状態(面・濁点・かな/カナ・ラテン文字シフト・空白の案内・かなへ戻る印・2 度押し待ち)。
    // 持ち主はここだけ(makeRootView からは渡さない)。寿命は以前の @State と同じ
    @State var inputState = KeyboardInputState()
    // 以下は inputState への取り次ぎ(呼び元を書き換えずに済ませるため)
    var inputMode: KeyboardInputMode {
        get { inputState.inputMode }
        nonmutating set { inputState.inputMode = newValue }
    }
    var diacriticMode: DiacriticMode {
        get { inputState.diacriticMode }
        nonmutating set { inputState.diacriticMode = newValue }
    }
    var kanaCharacterMode: KanaCharacterMode {
        get { inputState.kanaCharacterMode }
        nonmutating set { inputState.kanaCharacterMode = newValue }
    }
    var latinShiftState: LatinShiftState {
        get { inputState.latinShiftState }
        nonmutating set { inputState.latinShiftState = newValue }
    }
    var emojiInputSubmode: EmojiInputSubmode {
        get { inputState.emojiInputSubmode }
        nonmutating set { inputState.emojiInputSubmode = newValue }
    }
    var spaceToastText: String? {
        get { inputState.spaceToastText }
        nonmutating set { inputState.spaceToastText = newValue }
    }
    var spaceToastOpacity: Double {
        get { inputState.spaceToastOpacity }
        nonmutating set { inputState.spaceToastOpacity = newValue }
    }
    var isAwaitingLatinModeSwitchSecondTap: Bool { inputState.isAwaitingLatinModeSwitchSecondTap }
    @State private var lastInputModeObservation: InputModeObservation?
    @State var activeLayerIndex: Int? = nil
    // 触れているのが左の面切替の列か(3167)。列は段より前に描いているので、
    // 段のキーの左フリックの吹き出しが列に隠れていた。列側が触られていないときは列を下げる
    @State var isTouchingLeftModeSwitchColumn = false
    @State var lastShownSpaceToastTrigger = -1
    // フルアクセス案内を閉じたか。オフのままでも変換は動くので、閉じれば通常どおり使える。
    // フルアクセス未許可の案内を閉じた記録。拡張ローカルの UserDefaults.standard に永続化する
    // (フルアクセス無しでも書ける)。以前は @State で、アプリ切替ごとに案内が全面に再表示され
    // 「フルアクセス必須」に見えていた(ガイドライン 4.4.1。2785)。
    // 閉じた記録は版(edition)ごと(3464)。一度閉じると二度と出ず、テスターがオフのまま診断ログが取れていないことに
    // 気づけなかった。新しい版を入れたら 1 回だけ出し直す
    @State private var didDismissFullAccessNotice = UserDefaults.standard.string(
        forKey: KeyboardRootView.fullAccessNoticeDismissedEditionKey
    ) == KeyboardRootView.currentEdition
    static let fullAccessNoticeDismissedEditionKey = "fullAccessNoticeDismissedEdition"
    static var currentEdition: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
    }
    // 面を切り替えるキー(左下)の接触時間の下限(ms)。これより短い接触では面を変えない(2938)。
    // 根拠: 机に置いた衝撃での誤発火が 58ms(開始位置はキーの外、移動量 41pt の下フリック)。
    // 人の意図的なタップ/フリックは概ね 80ms 以上。文字入力のキーには効かせない
    static let kanaModeSwitcherMinimumTouchDurationMs = 70
    // 絵文字・記号の分類と、調査用ログ(記号面切替 2838)の引き金は inputState が持つ。以下は取り次ぎ
    var selectedEmojiCategory: EmojiCategory {
        get { inputState.selectedEmojiCategory }
        nonmutating set { inputState.selectedEmojiCategory = newValue }
    }
    var selectedSymbolCategory: SymbolCategory {
        get { inputState.selectedSymbolCategory }
        nonmutating set { inputState.selectedSymbolCategory = newValue }
    }
    var inputModeChangeTrigger: String {
        get { inputState.inputModeChangeTrigger }
        nonmutating set { inputState.inputModeChangeTrigger = newValue }
    }
    @State var radicalPickerState = RadicalPickerState()
    @State var kaomojiPanelState = KaomojiPanelState()
    // 書式化数値の入力の状態(バッファ・カテゴリー・単位/接頭辞・スイッチ・日付と書式)。
    // 持ち主はここだけ。寿命は以前の @State と同じ
    @State var formattedNumberState = FormattedNumberState()
    // 単位ドラムをプレス中、選択中単位のフル表記カードを表示するか。
    @State var formattedNumberDrumFullNameVisible: Bool = false
    // プレス中に自前ホイールから随時通知される中央行のタグ(空=非プレス)。
    @State var formattedNumberDrumLiveTag: String = ""
    @State var didTriggerComposingCommitLongPress = false
    @State var katakanaCommitFeedbackText: String? = nil
    @State var pendingKatakanaCommitWorkItem: DispatchWorkItem?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    var layoutMetrics: KeyboardLayoutMetrics = .phone
    // 広い横画面(iPhone Duo の内画面。3570)。生成後に代入する。普通の iPhone・iPad は常に false
    var usesWideLandscapeLayout = false
    // 大きな画面の iPhone(Duo の内画面)を縦で使うとき、申告に足した高さ。段と間隔に配る(3570)
    var largePortraitExtraHeight: CGFloat = 0
    var isLargePhonePortrait: Bool { largePortraitExtraHeight > 0 && !isLandscapeLayout }
    // 横向きでカメラのぶん膨らんだ下の安全領域の代わりに空ける量(Duo の外画面。VC 側で安全領域を切る。3570)
    var replacedLandscapeBottomInset: CGFloat = 0
    // 面の高さ(VC の hostContentHeight)。縦では containerFrame がホスト枠の補正の帯(17pt)を含むので、枠から
    // 逆算するときはこちらを使う(3570)
    var faceHeight: CGFloat = 0
    // 折りたたみの iPhone(Duo)か(VC の isFoldablePhone)。普通の iPhone では Duo 向けの調整を一切効かせない(3570)
    var isFoldablePhone = false
    // 足した 28pt は全部段に配る(+7×4)。純正は段 71・間隔 8 で、間隔は広げない
    static let largePortraitKeyHeightBoost: CGFloat = 7

    let shiftDoubleTapThreshold: TimeInterval = 0.32
    let latinModeSwitchDoubleTapThreshold: TimeInterval = 0.28
    let katakanaCommitDoubleTapThreshold: TimeInterval = 0.2
    let katakanaCommitFeedbackDelay: TimeInterval = 0.14
    let keyLabelColor = KeyboardThemePalette.keyLabel
    // 候補欄の枠の高さ。帯のぶんを詰める縦向き(定義コメント参照。3165-3166)では、
    // 空のときに上へ大きく空いて見えるので 4pt 詰め、そのぶんをキーの高さへ回す(ユーザー報告 3169)
    private var candidateHeaderExpandedHeight: CGFloat {
        layoutMetrics.candidateHeaderExpandedHeight - (trimsPortraitContentForHomeIndicator ? 4 : 0)
    }
    private let candidateHeaderContentDownshift: CGFloat = 4
    // 縦画面の候補欄の先頭に常に確保する未確定の行の高さ(3216→3219 で 12→9、ユーザ指定)。tokushima 方式はここに
    // 未確定文字(10pt)を上寄せで出し、はみ出す 2〜3pt はチップの上余白(6pt)に食い込ませる。écritu/mountain view は
    // 空のまま。常に確保するのは、入力中/確定後や方式の切り替えでチップの位置が動かないようにするため(3213-3216)
    static let candidateHeaderCompositionRowHeight: CGFloat = 8
    // 候補チップの内側の上下余白(3226 で 4→2、3239 で 2→1。候補欄 31pt に未確定の行を詰め込むため。欧文サジェストも同じ)
    static let candidateChipVerticalPadding: CGFloat = 1
    // 寸法・位置は KeyboardLayoutMetrics に集約(2609)。端末別の値はそちらで分岐する。
    private var frameMetrics: KeyboardLayoutMetrics.FrameMetrics {
        layoutMetrics.frame(usesCompactLandscapeLayout: isLandscapeLayout)
    }
    // 縦向きでホームインジケーターの帯が枠の外にある機種では、中身が枠より 24pt 高く、
    // 上下にはみ出していた(3163 の実測)。下に 8pt の隙間を残したうえで枠に収めるため、
    // 段間を 1pt、段の高さを 2pt だけ詰める(合計 12pt。ユーザー指定 3165)。
    // 帯の無い機種(ホームボタン機)と横向きは従来どおり
    var trimsPortraitContentForHomeIndicator: Bool {
        bottomSafeAreaOutsideFrame > 0 && !isLandscapeLayout
    }

    var keyboardRowSpacing: CGFloat {
        frameMetrics.rowSpacing - (trimsPortraitContentForHomeIndicator ? 1 : 0)
    }
    // 上のクラスタ高さの逆算で使う外周(private の keyboardTopPadding/BottomPadding と同じ値)
    var keyboardTopPaddingForCluster: CGFloat { keyboardTopPadding }
    var keyboardBottomPaddingForCluster: CGFloat { keyboardBottomPadding }

    private var keyboardTopPadding: CGFloat {
        // 帯のぶんの詰め(定義コメント参照。3166): キーを 1pt 戻したぶんを上の 3pt から出す
        if trimsPortraitContentForHomeIndicator {
            return 0
        }

        if usesWideLandscapeSidebar {
            return Self.wideLandscapeVerticalPadding
        }

        if isLandscapeLayout
            && (inputMode == .kana || inputMode == .number || isLandscapeLatinThreeByThreeMode) {
            return frameMetrics.topPaddingWhenRowsAreDense
        }

        return frameMetrics.topPadding
    }
    // 広い横画面の候補欄の幅(+LandscapeLayouts)も外側余白を引くので private にしない(3570)
    var keyboardHorizontalPadding: CGFloat { frameMetrics.horizontalPadding }
    // 下の余白。枠の外にホームインジケーターの帯がある縦向きでは、帯のぶんが二重になるので
    // 20pt は使わず 8pt に整理する(ユーザー指定 3165。高さの表も同じ前提で 12pt 多く要求する)。
    // 帯が無い機種(ホームボタン機)や横向きでは従来どおり
    private var keyboardBottomPadding: CGFloat {
        if usesWideLandscapeSidebar {
            return Self.wideLandscapeVerticalPadding
        }
        if replacedLandscapeBottomInset > 0 {
            return replacedLandscapeBottomInset + frameMetrics.bottomPadding
        }
        return bottomSafeAreaOutsideFrame > 0
            ? Self.portraitBottomGapOverHomeIndicator
            : frameMetrics.bottomPadding
    }
    // 広い横画面(iPhone Duo の内画面)の上下の余白(3570)。窓はホームバーより上で終わるのに iOS は下に 18pt の
    // 安全領域を伝えてくるため、キーの上 3pt・下 26pt と偏っていた。安全領域は使わず(VC 側で切る)上下を同じにする
    static let wideLandscapeVerticalPadding: CGFloat = 6
    // 3165 は 8pt。キーを 1pt 戻したぶんを上 3pt・下 1pt から出す(ユーザー指定 3166)。
    // 3228 で 7→5: 純正より 2pt 高かったぶん(動画の画素比較)をここから出す
    static let portraitBottomGapOverHomeIndicator: CGFloat = 5
    let candidateStateFontSize: CGFloat = 15
    let candidateTextFontSize: CGFloat = 16
    var compactActionKeyHeight: CGFloat { frameMetrics.actionKeyHeight }
    private let compactModeSwitchKeyWidth: CGFloat = 32
    private let wideModeSwitchKeyWidth: CGFloat = 58
    let compactEmojiKeyHeight: CGFloat = 28
    let compactKaomojiKeyHeight: CGFloat = 30
    let emojiGridSpacing: CGFloat = 2
    let kaomojiMaxColumns = 5
    let kaomojiMinKeyWidth: CGFloat = 52
    let kaomojiHorizontalPadding: CGFloat = 8
    let kaomojiFontSize: CGFloat = 18
    let kaomojiMinInterItemSpacingMultiplier: CGFloat = 1.2
    let kaomojiCategoryButtonWidth: CGFloat = 40

    var showsKanaConversionCandidates: Bool {
        inputMode == .kana && (!composingText.isEmpty || showsParenthesesWrapper)
    }

    // 横組み(段を詰めた背の低い構成)を使うかの唯一の判定。高さ計算側
    // (KeyboardViewController+Layout.preferredKeyboardHeight)も同じ metrics を見るので、
    // 「ビューは縦組み・枠は横組み」という食い違いが構造的に起きない。
    // iPad は verticalSizeClass が横画面でも .regular なうえ、metrics 側で
    // allowsCompactLandscapeLayout=false なので常に縦組みになる。
    var isLandscapeLayout: Bool {
        layoutMetrics.usesCompactLandscapeLayout(isLandscapeOrientation: verticalSizeClass == .compact)
    }

    var showsLatinSuggestionCandidates: Bool {
        inputMode == .latin && !latinSuggestionQuery.isEmpty
    }

    var needsQwertyMiddleRowApostrophe: Bool {
        latinLayoutMode == .qwerty
    }

    var usesPortraitLatinInlineDeleteLayout: Bool {
        !isLandscapeLayout
            && inputMode == .latin
            && (latinLayoutMode == .qwerty || latinLayoutMode == .azerty)
    }

    private var portraitLatinQwertyBottomRowSlackWidth: CGFloat {
        guard usesPortraitLatinInlineDeleteLayout,
            latinLayoutMode == .qwerty else {
            return 0
        }

        let estimatedKeyboardWidth = max(
            1,
            keyboardContainerWidth - keyboardHorizontalPadding * 2
        )
        let leadingControlWidth: CGFloat = showsCompactLeftModeSwitchButtons
            ? (leftModeSwitchButtonWidth + keyboardRowSpacing)
            : 0
        let letterAreaWidth = max(1, estimatedKeyboardWidth - leadingControlWidth)
        let topRowLetterCount = CGFloat(max(rows.first?.count ?? 10, 1))
        let topRowLetterSpacingCount = CGFloat(max(Int(topRowLetterCount) - 1, 0))
        let topRowLetterWidth = max(
            1,
            (letterAreaWidth - keyboardRowSpacing * topRowLetterSpacingCount) / topRowLetterCount
        )

        // Width budget previously expressed as trailing inset; now redistributed to Shift/Delete.
        let trailingPitchFactor: CGFloat = 0.75
        return (topRowLetterWidth + keyboardRowSpacing) * trailingPitchFactor
    }

    // 縦向きの QWERTY/AZERTY の下段(シフト+ラテン文字+アポストロフィー+削除)のキー幅(3512)。
    // アポストロフィー(')は英単語・メール・URI・パスワード用で頻度が低く字も細いので、ラテン文字の半分の幅の
    // 狭いキーにする。幅は 削除キーを足す前と同じに保ち(ユーザ指定)、残りをシフトとラテン文字で分ける
    struct PortraitLatinBottomRowKeyMetrics: Equatable {
        let letter: CGFloat
        let shift: CGFloat
        let delete: CGFloat
        let apostrophe: CGFloat
    }

    static let latinApostropheKeyWidthFactor: CGFloat = 0.5

    // 下段右端のアポストロフィーのキー。中心は「'」(U+0027。メール・URI・パスワードで要る方)、
    // 左フリックに「’」(U+2019。組版用)。ラテン文字でないキーなので QWERTY/AZERTY でもフリックが効く
    static let latinApostropheKey = FlickKanaSet(
        label: "'",
        center: "'",
        up: "",
        right: "",
        down: "",
        left: "’",
        // 左は物理的な左(フリック方向の流儀で並べ替えない)
        usesProfileDependentGuideOrder: false
    )
    func portraitLatinBottomRowKeyMetrics(rowIndex: Int) -> PortraitLatinBottomRowKeyMetrics? {
        guard usesPortraitLatinInlineDeleteLayout,
            rowIndex == 2 else {
            return nil
        }

        let estimatedKeyboardWidth = max(
            1,
            keyboardContainerWidth - keyboardHorizontalPadding * 2
        )
        let leadingControlWidth: CGFloat = showsCompactLeftModeSwitchButtons
            ? (leftModeSwitchButtonWidth + keyboardRowSpacing)
            : 0
        let availableRowWidth = max(1, estimatedKeyboardWidth - leadingControlWidth)

        // QWERTY のアポストロフィーは中段右端(3515。portraitQwertyMiddleRowApostropheWidth 参照)なので下段には無い
        return Self.portraitLatinBottomRowKeyMetrics(
            availableRowWidth: availableRowWidth,
            spacing: keyboardRowSpacing,
            slackWidth: portraitLatinQwertyBottomRowSlackWidth,
            letterCount: latinLayoutMode == .azerty ? 6 : 7,
            includesApostrophe: latinLayoutMode == .azerty
        )
    }

    // 純粋関数(テスト用に分離)。slackWidth は QWERTY で削除/シフトに配る余白(AZERTY は 0)。
    // アポストロフィーを足す前の並び(シフト+ラテン文字+削除。QWERTY は 9 キー、AZERTY は 8 キー)の
    // シフトと削除の幅をそのまま使い、残りの幅をラテン文字とアポストロフィー(ラテン文字の半分)で分ける。
    // 当初はシフトもラテン文字と一緒に縮めていたが、AZERTY で 3.6pt 狭くなり打ちにくかった(ユーザ報告 3514)。
    // includesApostrophe が false(QWERTY)なら以前の並びのまま(apostrophe は 0)
    static func portraitLatinBottomRowKeyMetrics(
        availableRowWidth: CGFloat,
        spacing: CGFloat,
        slackWidth: CGFloat,
        letterCount: Int,
        includesApostrophe: Bool
    ) -> PortraitLatinBottomRowKeyMetrics {
        let letters = CGFloat(letterCount)
        // 以前の並び: シフト + ラテン文字 + 削除(キー数 letters+2、隙間 letters+1)
        let previousKeyCount = letters + 2
        let previousLetterWidth = max(
            1,
            (availableRowWidth - slackWidth - spacing * (previousKeyCount - 1)) / previousKeyCount
        )
        let edgeWidth = previousLetterWidth + slackWidth / 2
        guard includesApostrophe else {
            return PortraitLatinBottomRowKeyMetrics(
                letter: previousLetterWidth, shift: edgeWidth, delete: edgeWidth, apostrophe: 0)
        }
        // 新しい並び: シフト + ラテン文字 + アポストロフィー + 削除(隙間 letters+2)
        let remaining = availableRowWidth - edgeWidth * 2 - spacing * (letters + 2)
        let letterWidth = max(1, remaining / (letters + latinApostropheKeyWidthFactor))

        return PortraitLatinBottomRowKeyMetrics(
            letter: letterWidth,
            shift: edgeWidth,
            delete: edgeWidth,
            apostrophe: letterWidth * latinApostropheKeyWidthFactor
        )
    }

    // 縦向き QWERTY の中段(asdfghjkl)右端のアポストロフィーの幅(3515、ユーザ指定)。中段は 9 字で上段(10 字)より
    // 広いので、ここに半分幅のキーを足してもラテン文字は上段より広いまま(iPhone 15: 33.5 → 31.0pt、上段 29.5pt)。
    // 下段(シフト+7 字+削除)は触らない。ラテン文字は伸縮のままなので、ここではラテン文字が半分幅の分だけ詰まる幅を返す
    func portraitQwertyMiddleRowApostropheWidth(rowIndex: Int) -> CGFloat? {
        guard usesPortraitLatinInlineDeleteLayout,
            latinLayoutMode == .qwerty,
            rowIndex == 1 else {
            return nil
        }
        let estimatedKeyboardWidth = max(1, keyboardContainerWidth - keyboardHorizontalPadding * 2)
        let leadingControlWidth: CGFloat = showsCompactLeftModeSwitchButtons
            ? (leftModeSwitchButtonWidth + keyboardRowSpacing)
            : 0
        return Self.portraitQwertyMiddleRowApostropheWidth(
            availableRowWidth: max(1, estimatedKeyboardWidth - leadingControlWidth),
            spacing: keyboardRowSpacing,
            letterCount: rows.indices.contains(1) ? rows[1].count : 9
        )
    }

    static func portraitQwertyMiddleRowApostropheWidth(
        availableRowWidth: CGFloat,
        spacing: CGFloat,
        letterCount: Int
    ) -> CGFloat {
        let letters = CGFloat(letterCount)
        let letterWidth = max(1, (availableRowWidth - spacing * letters) / (letters + latinApostropheKeyWidthFactor))
        return letterWidth * latinApostropheKeyWidthFactor
    }

    func shouldReplacePortraitAzertyRightShiftWithDelete(
        rowIndex: Int,
        kana: FlickKanaSet
    ) -> Bool {
        usesPortraitLatinInlineDeleteLayout
            && latinLayoutMode == .azerty
            && rowIndex == 2
            && isLandscapeLatinRightShiftKey(kana)
    }

    // clavier 縦画面では行3 (rowIndex == 2) の右 shift トークンを delete に差し替える
    // (AZERTY portrait の挙動と同じ)。
    var usesPortraitClavierInlineDeleteLayout: Bool {
        !isLandscapeLayout
            && inputMode == .number
            && effectiveNumberLayoutMode == .clavier
    }

    func shouldReplacePortraitClavierRightShiftWithDelete(
        rowIndex: Int,
        kana: FlickKanaSet
    ) -> Bool {
        usesPortraitClavierInlineDeleteLayout
            && rowIndex == 2
            && isLandscapeLatinRightShiftKey(kana)
    }

    func shouldAppendPortraitQwertyDeleteKey(rowIndex: Int) -> Bool {
        usesPortraitLatinInlineDeleteLayout
            && latinLayoutMode == .qwerty
            && rowIndex == 2
    }

    var portraitLatinDeleteReplacementSymbol: String {
        "@"
    }

    private var latinSpaceRightActionSymbols: [String] {
        if isLandscapeLayout,
            latinLayoutMode == .qwerty || latinLayoutMode == .azerty {
            return [".", "-"]
        }

        if !isLandscapeLayout,
            latinLayoutMode == .qwerty || latinLayoutMode == .azerty {
            return [".", "-"]
        }

        return ["!", "?", "@", "&", "/"]
    }

    private var latinSpaceLeftActionSymbols: [String] {
        if isLandscapeLayout,
            latinLayoutMode == .qwerty || latinLayoutMode == .azerty {
            return ["@", "_"]
        }

        if !isLandscapeLayout,
            latinLayoutMode == .qwerty || latinLayoutMode == .azerty {
            return ["/"]
        }

        return [":", "_", "(", ")"]
    }

    @ViewBuilder
    private func latinActionButtons(
        symbols: [String],
        fixedWidth: CGFloat? = nil,
        keyHeight: CGFloat? = nil
    ) -> some View {
        let resolvedKeyHeight = keyHeight ?? compactActionKeyHeight
        // 縦向きの QWERTY/AZERTY の / . - は数字 clavier と同じサイズ(定義コメント参照)。
        // フリック配列の !?@&/ や横向きは従来の 20pt
        let usesClavierSymbolSizes = !isLandscapeLayout
            && (latinLayoutMode == .qwerty || latinLayoutMode == .azerty)

        ForEach(symbols, id: \.self) { symbol in
            ActionKeyButton(
                title: symbol,
                fontSize: usesClavierSymbolSizes ? clavierInlineSymbolFontSize(for: symbol) : 20,
                fixedWidth: fixedWidth,
                action: { commitText(symbol) }
            )
                .frame(height: resolvedKeyHeight)
        }
    }

    @ViewBuilder
    func latinSpaceLeftActionButtons(
        fixedWidth: CGFloat? = nil,
        keyHeight: CGFloat? = nil
    ) -> some View {
        latinActionButtons(
            symbols: latinSpaceLeftActionSymbols,
            fixedWidth: fixedWidth,
            keyHeight: keyHeight
        )
    }

    @ViewBuilder
    func latinSpaceRightActionButtons(
        fixedWidth: CGFloat? = nil,
        keyHeight: CGFloat? = nil
    ) -> some View {
        latinActionButtons(
            symbols: latinSpaceRightActionSymbols,
            fixedWidth: fixedWidth,
            keyHeight: keyHeight
        )
    }

    private var landscapeEmojiHeaderHeight: CGFloat { 26 }

    var emojiHeaderTopPadding: CGFloat { isLandscapeLayout ? 8 : 13 }

    var candidateHeaderHeight: CGFloat {
        if isLandscapeLayout {
            if inputMode == .emoji {
                return landscapeEmojiHeaderHeight
            }

            return 0
        }

        // 候補表示時の押し下げをなくすため、テキスト系モードでも常に同じヘッダー領域を予約する。
        return candidateHeaderExpandedHeight
    }

    private var isActiveConversion: Bool {
        selectedConversionCandidateIndex != nil
    }

    // VoiceOver 用の状態名(表示はアイコンのミニカプセルに置き換え済み)。
    var conversionStateLabel: String {
        isActiveConversion ? "変換中" : "未確定"
    }

    // 状態はテキストラベルでなく SF Symbols のミニカプセルで示す(候補エリアの節約)。
    // 鉛筆=未確定(編集中)、循環矢印=変換中(スペース送り)。
    var conversionStateIconName: String {
        isActiveConversion ? "arrow.triangle.2.circlepath" : "pencil"
    }

    var conversionStateColor: Color {
        isActiveConversion ? accentColor : Color.orange
    }

    var isSpaceActsAsConversionKey: Bool {
        inputMode == .kana && !composingText.isEmpty
    }

    var spaceKeyDisplayTitle: String {
        if isSpaceActsAsConversionKey {
            return "変換"
        }

        if inputMode == .kana {
            return spaceToastText ?? ""
        }

        return ""
    }

    var spaceKeyDisplayOpacity: Double {
        if isSpaceActsAsConversionKey {
            return 1
        }

        return inputMode == .kana ? spaceToastOpacity : 0
    }

    var spaceKeyAccessibilityLabel: String {
        isSpaceActsAsConversionKey ? "変換" : "空白"
    }

    var isReturnActsAsCommitKey: Bool {
        inputMode == .kana && !composingText.isEmpty
    }

    // 改行/確定キー(タイトル・アイコン・カタカナ確定の長押し/ダブルタップを束ねる)。
    // 各レイアウトで同じ引数列を 7 か所に書いていたのを集約(2805)
    func returnActionKey(fixedWidth: CGFloat? = nil) -> ActionKeyButton {
        ActionKeyButton(
            title: returnActionKeyTitle,
            systemImageName: returnActionKeySystemImageName,
            accessibilityLabel: returnActionKeyAccessibilityLabel,
            fontSize: returnActionKeyFontSize,
            fixedWidth: fixedWidth,
            isEnabled: isReturnKeyEnabled,
            onLongPress: returnKeyKatakanaLongPressAction,
            onDoubleTap: returnKeyKatakanaDoubleTapAction,
            doubleTapThreshold: katakanaCommitDoubleTapThreshold,
            prefersImmediateSingleTapWhenDoubleTapEnabled: true,
            action: onReturn
        )
    }

    var returnActionKeyTitle: String {
        if isReturnActsAsCommitKey {
            return "確定"
        }

        if returnKeySystemImageName == nil, let returnKeyTitleOverride {
            return returnKeyTitleOverride
        }
        return returnKeySystemImageName == nil ? "⏎" : ""
    }

    var returnActionKeySystemImageName: String? {
        isReturnActsAsCommitKey ? nil : returnKeySystemImageName
    }

    var returnActionKeyAccessibilityLabel: String {
        if isReturnActsAsCommitKey {
            return "確定"
        }

        if returnKeySystemImageName == nil, let returnKeyTitleOverride {
            return returnKeyTitleOverride
        }
        return returnKeySystemImageName == nil ? "改行" : "検索"
    }

    var returnKeyKatakanaDoubleTapAction: (() -> Void)? {
        isReturnActsAsCommitKey ? handleReturnKeyKatakanaDoubleTap : nil
    }

    var returnKeyKatakanaLongPressAction: (() -> Void)? {
        isReturnActsAsCommitKey ? handleReturnKeyKatakanaLongPress : nil
    }

    var canTapComposingTextToCommit: Bool {
        !composingText.isEmpty
    }

    private var accentPalette: AccentPalette {
        AccentPalette(rawValue: accentPaletteRawValue) ?? .emeraude
    }

    var accentColor: Color {
        if isSystemDictionaryFallback {
            return Color(uiColor: .systemGray)
        }

        return accentPalette.color
    }

    var basicSymbolOrder: BasicSymbolOrder {
        BasicSymbolOrder(rawValue: basicSymbolOrderRawValue) ?? .ascii
    }

    var temperatureUnit: TemperatureUnitPreference {
        TemperatureUnitPreference(rawValue: temperatureUnitRawValue) ?? .celsius
    }

    var radicalStrokeChoices: RadicalStrokeChoices {
        RadicalStrokeChoices(rawValue: radicalStrokeCountStyleRawValue)
    }

    var currentFlickGuideDisplayMode: FlickGuideDisplayMode {
        switch inputMode {
        case .kana:
            return kanaFlickGuideDisplayMode
        case .latin:
            guard latinLayoutMode == .flick else {
                return .off
            }
            return latinFlickGuideDisplayMode
        case .number:
            // clavier はフリック方向を持たない単純キーなので、フリックガイドは常に off
            // (これにより中央ラベルの上方オフセットがかからず、文字が中央表示になる)
            if effectiveNumberLayoutMode == .clavier {
                return .off
            }
            return numberFlickGuideDisplayMode
        case .emoji:
            return .off
        case .formattedNumber:
            return .off
        }
    }

    var showsFlickGuideCharacters: Bool {
        currentFlickGuideDisplayMode == .fourDirections
    }

    var showsModifierFlickGuideCharacters: Bool {
        modifierFlickGuideDisplayMode == .fourDirections
    }

    var isCurrentFlickGuideDisplayOff: Bool {
        currentFlickGuideDisplayMode == .off
    }

    var isModifierFlickGuideDisplayOff: Bool {
        modifierFlickGuideDisplayMode == .off
    }

    // 適用(と漢字ピッカーの計測)は KeyboardInputState.transitionState の setter が行なう
    var transitionState: KeyboardModeTransitionState {
        get { inputState.transitionState }
        nonmutating set { inputState.transitionState = newValue }
    }

    var activeKanaModifierMode: DiacriticMode {
        kanaModifierPlacementMode == .prefix ? diacriticMode : .none
    }

    var isPrefixModifierActive: Bool {
        inputMode == .kana && kanaModifierPlacementMode == .prefix && diacriticMode != .none
    }

    var rows: [[FlickKanaSet]] {
        switch inputMode {
        case .kana:
            return FlickKanaLayout.rows(for: activeKanaModifierMode, layoutMode: kanaLayoutMode, profile: directionProfile, yaBracket: kanaYaBracketMode).map { row in
                row.map {
                    displayedKanaForKanaCharacterModeIfNeeded($0.remapped(for: directionProfile))
                }
            }
        case .number:
            return FlickKanaLayout.numberRows(
                for: directionProfile,
                layoutMode: effectiveNumberLayoutMode,
                temperatureUnit: temperatureUnit,
                isShifted: latinShiftState != .off
            )
        case .latin:
            return FlickKanaLayout.latinRows(for: directionProfile, layoutMode: latinLayoutMode)
        case .emoji:
            return []
        case .formattedNumber:
            // 独自テンキーを formattedNumberKeyboardView で構築するため FlickKanaSet 行は不要。
            return []
        }
    }

    var isKanaThreeByThreeMode: Bool {
        inputMode == .kana && kanaLayoutMode == .threeByThreePlusWa
    }

    var isKanaFiveByTwoMode: Bool {
        inputMode == .kana && kanaLayoutMode == .fiveByTwo
    }

    // 中身の寄せ。縦画面は下揃え(最下段を枠の下端に合わせる)。横画面は全ての面を同じ高さに
    // 揃えた(3175)ぶん、かな・ラテン・数字では中身より枠が高く、余りが全部上に付いていた。
    // 上下で同じだけ空くように中央寄せにする(ユーザー指定 3176)
    var keyboardContentAlignment: Alignment { isLandscapeLayout ? .center : .bottom }

    // 面(記号・絵文字・顔文字・部首・書式化)の下段バーの端のキー幅。横画面では かな面の
    // ⌘ キー・削除キーと位置を揃えたい(ユーザー指定 3189)。右は余裕があるので少し広くする
    var modePanelReturnKeyWidth: CGFloat { isLandscapeLayout ? leftModeSwitchButtonWidth : 56 }
    var modePanelDeleteKeyWidth: CGFloat { isLandscapeLayout ? 76 : 56 }

    // 面選択のパレットの列数。横画面は盤の高さが足りないので 2 列に折る(ユーザー指定 3171)
    var modePaletteColumnCount: Int { isLandscapeLayout ? 2 : 1 }

    var kanaCandidateHeaderTopPadding: CGFloat {
        // 枠を 4pt 詰めた縦向き(3169)ではチップの上余白も詰める。中身が枠に収まるようになって
        // 以前は隠れていた余白が全部見えるようになったため(ユーザー報告)
        let downshift = trimsPortraitContentForHomeIndicator ? 0 : candidateHeaderContentDownshift
        // 3226: 候補欄 31pt = 未確定の行 8 + 余白 + チップ。3239 でチップ 21→19、余白 2→4 にして、未確定の下線(11pt 文字、
        // 行の上端から約 11pt)がチップの上縁(12pt)に重ならないようにした(ユーザ報告)。かな面以外も同じ余白
        return 4 + downshift
    }

    var usesThreeByThreeGridForNumberOrLatin: Bool {
        (inputMode == .number || inputMode == .latin)
            && rows.count == 4
            && rows.allSatisfy { $0.count == 3 }
    }

    private var kanaFiveByTwoSideInset: CGFloat {
        isKanaFiveByTwoMode ? 6 : 0
    }

    func horizontalInsetsForMainRow(_ rowIndex: Int) -> EdgeInsets {
        guard isKanaFiveByTwoMode else {
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        }

        // Keep total horizontal inset the same, but move the top two rows left.
        if rowIndex < 2 {
            return EdgeInsets(
                top: 0,
                leading: 0,
                bottom: 0,
                trailing: kanaFiveByTwoSideInset * 2
            )
        }

        return EdgeInsets(
            top: 0,
            leading: kanaFiveByTwoSideInset,
            bottom: 0,
            trailing: kanaFiveByTwoSideInset
        )
    }

    let punctuationKana = FlickKanaSet(
        label: "、",
        center: "、",
        up: "?",
        right: "!",
        down: "・",
        left: "。"
    )

    // 設定の文字列→割り当て。読めない値は組み込みの初期値(コンテナーアプリの builtInDefaultValues と同じ)に倒す
    private static func modeSwitcherAction(
        _ rawValue: String,
        fallback: KanaModeSwitcherAction
    ) -> KanaModeSwitcherAction {
        KanaModeSwitcherAction(rawValue: rawValue) ?? fallback
    }

    // 左端上段[123] の右フリック
    var leftModeSwitchNumberKeyRightFlickAction: KanaModeSwitcherAction {
        Self.modeSwitcherAction(leftModeSwitchNumberKeyRightFlickActionRawValue, fallback: .formattedNumber)
    }

    // 左端中段[abc] の右フリック
    var leftModeSwitchLatinKeyRightFlickAction: KanaModeSwitcherAction {
        Self.modeSwitcherAction(leftModeSwitchLatinKeyRightFlickActionRawValue, fallback: .emoji)
    }

    // 左端下段[あい] の右フリック
    var leftModeSwitchKanaKeyRightFlickAction: KanaModeSwitcherAction {
        Self.modeSwitcherAction(leftModeSwitchKanaKeyRightFlickActionRawValue, fallback: .kanjiRadical)
    }

    // 左端最下段のタップ
    var kanaModeSwitcherTapAction: KanaModeSwitcherAction {
        Self.modeSwitcherAction(kanaModeSwitcherTapActionRawValue, fallback: .emoji)
    }

    // 左端最下段の右フリック
    var kanaModeSwitcherRightFlickAction: KanaModeSwitcherAction {
        Self.modeSwitcherAction(kanaModeSwitcherRightFlickActionRawValue, fallback: .kaomoji)
    }

    // 🌐 キーの右フリック・上フリック
    var compactKeyboardSwitchKeyRightFlickAction: KanaModeSwitcherAction {
        Self.modeSwitcherAction(compactKeyboardSwitchKeyRightFlickActionRawValue, fallback: .kaomoji)
    }

    var compactKeyboardSwitchKeyUpFlickAction: KanaModeSwitcherAction {
        Self.modeSwitcherAction(compactKeyboardSwitchKeyUpFlickActionRawValue, fallback: .symbols)
    }

    // 左端最下段のキー(面選択のパレット付き)。タップと右フリックに割り当てた面の字を出す。上・下・左は無し
    // (パレットは長押しで出る。3174〜3617 はパレットが触れた瞬間に出てフリックが届かなかったため案内も外していた)
    var kanaModeSwitcherKana: FlickKanaSet {
        FlickKanaSet(
            label: kanaModeSwitcherTapAction.keyLabel,
            center: kanaModeSwitcherTapAction.keyLabel,
            up: "",
            right: kanaModeSwitcherRightFlickAction.keyLabel,
            down: "",
            left: "",
            usesProfileDependentGuideOrder: false
        )
    }

    var compactKeyboardSwitchKana: FlickKanaSet {
        FlickKanaSet(
            label: "🌐",
            center: "🌐",
            up: compactKeyboardSwitchKeyUpFlickAction.keyLabel,
            right: compactKeyboardSwitchKeyRightFlickAction.keyLabel,
            down: "熙",  // 単漢字の面(康熙字典の熙。面選択パレットのアイコンと同じ字。ユーザ指定)
            left: "",
            usesProfileDependentGuideOrder: false
        )
    }

    var modifierSelectorKey: FlickKanaSet {
        let modeSwitchText = inputMode == .kana ? kanaCharacterMode.toggleGuide : "123"

        if inputMode == .kana && kanaModifierPlacementMode == .postfix {
            let postfixFlickUp = kanaPostModifierFlickDakutenEnabled ? "゛" : ""
            let postfixFlickRight = kanaPostModifierFlickDakutenEnabled ? "゜" : ""
            switch kanaPostModifierButtonState {
            case .kaomoji:
                return makeModifierSelectorKey(
                    label: "^_^",
                    up: "",
                    right: "",
                    modeSwitchText: modeSwitchText
                )
            case .smallKana:
                return makeModifierSelectorKey(
                    label: "小",
                    up: postfixFlickUp,
                    right: postfixFlickRight,
                    modeSwitchText: modeSwitchText
                )
            case .dakuten:
                return makeModifierSelectorKey(
                    label: "゛",
                    up: postfixFlickUp,
                    right: postfixFlickRight,
                    modeSwitchText: modeSwitchText
                )
            case .handakuten:
                return makeModifierSelectorKey(
                    label: "゜",
                    up: postfixFlickUp,
                    right: postfixFlickRight,
                    modeSwitchText: modeSwitchText
                )
            }
        }

        return makeModifierSelectorKey(
            label: "小",
            up: "゛",
            right: "゜",
            modeSwitchText: modeSwitchText
        )
    }

    var shortcutVocabularyEntries: [String] {
        shortcutVocabulary.uniquedTrimmedCandidates(keepingOriginalText: true)
    }

    var mainFlickKeyHeight: CGFloat {
        if isLandscapeLayout {
            // 広い横画面は窓の高さから 4 段を割り付ける(3570)。下の安全領域ぶんが空いていたのをキーに回す
            if usesWideLandscapeSidebar, containerFrame.height > 0 {
                let available = containerFrame.height - Self.wideLandscapeVerticalPadding * 2 - keyboardRowSpacing * 3
                return max(40, floor(available / 4))
            }
            return 40
        }
        // 帯のぶんの詰め(定義コメント参照)。3166 で 45pt、3169 で候補欄を 4pt 詰めて 46pt へ戻し、
        // 3216 で純正のかなキーボード(実測 47pt)に揃えた
        return 47 + (isLargePhonePortrait ? Self.largePortraitKeyHeightBoost : 0)
    }

    // 記号・絵文字・顔文字・部首・書式化の面の「4 段ぶん」の高さ。横画面では枠が足りず、
    // 3170 の縮小が働いて下段バーが上へずれていた(かな面の ⌘ キーと高さが揃わない)。
    // 枠から逆算した値に収めて、下段バーがかな面の最下段と同じ位置に来るようにする(3189)
    var fourRowAlignedClusterHeight: CGFloat {
        let designed = mainFlickKeyHeight * 4 + keyboardRowSpacing * 3
        if !isLandscapeLayout {
            // 縦で窓が設計より高いとき(Duo は内画面・外画面ともホームバーの帯が無い)、決め打ちだと最下段の下が
            // 空いた(内画面でかな 20pt に対し 47pt、外画面で 25pt 余り。3570)。余りを上のまとまりに回して枠を埋める
            return designed + portraitPanelSlack
        }
        guard containerFrame.height > 0 else {
            return designed
        }
        let available = containerFrame.height
            - keyboardTopPaddingForCluster
            - keyboardBottomPaddingForCluster
            - candidateHeaderHeight
            - keyboardRowSpacing
        guard available > mainFlickKeyHeight * 2 else {
            return designed
        }
        return min(designed, available)
    }

    // 縦で、面が「4 段ぶん」の設計より高いぶん。Duo だけ(普通の iPhone は常に 0 で従来どおり)
    var portraitPanelSlack: CGFloat {
        guard isFoldablePhone, !isLandscapeLayout, faceHeight > 0 else {
            return 0
        }
        let designed = mainFlickKeyHeight * 4 + keyboardRowSpacing * 3
        let available = faceHeight
            - keyboardTopPaddingForCluster
            - keyboardBottomPaddingForCluster
            - candidateHeaderHeight
            - keyboardRowSpacing
        return max(0, floor(available - designed))
    }

    var fourRowAlignedTopContentHeight: CGFloat {
        fourRowAlignedClusterHeight - mainFlickKeyHeight - keyboardRowSpacing
    }

    var numberThreeByThreeDirectionalHintScale: CGFloat {
        isLandscapeLayout ? 0.82 : 1
    }

    private var shorterScreenEdge: CGFloat {
        min(keyboardContainerWidth, UIScreen.main.bounds.height)
    }

    // 盤面の幅見積もりの基準。KeyboardViewController が view.bounds.width を渡す(レイアウト後に更新)。
    // 未レイアウト(0)のときだけ UIScreen.main で代用する(2786)
    var keyboardContainerWidth: CGFloat {
        containerWidth > 0 ? containerWidth : UIScreen.main.bounds.width
    }

    var usesCompactKanaFiveByTwoBottomActionRow: Bool {
        !isLandscapeLayout
            && isKanaFiveByTwoMode
            && showsNextKeyboardKey
            && shorterScreenEdge <= 390
    }

    var bottomActionRowGlobeKeyWidth: CGFloat {
        usesCompactKanaFiveByTwoBottomActionRow ? 44 : 54
    }

    var bottomActionRowDeleteKeyWidth: CGFloat {
        usesCompactKanaFiveByTwoBottomActionRow ? 56 : 64
    }

    var bottomActionRowKanaTrailingKeyWidth: CGFloat {
        usesCompactKanaFiveByTwoBottomActionRow ? selectorKeySize : kanaFiveByTwoTrailingKeyWidth
    }

    var bottomActionRowReturnKeyWidth: CGFloat {
        usesCompactKanaFiveByTwoBottomActionRow ? 64 : 72
    }

    private var portraitLatinInlineActionBaseKeyWidth: CGFloat {
        guard usesPortraitLatinInlineDeleteLayout || usesPortraitClavierInlineDeleteLayout else {
            return 0
        }

        let estimatedKeyboardWidth = max(
            1,
            keyboardContainerWidth - keyboardHorizontalPadding * 2
        )
        let leadingControlWidth: CGFloat = shouldShowCompactLeftModeSwitchInBottomActionRow
            ? leftModeSwitchButtonWidth
            : 0
        let globeKeyWidth: CGFloat = showsNextKeyboardKey
            ? bottomActionRowGlobeKeyWidth
            : 0
        let fixedWidthTotal = leadingControlWidth + globeKeyWidth + bottomActionRowReturnKeyWidth
        let spacingCount = CGFloat(5
            + (shouldShowCompactLeftModeSwitchInBottomActionRow ? 1 : 0)
            + (showsNextKeyboardKey ? 1 : 0))
        let flexibleKeyCount: CGFloat = 5

        return max(
            1,
            (estimatedKeyboardWidth - fixedWidthTotal - keyboardRowSpacing * spacingCount)
                / flexibleKeyCount
        )
    }

    var portraitLatinInlineActionSymbolKeyWidth: CGFloat {
        max(1, portraitLatinInlineActionBaseKeyWidth - 3)
    }

    var portraitLatinInlineReturnKeyWidth: CGFloat {
        66
    }

    var numberDownDirectionalHintScale: CGFloat {
        1.12
    }

    var numberDownDirectionalHintVerticalOffsetAdjustment: CGFloat {
        -2
    }

    var modifierDirectionalFlickThreshold: CGFloat {
        if inputMode == .kana && kanaModifierPlacementMode == .postfix {
            // Postfix modifier misfires are expensive (e.g. つ -> づ), so require larger movement.
            return 26
        }

        return 18
    }

    var modifierDirectionalCommitThreshold: CGFloat? {
        if inputMode == .kana && kanaModifierPlacementMode == .postfix {
            // Prefer center on postfix modifier unless movement is clearly directional.
            return 32
        }

        return nil
    }

    var selectorKeySize: CGFloat {
        mainFlickKeyHeight
    }

    var kanaFiveByTwoTrailingKeyWidth: CGFloat {
        if isKanaFiveByTwoMode {
            return selectorKeySize + 8
        }

        return selectorKeySize
    }

    var actionRowTopSpacing: CGFloat {
        inputMode == .kana ? 0 : 8
    }

    var shouldShowCompactLeftModeSwitchInBottomActionRow: Bool {
        showsCompactLeftModeSwitchButtons
            && rows.count <= 3
            && !usesCompactKanaFiveByTwoBottomActionRow
    }

    var showsCompactLeftModeSwitchButtons: Bool {
        if inputMode == .kana {
            return isKanaFiveByTwoMode
        }

        if inputMode == .latin {
            return latinLayoutMode == .qwerty || latinLayoutMode == .azerty
        }

        if inputMode == .number {
            return effectiveNumberLayoutMode == .clavier
        }

        return false
    }

    // clavier 配列は縦画面専用。横画面の場合は calculette にフォールバックする。
    // 数値系フィールド(keyboardType追従で数字モード起動=initialInputMode が number)では、
    // clavier 設定でもテンキー(téléphone)で開く(ユーザ指定 2568)。
    var effectiveNumberLayoutMode: NumberLayoutMode {
        if numberLayoutMode == .clavier && initialInputMode == .number {
            return .telephone
        }
        if numberLayoutMode == .clavier && isLandscapeLayout {
            return .calculette
        }
        return numberLayoutMode
    }

    // メインキー(letter / number / kana)の中央ラベルのフォントウエイト。
    // AZERTY/QWERTY のラテン文字キー、および clavier 配列の数字・記号キーは semibold、
    // それ以外(かなフリック、calculette/telephone)は従来通り bold。
    var rowKeyMainLabelFontWeight: Font.Weight {
        if inputMode == .latin && (latinLayoutMode == .qwerty || latinLayoutMode == .azerty) {
            return .semibold
        }
        if inputMode == .number && effectiveNumberLayoutMode == .clavier {
            return .semibold
        }
        return .bold
    }

    // 数字 clavier 配列のメインキー(1〜9/0、漢数字は -4)の基準サイズ。
    var clavierKeyFontSize: CGFloat { 26 }

    // iPhone 縦向きの最下行に並ぶ記号キー(@ / . -)のサイズ。ラテン(QWERTY/AZERTY)と
    // 数字 clavier で別実装だったため 22/20 と 26 に割れていたのを揃える(ユーザ指定 2759):
    // 字面の大きい @ と / は 24pt、. と - は 26pt。数字 clavier の shift 面(・〜…±)は 26pt
    func clavierInlineSymbolFontSize(for symbol: String) -> CGFloat {
        symbol == "@" || symbol == "/" ? 24 : 26
    }

    // clavier system 行に並べる 4 つの記号(shift 状態で切替)。
    // 配置順: index 0 = delete 跡(AZERTY の `@` 位置)、index 1 = space-left(`/`)、
    //         index 2/3 = space-right(`.`/`-`)。
    private var clavierSystemRowSymbols: [String] {
        if latinShiftState != .off {
            return ["・", "〜", "…", "±"]
        }
        return ["@", "/", ".", "-"]
    }

    func clavierInlineSymbol(at index: Int) -> String {
        let symbols = clavierSystemRowSymbols
        guard symbols.indices.contains(index) else {
            return ""
        }
        return symbols[index]
    }

    var usesWideLeftModeSwitchButtons: Bool {
        if isLandscapeLayout {
            return true
        }

        // 数字配列が clavier の場合は(他モードのときも含めて)左モード切替列を幅狭で
        // 統一する(AZERTY/QWERTY のとき幅狭にしているのと同じ理由 = clavier モード時に
        // 行幅を最大化したい)。
        if numberLayoutMode == .clavier {
            return false
        }

        return kanaLayoutMode == .threeByThreePlusWa && latinLayoutMode == .flick
    }

    var leftModeSwitchButtonWidth: CGFloat {
        // 大きな画面の縦は [幅狭] でもアルファベットのキーと同じ幅(11 等分。ユーザー指定 3570)
        if isLargePhonePortrait, !usesWideLeftModeSwitchButtons, keyboardContainerWidth > 0 {
            let available = keyboardContainerWidth - keyboardHorizontalPadding * 2 - keyboardRowSpacing * 10
            return max(compactModeSwitchKeyWidth, floor(available / 11))
        }
        if let largePortraitWideColumnWidth {
            return largePortraitWideColumnWidth
        }
        return usesWideLeftModeSwitchButtons ? wideModeSwitchKeyWidth : compactModeSwitchKeyWidth
    }

    // 大きな画面の縦の [幅広] は、左右の端の列も真ん中の 3 列と同じ幅(5 等分。純正と同じ。ユーザー指定 3570)
    private var largePortraitWideColumnWidth: CGFloat? {
        guard isLargePhonePortrait, usesWideLeftModeSwitchButtons, keyboardContainerWidth > 0 else {
            return nil
        }
        let available = keyboardContainerWidth - keyboardHorizontalPadding * 2 - keyboardRowSpacing * 4
        return max(wideModeSwitchKeyWidth, floor(available / 5))
    }

    var rightEdgeUtilityColumnWidth: CGFloat {
        if let largePortraitWideColumnWidth {
            return largePortraitWideColumnWidth
        }
        let mirroredUtilityColumnWidth = wideModeSwitchKeyWidth * 2 - leftModeSwitchButtonWidth
        return max(wideModeSwitchKeyWidth, mirroredUtilityColumnWidth)
    }

    var kanaModeSwitchButtonTitle: String {
        usesWideLeftModeSwitchButtons ? "あいう" : "あい"
    }

    var kanaModeSwitcherPreviewHorizontalPadding: CGFloat {
        if !usesWideLeftModeSwitchButtons {
            return 3
        }

        return 8
    }

    var kanaFiveByTwoTopNumberKeys: [String] {
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    }

    var landscapeEmptyCandidatePlaceholderCount: Int { 6 }

    let landscapeLatinTypewriterMiddleRowOffsetFactor: CGFloat = 0.25
    let landscapeLatinTypewriterBottomRowOffsetFromMiddleFactor: CGFloat = 0.5

    // メモリ切迫の可視化(でばぐ表示、常設)。かな削除キーの背景色:
    // 警告1回目=黄 / 2回目以降=橙+左下に回数。
    // えんじ(sqlite 最終手段アンロード)は到達不能な閾値(115MB>上限77MB)だったため 2769 で撤去。
    // 薄ピンク(欧文サジェスト構築の高水位見送り)は構築自体を前計算ファイル化して無くした(2770)
    // でばぐ可視化を出すか。開発ビルド(DEBUG、Xcode の ⌘R)だけで出し、Release(TestFlight・App Store)では
    // 出さない(3321、ユーザ指定)。以前(2918 / 3009)は ECRITU_PRERELEASE_DIAGNOSTICS で切り、TestFlight の
    // テスターの画面にも出していた。
    // 目的: キーが赤くなる描画異常(緑・青が落ちる)が起きたとき、同じ画面にメモリ警告の有無が写るようにして
    // 「メモリ切迫が引き金か」を 1 枚で判定する。黄も橙も緑・青が落ちれば真っ赤になるが、数字は白なので読める
    // スイッチがオフでも数値を出す footprint の最大値(MB。3334)
    static let memoryBadgeAlwaysShownAboveMB = 45
#if DEBUG
    static let memoryPressureVisualizationEnabled = true
#else
    static let memoryPressureVisualizationEnabled = false
#endif


    var memoryPressureDeleteKeyColor: Color? {
        guard Self.memoryPressureVisualizationEnabled else {
            return nil
        }
        // 色はバースト数(2秒以内の連続警告は1イベント)で決める。1回=黄、2回以上=橙
        switch candidateBarModel.memoryWarningBurstCountForDebugDisplay {
        case 0:
            return nil
        case 1:
            return Color.yellow.opacity(0.85)
        default:
            return Color.orange.opacity(0.9)
        }
    }

    // 削除キー左下の注記(でばぐ表示のみ)。警告回数と footprint を常に出す(62 で軽量化・70 で最小化・上限 77)。
    // **バッジは 1 本にまとめること**(2921): ActionKeyButton に格納プロパティを足すと、キー群の巨大なタプルが
    // その分だけ太り、横画面の body 構築で App Extension のスタックを食い潰して落ちた
    var memoryPressureDeleteKeyBadge: String? {
        // 数値はアプリの「キーボード診断ログ」のスイッチでオンにしたときは常に、オフ(初期設定)でも footprint の最大値が
        // 45MB を超えたら出す(3334、ユーザ指定。色は別)
        guard Self.memoryPressureVisualizationEnabled else {
            return nil
        }
        let peakMB = max(candidateBarModel.memoryFootprintPeakMBForDebugDisplay,
                         candidateBarModel.memoryFootprintProcessPeakMBForDebugDisplay)
        guard candidateBarModel.showsMemoryBadgeForDebugDisplay || peakMB > Self.memoryBadgeAlwaysShownAboveMB else {
            return nil
        }

        // 4 つの数字を常に出す(ユーザ指定 3298)。キー高 46pt に 10pt 2 行で収める。
        //   1 行目「重複を省いた警告回数 (警告回数)」: 2 秒窓でまとめたバースト数と実回数(2702/2768)
        //   2 行目「今の値/最大値」: footprint の MB。最大値はプロセス生涯(表示のたび 0 に戻るセッション側と大きい方)
        let bursts = candidateBarModel.memoryWarningBurstCountForDebugDisplay
        let raw = candidateBarModel.memoryWarningCountForDebugDisplay
        let peak = max(candidateBarModel.memoryFootprintPeakMBForDebugDisplay,
                       candidateBarModel.memoryFootprintProcessPeakMBForDebugDisplay)
        let current = candidateBarModel.memoryFootprintCurrentMBForDebugDisplay
        return "\(bursts) (\(raw))\n\(current)/\(peak)"
    }

    // 削除キー(⌫、長押しリピート)。各レイアウトで同じ引数列を 10 か所に書いていたのを集約(2805)。
    // showsMemoryPressure はかな配列(5x2/3x3)だけ true(DEBUG のメモリ圧迫可視化: 黄/橙の背景と回数バッジ)
    func deleteActionKey(
        fixedWidth: CGFloat? = nil,
        showsMemoryPressure: Bool = false,
        action: (() -> Void)? = nil
    ) -> ActionKeyButton {
        ActionKeyButton(
            title: "⌫",
            accessibilityLabel: "削除",
            fontSize: 26,
            fixedWidth: fixedWidth,
            repeatsWhileHolding: true,
            repeatInitialDelay: keyRepeatInitialDelay,
            repeatInterval: keyRepeatInterval,
            backgroundColorOverride: showsMemoryPressure ? memoryPressureDeleteKeyColor : nil,
            cornerBadgeText: showsMemoryPressure ? memoryPressureDeleteKeyBadge : nil,
            touchProbeLabel: deleteKeyTouchProbeLabel,
            rawTouchKeyID: deleteKeyRawTouchID,
            action: action ?? onDeleteBackward
        )
    }

    // 生タッチ駆動(3525)の枠の名前。面ごとに分けるのは、面の切り替えで新旧の削除キーが同時に存在し、
    // 同じ名前だと古いキーの片づけが新しい枠を消しうるため
    private var deleteKeyRawTouchID: String {
        "⌫ \(inputMode) \(kanaLayoutMode.rawValue) \(latinLayoutMode.rawValue)"
    }

    // 調査用ログ(削除キーの 1 文字め 3524): 計測行の見出し。かな面は配列、欧文面は配列の種類まで。原因判明後に外す
    private var deleteKeyTouchProbeLabel: String? {
        #if DEBUG
        switch inputMode {
        case .kana:
            return "かな(\(kanaLayoutMode.rawValue))"
        case .latin:
            return "欧文(\(latinLayoutMode))"
        default:
            return "\(inputMode)"
        }
        #else
        return nil
        #endif
    }

    @ViewBuilder
    // 縦向き QWERTY/AZERTY の下段右端のアポストロフィーのキー(3512。latinApostropheKey 参照)。
    // ラテン文字キーと同じ FlickKeyView で、左フリックに「’」。長押し候補は無い
    func latinApostropheKeyView(width: CGFloat?, rowIndex: Int) -> some View {
        let key = FlickKeyView(
            kana: Self.latinApostropheKey,
            onCommit: commitText,
            mainLabelFontSize: 26,
            mainLabelFontWeight: rowKeyMainLabelFontWeight,
            showsDirectionalHints: showsFlickGuideCharacters,
            allowsDirectionalFlick: true,
            onTouchStateChanged: { isTouching in
                updateActiveLayer(isTouching, layerIndex: rowIndex)
            }
        )

        if let width {
            key
                .frame(width: width, height: mainFlickKeyHeight)
        } else {
            key
                .frame(maxWidth: .infinity)
                .frame(height: mainFlickKeyHeight)
        }
    }

    @ViewBuilder
    func inlineLatinDeleteKey(fixedWidth: CGFloat? = nil) -> some View {
        let deleteKey = deleteActionKey()

        if let fixedWidth {
            deleteKey
                .frame(width: fixedWidth, height: mainFlickKeyHeight)
        } else {
            deleteKey
                .frame(maxWidth: .infinity)
                .frame(height: mainFlickKeyHeight)
        }
    }

    var body: some View {
        // 背景のグラデーションは UIKit 側(KeyboardViewController の backgroundGradientLayer)が描く。
        // SwiftUI 側に置くと横画面で安全領域の左右余白ぶん(片側 60pt)塗れず、上 2 隅の角 R も付けられなかった(2920)。
        // ZStack の要素は減らさず透明で残す ─ 要素を消すと body の不透明型が変わり Release の WMO が
        // 「Possible non-terminating type substitution」で落ちる(既知の脆さ。project_release_wmo_body_limit 参照)
        ZStack {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()

            VStack(spacing: keyboardRowSpacing) {
                if usesLandscapeKanaCandidateSidebar {
                    HStack(spacing: keyboardRowSpacing) {
                        landscapeKanaFixedModeSwitchColumn
                            .frame(width: leftModeSwitchButtonWidth)
                            .frame(height: landscapeKanaReferenceClusterHeight, alignment: .top)

                        if landscapeKanaCandidateSide == .left {
                            landscapeKanaCandidateSidebar
                                .frame(width: landscapeCandidateSidebarWidth())
                                .frame(height: landscapeKanaReferenceClusterHeight, alignment: .top)

                            landscapeKanaSwappableMainCluster
                                .frame(maxWidth: .infinity)
                                .frame(height: landscapeKanaReferenceClusterHeight, alignment: .top)
                        } else {
                            landscapeKanaSwappableMainCluster
                                .frame(maxWidth: .infinity)
                                .frame(height: landscapeKanaReferenceClusterHeight, alignment: .top)

                            landscapeKanaCandidateSidebar
                                .frame(width: landscapeCandidateSidebarWidth())
                                .frame(height: landscapeKanaReferenceClusterHeight, alignment: .top)
                        }
                    }
                    .padding(.top, isKanaFiveByTwoMode ? keyboardRowSpacing + 1 : 0)
                } else if usesLandscapeLatinSuggestionSidebar {
                    HStack(spacing: keyboardRowSpacing) {
                        landscapeLatinModeSwitchColumn
                            .frame(width: leftModeSwitchButtonWidth)
                            .frame(height: landscapeLatinReferenceClusterHeight, alignment: .top)

                        if landscapeKanaCandidateSide == .left {
                            landscapeLatinSuggestionSidebar
                                .frame(width: landscapeCandidateSidebarWidth())
                                .frame(height: landscapeLatinReferenceClusterHeight, alignment: .top)

                            landscapeLatinSwappableMainCluster
                                .frame(maxWidth: .infinity)
                                .frame(height: landscapeLatinReferenceClusterHeight, alignment: .top)
                        } else {
                            landscapeLatinSwappableMainCluster
                                .frame(maxWidth: .infinity)
                                .frame(height: landscapeLatinReferenceClusterHeight, alignment: .top)

                            landscapeLatinSuggestionSidebar
                                .frame(width: landscapeCandidateSidebarWidth())
                                .frame(height: landscapeLatinReferenceClusterHeight, alignment: .top)
                        }
                    }
                } else {
                    topHeaderView
                    keyboardMainContent
                }
            }
            .padding(.top, keyboardTopPadding)
            .padding(.horizontal, keyboardHorizontalPadding)
            .padding(.bottom, keyboardBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: keyboardContentAlignment)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: keyboardContentAlignment)
        .onAppear {
            if inputMode != initialInputMode {
                inputMode = initialInputMode
            }
            // 表示時点の観測値を基準として記録する。.onChange は初期値では発火しないので、これが無いと
            // 最初の変化のときに前の値が無く、欄の種類への追従が見送られる。欄の種類は表示の約 130ms 後に
            // 届くので、ここで見送ると初期の面のまま開いていた(3586 の実機ログ、メールの欄で確認)
            lastInputModeObservation = InputModeObservation(
                inputMode: inputMode,
                initialInputMode: initialInputMode,
                emojiInputSubmode: emojiInputSubmode
            )
            onInputModeChanged(inputMode, "初期表示")
            showInitialSpaceToastIfNeeded()
        }
        // inputMode の変化通知に加えて、フィールド移動での keyboardType trait 変化
        // (initialInputMode)への追従もこの1個で担う(4.4.1)。素の .onChange を
        // もう1個足すと Swift 6.3.3 Release(WMO)がopaque type置換の発散でクラッシュ
        // するため、複合値の監視に置き換えてモディファイア数を増やさない
        .onChange(of: InputModeObservation(inputMode: inputState.inputMode, initialInputMode: initialInputMode, emojiInputSubmode: inputState.emojiInputSubmode)) { _, signal in
            handleInputModeObservationChange(signal)
        }
        .onChange(of: spaceToastTrigger) { _, _ in
            showInitialSpaceToastIfNeeded()
        }
        .onDisappear {
            didTriggerComposingCommitLongPress = false
            cancelPendingKatakanaCommit()
            cancelLatinModeSwitchSecondTapWindow()
        }
        .environment(\.flickDirectionProfile, directionProfile)
        .environment(\.flickGuideDisplayMode, currentFlickGuideDisplayMode)
        .environment(\.keyboardAccentColor, accentColor)
        // 吹き出し・候補パネルのクランプ基準(UIKit 側で測ったウィンドウ座標の枠。2786)
        .environment(\.keyboardContainerFrame, containerFrame)
    }

    // フルアクセス未許可の案内(候補ヘッダー行に出す 1 行バナー)。インストール直後や削除→
    // 再インストールの直後はオフに戻るが、読み取りだけは効くため見た目が設定どおりで気づけない。
    // 学習・設定の保存が黙って失敗し続けるので候補が無い間だけヘッダーで知らせる。変換・入力は
    // フルアクセス無しでも全部動くので、キー面(地球儀を含む)は決して覆わない(2785)。
    var showsFullAccessNotice: Bool {
        !hasFullAccess && !didDismissFullAccessNotice
    }

    var fullAccessNoticeHeaderView: some View {
        HStack(spacing: 8) {
            Text(Self.fullAccessNoticeText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(keyLabelColor.opacity(0.75))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

            fullAccessNoticeDismissButton
        }
        .padding(.leading, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // 横画面のかなの候補欄(縦長)に出す同じ案内(3570)。横画面には候補欄の段が無く、案内が一度も出なかった。
    // 何も打っていないとき空の枠の代わりに出し、打ち始めれば候補に置き換わる(縦画面の段と同じ考え方)
    var fullAccessNoticeSidebarView: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(Self.fullAccessNoticeText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(keyLabelColor.opacity(0.75))
                .lineLimit(6)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

            fullAccessNoticeDismissButton
        }
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static let fullAccessNoticeText = "フルアクセスがオフです — 学習・設定の保存は反映されません(設定 › 一般 › キーボード › キーボード › écritu)"

    private var fullAccessNoticeDismissButton: some View {
        Button {
            didDismissFullAccessNotice = true
            UserDefaults.standard.set(Self.currentEdition, forKey: Self.fullAccessNoticeDismissedEditionKey)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(keyLabelColor.opacity(0.6))
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("この案内を閉じる")
    }

}

#Preview {
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
        showsNextKeyboardKey: true,
        containerFrame: .zero,
        directionProfile: .ecritu,
        kanaLayoutMode: .fiveByTwo,
        kanaModifierPlacementMode: .prefix,
        numberLayoutMode: .calculette,
        latinLayoutMode: .flick,
        accentPaletteRawValue: "emeraude",
        isSystemDictionaryFallback: false,
        hasFullAccess: true,
        keyboardBackgroundThemeRawValue: "bleu",
        basicSymbolOrderRawValue: "ascii",
        temperatureUnitRawValue: TemperatureUnitPreference.celsius.rawValue,
        radicalStrokeCountStyleRawValue: "",
        spaceToastTrigger: 1,
        returnKeySystemImageName: nil,
        returnKeyTitleOverride: nil,
        isReturnKeyEnabled: true,
        kanaFlickGuideDisplayMode: .fourDirections,
        latinFlickGuideDisplayMode: .fourDirections,
        numberFlickGuideDisplayMode: .fourDirections,
        modifierFlickGuideDisplayMode: .fourDirections,
        keyRepeatInitialDelay: 0.5,
        keyRepeatInterval: 0.1,
                leftModeSwitchNumberKeyRightFlickActionRawValue: "formattedNumber",
                leftModeSwitchLatinKeyRightFlickActionRawValue: "emoji",
                leftModeSwitchKanaKeyRightFlickActionRawValue: "kanjiRadical",
                kanaModeSwitcherTapActionRawValue: "emoji",
                kanaModeSwitcherRightFlickActionRawValue: "kaomoji",
                compactKeyboardSwitchKeyRightFlickActionRawValue: "kaomoji",
                compactKeyboardSwitchKeyUpFlickActionRawValue: "symbols",
                kanaPostModifierEmptyTapActionRawValue: "kaomoji",
                kanaPostModifierEmptyTapKaomojiCategoryID: "shortcut",
                kanaPostModifierEmptyTapEmojiCategoryID: "0",
                kanaPostModifierEmptyTapSymbolCategoryID: "0",
                kanaPostModifierFlickDakutenEnabled: true,
                landscapeCandidateSideRawValue: "left",
            landscapeNumberPaneSideRawValue: "left",
        landscapeLatinSuggestionModeRawValue: "sidebar",
        shortcutVocabulary: [],
        candidateBarModel: {
            let model = KeyboardCandidateBarModel()
            model.composingText = "かな"
            model.conversionCandidates = ["仮名", "かな"]
            model.selectedConversionCandidateIndex = 0
            model.latinSuggestionQuery = "caf"
            model.latinSuggestions = ["cafe", "café"]
            return model
        }(),
        showsParenthesesWrapper: false,
        initialSpaceToastText: nil,
        initialInputMode: .kana
    )
}

// inputMode(手動切替)と initialInputMode(フィールドの keyboardType trait)の複合監視値。
struct InputModeObservation: Equatable {
    let inputMode: KeyboardInputMode
    let initialInputMode: KeyboardInputMode
    // 絵文字面のサブモード(絵文字/顔文字/記号/漢字ピッカー)。でばぐ表示の更新要求のためだけに監視する(3304)
    let emojiInputSubmode: EmojiInputSubmode

    // 欄の種類(keyboardType)から決まる初期の面が変わったときに、面をそれへ合わせるかどうか。
    // 前の観測値が無いとき(基準の記録前)と、すでにその面のときは合わせない。
    // 同じ欄の中の手動切替では initialInputMode が変わらないので、手で選んだ面を上書きしない
    static func traitFollowTarget(
        previous: InputModeObservation?,
        signal: InputModeObservation,
        currentInputMode: KeyboardInputMode
    ) -> KeyboardInputMode? {
        guard let previous,
            previous.initialInputMode != signal.initialInputMode,
            currentInputMode != signal.initialInputMode else {
            return nil
        }
        return signal.initialInputMode
    }
}

extension KeyboardRootView {
    // 同一フィールド内の手動切替では initialInputMode が変わらないため、trait 追従が
    // ユーザの選択を上書きすることはない。trait が変わって面を切り替えた場合は、
    // inputMode の変化として次の発火で onInputModeChanged が呼ばれる(従来と同順)。
    func handleInputModeObservationChange(_ signal: InputModeObservation) {
        let previous = lastInputModeObservation
        lastInputModeObservation = signal

        if let target = InputModeObservation.traitFollowTarget(
            previous: previous,
            signal: signal,
            currentInputMode: inputMode
        ) {
            #if DEBUG
            inputModeChangeTrigger = "フィールド trait 追従"  // 調査用ログ(記号面切替 2838)
            #endif
            inputMode = target
            return
        }
        if previous == nil || previous?.inputMode != signal.inputMode {
            // 調査用ログ(記号面切替 2838): 引き金とサブモードを添える。原因判明後に外す
            #if DEBUG
            var detail = inputModeChangeTrigger
            if signal.inputMode == .emoji {
                detail += " sub=\(emojiInputSubmode)"
            }
            onInputModeChanged(signal.inputMode, detail)
            inputModeChangeTrigger = "面内キー"
            #else
            onInputModeChanged(signal.inputMode, "")
            #endif
        }
        // 面の切り替え(サブモードの切り替えを含む)で、削除キーのでばぐ表示(数字と色)を更新する(3304)。
        // 文字の変化(textDidChange)でしか更新していなかったため、絵文字パネルで増えたぶんが次の変換のときに
        // まとめて現れ、「変換で増えた」ように見えていた(2026-10-02 実機)
        if previous == nil
            || previous?.inputMode != signal.inputMode
            || previous?.emojiInputSubmode != signal.emojiInputSubmode {
            var face = String(describing: signal.inputMode)
            if signal.inputMode == .emoji {
                face += "/\(signal.emojiInputSubmode)"
            }
            onMemoryDebugDisplayRefreshRequested(face)
        }
    }
}
