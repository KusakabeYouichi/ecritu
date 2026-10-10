import Combine
import SwiftUI

enum FlickGuideDisplayMode: String {
    case off
    case fourDirections
    case down
}

// 押下表示残留(赤キー)のフェイルセーフ発火を診断へ通知するフック。
// KeyboardViewController が viewDidLoad で設定し、watchdog が強制解除した時に呼ぶ。
enum KeyboardStuckTouchDiagnostics {
    static var onForceClear: ((String) -> Void)?
    // 調査用ログ(記号面切替 2838): touchForensicsLabel 付きのキーが commit したときの接触詳細。原因判明後に外す
    static var onTouchForensics: ((String) -> Void)?
    // 直近の commit の接触時間(ms)。面を切り替えるキーだけが「短すぎる接触は採らない」判定に使う(2938)。
    // FlickKeyView に格納プロパティを足すとキー群の巨大なタプルが太る(2921 のスタック超過)ので、
    // キー側でなくここへ置いて受け手(selectKanaModeSwitcher)が読む。測れなかったときは nil
    static var lastCommitDurationMs: Int?
    // 調査用ログ(長押しパネルの遅れ 3507): 下段(c 等)のアクサン候補だけ出るのが遅い件。接触の時刻(value.time)、
    // onChanged が届いた時刻、タイマー発火、パネル出現 の 4 点を 1 本指前提で記録し、パネルの onAppear で 1 行流す。
    // 原因判明後に外す
    #if DEBUG
    static var longPressProbeLabel: String?
    // DragGesture.Value.time は端末の稼働時間を基準にした Date(2001 年基準の wall clock ではない)。
    // 配送遅れは稼働時間(RawTouchLongPress.uptimeNow)と突き合わせて届いた時点で ms に直す(実測 2026-10-11: 下段 c だけ +660ms)
    static var longPressProbeDeliveryDelayMs: Int?
    static var longPressProbeKeyMidY: CGFloat?
    static var longPressProbeTouchHandlingMs: Int?
    static var longPressProbeCompensationMs: Int?
    static var longPressProbeDeliveredAt: Date?
    static var longPressProbeFiredAt: Date?
    // 生タッチ駆動で盤を出したときは、触れてから起動までを生タッチ側の時刻で出す(3516)
    static var longPressProbeRawBeganAt: Date?
    static var longPressProbeRawActivatedAt: Date?
    #endif
}

// 生タッチ駆動の長押し(3516)。縦画面では画面下端のシステム操作の門番(_UISystemGestureGate)が、下の段に
// 触れた touch を約 0.75 秒握ってから SwiftUI のジェスチャーへ配る(3172 で名指し。待ちの指定を外しても
// 効かず、門番を止めるとホストが落ちた 3173/3181)。一方、面に付けた素の UIGestureRecognizer には
// 30ms 以内に届く(3150 の実測)。そこで、アクサン候補を持つ英字キー(フリックの効かないキー)だけ、
// 素の認識器で見た touch から長押しの待ちを数え、盤を SwiftUI の判定より先に出す。
//
// 役割分担: ここは「触れた位置がどのキーか」「0.35 秒経った」「指が動いた/離れた」を Combine で流すだけ。
// 盤の表示・候補の選択・確定は受け手の FlickKeyView が今までどおり行なう。遅れて届いた SwiftUI の
// ジェスチャーは、盤が出ていればそのまま引き継ぎ(選択と確定は SwiftUI 側)、生タッチ側で既に確定して
// いれば何もしない(takeConsumed)。キーの枠は FlickKeyView が onGeometryChange で登録する(SwiftUI の
// .global = ホスティングビューの座標。認識器もホスティングビューに付ける)
enum RawTouchLongPress {
    enum Kind {
        case activate
        case move
        case end
        case cancel
    }

    struct Event {
        let keyID: String
        let globalX: CGFloat
        let kind: Kind
    }

    static let events = PassthroughSubject<Event, Never>()
    static let delay: TimeInterval = 0.35
    // 生タッチ側で確定した押しの印は、SwiftUI の判定が届かないまま残っても次の接触で捨てる。念のため期限も置く
    static let consumedLifetime: TimeInterval = 1.5

    private static var frames: [String: CGRect] = [:]
    private static var trackedTouchID: ObjectIdentifier?
    private static var pendingKeyID: String?
    private static var pendingWorkItem: DispatchWorkItem?
    private static var activeKeyID: String?
    private static var lastGlobalX: CGFloat = 0
    private static var consumedKeyID: String?
    private static var consumedAt: Date?

    static func keyID(for kana: FlickKanaSet) -> String {
        kana.center.lowercased()
    }

    // 端末の稼働時間(秒)。UITouch.timestamp / DragGesture.Value.time と同じ基準(起動からの経過、スリープ中は止まる)。
    // ProcessInfo.systemUptime は「必要な理由」の申告が要る API(3301)なので、Release で使う経路はこちら
    static func uptimeNow() -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    static func register(keyID: String, frame: CGRect) {
        if frame.isEmpty {
            frames[keyID] = nil
        } else {
            frames[keyID] = frame
        }
    }

    static func unregister(keyID: String) {
        frames[keyID] = nil
    }

    static var registeredKeyCount: Int {
        frames.count
    }

    static func touchBegan(id: ObjectIdentifier, at point: CGPoint) {
        consumedKeyID = nil
        consumedAt = nil
        guard trackedTouchID == nil else {
            return
        }
        trackedTouchID = id
        lastGlobalX = point.x
        cancelPending()
        guard let keyID = frames.first(where: { $0.value.contains(point) })?.key else {
            return
        }
        #if DEBUG
        KeyboardStuckTouchDiagnostics.longPressProbeRawBeganAt = Date()
        #endif
        pendingKeyID = keyID
        let workItem = DispatchWorkItem {
            guard let keyID = pendingKeyID else {
                return
            }
            pendingKeyID = nil
            pendingWorkItem = nil
            activeKeyID = keyID
            events.send(Event(keyID: keyID, globalX: lastGlobalX, kind: .activate))
        }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    static func touchMoved(id: ObjectIdentifier, to point: CGPoint) {
        guard id == trackedTouchID else {
            return
        }
        lastGlobalX = point.x
        if let activeKeyID {
            events.send(Event(keyID: activeKeyID, globalX: point.x, kind: .move))
        }
    }

    static func touchEnded(id: ObjectIdentifier, at point: CGPoint, cancelled: Bool) {
        guard id == trackedTouchID else {
            return
        }
        trackedTouchID = nil
        cancelPending()
        guard let keyID = activeKeyID else {
            return
        }
        activeKeyID = nil
        events.send(Event(keyID: keyID, globalX: point.x, kind: cancelled ? .cancel : .end))
    }

    // 受け手(FlickKeyView)が生タッチ側で確定したときに呼ぶ。遅れて届く SwiftUI の判定に「済み」を伝える
    static func noteConsumed(keyID: String) {
        consumedKeyID = keyID
        consumedAt = Date()
    }

    static func takeConsumed(keyID: String) -> Bool {
        guard consumedKeyID == keyID, let consumedAt else {
            return false
        }
        consumedKeyID = nil
        self.consumedAt = nil
        return Date().timeIntervalSince(consumedAt) <= consumedLifetime
    }

    private static func cancelPending() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        pendingKeyID = nil
    }

