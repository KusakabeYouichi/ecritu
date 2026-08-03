import SwiftUI

// 部首の位置カテゴリー(偏/旁/冠/脚/垂/繞/構/独立)と、その字形一覧。
// 分類の源泉は references/bushu.plist(バンドル同梱)。1字形が複数カテゴリーに
// 属してよく、位置を持たない部首は「独立」に入る(2444)。
enum RadicalPositionCategory: String, CaseIterable, Identifiable {
    case hen = "偏"
    case tsukuri = "旁"
    case kanmuri = "冠"
    case ashi = "脚"
    case tare = "垂"
    case nyou = "繞"
    case kamae = "構"
    case independent = "独立"

    var id: String { rawValue }

    var title: String { rawValue }

    var reading: String {
        switch self {
        case .hen: return "へん"
        case .tsukuri: return "つくり"
        case .kanmuri: return "かんむり"
        case .ashi: return "あし"
        case .tare: return "たれ"
        case .nyou: return "にょう"
        case .kamae: return "かまえ"
        case .independent: return "その他"
        }
    }

    var accessibilityLabel: String { "\(title)(\(reading))" }
}

// 漢字の枠(マス)のどこを部首が占めるかを描く抽象アイコン。枠は共通の角丸矩形で、
// 塗りの位置だけがカテゴリーの違いを表す。画像アセットを持たずサイズ自由。
struct RadicalPositionIcon: Shape {
    let category: RadicalPositionCategory

    func path(in rect: CGRect) -> Path {
        // 32×32 の設計座標を rect に合わせる。枠は 3〜29(内側26)。
        let unit = min(rect.width, rect.height) / 32
        let origin = CGPoint(
            x: rect.midX - unit * 16,
            y: rect.midY - unit * 16
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * unit, y: origin.y + y * unit)
        }
        func band(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(
                origin: point(x0, y0),
                size: CGSize(width: (x1 - x0) * unit, height: (y1 - y0) * unit)
            )
        }

        var path = Path()
        let third: CGFloat = 12
        let far: CGFloat = 20

        switch category {
        case .hen:
            path.addRect(band(3, 3, third, 29))
        case .tsukuri:
            // 旁は偏より広いのが通例なので右1/2(偏は1/3)
            path.addRect(band(16, 3, 29, 29))
        case .kanmuri:
            path.addRect(band(3, 3, 29, third))
        case .ashi:
            path.addRect(band(3, far, 29, 29))
        case .tare:
            // 上の帯 + 左へ垂れる(广)
            path.addRect(band(3, 3, 29, third))
            path.addRect(band(3, third, third, 29))
        case .nyou:
            // 左 + 下へ回り込む(辶)
            path.addRect(band(3, 3, third, 29))
            path.addRect(band(third, far, 29, 29))
        case .kamae:
            // 門の形。左右の柱+上の帯で、下の真ん中1/3は開ける(間/開)
            path.addRect(band(3, 3, 29, third))
            path.addRect(band(3, third, third, 29))
            path.addRect(band(far, third, 29, 29))
        case .independent:
            // 位置を持たない = 中央の小さな塊
            path.addRect(band(11, 11, 21, 21))
        }
        return path
    }
}

// 部首の画数の数え方。辞書によって流儀が分かれる字形(艹 3/4、辶 3/4、礻 4/5、飠 7/8)の
// 扱いをコンテナーアプリの設定で切り替える(2448)。
enum RadicalStrokeCountStyle: String, CaseIterable, Identifiable {
    case modern
    case traditional

    var id: String { rawValue }
}

struct RadicalForm: Identifiable, Equatable {
    let form: String
    let radical: Int
    // その字形自体の画数(氵=3画/水=4画)。部首一覧の画数区切りに使う。新字体で数えた値
    let strokes: Int
    // 旧字体(伝統)で数えた画数。流儀が分かれる字形だけ持つ(無ければ strokes と同じ)
    let strokesTraditional: Int?
    let name: String
    let categories: [String]
    let examples: String

    var id: String { "\(radical)-\(form)" }

    func strokes(style: RadicalStrokeCountStyle) -> Int {
        switch style {
        case .modern:
            return strokes
        case .traditional:
            return strokesTraditional ?? strokes
        }
    }
}

enum KanjiRadicalCatalog {
    // bushu.plist は245エントリーの小さなデータなので初回参照時に一度だけ読む。
    private static let lock = NSLock()
    private static var cache: [RadicalForm]?
    // テスト用: バンドル未同梱の環境(unit test)でリポジトリの references/ を直接読ませる。
    // 欧文語彙の genericLatinLexiconDirectoryURLOverride と同じ役割。
    static var resourceDirectoryURLOverride: URL? {
        didSet {
            lock.lock()
            cache = nil
            lock.unlock()
        }
    }

    static var allForms: [RadicalForm] {
        lock.lock()
        if let cache {
            lock.unlock()
            return cache
        }
        lock.unlock()
        let loaded = load()
        lock.lock()
        cache = loaded
        lock.unlock()
        return loaded
    }

    // カテゴリー内は画数順(同画数は部首番号順)。部首を探すときの手掛かりが画数のため、
    // 一覧もその順に並べ、画数の区切りを挟めるようにする(2447)。画数の流儀は設定で切替(2448)。
    static func forms(
        in category: RadicalPositionCategory,
        style: RadicalStrokeCountStyle = .modern
    ) -> [RadicalForm] {
        allForms
            .filter { $0.categories.contains(category.rawValue) }
            .sorted { lhs, rhs in
                let left = lhs.strokes(style: style)
                let right = rhs.strokes(style: style)
                return left != right ? left < right : lhs.radical < rhs.radical
            }
    }

    private static func load() -> [RadicalForm] {
        let resolved = resourceDirectoryURLOverride?.appendingPathComponent("bushu.plist")
            ?? Bundle(for: KanaKanjiStore.self).url(forResource: "bushu", withExtension: "plist")
        guard let url = resolved,
            let data = try? Data(contentsOf: url),
            let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { entry in
            guard let form = entry["form"] as? String,
                let radical = entry["radical"] as? Int,
                let strokes = entry["strokes"] as? Int,
                let name = entry["name"] as? String,
                let categories = entry["categories"] as? [String] else {
                return nil
            }
            return RadicalForm(
                form: form,
                radical: radical,
                strokes: strokes,
                strokesTraditional: entry["strokesTraditional"] as? Int,
                name: name,
                categories: categories,
                examples: entry["examples"] as? String ?? ""
            )
        }
    }
}
