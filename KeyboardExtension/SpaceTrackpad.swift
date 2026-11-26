import Combine
import CoreGraphics
import Foundation
import SwiftUI
import UIKit

// 空白キーの長押しでカーソルを動かす(トラックパッド。Apple 純正と同じ。c10)。
// 判断(発動・積算・移動量)は純粋な型に置き、ビューと VC は結果を配線するだけにする
enum SpaceTrackpad {
    // 押してからこの時間、フリックの閾値未満のままならトラックパッドになる
    static let activationDelay: TimeInterval = 0.4
    // 指の横移動この量ごとに 1 文字
    static let pointsPerCharacter: CGFloat = 9
    // スナップショットの端に着いたとき、最後のカーソル移動からこの時間たっていれば文脈を読み直す(改訂 2 の R1)
    static let edgeRereadInterval: TimeInterval = 0.1

    // 変換前の文字がある(空白キーが[変換])ときは効かせない。従来の候補送りの連打のまま
    static func isAvailable(composingEmpty: Bool) -> Bool {
        composingEmpty
    }
}

// 空白キーの 1 回の接触の状態。押した → (0.4 秒・閾値未満)トラックパッド/(閾値超え)フリック/(先に離す)空白
struct SpaceTrackpadGesture {
    enum Phase: Equatable {
        case idle
        case pending
        case active
        case flick
    }

    enum Release: Equatable {
        case space
        case tab
        // トラックパッドだった接触は、離しても何も入れない
        case nothing
    }

    private(set) var phase: Phase = .idle
    private var beganAt: TimeInterval = 0
    private var lastTranslation: CGSize = .zero
    private var accumulator = SpaceTrackpadAccumulator(anchorX: 0)
    // 直前の接触の結果。片づけ(取り消しの通知)が指を離した通知より先に来ても、同じ接触の結果を返すために次の begin まで持つ
    private var lastRelease: Release = .space

    // 発動の時刻の比較のゆとり。タイマーが計った時刻よりわずかに早く届いても発動を取りこぼさない
    private static let activationTimeTolerance: TimeInterval = 0.001

    mutating func begin(at time: TimeInterval) {
        phase = .pending
        beganAt = time
        lastTranslation = .zero
        lastRelease = .space
    }

    // 指が動いた。トラックパッド中なら動かす文字数(左が負)を返す。それ以外は 0
    mutating func move(to translation: CGSize) -> Int {
        lastTranslation = translation
        switch phase {
        case .pending:
            if FlickGestureResolver.resolve(translation: translation) != .milieu {
                phase = .flick
            }
            return 0
        case .active:
            return accumulator.update(translationX: translation.width)
        case .idle, .flick:
            return 0
        }
    }

    // 発動の判定(押してからの時計で呼ぶ)。トラックパッドになったら true。積算の起点はこの時点の指の位置
    mutating func activateIfDue(at time: TimeInterval, isAvailable: Bool) -> Bool {
        guard phase == .pending,
            isAvailable,
            time - beganAt + Self.activationTimeTolerance >= SpaceTrackpad.activationDelay else {
            return false
        }
        phase = .active
        accumulator = SpaceTrackpadAccumulator(anchorX: lastTranslation.width)
        return true
    }

    // 吹き出し・強調色に使う向き。トラックパッド中は出さない(.milieu)。空白キーのフリックは上(タブ)だけ
    var feedbackDirection: FlickDirection {
        guard phase != .active else {
            return .milieu
        }
        return FlickGestureResolver.resolve(translation: lastTranslation) == .haut ? .haut : .milieu
    }

    // 接触を終える。終えた後にもう一度呼ぶと、同じ接触の結果をもう一度返す(トラックパッドだった接触で空白を入れない)
    mutating func end() -> Release {
        switch phase {
        case .active:
            lastRelease = .nothing
        case .idle:
            break
        case .pending, .flick:
            lastRelease = FlickGestureResolver.resolve(translation: lastTranslation) == .haut ? .tab : .space
        }
        phase = .idle
        return lastRelease
    }
}

// 指の横移動を文字数へ直す。端数は持ち越す。縦の移動は見ない(上下は今回なし)
struct SpaceTrackpadAccumulator {
    private var lastX: CGFloat
    private var remainder: CGFloat = 0

    init(anchorX: CGFloat) {
        lastX = anchorX
    }

    mutating func update(translationX: CGFloat) -> Int {
        remainder += translationX - lastX
        lastX = translationX
        let steps = Int((remainder / SpaceTrackpad.pointsPerCharacter).rounded(.towardZero))
        remainder -= CGFloat(steps) * SpaceTrackpad.pointsPerCharacter
        return steps
    }
}

// 読めた文脈(カーソルの前後)の上で、自前のカーソル位置(Character の添字)を動かす。
// ホストへ送る量は、またいだ Character 群の utf16 数の合計(絵文字・結合文字の途中に入らない)
struct SpaceTrackpadCursor {
    private let characters: [Character]
    private(set) var position: Int