    // テスト用: 状態を初期に戻す
    static func resetForTesting() {
        frames = [:]
        trackedTouchID = nil
        cancelPending()
        activeKeyID = nil
        lastGlobalX = 0
        consumedKeyID = nil
        consumedAt = nil
    }
}

// 対象のキーだけ RawTouchLongPress の合図を購読する(全キーに onReceive を付けると購読の分だけ SwiftUI 内部が太る)
private struct RawLongPressReceiver: ViewModifier {
    let enabled: Bool
    let handler: (RawTouchLongPress.Event) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onReceive(RawTouchLongPress.events, perform: handler)
        } else {
            content
        }
    }
}

// 生タッチを RawTouchLongPress へ流すだけの認識器。状態を変えない(.possible のまま)ので他の操作を邪魔しない
final class RawTouchLongPressGestureRecognizer: UIGestureRecognizer {
    // 位置を取る座標系(SwiftUI の .global = ホスティングビュー)。認識器自体はルートの view に付ける
    weak var coordinateView: UIView?

    private func forward(_ touches: Set<UITouch>, phase: UITouch.Phase) {
        guard let view = coordinateView ?? view else {
            return
        }
        for touch in touches {
            let id = ObjectIdentifier(touch)
            let point = touch.location(in: view)
            switch phase {
            case .began:
                #if DEBUG
                // 調査用ログ(3518): 生タッチが届いた時刻と位置。配送遅れは端末が指を検出した時刻(touch.timestamp)との差
                let deliveryMs = Int(((RawTouchLongPress.uptimeNow() - touch.timestamp) * 1000).rounded())
                KeyboardStuckTouchDiagnostics.onTouchForensics?(
                    String(format: "生タッチ began (%.0f,%.0f) 配送遅れ=%dms 登録キー=%d", point.x, point.y, deliveryMs,
                        RawTouchLongPress.registeredKeyCount))
                #endif
                RawTouchLongPress.touchBegan(id: id, at: point)
            case .moved:
                RawTouchLongPress.touchMoved(id: id, to: point)
            case .ended:
                RawTouchLongPress.touchEnded(id: id, at: point, cancelled: false)
            default:
                RawTouchLongPress.touchEnded(id: id, at: point, cancelled: true)
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        forward(touches, phase: .began)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        forward(touches, phase: .moved)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        forward(touches, phase: .ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        forward(touches, phase: .cancelled)
    }

    static func install(on view: UIView, coordinateView: UIView) {
        let recognizer = RawTouchLongPressGestureRecognizer(target: nil, action: nil)
        recognizer.coordinateView = coordinateView
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        view.addGestureRecognizer(recognizer)
    }
}

enum LongPressCandidatePanelPlacement {
    case above
    case below
}

// 長押し候補パネルの並び。既定は横(欧文のアクセント選択)。縦は面選択のパレット(3124):
// 左下キーの真上に縦に積み、指を上へ滑らせて離すと決まる。項目が 2〜3 文字の語なので横だと
// 盤が盤面いっぱいに広がってしまう
enum LongPressCandidateAxis {
    case horizontal
    case vertical
}

private struct KeyboardAccentColorKey: EnvironmentKey {
    static let defaultValue = Color(red: 0.06, green: 0.73, blue: 0.56)
}

private struct FlickGuideDisplayModeKey: EnvironmentKey {
    static let defaultValue: FlickGuideDisplayMode = .fourDirections
}

private struct FlickDirectionProfileKey: EnvironmentKey {
    static let defaultValue: FlickDirectionProfile = .ecritu
}

// キーボードのルートビューのグローバル座標での枠。iPad 互換モード(iPhone 専用アプリの拡張が
// 画面中央の小さな箱で出る)では UIScreen.main が iPad 全幅を返し、吹き出し・候補パネルの
// はみ出し判定が箱の外を基準にしてしまうため、実枠でクランプする(2786)。zero=未計測(UIScreen で代用)
private struct KeyboardContainerFrameKey: EnvironmentKey {
    static let defaultValue: CGRect = .zero
}

extension EnvironmentValues {
    var keyboardContainerFrame: CGRect {
        get { self[KeyboardContainerFrameKey.self] }
        set { self[KeyboardContainerFrameKey.self] = newValue }
    }

    // 横方向のクランプ範囲: 実枠が測れていれば [minX, maxX]、未計測なら画面全幅
    var keyboardHorizontalBounds: (minX: CGFloat, maxX: CGFloat) {
        let frame = keyboardContainerFrame
        if frame.width > 0 {
            return (frame.minX, frame.maxX)
        }
        return (0, UIScreen.main.bounds.width)
    }

    var keyboardAccentColor: Color {
        get { self[KeyboardAccentColorKey.self] }
        set { self[KeyboardAccentColorKey.self] = newValue }
    }

    var flickGuideDisplayMode: FlickGuideDisplayMode {
        get { self[FlickGuideDisplayModeKey.self] }
        set { self[FlickGuideDisplayModeKey.self] = newValue }
    }

    var flickDirectionProfile: FlickDirectionProfile {
        get { self[FlickDirectionProfileKey.self] }
        set { self[FlickDirectionProfileKey.self] = newValue }
    }
}

struct FlickKeyView: View {
    private enum Metrics {
        static let keyCornerRadius: CGFloat = 10
        static let previewDistance: CGFloat = 44
        static let secondaryFlickThreshold: CGFloat = 12
        static let directionHintVerticalOffset: CGFloat = 16
        static let directionHintHorizontalOffset: CGFloat = 20

        static let longPressDelay: TimeInterval = 0.35
        static let candidateCellWidth: CGFloat = 34
        static let candidateCellHeight: CGFloat = 34
        static let candidateSpacing: CGFloat = 3
        static let candidatePanelPadding: CGFloat = 8
        static let candidatePanelVerticalPadding: CGFloat = 3
        static let candidatePanelContentInset: CGFloat = 16
        static let candidatePanelMinCellWidth: CGFloat = 24

        static let panelHorizontalMargin: CGFloat = 24
        static let panelSafetyInset: CGFloat = 10
        static let panelEdgeBuffer: CGFloat = 12
    }

    let kana: FlickKanaSet
    let onCommit: (String) -> Void
    var onCommitWithDirection: ((String, FlickDirection) -> Void)? = nil
    var mainLabelFontSize: CGFloat = 28
    var mainLabelFontWeight: Font.Weight = .bold
    var flickGuideDisplayModeOverride: FlickGuideDisplayMode? = nil
    var showsDirectionalHints: Bool = true
    var showsGuideText: Bool = true
    var idleReplacement: AnyView? = nil
    var longPressCandidates: [String] = []
    var longPressCandidatePanelPlacement: LongPressCandidatePanelPlacement = .above
    var longPressCandidateAxis: LongPressCandidateAxis = .horizontal
    // 縦並びのときの 1 項目の幅(語のラベル用)。横並びでは使わない
    var longPressCandidateCellWidth: CGFloat? = nil
    // 縦の盤(面選択のパレット)の列数。横画面は高さが足りないので 2 列に折る(ユーザー指定 3171)
    var longPressCandidateColumnCount: Int = 1
    // 長押し成立までの待ち時間の上書き(面選択のパレットは待たせない。3125)
    var longPressDelayOverride: TimeInterval? = nil
    var onLongPress: (() -> Void)? = nil
    var allowsDirectionalFlick: Bool = true
    var directionalFlickThreshold: CGFloat = 18
    var directionalCommitThreshold: CGFloat? = nil
    var activePreviewFontSize: CGFloat = 24
    var activeMainLabelFontSizeProvider: ((FlickDirection, String) -> CGFloat)? = nil
    var activePreviewFontSizeProvider: ((FlickDirection, String) -> CGFloat)? = nil
    var activePreviewHorizontalPadding: CGFloat = 12
    var directionalHintHorizontalOffset: CGFloat = Metrics.directionHintHorizontalOffset
    var directionalHintFontScale: CGFloat = 1
    var downDirectionalHintFontScale: CGFloat = 1
    var downDirectionalHintVerticalOffsetAdjustment: CGFloat = 0
    var onTouchStateChanged: (Bool) -> Void = { _ in }
    // 調査用ログ(記号面切替 2838): 設定するとこのキーの commit ごとに接触詳細(開始位置/移動量/接触時間)を診断へ流す。原因判明後に外す
    var touchForensicsLabel: String? = nil

    @State private var touchBeganAt: Date?
    @State private var activeDirection: FlickDirection = .milieu
    @State private var isTouching = false
    @State private var longPressIsActive = false
    @State private var highlightedLongPressIndex = 0
    @State private var latestTouchLocationY: CGFloat = 0
    @State private var longPressWorkItem: DispatchWorkItem?
    @State private var stuckTouchWatchdogWorkItem: DispatchWorkItem?
    @State private var didTriggerLongPressAction = false
    @State private var latestTouchLocationX: CGFloat = 0
    @State private var longPressAnchorLocationX: CGFloat = 0
    @State private var longPressAnchorLocationY: CGFloat = 0
    @State private var keyFrameInGlobal: CGRect = .zero
    @State private var secondaryFlickPrimaryDirection: FlickDirection?
    @State private var secondaryFlickVerticalDirection: FlickDirection?
    @State private var secondaryFlickAnchorTranslation: CGSize = .zero
    @GestureState private var isGestureInProgress = false
    @Environment(\.keyboardAccentColor) private var accentColor
    @Environment(\.flickGuideDisplayMode) private var flickGuideDisplayMode
    @Environment(\.flickDirectionProfile) private var flickDirectionProfile
    @Environment(\.keyboardHorizontalBounds) private var keyboardHorizontalBounds

    private let keyLabelColor = KeyboardThemePalette.keyLabel

    private var effectiveFlickGuideDisplayMode: FlickGuideDisplayMode {
        flickGuideDisplayModeOverride ?? flickGuideDisplayMode
    }

    private var centerLabelOffsetY: CGFloat {
        effectiveFlickGuideDisplayMode == .down ? -6 : 0
    }

    private var idleMainLabelFontSize: CGFloat {
        effectiveFlickGuideDisplayMode == .down ? min(mainLabelFontSize, 24) : mainLabelFontSize
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.keyCornerRadius, style: .continuous)
                .fill(isTouching ? accentColor.opacity(0.85) : KeyboardThemePalette.keyBackground)

            RoundedRectangle(cornerRadius: Metrics.keyCornerRadius, style: .continuous)
                .stroke(KeyboardThemePalette.keyBorder, lineWidth: 1)

            if isTouching {
                Text(displayText)
                    .font(
                        .system(
                            size: resolvedActiveMainLabelFontSize(for: activeDirection),
                            weight: .bold,
                            design: .rounded
                        )
                        // 書式化の見本 1,000 は 5 字ぶん横に長い。幅の詰まった字面にして、
                        // それでも入らなければ縮める(ユーザー指摘 3155)。1 字のキーには影響しない
                        .width(displayTextNeedsCondensedWidth ? .condensed : .standard)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 2)
                    .foregroundStyle(Color.white)
            } else if let idleReplacement {
                idleReplacement
                    .offset(y: centerLabelOffsetY)
            } else {
                Text(kana.center)
                    .font(.system(size: idleMainLabelFontSize, weight: mainLabelFontWeight, design: .rounded))
                    .foregroundStyle(keyLabelColor)
                    .offset(y: centerLabelOffsetY)
            }

            // ガイド文字は「隠す」のではなく「作らない」(2686)。以前は .opacity(0) で
            // 隠していたため、非表示のキーでも4方向ぶんの Text が常時生成され、
            // SwiftUI の AttributeGraph(実機実測 7.9MB、PropertyList.Tracker 1446件)を
            // 押し上げていた。押下中(isTouching)も非表示なので同じ条件で分岐する
            if showsDirectionalHintTexts {
                directionalHints
            }
            if showsDownDirectionalHintTexts {
                downDirectionalHints
            }

            if isTouching,
                !longPressIsActive,
                (activeDirection != .milieu || secondaryFlickPrimaryDirection != nil) {
                Text(displayText)
                    .font(
                        .system(
                            size: resolvedActivePreviewFontSize(for: activeDirection),
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                    // 吹き出しはキーの幅に縛らず字の幅で描く(3516)。ZStack はキーの幅を提案するので、半幅の
                    // アポストロフィーのキー(約 15pt)では字の取り分が負になり、緑のカプセルだけで字が描かれなかった
                    .fixedSize()
                    .foregroundStyle(.white)
                    .padding(.horizontal, activePreviewHorizontalPadding)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(accentColor.opacity(0.95)))
                    .offset(resolvedPreviewOffset)
            }

        }
        // 横長の長押しパネル(英字のアクセント候補)もキーの大きさに影響しない overlay に置く(3488)。以前は ZStack の
        // 子で、パネルの幅までキーが広がり同じ段の他のキーを押し縮めていた(上段では消えた。ユーザ報告の画像)
        .overlay {
            if longPressIsActive,
                !longPressCandidates.isEmpty,
                longPressCandidateAxis == .horizontal {
                longPressCandidatePanel
                    .fixedSize()
                    .offset(x: candidatePanelOffsetX, y: candidatePanelOffsetY)
                    .zIndex(KeyboardLayerZIndex.floatingOverlay)
                    .onAppear {
                        #if DEBUG
                        reportLongPressProbe()  // 調査用ログ(長押しパネルの遅れ 3507)
                        #endif
                    }
            }
        }
        // 縦の盤(面選択のパレット)はキーの左上を基準に置く(3128)。キー枠の測定値(preference)は
        // 実機でずっと (0,0) のままで寄せが効かず、盤の左が画面外へ出ていた(ユーザ報告の画像)。
        // overlay はレイアウトに影響せず、キーの枠に揃うので測定が要らない
        .overlay(alignment: .topLeading) {
            if longPressIsActive,
                !longPressCandidates.isEmpty,
                longPressCandidateAxis == .vertical {
                LongPressVerticalCandidatePanel(
                    candidates: longPressCandidates,
                    highlightedIndex: highlightedLongPressIndex,
                    cellWidth: longPressCandidateCellWidth ?? Metrics.candidateCellWidth,
                    columnCount: longPressCandidateColumnCount
                )
                    .offset(
                        x: LongPressVerticalCandidatePanel.keyLeadingInset,
                        y: -(LongPressVerticalCandidatePanel.panelHeight(
                            count: longPressCandidates.count,
                            columns: longPressCandidateColumnCount
                        ) + LongPressVerticalCandidatePanel.gap)
                    )
                    .zIndex(KeyboardLayerZIndex.floatingOverlay)
            }
        }
        .contentShape(Rectangle())
        .gesture(flickGesture)
        // キー枠の測定(横長の長押しパネルを画面端で寄せる計算に使う)。以前は GeometryReader+preference で、
        // キーごとに背景のビュー・preference の受け渡し・変更通知が AttributeGraph に常駐していた。
        // onGeometryChange は値が変わったときだけ呼ばれる軽い仕組み(3480。実機メモリグラフで SwiftUI 内部が約 2MB)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { newValue in
            keyFrameInGlobal = newValue
            if isRawLongPressDriven {
                RawTouchLongPress.register(keyID: rawLongPressKeyID, frame: newValue)
            }
        }
        .modifier(RawLongPressReceiver(enabled: isRawLongPressDriven, handler: handleRawLongPress))
        .onChange(of: isGestureInProgress) { inProgress in
            if !inProgress {
                finalizeTouchInteractionState()
            }
        }
        .onDisappear {
            finalizeTouchInteractionState()
            if isRawLongPressDriven {
                RawTouchLongPress.unregister(keyID: rawLongPressKeyID)
            }
        }
        .zIndex(isTouching ? KeyboardLayerZIndex.touchingKey : 0)
    }

    // 横に長い字面(書式化の 1,000)かどうか。押している間のキーの描き方を変える
    private var displayTextNeedsCondensedWidth: Bool {
        displayText.count >= 4
    }

    private var displayText: String {
        if longPressIsActive,
            !longPressCandidates.isEmpty,
            longPressCandidates.indices.contains(highlightedLongPressIndex) {
            let candidate = longPressCandidates[highlightedLongPressIndex]
            // 面選択のパレットでは、押している間のキーの表示は面のアイコンだけにする(ユーザ指定 3129)。
            // 語のラベル(顔文字 等)はキーの幅に入らず 2 行に折り返してしまう
            if longPressCandidateAxis == .vertical {
                return LongPressVerticalCandidatePanel.iconByLabel[candidate]?.text ?? candidate
            }
            return candidate
        }

        if let secondaryOutput = resolvedSecondaryFlickOutput {
            return secondaryOutput
        }

        if let primaryDirection = secondaryFlickPrimaryDirection {
            return kana.output(for: primaryDirection)
        }

        return kana.output(for: activeDirection)
    }

    private var resolvedSecondaryFlickOutput: String? {
        guard let primaryDirection = secondaryFlickPrimaryDirection,
            let verticalDirection = secondaryFlickVerticalDirection else {
            return nil
        }

        return FlickKanaLayout.secondaryBracketFlickOutput(
            forPrimaryOutput: kana.output(for: primaryDirection),
            verticalDirection: verticalDirection
        )
    }

    private var resolvedPreviewOffset: CGSize {
        if let primaryDirection = secondaryFlickPrimaryDirection {
            let xOffset = primaryDirection == .gauche ? -Metrics.previewDistance : Metrics.previewDistance

            if let verticalDirection = secondaryFlickVerticalDirection,
                resolvedSecondaryFlickOutput != nil {
                let yOffset = verticalDirection == .haut ? -Metrics.previewDistance : Metrics.previewDistance
                return CGSize(width: xOffset, height: yOffset)
            }

            return CGSize(width: xOffset, height: 0)
        }

        return previewOffset(for: activeDirection)
    }

    private func resolvedActiveMainLabelFontSize(for direction: FlickDirection) -> CGFloat {
        // 面選択のパレット中は、キーの出力ではなく選んでいる面のアイコンを描いている。
        // 大きさの判定にキーの出力を渡すと別の字の指定が選ばれ、☺︎/^_^ の大きさが効かなかった
        // (ユーザー報告 3154)。この場合だけ実際に描いている字を渡す
        let currentText = longPressIsActive && longPressCandidateAxis == .vertical
            ? displayText
            : kana.output(for: direction)

        if let activeMainLabelFontSizeProvider {
            return activeMainLabelFontSizeProvider(direction, currentText)
        }

        return mainLabelFontSize
    }

    private func resolvedActivePreviewFontSize(for direction: FlickDirection) -> CGFloat {
        let previewText = kana.output(for: direction)

        if let activePreviewFontSizeProvider {
            return activePreviewFontSizeProvider(direction, previewText)
        }

        return activePreviewFontSize
    }

    private func previewOffset(for direction: FlickDirection) -> CGSize {
        switch direction {
        case .milieu:
            return CGSize(width: 0, height: -Metrics.previewDistance)
        case .haut:
            return CGSize(width: 0, height: -Metrics.previewDistance)
        case .droite:
            return CGSize(width: Metrics.previewDistance, height: 0)
        case .bas:
            return CGSize(width: 0, height: Metrics.previewDistance)
        case .gauche:
            return CGSize(width: -Metrics.previewDistance, height: 0)
        }
    }

    private var directionalHints: some View {
        ZStack {
            directionalHintText(kana.up, direction: .haut)
                .offset(y: -Metrics.directionHintVerticalOffset)

            directionalHintText(kana.down, direction: .bas)
                .offset(y: Metrics.directionHintVerticalOffset)

            directionalHintText(kana.left, direction: .gauche)
                .offset(x: -directionalHintHorizontalOffset)

            directionalHintText(kana.right, direction: .droite)
                .offset(x: directionalHintHorizontalOffset)
        }
        .allowsHitTesting(false)
    }

    // 4方向ガイドを描くか(旧 .opacity 条件と同値)
    private var showsDirectionalHintTexts: Bool {
        !isTouching
            && showsGuideText
            && showsDirectionalHints
            && effectiveFlickGuideDisplayMode == .fourDirections
    }

    // 下段まとめガイドを描くか(旧 .opacity 条件と同値)
    private var showsDownDirectionalHintTexts: Bool {
        !isTouching && showsGuideText && effectiveFlickGuideDisplayMode == .down
    }

    private var downDirectionalHints: some View {
        HStack(spacing: 2) {
            ForEach(Array(downDirectionalHintTexts.enumerated()), id: \.offset) { _, text in
                Text(text)
                    .font(downDirectionalHintFont(for: text))
                    .minimumScaleFactor(0.1)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(keyLabelColor.opacity(0.55))
            }
        }
        .padding(.horizontal, 4)
        .offset(y: Metrics.directionHintVerticalOffset + downDirectionalHintVerticalOffsetAdjustment)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func directionalHintText(_ text: String, direction: FlickDirection) -> some View {
        if isModeSwitchHintText(text) {
            Text(text)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.01)
                .lineLimit(1)
                .allowsTightening(true)
                .fixedSize(horizontal: true, vertical: false)
                .tracking(-0.2)
                .scaleEffect(0.32)
                .foregroundStyle(keyLabelColor.opacity(0.55))
                .offset(specialDirectionalHintOffset(for: text, direction: direction))
        } else {
            Text(text)
                .font(directionalHintFont(for: text))
                .minimumScaleFactor(0.1)
                .lineLimit(1)
                .allowsTightening(true)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(keyLabelColor.opacity(0.55))
                .offset(specialDirectionalHintOffset(for: text, direction: direction))
        }
    }

    private func isModeSwitchHintText(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return text == "123" || normalized == "abc"
    }

    private func directionalHintFont(for text: String) -> Font {
        if isDakutenGuideText(text) {
            return .system(size: scaledDirectionalHintSize(25), weight: .bold, design: .rounded)
        }

        if text == "小" {
            return .system(size: scaledDirectionalHintSize(6), weight: .semibold, design: .rounded)
        }

        switch text.count {
        case 7...:
            return .system(size: scaledDirectionalHintSize(6), weight: .medium, design: .rounded)
        case 5...6:
            return .system(size: scaledDirectionalHintSize(7), weight: .medium, design: .rounded)
        case 3...4:
            return .system(size: scaledDirectionalHintSize(8), weight: .semibold, design: .rounded)
        case 2:
            return .system(size: scaledDirectionalHintSize(9), weight: .semibold, design: .rounded)
        default:
            return .system(size: scaledDirectionalHintSize(10), weight: .semibold, design: .rounded)
        }
    }

    private var downDirectionalHintTexts: [String] {
        kana.orderedDirectionalGuideTexts(for: flickDirectionProfile)
    }

    private func downDirectionalHintFont(for text: String) -> Font {
        if isDakutenGuideText(text) {
            return .system(size: scaledDownDirectionalHintSize(12), weight: .bold, design: .rounded)
        }

        if text == "小" {
            return .system(size: scaledDownDirectionalHintSize(6), weight: .semibold, design: .rounded)
        }

        switch text.count {
        case 7...:
            return .system(size: scaledDownDirectionalHintSize(5), weight: .medium, design: .rounded)
        case 5...6:
            return .system(size: scaledDownDirectionalHintSize(6), weight: .medium, design: .rounded)
        case 3...4:
            return .system(size: scaledDownDirectionalHintSize(7), weight: .semibold, design: .rounded)
        case 2:
            return .system(size: scaledDownDirectionalHintSize(8), weight: .semibold, design: .rounded)
        default:
            return .system(size: scaledDownDirectionalHintSize(9), weight: .semibold, design: .rounded)
        }
    }

    private func scaledDirectionalHintSize(_ baseSize: CGFloat) -> CGFloat {
        baseSize * directionalHintFontScale
    }

    private func scaledDownDirectionalHintSize(_ baseSize: CGFloat) -> CGFloat {
        scaledDirectionalHintSize(baseSize) * downDirectionalHintFontScale
    }

    private func isDakutenGuideText(_ text: String) -> Bool {
        text == "゛" || text == "゜"
    }

    private func specialDirectionalHintOffset(for text: String, direction: FlickDirection) -> CGSize {
        guard isDakutenGuideText(text) else {
            return .zero
        }

        let baseOffset: CGSize

        switch direction {
        case .haut:
            baseOffset = CGSize(width: 4, height: 8)
        case .gauche:
            baseOffset = CGSize(width: 8, height: 4)
        case .droite:
            baseOffset = CGSize(width: 4, height: 4)
        case .bas:
            baseOffset = CGSize(width: 4, height: 4)
        case .milieu:
            baseOffset = CGSize(width: 4, height: 4)
        }

        // Keep the two marks visually distinct: handakuten slightly right/down,
        // dakuten slightly down to stay inside the key while preserving alignment.
        if text == "゜" {
            return CGSize(width: baseOffset.width + 1, height: baseOffset.height + 1)
        }

        if text == "゛" {
            return CGSize(width: baseOffset.width, height: baseOffset.height + 2)
        }

        return baseOffset
    }

    @ViewBuilder
    private func longPressCandidateCell(index: Int, candidate: String, cellWidth: CGFloat, fontSize: CGFloat) -> some View {
        Text(candidate)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(KeyboardThemePalette.longPressPanelText)
            .frame(width: cellWidth, height: Metrics.candidateCellHeight)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        index == highlightedLongPressIndex
                            ? KeyboardThemePalette.longPressPanelCellHighlight
                            : KeyboardThemePalette.longPressPanelCellBackground
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(KeyboardThemePalette.keyBorder, lineWidth: 1)
            )
    }

