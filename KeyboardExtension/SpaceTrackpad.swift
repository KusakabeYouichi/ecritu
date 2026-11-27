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
    // 指の縦移動この量ごとに 1 行(ユーザ指定 3916: Apple のと同じく上下にも動かす)。文字より粗くして、横へ滑らせているときに行が跳ねないようにする
    static let pointsPerLine: CGFloat = 20
    // スナップショットの端に着いたとき、最後のカーソル移動からこの時間たっていれば文脈を読み直す(改訂 2 の R1)
    static let edgeRereadInterval: TimeInterval = 0.1

    // 変換前の文字がある(空白キーが[変換])ときは効かせない。従来の候補送りの連打のまま
    static func isAvailable(composingEmpty: Bool) -> Bool {
        composingEmpty
    }
}

// 1 回の指の動きで動かす量。文字は左が負、行は上が負
struct SpaceTrackpadStep: Equatable {
    var characters: Int
    var lines: Int

    static let zero = SpaceTrackpadStep(characters: 0, lines: 0)

    var isZero: Bool {
        characters == 0 && lines == 0
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
    private var lineAccumulator = SpaceTrackpadAccumulator(anchorX: 0, unit: SpaceTrackpad.pointsPerLine)
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

    // 指が動いた。トラックパッド中なら動かす文字数(左が負)と行数(上が負)を返す。それ以外は 0
    mutating func move(to translation: CGSize) -> SpaceTrackpadStep {
        lastTranslation = translation
        switch phase {
        case .pending:
            if FlickGestureResolver.resolve(translation: translation) != .milieu {
                phase = .flick
            }
            return .zero
        case .active:
            return SpaceTrackpadStep(
                characters: accumulator.update(translationX: translation.width),
                lines: lineAccumulator.update(translationX: translation.height)
            )
        case .idle, .flick:
            return .zero
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
        lineAccumulator = SpaceTrackpadAccumulator(anchorX: lastTranslation.height, unit: SpaceTrackpad.pointsPerLine)
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

// 指の 1 方向の移動を、unit ごとの段数へ直す。端数は持ち越す。横(文字)と縦(行)で 1 つずつ持つ
struct SpaceTrackpadAccumulator {
    private var lastX: CGFloat
    private var remainder: CGFloat = 0
    private let unit: CGFloat

    init(anchorX: CGFloat, unit: CGFloat = SpaceTrackpad.pointsPerCharacter) {
        lastX = anchorX
        self.unit = unit
    }

    mutating func update(translationX: CGFloat) -> Int {
        remainder += translationX - lastX
        lastX = translationX
        let steps = Int((remainder / unit).rounded(.towardZero))
        remainder -= CGFloat(steps) * unit
        return steps
    }
}

// 読めた文脈(カーソルの前後)の上で、自前のカーソル位置(Character の添字)を動かす。
// ホストへ送る量は、またいだ Character 群の utf16 数の合計(絵文字・結合文字の途中に入らない)
struct SpaceTrackpadCursor {
    private let characters: [Character]
    private(set) var position: Int
    // 行を続けて動かすときの桁(行頭からの Character 数)。短い行を通っても元の桁へ戻る(Apple のと同じ)。横に動かしたら忘れる
    private var preferredColumn: Int?

    init(before: String?, after: String?) {
        let beforeCharacters = Array(before ?? "")
        characters = beforeCharacters + Array(after ?? "")
        position = beforeCharacters.count
    }

    // steps 文字ぶん動かす(左が負)。端で止まる。戻り値はホストへ送る utf16 の量(動かなければ 0)
    mutating func move(by steps: Int) -> Int {
        preferredColumn = nil
        return moveTo(min(max(position + steps, 0), characters.count))
    }

    // lines 行ぶん動かす(上が負)。行は改行で区切った行(折り返しの見た目の行はキーボードからは分からない)。
    // 読めた文脈の最初の行・最後の行より先へは動かない(0 を返し、端の読み直しに任せる)
    mutating func moveLines(by lines: Int) -> Int {
        guard lines != 0 else {
            return 0
        }
        let currentStart = lineStart(containing: position)
        let column = preferredColumn ?? (position - currentStart)
        var start = currentStart
        for _ in 0..<abs(lines) {
            if lines < 0 {
                guard start > 0 else { break }
                // start - 1 は前の行の終わりの改行
                start = lineStart(containing: start - 1)
            } else {
                guard let end = lineEnd(from: start), end < characters.count else { break }
                start = end + 1
            }
        }
        guard start != currentStart else {
            return 0
        }
        let target = min(start + column, lineEnd(from: start) ?? characters.count)
        let offset = moveTo(target)
        preferredColumn = column
        return offset
    }

    // 行頭にいる(直前が改行)/行末の改行の手前にいる。改行をまたげたかの判定に使う
    var isAtLineStart: Bool {
        position > 0 && characters[position - 1].isNewline
    }

    var isAtLineEnd: Bool {
        position < characters.count && characters[position].isNewline
    }

    // 今の桁(覚えている桁があればそれ)
    var column: Int {
        preferredColumn ?? (position - lineStart(containing: position))
    }

    // 今の行の中で桁 column へ(行が短ければ行末)。以後の上下はこの桁を覚える
    mutating func moveToColumn(_ column: Int) -> Int {
        let start = lineStart(containing: position)
        let offset = moveTo(min(start + column, lineEnd(from: start) ?? characters.count))
        preferredColumn = column
        return offset
    }

    // 読めた文脈の端の改行をまたぐ量(下=後ろの文脈の終わり+改行 1、上=前の文脈の頭−改行 1)。
    // 見えない改行は "\n" の 1 とみなす。文章の端ならホストが止めるので害は無い。位置は端へ移す(読み直すまでの仮)
    mutating func offsetCrossingLineEdge(down: Bool) -> Int {
        let keptColumn = column
        let offset = moveTo(down ? characters.count : 0)
        preferredColumn = keptColumn
        return offset + (down ? 1 : -1)
    }

    // index の文字を含む行の頭(index が行末の改行なら、その改行で終わる行の頭)
    private func lineStart(containing index: Int) -> Int {
        var i = index
        while i > 0, !characters[i - 1].isNewline {
            i -= 1
        }
        return i
    }

    // start から始まる行の終わりの改行の位置。最後の行(改行が無い)は nil
    private func lineEnd(from start: Int) -> Int? {
        var i = start
        while i < characters.count {
            if characters[i].isNewline {
                return i
            }
            i += 1
        }
        return nil
    }

    private mutating func moveTo(_ target: Int) -> Int {
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
    // 見えない改行をまたいで、読み直し待ちの桁(nil=待っていない。3920)
    private var pendingColumn: Int?
    private var pendingCrossingDown = true
    // 待つ間にたまった上下の行数(上が負)。捨てると下だけ遅かった(ユーザ報告 3921)
    private var queuedLines = 0

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
        // 改行をまたいだ直後の待ちの間の横の動きは捨てる(短い)
        guard let resolved = resolvePendingCrossing(now: now, rereadContext: rereadContext) else {
            return 0
        }
        var reread = resolved.justReread
        return resolved.prefix + move(now: now, rereadContext: rereadContext, didReread: &reread) { $0.move(by: steps) }
    }

    // lines 行ぶん動かすためにホストへ送る utf16 の量(上が負。3916)。端の読み直しは文字と同じ。
    // 読み直しても先の行が見えないときは、行の端の改行をまたいで 1 行ぶんだけ進め、次の指の動きで読み直して同じ桁に合わせる(3920)。
    // ホスト(メモ等)は後ろの文脈を今の行の終わりまでしか渡さず、始めた位置より下へ行けなかった(実機ログ 3919: 後ろはいつも改行 0)
    mutating func utf16Offset(
        forLines lines: Int,
        now: TimeInterval,
        rereadContext: () -> (before: String?, after: String?)
    ) -> Int {
        guard lines != 0 else {
            return 0
        }
        guard let resolved = resolvePendingCrossing(now: now, rereadContext: rereadContext) else {
            queuedLines += lines
            return 0
        }
        let total = lines + queuedLines
        queuedLines = 0
        guard total != 0 else {
            return resolved.prefix
        }
        var reread = resolved.justReread
        let offset = move(now: now, rereadContext: rereadContext, didReread: &reread) { $0.moveLines(by: total) }
        guard offset == 0, reread else {
            return resolved.prefix + offset
        }
        // 読み直した直後でも先の行が見えない。1 行ぶん改行をまたぎ、残りは次に回す
        let crossing = cursor.offsetCrossingLineEdge(down: total > 0)
        pendingColumn = cursor.column
        pendingCrossingDown = total > 0
        queuedLines = total - total.signum()
        lastAdjustAt = now
        return resolved.prefix + crossing
    }

    // 改行をまたいだ後なら、ホストに届くまで待ってから読み直し、覚えた桁へ合わせる。
    // nil=まだ待つ。prefix=桁合わせでホストへ送る量、justReread=いま読み直した(先が見えなければすぐ次をまたいでよい)
    private mutating func resolvePendingCrossing(
        now: TimeInterval,
        rereadContext: () -> (before: String?, after: String?)
    ) -> (prefix: Int, justReread: Bool)? {
        guard let column = pendingColumn else {
            return (0, false)
        }
        guard now - lastAdjustAt >= SpaceTrackpad.edgeRereadInterval else {
            return nil
        }
        let context = rereadContext()
        cursor = SpaceTrackpadCursor(before: context.before, after: context.after)
        // またげたか(下=行頭にいる、上=行末の改行の手前にいる)。文章の端でホストが止めたなら、ためた行は捨てる
        // (捨てないと、端で下へ動かし続けたぶんを上へ戻すまで上に動かなくなる)
        let crossed = pendingCrossingDown ? cursor.isAtLineStart : cursor.isAtLineEnd
        let prefix = cursor.moveToColumn(column)
        pendingColumn = nil
        lastAdjustAt = now
        if !crossed {
            queuedLines = 0
        }
        return (prefix, crossed)
    }

    // 今の文脈で動かし、動かなければ(0.1 秒たっていれば)読み直してもう一度
    private mutating func move(
        now: TimeInterval,
        rereadContext: () -> (before: String?, after: String?),
        didReread: inout Bool,
        move: (inout SpaceTrackpadCursor) -> Int
    ) -> Int {
        var offset = move(&cursor)
        if offset == 0, now - lastAdjustAt >= SpaceTrackpad.edgeRereadInterval {
            let context = rereadContext()
            cursor = SpaceTrackpadCursor(before: context.before, after: context.after)
            offset = move(&cursor)
            lastAdjustAt = now
            didReread = true
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
    // 描いた個体ごとの回数(個体の印 → 回数。3910)。見えている個体でなく裏に残った個体だけが描いていないかを見る
    private(set) var boardDrawCountByOwner: [String: Int] = [:]

    func setActive(_ active: Bool) {
        if active {
            boardDrawCount = 0
            lastBoardSize = .zero
            boardDrawCountByOwner = [:]
        }
        if isActive != active {
            isActive = active
        }
    }

    // 最後に描いたときの外観と線の色(診断ログ用。描いているのに見えない件の切り分け 3918)。例: 外観=light 線=0.00,0.00,0.00,0.18
    private(set) var lastBoardAppearance = ""

    func noteBoardDrawn(size: CGSize, ownerTag: String, appearance: String = "") {
        boardDrawCount += 1
        lastBoardSize = size
        boardDrawCountByOwner[ownerTag, default: 0] += 1
        lastBoardAppearance = appearance
    }

    // 終了の行に書く形。例: D06ED979×1 7E303189×2(印の順)
    var boardDrawOwnersSummary: String {
        boardDrawCountByOwner.isEmpty
            ? "なし"
            : boardDrawCountByOwner.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
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
