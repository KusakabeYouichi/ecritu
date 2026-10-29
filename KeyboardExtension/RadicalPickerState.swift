import Foundation
import Observation

// 字グリッドに総画数の区切り(タップ不可)を挟む。索引は総画数順に並んでいるので
// 値が変わった位置に入れるだけでよい(2483)
enum KanjiCharacterListItem {
    case totalStrokeMarker(Int)
    case character(KanjiRadicalFileIndex.Entry)
}

// 部首一覧に画数の区切り(タップ不可)を挟む。部首を探す手掛かりは画数のため(2447)
enum RadicalListItem {
    case strokeMarker(Int)
    case form(RadicalForm)
}

// 部首ピッカーの一覧の組み立て規則(表示から切り離した純関数)。
enum RadicalPickerListing {
    // 総画数は Unicode(Unihan kTotalStrokes)の値をそのまま使う。部首の数え方の設定ぶんを
    // 足し引きする方式(2483)は、字ごとにどの字形を使うか索引に無いため一律加算になり不正確
    // だった。数え方が分かれる字形はヘッダーに「N画に数えてください」と添えて読み替えを促す(2492)。
    static func characterListItems(entries: [KanjiRadicalFileIndex.Entry]) -> [(id: String, kind: KanjiCharacterListItem)] {
        var items: [(id: String, kind: KanjiCharacterListItem)] = []
        var lastTotal = -1
        for entry in entries {
            let total = entry.totalStrokes
            if total > 0, total != lastTotal {
                items.append((id: "total-\(total)", kind: .totalStrokeMarker(total)))
                lastTotal = total
            }
            items.append((id: "char-\(entry.character)", kind: .character(entry)))
        }
        return items
    }

    static func radicalListItems(
        forms: [RadicalForm],
        strokeChoices: RadicalStrokeChoices
    ) -> [(id: String, kind: RadicalListItem)] {
        var items: [(id: String, kind: RadicalListItem)] = []
        var lastStrokes = -1
        for form in forms {
            let strokes = form.strokes(choices: strokeChoices)
            if strokes != lastStrokes {
                items.append((id: "marker-\(strokes)", kind: .strokeMarker(strokes)))
                lastStrokes = strokes
            }
            items.append((id: form.id, kind: .form(form)))
        }
        return items
    }
}

// 部首ピッカーの選択(分類と、開いている部首)。分類を変えたら部首の選択は閉じる。
@Observable
@MainActor
final class RadicalPickerState {
    private(set) var selectedCategory: RadicalPositionCategory = .hen
    private(set) var selectedForm: RadicalForm?

    func selectCategory(_ category: RadicalPositionCategory) {
        selectedCategory = category
        selectedForm = nil
    }

    func selectForm(_ form: RadicalForm) {
        selectedForm = form
    }

    func clearForm() {
        selectedForm = nil
    }
}