    private var longPressCandidatePanel: some View {
        let cellWidth = effectiveCandidateCellWidth
        let candidateFontSize: CGFloat = cellWidth < 30 ? 18 : 20

        return HStack(spacing: Metrics.candidateSpacing) {
            ForEach(Array(longPressCandidates.enumerated()), id: \.offset) { index, candidate in
                longPressCandidateCell(index: index, candidate: candidate, cellWidth: cellWidth, fontSize: candidateFontSize)
            }
        }
        .padding(.horizontal, Metrics.candidatePanelPadding)
        .padding(.vertical, Metrics.candidatePanelVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.keyCornerRadius, style: .continuous)
                .fill(KeyboardThemePalette.longPressPanelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.keyCornerRadius, style: .continuous)
                .stroke(KeyboardThemePalette.longPressPanelBorder, lineWidth: 1)
        )
        .keyboardSoftShadow(RoundedRectangle(cornerRadius: Metrics.keyCornerRadius, style: .continuous), color: KeyboardThemePalette.longPressPanelShadow, radius: 4, y: 1)
        .allowsHitTesting(false)
    }

    private var candidatePanelWidth: CGFloat {
        let count = CGFloat(longPressCandidates.count)
        let contentWidth = count * effectiveCandidateCellWidth + max(0, count - 1) * Metrics.candidateSpacing
        return contentWidth + Metrics.candidatePanelContentInset
    }

    private var effectiveCandidateCellWidth: CGFloat {
        guard !longPressCandidates.isEmpty else {
            return Metrics.candidateCellWidth
        }

        let count = CGFloat(longPressCandidates.count)
        let sideInset = Metrics.panelHorizontalMargin + Metrics.panelSafetyInset + Metrics.panelEdgeBuffer
        let bounds = keyboardHorizontalBounds
        let maxPanelWidth = (bounds.maxX - bounds.minX) - sideInset * 2
        let availableContentWidth = maxPanelWidth - Metrics.candidatePanelContentInset - max(0, count - 1) * Metrics.candidateSpacing
        let maxCellWidth = floor(availableContentWidth / count)

        return max(Metrics.candidatePanelMinCellWidth, min(Metrics.candidateCellWidth, maxCellWidth))
    }

    private var candidatePanelOffsetX: CGFloat {
        guard keyFrameInGlobal.width > 0,
                !longPressCandidates.isEmpty else {
            return 0
        }

        let panelWidth = candidatePanelWidth
        let bounds = keyboardHorizontalBounds
        let panelMinX = keyFrameInGlobal.midX - panelWidth * 0.5
        let panelMaxX = keyFrameInGlobal.midX + panelWidth * 0.5
        let minX = bounds.minX + Metrics.panelHorizontalMargin + Metrics.panelSafetyInset + Metrics.panelEdgeBuffer
        let maxX = bounds.maxX - (Metrics.panelHorizontalMargin + Metrics.panelSafetyInset + Metrics.panelEdgeBuffer)
        var shift: CGFloat = 0

        if panelMinX < minX {
            shift += minX - panelMinX
        }

        if panelMaxX > maxX {
            shift -= panelMaxX - maxX
        }

        return shift
    }

    private var candidatePanelOffsetY: CGFloat {
        switch longPressCandidatePanelPlacement {
        case .above:
            return -Metrics.previewDistance
        case .below:
            return Metrics.previewDistance
        }
    }

    private var flickGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isGestureInProgress) { _, state, _ in
                state = true
            }
            .onChanged { value in
                if !isTouching {
                    // 生タッチ側で既に確定した押し(RawTouchLongPress 3516)。遅れて届いた SwiftUI の判定では何もしない
                    if isRawLongPressDriven, RawTouchLongPress.takeConsumed(keyID: rawLongPressKeyID) {
                        didTriggerLongPressAction = true
                        return
                    }
                    // 調査用ログ(長押しパネルの遅れ 3507): 接触の時刻と届いた時刻(差が配送遅れ)。接触開始の処理
                    // (onTouchStateChanged 等)より前に取り、OS の配送と自前の処理を切り分ける(3511)。
                    // 自前の処理の時間は「接触処理」として別に出す
                    #if DEBUG
                    let probeStartedAt = Date()
                    if !longPressCandidates.isEmpty {
                        KeyboardStuckTouchDiagnostics.longPressProbeLabel = longPressCandidates.first
                        KeyboardStuckTouchDiagnostics.longPressProbeDeliveryDelayMs = Int(
                            ((RawTouchLongPress.uptimeNow() - value.time.timeIntervalSinceReferenceDate) * 1000).rounded())
                        KeyboardStuckTouchDiagnostics.longPressProbeKeyMidY = keyFrameInGlobal.midY
                        KeyboardStuckTouchDiagnostics.longPressProbeDeliveredAt = probeStartedAt
                        KeyboardStuckTouchDiagnostics.longPressProbeFiredAt = nil
                    }
                    #endif
                    onTouchStateChanged(true)
                    didTriggerLongPressAction = false
                    scheduleLongPressIfNeeded(touchTime: value.time)
                    resetSecondaryFlickState()
                    scheduleStuckTouchWatchdog()
                    touchBeganAt = value.time
                    #if DEBUG
                    if !longPressCandidates.isEmpty {
                        KeyboardStuckTouchDiagnostics.longPressProbeTouchHandlingMs = Int(
                            (Date().timeIntervalSince(probeStartedAt) * 1000).rounded())
                    }
                    #endif
                }
                isTouching = true
                latestTouchLocationX = value.location.x
                latestTouchLocationY = value.location.y

                if didTriggerLongPressAction {
                    return
                }

                if longPressIsActive {
                    highlightedLongPressIndex = longPressCandidateAxis == .vertical
                        ? longPressIndex(forVertical: value.location.y)
                        : longPressIndex(for: value.location.x)
                    return
                }

                guard allowsDirectionalFlick else {
                    activeDirection = .milieu
                    resetSecondaryFlickState()
                    return
                }

                let resolvedDirection = FlickGestureResolver.resolve(
                    translation: value.translation,
                    threshold: directionalFlickThreshold
                )
                let effectiveResolvedDirection = effectiveDirection(for: resolvedDirection)
                activeDirection = effectiveResolvedDirection

                if onLongPress != nil,
                    longPressCandidates.isEmpty,
                    effectiveResolvedDirection != .milieu {
                    // Do not let long-press override a deliberate directional flick.
                    cancelLongPressTimer()
                }

                updateSecondaryFlickState(
                    translation: value.translation,
                    resolvedDirection: effectiveResolvedDirection
                )
            }
            .onEnded { value in
                cancelLongPressTimer()

                if didTriggerLongPressAction {
                    finalizeTouchInteractionState()
                    return
                }

                let committedDirection: FlickDirection = {
                    guard !longPressIsActive,
                        allowsDirectionalFlick,
                        let directionalCommitThreshold else {
                        return activeDirection
                    }

                    let resolvedDirection = FlickGestureResolver.resolve(
                        translation: value.translation,
                        threshold: directionalCommitThreshold
                    )
                    return effectiveDirection(for: resolvedDirection)
                }()

                let committedText: String
                let committedDirectionForCallback: FlickDirection

                if longPressIsActive,
                    longPressCandidateAxis == .vertical,
                    !longPressCandidates.indices.contains(highlightedLongPressIndex) {
                    // 盤を出したまま、どれも選ばずに離した。長く押していたなら何も起きない
                    // (ユーザ指定 3138)。ただし盤は触れた瞬間に出る(3174)ので、さっと離した
                    // ときは「ただのタップ」として扱う ─ でないと面切替のタップができなくなる
                    let heldMs = touchBeganAt.map { Int(value.time.timeIntervalSince($0) * 1000) } ?? 0
                    guard heldMs <= Self.paletteTapReleaseMaxMs else {
                        finalizeTouchInteractionState()
                        return
                    }

                    let tapText = kana.output(for: .milieu)
                    finalizeTouchInteractionState()
                    if let onCommitWithDirection {
                        onCommitWithDirection(tapText, .milieu)
                    } else {
                        onCommit(tapText)
                    }
                    return
                }

                if longPressIsActive,
                    !longPressCandidates.isEmpty,
                    longPressCandidates.indices.contains(highlightedLongPressIndex) {
                    committedText = longPressCandidates[highlightedLongPressIndex]
                    committedDirectionForCallback = committedDirection
                } else if let secondaryOutput = resolvedSecondaryFlickOutput,
                    let primaryDirection = secondaryFlickPrimaryDirection {
                    committedText = secondaryOutput
                    committedDirectionForCallback = primaryDirection
                } else if let primaryDirection = secondaryFlickPrimaryDirection {
                    committedText = kana.output(for: primaryDirection)
                    committedDirectionForCallback = primaryDirection
                } else {
                    committedText = kana.output(for: committedDirection)
                    committedDirectionForCallback = committedDirection
                }

                // 面を切り替えるキーの「短すぎる接触」判定に使う(定数コメント参照。2938)
                let commitDurationMs = touchBeganAt.map { Int(value.time.timeIntervalSince($0) * 1000) }
                KeyboardStuckTouchDiagnostics.lastCommitDurationMs = commitDurationMs
                // 調査用ログ(記号面切替 2838): 触った覚えの無い左下キー commit の接触詳細。原因判明後に外す
                // 受け手のログは Debug だけなので、Release では文字列も組み立てない(3413)
                #if DEBUG
                if let touchForensicsLabel {
                    let size = keyFrameInGlobal.size
                    let start = value.startLocation
                    let durationMs = commitDurationMs ?? -1
                    let detail = String(
                        format: "%@ dir=%@ start=(%.0f,%.0f)/key=(%.0f,%.0f) move=(%.0f,%.0f) durMs=%d longPress=%d",
                        touchForensicsLabel, String(describing: committedDirectionForCallback),
                        start.x, start.y, size.width, size.height,
                        value.translation.width, value.translation.height, durationMs, longPressIsActive ? 1 : 0
                    )
                    KeyboardStuckTouchDiagnostics.onTouchForensics?(detail)
                }
                #endif

                finalizeTouchInteractionState()

                if let onCommitWithDirection {
                    onCommitWithDirection(committedText, committedDirectionForCallback)
                } else {
                    onCommit(committedText)
                }
            }
    }

    private func effectiveDirection(for direction: FlickDirection) -> FlickDirection {
        guard direction != .milieu else {
            return .milieu
        }

        return kana.output(for: direction).isEmpty ? .milieu : direction
    }

    private func updateSecondaryFlickState(
        translation: CGSize,
        resolvedDirection: FlickDirection
    ) {
        if secondaryFlickPrimaryDirection == nil {
            guard resolvedDirection == .gauche || resolvedDirection == .droite else {
                return
            }

            let primaryOutput = kana.output(for: resolvedDirection)

            guard FlickKanaLayout.hasSecondaryFlickOutput(forPrimaryOutput: primaryOutput) else {
                return
            }

            secondaryFlickPrimaryDirection = resolvedDirection
            secondaryFlickVerticalDirection = nil
            secondaryFlickAnchorTranslation = translation
            return
        }

        guard let primaryDirection = secondaryFlickPrimaryDirection else {
            return
        }

        if (primaryDirection == .gauche && resolvedDirection == .droite)
            || (primaryDirection == .droite && resolvedDirection == .gauche) {
            resetSecondaryFlickState()
            return
        }

        let relativeTranslation = CGSize(
            width: translation.width - secondaryFlickAnchorTranslation.width,
            height: translation.height - secondaryFlickAnchorTranslation.height
        )
        let resolvedVerticalDirection = FlickGestureResolver.resolve(
            translation: relativeTranslation,
            threshold: Metrics.secondaryFlickThreshold
        )

        if resolvedVerticalDirection == .haut || resolvedVerticalDirection == .bas {
            secondaryFlickVerticalDirection = resolvedVerticalDirection
            return
        }

        secondaryFlickVerticalDirection = nil
    }

    private func resetSecondaryFlickState() {
        secondaryFlickPrimaryDirection = nil
        secondaryFlickVerticalDirection = nil
        secondaryFlickAnchorTranslation = .zero
    }

    // 盤を出したまま何も選ばずに離したとき、これ以内なら「ただのタップ」とみなす(3174)
    static let paletteTapReleaseMaxMs = 400

    // 生タッチ駆動の長押し(RawTouchLongPress 3516)の対象: アクサン候補を持ちフリックの効かない英字キー
    private var isRawLongPressDriven: Bool {
        !allowsDirectionalFlick && !longPressCandidates.isEmpty && longPressCandidateAxis == .horizontal && onLongPress == nil
    }

    private var rawLongPressKeyID: String {
        RawTouchLongPress.keyID(for: kana)
    }

    // 生タッチ側からの合図。盤を出す/選択を動かす/離したら確定。SwiftUI のジェスチャーが既に届いている
    // (isGestureInProgress)なら選択と確定は SwiftUI 側に任せ、ここでは盤を出すだけ
    private func handleRawLongPress(_ event: RawTouchLongPress.Event) {
        guard event.keyID == rawLongPressKeyID else {
            return
        }
        let localX = event.globalX - keyFrameInGlobal.minX
        switch event.kind {
        case .activate:
            guard !longPressIsActive, !didTriggerLongPressAction else {
                return
            }
            cancelLongPressTimer()
            if !isTouching {
                isTouching = true
                onTouchStateChanged(true)
            }
            activeDirection = .milieu
            latestTouchLocationX = localX
            latestTouchLocationY = keyFrameInGlobal.height * 0.5
            longPressAnchorLocationX = localX
            longPressAnchorLocationY = latestTouchLocationY
            highlightedLongPressIndex = 0
            longPressIsActive = true
            #if DEBUG
            KeyboardStuckTouchDiagnostics.longPressProbeLabel = longPressCandidates.first
            KeyboardStuckTouchDiagnostics.longPressProbeRawActivatedAt = Date()
            KeyboardStuckTouchDiagnostics.longPressProbeFiredAt = nil
            #endif
        case .move:
            guard longPressIsActive, !isGestureInProgress else {
                return
            }
            latestTouchLocationX = localX
            highlightedLongPressIndex = longPressIndex(for: localX)
        case .end:
            guard longPressIsActive, !isGestureInProgress else {
                return
            }
            let committedText = longPressCandidates.indices.contains(highlightedLongPressIndex)
                ? longPressCandidates[highlightedLongPressIndex]
                : kana.output(for: .milieu)
            RawTouchLongPress.noteConsumed(keyID: rawLongPressKeyID)
            finalizeTouchInteractionState()
            if let onCommitWithDirection {
                onCommitWithDirection(committedText, .milieu)
            } else {
                onCommit(committedText)
            }
        case .cancel:
            guard longPressIsActive, !isGestureInProgress else {
                return
            }
            finalizeTouchInteractionState()
        }
    }

    // 長押しの待ち時間は、指が触れた時刻(touchTime。端末の稼働時間基準)から数える(3515)。
    // 実機(2026-10-11)では、下段(常に)と中段(ときどき)で、触れてから onChanged が届くまでに約 0.67 秒の
    // 遅れがあった(上段は約 0.1 秒。自前の接触処理は 0ms なので OS 側の配送)。届いてから 0.35 秒数えると
    // 下段のアクサン候補だけ 1.1 秒かかって見える。届いた時点で既に 0.35 秒以上押していれば、すぐ出す。
    // フリックが効くキー(かな)は、遅れて届いた最初のイベントが既に移動中のことがあるので補正しない
    private func longPressDelayCompensation(touchTime: Date) -> TimeInterval {
        guard !allowsDirectionalFlick, !longPressCandidates.isEmpty else {
            return 0
        }
        let deliveryDelay = RawTouchLongPress.uptimeNow() - touchTime.timeIntervalSinceReferenceDate
        // 稼働時間基準でない Date が来たら(負や桁違い)補正しない
        guard deliveryDelay > 0, deliveryDelay < 5 else {
            return 0
        }
        return deliveryDelay
    }

    private func scheduleLongPressIfNeeded(touchTime: Date) {
        guard !longPressCandidates.isEmpty || onLongPress != nil else {
            return
        }

        cancelLongPressTimer()
        let compensation = longPressDelayCompensation(touchTime: touchTime)
        #if DEBUG
        if !longPressCandidates.isEmpty {
            KeyboardStuckTouchDiagnostics.longPressProbeCompensationMs = Int((compensation * 1000).rounded())
        }
        #endif

        let workItem = DispatchWorkItem {
            if let onLongPress {
                didTriggerLongPressAction = true
                onLongPress()
                return
            }
            // 生タッチ側が先に盤を出していたら、選択位置をここで戻さない(3516)
            guard !longPressIsActive else {
                return
            }

            longPressIsActive = true
            #if DEBUG
            KeyboardStuckTouchDiagnostics.longPressProbeFiredAt = Date()  // 調査用ログ(長押しパネルの遅れ 3507)
            #endif
            activeDirection = .milieu
            longPressAnchorLocationX = latestTouchLocationX
            longPressAnchorLocationY = latestTouchLocationY
            // 縦(面選択のパレット)は、指が盤に入るまでどれも選ばない(ユーザ指定 3138)
            highlightedLongPressIndex = longPressCandidateAxis == .vertical
                ? LongPressVerticalCandidatePanel.noSelection
                : 0
        }

        longPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, (longPressDelayOverride ?? Metrics.longPressDelay) - compensation),
            execute: workItem
        )
    }

    private func cancelLongPressTimer() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
    }

    #if DEBUG
    // 調査用ログ(長押しパネルの遅れ 3507): 接触→配送→タイマー発火→パネル出現 の各区間(ms)を診断ログへ 1 行。
    // 配送遅れ = 指が触れた時刻(value.time)と onChanged が届いた時刻の差。下段だけ大きければ OS 側の遅延、
    // パネル出現だけ大きければ描画(main の詰まり)。原因判明後に外す
    private func reportLongPressProbe() {
        if let label = KeyboardStuckTouchDiagnostics.longPressProbeLabel,
            let activatedAt = KeyboardStuckTouchDiagnostics.longPressProbeRawActivatedAt {
            // 生タッチ駆動(3516): 触れてから起動まで(生タッチ側の時刻)と、起動からパネル出現まで
            KeyboardStuckTouchDiagnostics.longPressProbeLabel = nil
            KeyboardStuckTouchDiagnostics.longPressProbeRawActivatedAt = nil
            let now = Date()
            let beganAt = KeyboardStuckTouchDiagnostics.longPressProbeRawBeganAt
            let sinceBeganMs = beganAt.map { Int((activatedAt.timeIntervalSince($0) * 1000).rounded()) } ?? -1
            let appearMs = Int((now.timeIntervalSince(activatedAt) * 1000).rounded())
            KeyboardStuckTouchDiagnostics.onTouchForensics?(
                "長押し計測(生タッチ駆動) key=\(label) 触れてから起動=\(sinceBeganMs)ms パネル出現=\(appearMs)ms"
                    + " 合計=\(sinceBeganMs + appearMs)ms 登録キー=\(RawTouchLongPress.registeredKeyCount)"
            )
            return
        }
        guard let label = KeyboardStuckTouchDiagnostics.longPressProbeLabel,
            let deliveryDelayMs = KeyboardStuckTouchDiagnostics.longPressProbeDeliveryDelayMs,
            let deliveredAt = KeyboardStuckTouchDiagnostics.longPressProbeDeliveredAt,
            let firedAt = KeyboardStuckTouchDiagnostics.longPressProbeFiredAt else {
            return
        }
        KeyboardStuckTouchDiagnostics.longPressProbeLabel = nil
        let now = Date()
        func ms(_ from: Date, _ to: Date) -> Int { Int((to.timeIntervalSince(from) * 1000).rounded()) }
        let plannedMs = Int(((longPressDelayOverride ?? Metrics.longPressDelay) * 1000).rounded())
        let timerMs = ms(deliveredAt, firedAt)
        let appearMs = ms(firedAt, now)
        let midY = KeyboardStuckTouchDiagnostics.longPressProbeKeyMidY ?? -1
        let screenHeight = UIScreen.main.bounds.height
        KeyboardStuckTouchDiagnostics.onTouchForensics?(
            "長押し計測 key=\(label) 配送遅れ=\(deliveryDelayMs)ms"
                + " 接触処理=\(KeyboardStuckTouchDiagnostics.longPressProbeTouchHandlingMs ?? -1)ms"
                + " 補正=\(KeyboardStuckTouchDiagnostics.longPressProbeCompensationMs ?? 0)ms"
                + " タイマー=\(timerMs)ms(予定 \(plannedMs))"
                + " パネル出現=\(appearMs)ms 合計=\(deliveryDelayMs + timerMs + appearMs)ms"
                + String(format: " キー中心y=%.0f/画面高=%.0f(下端まで %.0fpt)", midY, screenHeight, screenHeight - midY)
        )
    }
    #endif

    private func scheduleStuckTouchWatchdog() {
        // SwiftUI の @GestureState reset / .onEnded がメインスレッド過負荷等で
        // 取りこぼされ isTouching が残ってしまうケースのフェイルセーフ。
        // 既存タイマーをキャンセルして 1.2 秒後に「指は離れているのに isTouching=true」
        // の状態を検知したら強制的に押下表示を解除する。
        stuckTouchWatchdogWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            if isTouching && !isGestureInProgress {
                KeyboardStuckTouchDiagnostics.onForceClear?("FlickKeyView key=\(kana.label)")
                finalizeTouchInteractionState()
            }
        }
        stuckTouchWatchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    private func cancelStuckTouchWatchdog() {
        stuckTouchWatchdogWorkItem?.cancel()
        stuckTouchWatchdogWorkItem = nil
    }

    private func finalizeTouchInteractionState() {
        cancelLongPressTimer()
        cancelStuckTouchWatchdog()
        activeDirection = .milieu
        resetSecondaryFlickState()
        longPressIsActive = false
        latestTouchLocationX = 0
        longPressAnchorLocationX = 0
        longPressAnchorLocationY = 0
        didTriggerLongPressAction = false

        if isTouching {
            isTouching = false
            onTouchStateChanged(false)
        }
    }

    // 縦並び: キー上辺(local y = 0)より上に積んだ盤の何段目かを、指の y から決める
    private func longPressIndex(forVertical locationY: CGFloat) -> Int {
        guard !longPressCandidates.isEmpty else {
            return 0
        }

        return LongPressVerticalCandidatePanel.index(
            forLocalX: latestTouchLocationX,
            localY: locationY,
            count: longPressCandidates.count,
            columns: longPressCandidateColumnCount,
            cellWidth: longPressCandidateCellWidth ?? Metrics.candidateCellWidth
        )
    }

    private func longPressIndex(for locationX: CGFloat) -> Int {
        guard !longPressCandidates.isEmpty else {
            return 0
        }

        let slotWidth = effectiveCandidateCellWidth + Metrics.candidateSpacing
        let rawIndex = Int(round((locationX - longPressAnchorLocationX) / slotWidth))

        return max(0, min(longPressCandidates.count - 1, rawIndex))
    }
}

#Preview {
    FlickKeyView(kana: FlickKanaLayout.fiveByTwoRows[0][0]) { _ in }
        .frame(width: 64, height: 58)
        .padding()
}
