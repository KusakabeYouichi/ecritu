import Foundation
import Observation

// 顔文字パネルの分類(基本/ショートカット/検索/取り込み分類)。
struct KaomojiCategory: Identifiable, Hashable {
    enum Kind: Hashable {
        case shortcut
        case existing
        case imported(String)
        case search
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .shortcut:
            return "shortcut"
        case .existing:
            return "existing"
        case .imported(let name):
            return "imported:\(name)"
        case .search:
            return "search"
        }
    }

    var title: String {
        switch kind {
        case .shortcut:
            return "Raccourcis (ショートカット)"
        case .existing:
            return "Base (基本)"
        case .imported(let name):
            switch name {
            case "rire":
                return "Sourire / Rire (笑顔)"
            case "kawaii":
                return "Kawaii / Chou (かわいい)"
            case "timide":
                return "Timide (照れ)"
            case "panique":
                return "Stress / Panique (焦り)"
            case "decu":
                return "Déçu / Déprimé (がっかり)"
            case "triste":
                return "Triste (悲しい)"
            case "colere":
                return "En colère (怒り)"
            case "surprise":
                return "Surprise (驚き)"
            case "dodo":
                return "Dodo (眠い)"
            case "coucou":
                return "Coucou (挨拶)"
            case "amour":
                return "Amour (愛)"
            case "excite":
                return "Excité / Crazy (興奮)"
            case "action":
                return "Action (動き)"
            case "bizarre":
                return "Bizarre (奇妙)"
            case "heros":
                return "Héros (キャラ)"
            case "special":
                return "Spécial (特殊)"
            case "lignes":
                return "Lignes (区切り線)"
            default:
                return name
            }
        case .search:
            return "Recherche (検索)"
        }
    }

    var icon: String {
        switch kind {
        case .shortcut:
            return "⚡️"
        case .existing:
            return "🙂"
        case .imported(let name):
            switch name {
            case "rire":
                return "😂"
            case "kawaii":
                return "🥰"
            case "timide":
                return "😊"
            case "panique":
                return "💦"
            case "decu":
                return "😔"
            case "triste":
                return "😢"
            case "colere":
                return "😠"
            case "surprise":
                return "😲"
            case "dodo":
                return "😴"
            case "coucou":
                return "🙋"
            case "amour":
                return "❤️"
            case "excite":
                return "💥"
            case "action":
                return "🏃"
            case "bizarre":
                return "🤪"
            case "heros":
                return "🧑"
            case "special":
                return "✨"
            case "lignes":
                return "💬"
            default:
                return "🗂️"
            }
        case .search:
            return "🔎"
        }
    }
}

// 顔文字パネルの選択状態と、そこから決まる規則(分類の並び・一覧・読み検索)。
// 幅の計算や描画はビューに残す
@Observable
@MainActor
final class KaomojiPanelState {
    var selectedCategoryID = "existing"
    var selectedReadingPrefix: String? = nil
    var selectedReading: String? = nil

    static var categories: [KaomojiCategory] {
        // 分類の表示順は KaomojiCatalog.displayCategoryOrder に一元化(設定アプリも同じ並びを写す)
        let importedCategorySet = Set(KaomojiCatalog.importedCategoryOrder)
        let orderedImportedCategories = KaomojiCatalog.displayCategoryOrder
            .filter { importedCategorySet.contains($0) }
        let remainingImportedCategories = KaomojiCatalog.importedCategoryOrder
            .filter { !orderedImportedCategories.contains($0) }

        // 先頭3件(基本→ショートカット→検索)は設定アプリの選択肢と同じ順。
        // 導入時から ⚡→🙂→🔎 で設定側(🙂→⚡→🔎)と食い違っていたのを是正(ユーザ指示 2755)
        var categories: [KaomojiCategory] = [
            KaomojiCategory(kind: .existing),
            KaomojiCategory(kind: .shortcut),
            KaomojiCategory(kind: .search)
        ]

        categories.append(contentsOf: orderedImportedCategories.map { name in
            KaomojiCategory(kind: .imported(name))
        })
        categories.append(contentsOf: remainingImportedCategories.map { name in
            KaomojiCategory(kind: .imported(name))
        })
        return categories
    }

    var selectedCategory: KaomojiCategory {
        Self.categories.first(where: { $0.id == selectedCategoryID })
            ?? KaomojiCategory(kind: .existing)
    }

    var isSearchCategorySelected: Bool {
        if case .search = selectedCategory.kind {
            return true
        }

        return false
    }

    var isShortcutCategorySelected: Bool {
        if case .shortcut = selectedCategory.kind {
            return true
        }

        return false
    }

    // ショートカット分類の一覧はビューの設定(shortcutVocabularyEntries)なので引数で受ける
    func entries(shortcutEntries: [String]) -> [String] {
        switch selectedCategory.kind {
        case .shortcut:
            return shortcutEntries
        case .existing:
            return KaomojiCatalog.existingEntries
        case .imported(let name):
            return KaomojiCatalog.entries(forImportedCategory: name)
        case .search:
            return []
        }
    }

    // 「全」では全部の読み(816 個)を出す。以前は先頭 120 個で切っていて、か行の途中から後ろの読みは「全」から
    // たどれず、切れている表示も無かった(ユーザ指摘)。一覧は遅延描画なので見えている分しか作らない
    var searchReadings: [String] {
        KaomojiCatalog.readings(prefix: selectedReadingPrefix)
    }

    var searchResults: [String] {
        guard let selectedReading,
            !selectedReading.isEmpty else {
            return []
        }

        return KaomojiCatalog.entries(forReading: selectedReading)
    }

    func selectCategory(_ category: KaomojiCategory) {
        selectedCategoryID = category.id

        if case .search = category.kind {
            return
        }

        selectedReadingPrefix = nil
        selectedReading = nil
    }

    // 修飾キーの空タップから開くとき用。ID だけ変え、検索の接頭・読みは触らない
    func selectCategory(id: String) {
        selectedCategoryID = id
    }

    func selectReadingPrefix(_ prefix: String?) {
        selectedReadingPrefix = prefix
        selectedReading = nil
    }

    func selectReading(_ reading: String?) {
        selectedReading = reading
    }

    func clearReading() {
        selectedReading = nil
    }
}