    init(before: String?, after: String?) {
        let beforeCharacters = Array(before ?? "")
        characters = beforeCharacters + Array(after ?? "")
        position = beforeCharacters.count
    }

    // steps 文字ぶん動かす(左が負)。端で止まる。戻り値はホストへ送る utf16 の量(動かなければ 0)
    mutating func move(by steps: Int) -> Int {
        let target = min(max(position + steps, 0), characters.count)
        guard target != position else {
            return 0
        }
        let lower = min(position, target)
        let upper = max(position, target)
        let length = characters[lower..<upper].reduce(0) { $0 + $1.utf16.count }
        let offset = target > position ? length : -length
        position = target
        return offset
    }
}

// トラックパッド 1 回ぶんのカーソル。端に着いたら、最後の移動から少し待って文脈を読み直し、その向きに字があれば続ける(R1)。
// 移動の直後に読み直さない(ホストの文脈がまだ古いことがある)
struct SpaceTrackpadCursorSession {
    private var cursor: SpaceTrackpadCursor
    // 最後にカーソルを動かした時刻か、文脈を読んだ時刻(読み直しも 0.1 秒に 1 回まで)
    private var lastAdjustAt: TimeInterval

    init(before: String?, after: String?, now: TimeInterval) {
        cursor = SpaceTrackpadCursor(before: before, after: after)
        lastAdjustAt = now
    }

    // steps 文字ぶん動かすためにホストへ送る utf16 の量(0 なら送らない)
    mutating func utf16Offset(
        forSteps steps: Int,
        now: TimeInterval,
        rereadContext: () -> (before: String?, after: String?)
    ) -> Int {
        guard steps != 0 else {
            return 0
        }
        var offset = cursor.move(by: steps)
        if offset == 0, now - lastAdjustAt >= SpaceTrackpad.edgeRereadInterval {
            let context = rereadContext()
            cursor = SpaceTrackpadCursor(before: context.before, after: context.after)
            offset = cursor.move(by: steps)
            lastAdjustAt = now
        }
        if offset != 0 {
            lastAdjustAt = now
        }
        return offset
    }
}

// トラックパッド中か。キーの表示(文字を消す)・3×3+わ の盤の絵・面の生タッチ認識器が読む。
// 置き場はここ 1 つ。書くのは VC(始め/終わり)と、VC が既に無いときの空白キーの片づけ
final class SpaceTrackpadDisplayState: ObservableObject {
    static let shared = SpaceTrackpadDisplayState()

    @Published private(set) var isActive = false
    // 盤の絵を描いた回数と大きさ(診断ログ用。かなで盤が出ず枠だけのことがある件の切り分け。3909)。描画の中で書くので発行しない
    private(set) var boardDrawCount = 0
    private(set) var lastBoardSize: CGSize = .zero

    func setActive(_ active: Bool) {
        if active {
            boardDrawCount = 0
            lastBoardSize = .zero
        }
        if isActive != active {
            isActive = active
        }
    }

    func noteBoardDrawn(size: CGSize) {
        boardDrawCount += 1
        lastBoardSize = size
    }
}

// トラックパッド中はキーの文字・アイコンを消す(枠と面の色は残す)。キーの型に格納プロパティを足すと
// キー群の大きなタプルが太る(2921)ので、購読はこの修飾の側に持たせる。VoiceOver のラベルは消さない
private struct SpaceTrackpadHidesKeyLabelModifier: ViewModifier {
    @ObservedObject private var trackpadDisplay = SpaceTrackpadDisplayState.shared

    func body(content: Content) -> some View {
        content.opacity(trackpadDisplay.isActive ? 0 : 1)
    }
}

// トラックパッド中は左の列のキーの面を普通の色にそろえる。今いる面のキー(押せない印で濃い)だけ色が違うと、
// 盤の出口の 2 ます([abc][あいう])の片方だけが塞がって見えた(ユーザ指定 3909)
private struct SpaceTrackpadNeutralFaceModifier: ViewModifier {
    let normal: Color
    let cornerRadius: CGFloat
    @ObservedObject private var trackpadDisplay = SpaceTrackpadDisplayState.shared

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(trackpadDisplay.isActive ? KeyboardThemePalette.keyBackground : normal)
        )
    }
}

extension View {
    func hiddenDuringSpaceTrackpad() -> some View {
        modifier(SpaceTrackpadHidesKeyLabelModifier())
    }

    func spaceTrackpadNeutralFace(normal: Color, cornerRadius: CGFloat) -> some View {
        modifier(SpaceTrackpadNeutralFaceModifier(normal: normal, cornerRadius: cornerRadius))
    }
}

// トラックパッド中だけ面の最前面に置く透明な受け板(改訂 2 の R3)。2 本目の指がほかのキーに触れたら、
// その打鍵はキーへ届けずに捨て、トラックパッドを終える。続けている空白キーの touch は始まった時点の
// ビューに結び付いているので、この板を足しても切れない
final class SpaceTrackpadTouchShieldView: UIView {
    var onTouch: () -> Void = {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouch()
    }
}
