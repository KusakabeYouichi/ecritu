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
// 流儀が分かれる部首の画数の選択肢(字形と画数)。部首ごとに個別に選べる(2502)。
// 先頭の画数が Unihan の総画数の計算基準で、字グリッドの総画数はどの選択でも変わらない。
struct RadicalStrokeOption: Equatable, Hashable, Identifiable {
    let form: String
    let strokes: Int

    var id: String { "\(form)-\(strokes)" }
    var title: String { "\(form) \(strokes)画" }
}

enum RadicalStrokeChoiceCatalog {
    // 部首番号 → 選択肢。しめすへんは 礻(4)/⺭(5)/示(5) で画数が重複するが3択で並べる(ユーザー指定)
    static let optionsByRadical: [Int: [RadicalStrokeOption]] = [
        140: [.init(form: "⺾", strokes: 3), .init(form: "⺿", strokes: 4), .init(form: "艸", strokes: 6)],
        162: [.init(form: "⻌", strokes: 3), .init(form: "⻍", strokes: 4), .init(form: "辵", strokes: 7)],
        113: [.init(form: "礻", strokes: 4), .init(form: "⺭", strokes: 5), .init(form: "示", strokes: 5)],
        184: [.init(form: "飠", strokes: 7), .init(form: "⻟", strokes: 8), .init(form: "食", strokes: 9)]
    ]

    // 設定画面の並び順(部首番号順ではなく画数の小さい部首から)
    static let orderedRadicals: [Int] = [140, 162, 113, 184]

    static func options(forRadical radical: Int) -> [RadicalStrokeOption] {
        optionsByRadical[radical] ?? []
    }

    // 総画数(Unihan kTotalStrokes)の計算基準になる画数 = 選択肢の先頭
    static func totalBasisStrokes(forRadical radical: Int) -> Int? {
        optionsByRadical[radical]?.first?.strokes
    }
}

// 部首ごとの画数選択。共有 defaults には "140:4,162:3" のような1本の文字列で持つ
// (キーボードへの受け渡し経路を増やさないため)。旧設定 modern/traditional も受け取る。
struct RadicalStrokeChoices: Equatable {
    private var strokesByRadical: [Int: Int]

    init(strokesByRadical: [Int: Int] = [:]) {
        self.strokesByRadical = strokesByRadical
    }

    init(rawValue: String) {
        // 旧設定(単一の流儀)からの移行: traditional は各部首の2番目の選択肢に対応する
        switch rawValue {
        case "traditional":
            var mapped: [Int: Int] = [:]
            for radical in RadicalStrokeChoiceCatalog.orderedRadicals {
                let options = RadicalStrokeChoiceCatalog.options(forRadical: radical)
                if options.count >= 2 {
                    mapped[radical] = options[1].strokes
                }
            }
            self.init(strokesByRadical: mapped)
            return
        case "", "modern":
            self.init(strokesByRadical: [:])
            return
        default:
            break
        }
        var parsed: [Int: Int] = [:]
        for pair in rawValue.split(separator: ",") {
            let fields = pair.split(separator: ":")
            guard fields.count == 2,
                let radical = Int(fields[0]),
                let strokes = Int(fields[1]) else {
                continue
            }
            parsed[radical] = strokes
        }
        self.init(strokesByRadical: parsed)
    }

    var rawValue: String {
        RadicalStrokeChoiceCatalog.orderedRadicals
            .compactMap { radical in
                strokesByRadical[radical].map { "\(radical):\($0)" }
            }
            .joined(separator: ",")
    }

    // 未指定なら選択肢の先頭(=Unihan 基準)
    func selectedOption(forRadical radical: Int) -> RadicalStrokeOption? {
        let options = RadicalStrokeChoiceCatalog.options(forRadical: radical)
        guard !options.isEmpty else {
            return nil
        }
        guard let strokes = strokesByRadical[radical] else {
            return options.first
        }
        return options.first { $0.strokes == strokes } ?? options.first
    }

    func strokes(forRadical radical: Int) -> Int? {
        selectedOption(forRadical: radical)?.strokes
    }

    mutating func setStrokes(_ strokes: Int, forRadical radical: Int) {
        strokesByRadical[radical] = strokes
    }
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

    // 部首ごとの選択(設定)を反映した画数。選択肢を持たない字形は plist の値そのまま。
    func strokes(choices: RadicalStrokeChoices) -> Int {
        guard strokesTraditional != nil,
            let selected = choices.strokes(forRadical: radical) else {
            return strokes
        }
        return selected
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
        choices: RadicalStrokeChoices = RadicalStrokeChoices()
    ) -> [RadicalForm] {
        allForms
            .filter { $0.categories.contains(category.rawValue) }
            .sorted { lhs, rhs in
                let left = lhs.strokes(choices: choices)
                let right = rhs.strokes(choices: choices)
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
