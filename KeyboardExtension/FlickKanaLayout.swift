import Foundation

enum TemperatureUnitPreference: String {
    case celsius
    case fahrenheit

    var primarySymbol: String {
        switch self {
        case .celsius:
            return "℃"
        case .fahrenheit:
            return "℉"
        }
    }

    static func fromAppleTemperatureUnit(_ rawValue: String) -> TemperatureUnitPreference? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "celsius", "centigrade":
            return .celsius
        case "fahrenheit":
            return .fahrenheit
        default:
            return nil
        }
    }
}

enum FlickKanaLayout {
    static let latinShiftKeyToken = "__latin_shift__"
    // わキーは方向プロファイルごとに別定義(2026-08-31、ゐ/ゑ対応の案C)。
    // écritu方向: 母音方向の一貫性(い段=上/お段=下)を わ行にも通す — 上ゐ・下を。
    //   最頻出の ー(左)/ん(右) は1段のまま無傷。2段フリック: ー→下=ゑ、ん→下=〜。
    // Apple方向: 従来の1段割り当てを無傷で維持し、2段で を→下=ゐ、ー→下=ゑ を追加。
    // 〜 が écritu の1段目に存在しないため、汎用の remapped(for:) では導出できない。
    static let kanaWaSetEcritu = FlickKanaSet(
        label: "わ", center: "わ", up: "ゐ", right: "ん", down: "を", left: "ー",
        usesProfileDependentGuideOrder: false
    )
    static let kanaWaSetApple = FlickKanaSet(
        label: "わ", center: "わ", up: "ん", right: "ー", down: "〜", left: "を",
        usesProfileDependentGuideOrder: false
    )
    static let kanaYaSet = FlickKanaSet(label: "や", center: "や", up: "『", right: "ゆ", down: "よ", left: "』")

    // 2段フリック(横フリック後、指を離さず上下)の出力表。や の括弧に加え、
    // わ の旧仮名 ゐ/ゑ と、案Cで2段へ移した ー/〜 を担う(2026-08-31)。
    static func secondaryBracketFlickOutput(
        forPrimaryOutput primaryOutput: String,
        verticalDirection: FlickDirection
    ) -> String? {
        switch (primaryOutput, verticalDirection) {
        case ("を", .bas):
            return "ゐ"
        case ("ー", .bas):
            return "ゑ"
        case ("ん", .bas):
            return "〜"
        case ("『", .haut):
            return "("
        case ("『", .bas):
            return "「"
        case ("』", .haut):
            return ")"
        case ("』", .bas):
            return "」"
        default:
            return nil
        }
    }

    // FlickKeyView が2段フリックを起動してよい1段目出力か(左右フリック限定は呼び出し側)
    static func hasSecondaryFlickOutput(forPrimaryOutput primaryOutput: String) -> Bool {
        secondaryBracketFlickOutput(forPrimaryOutput: primaryOutput, verticalDirection: .haut) != nil
            || secondaryBracketFlickOutput(forPrimaryOutput: primaryOutput, verticalDirection: .bas) != nil
    }

    static let fiveByTwoRows: [[FlickKanaSet]] = [
        [
            FlickKanaSet(label: "あ", center: "あ", up: "い", right: "う", down: "お", left: "え"),
            FlickKanaSet(label: "か", center: "か", up: "き", right: "く", down: "こ", left: "け"),
            FlickKanaSet(label: "さ", center: "さ", up: "し", right: "す", down: "そ", left: "せ"),
            FlickKanaSet(label: "た", center: "た", up: "ち", right: "つ", down: "と", left: "て"),
            FlickKanaSet(label: "な", center: "な", up: "に", right: "ぬ", down: "の", left: "ね")
        ],
        [
            FlickKanaSet(label: "は", center: "は", up: "ひ", right: "ふ", down: "ほ", left: "へ"),
            FlickKanaSet(label: "ま", center: "ま", up: "み", right: "む", down: "も", left: "め"),
            kanaYaSet,
            FlickKanaSet(label: "ら", center: "ら", up: "り", right: "る", down: "ろ", left: "れ"),
            kanaWaSetEcritu
        ]
    ]

    static let threeByThreePlusWaRows: [[FlickKanaSet]] = [
        [
            FlickKanaSet(label: "あ", center: "あ", up: "い", right: "う", down: "お", left: "え"),
            FlickKanaSet(label: "か", center: "か", up: "き", right: "く", down: "こ", left: "け"),
            FlickKanaSet(label: "さ", center: "さ", up: "し", right: "す", down: "そ", left: "せ")
        ],
        [
            FlickKanaSet(label: "た", center: "た", up: "ち", right: "つ", down: "と", left: "て"),
            FlickKanaSet(label: "な", center: "な", up: "に", right: "ぬ", down: "の", left: "ね"),
            FlickKanaSet(label: "は", center: "は", up: "ひ", right: "ふ", down: "ほ", left: "へ")
        ],
        [
            FlickKanaSet(label: "ま", center: "ま", up: "み", right: "む", down: "も", left: "め"),
            kanaYaSet,
            FlickKanaSet(label: "ら", center: "ら", up: "り", right: "る", down: "ろ", left: "れ")
        ]
    ]

    static func rows(
        for mode: DiacriticMode,
        layoutMode: KanaLayoutMode = .fiveByTwo,
        profile: FlickDirectionProfile = .ecritu
    ) -> [[FlickKanaSet]] {
        var sourceRows: [[FlickKanaSet]]

        switch layoutMode {
        case .fiveByTwo:
            sourceRows = fiveByTwoRows
        case .threeByThreePlusWa:
            sourceRows = threeByThreePlusWaRows
        }

        // わ はプロファイル別定義(汎用置換の対象外)なのでここで差し替える
        sourceRows = sourceRows.map { row in
            row.map { $0.label == "わ" ? (profile == .apple ? kanaWaSetApple : kanaWaSetEcritu) : $0 }
        }

        guard let map = characterMap(for: mode) else {
            return sourceRows
        }

        return sourceRows.map { row in
            row.map { applyingMap(map, to: $0) }
        }
    }

    static func waSet(for mode: DiacriticMode, profile: FlickDirectionProfile = .ecritu) -> FlickKanaSet {
        let base = profile == .apple ? kanaWaSetApple : kanaWaSetEcritu
        guard let map = characterMap(for: mode) else {
            return base
        }

        return applyingMap(map, to: base)
    }

    static func numberRows(
        for profile: FlickDirectionProfile,
        layoutMode: NumberLayoutMode,
        temperatureUnit: TemperatureUnitPreference = .celsius,
        isShifted: Bool = false
    ) -> [[FlickKanaSet]] {
        let row123: [FlickKanaSet] = [
            numberSet(center: "1", left: "←", up: "↑", right: "→", down: "↓", profile: profile, preservesAppleDirectionalOrder: true),
            numberSet(center: "2", left: "¥", up: "$", right: "€", down: "₿", profile: profile),
            numberSet(
                center: "3",
                left: "%",
                up: "°",
                right: "#",
                down: temperatureUnit.primarySymbol,
                profile: profile
            )
        ]

        let row456: [FlickKanaSet] = [
            numberSet(center: "4", left: "○", up: "*", right: "~", down: "_", profile: profile),
            numberSet(center: "5", left: "+", up: "×", right: "÷", down: "±", profile: profile),
            numberSet(center: "6", left: "=", up: "<", right: ">", down: "≠", profile: profile)
        ]

        let row789: [FlickKanaSet] = [
            numberSet(center: "7", left: "「", up: "」", right: ":", down: ";", profile: profile),
            numberSet(center: "8", left: "〒", up: "々", right: "〆", down: "...", profile: profile),
            numberSet(center: "9", left: "|", up: "\\", right: "`", down: "^", profile: profile)
        ]

        let telephoneLeftParenKey = numberSet(
            center: "(",
            left: ")",
            up: "[",
            right: "]",
            down: "&",
            profile: profile
        )
        let zeroKey = numberSet(center: "0", left: "{", up: "}", right: "\"", down: "'", profile: profile)
        let telephoneDotKey = numberSet(center: ".", left: ",", up: "-", right: "/", down: "@", profile: profile)
        let calculetteDotKey = numberSet(center: ".", left: ",", up: "&", right: "/", down: "@", profile: profile)
        let calculetteRightBottomKey = numberSet(
            center: "-",
            left: "(",
            up: "[",
            right: ")",
            down: "]",
            profile: profile,
            preservesAppleDirectionalOrder: true
        )

        let rowBottomTelephone: [FlickKanaSet] = [
            telephoneLeftParenKey,
            zeroKey,
            telephoneDotKey
        ]

        let rowBottomCalculette: [FlickKanaSet] = [
            zeroKey,
            calculetteDotKey,
            calculetteRightBottomKey
        ]

        switch layoutMode {
        case .telephone:
            return [row123, row456, row789, rowBottomTelephone]
        case .calculette:
            return [row789, row456, row123, rowBottomCalculette]
        case .clavier:
            return clavierRows(for: profile, isShifted: isShifted)
        }
    }

    // clavier 配列(縦画面専用、AZERTY 風の 3 段 + システム行 = 計4段)。
    // 横画面では呼ばれない想定。呼び出し側で fallback して calculette を使う。
    private static func clavierRows(
        for profile: FlickDirectionProfile,
        isShifted: Bool
    ) -> [[FlickKanaSet]] {
        // 行1: 1-9, 0(shift時は漢数字 一二三四五六七八九〇)
        let row1Chars: [String] = isShifted
            ? ["一", "二", "三", "四", "五", "六", "七", "八", "九", "〇"]
            : ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

        let row2Chars: [String] = isShifted
            ? ["!", "?", "'", "\"", "~", "_", "^", "`", "\\", "|"]
            : ["#", "$", "%", "&", "*", "+", "=", ":", ";", ","]

        // 行3: AZERTY 行3 と同じ構造 = shift_left + 6 記号 + shift_right (8 スロット)。
        // 描画時に portrait モードでは shift_right を delete に差し替える
        // (`shouldReplacePortraitClavierRightShiftWithDelete`)。
        let row3Chars: [String] = isShifted
            ? ["<", ">", "『", "』", "「", "」"]
            : ["(", ")", "[", "]", "{", "}"]

        func numberOnlySet(_ ch: String) -> FlickKanaSet {
            numberSet(center: ch, left: "", up: "", right: "", down: "", profile: profile)
        }

        var row3: [FlickKanaSet] = [shiftKey(position: .left)]
        row3.append(contentsOf: row3Chars.map(numberOnlySet))
        row3.append(shiftKey(position: .right))

        return [
            row1Chars.map(numberOnlySet),
            row2Chars.map(numberOnlySet),
            row3
        ]
    }

    static func latinRows(for profile: FlickDirectionProfile, layoutMode: LatinLayoutMode) -> [[FlickKanaSet]] {
        switch layoutMode {
        case .flick:
            return latinFlickRows
        case .qwerty:
            return latinRows(from: qwertyRows, profile: profile, layoutMode: .qwerty)
        case .azerty:
            return latinRows(from: azertyRows, profile: profile, layoutMode: .azerty)
        }
    }

    static func latinLongPressCandidates(for center: String, layoutMode: LatinLayoutMode) -> [String] {
        guard layoutMode != .flick,
                center.count == 1,
                let first = center.lowercased().first else {
            return []
        }

        return latinLongPressCandidateMap[first] ?? []
    }

    private static let dakutenMap: [Character: Character] = [
        "か": "が", "き": "ぎ", "く": "ぐ", "け": "げ", "こ": "ご",
        "さ": "ざ", "し": "じ", "す": "ず", "せ": "ぜ", "そ": "ぞ",
        "た": "だ", "ち": "ぢ", "つ": "づ", "て": "で", "と": "ど",
        "は": "ば", "ひ": "び", "ふ": "ぶ", "へ": "べ", "ほ": "ぼ",
        "う": "ゔ"
    ]

    private static let handakutenMap: [Character: Character] = [
        "は": "ぱ", "ひ": "ぴ", "ふ": "ぷ", "へ": "ぺ", "ほ": "ぽ"
    ]

    private static let smallKanaMap: [Character: Character] = [
        "あ": "ぁ", "い": "ぃ", "う": "ぅ", "え": "ぇ", "お": "ぉ",
        "つ": "っ",
        "や": "ゃ", "ゆ": "ゅ", "よ": "ょ",
        "わ": "ゎ"
    ]

    private static let postModifierSmallPriorityCharacters: Set<Character> = [
        "あ", "い", "え", "お", "わ", "や", "ゆ", "よ", "う", "つ"
    ]

    private static let postModifierDakutenPriorityCharacters: Set<Character> = [
        "か", "き", "く", "け", "こ",
        "さ", "し", "す", "せ", "そ",
        "た", "ち", "て", "と",
        "は", "ひ", "ふ", "へ", "ほ"
    ]

    private static let postModifierDakutenSecondTapCharacters: Set<Character> = ["ぅ", "っ"]

    private static let postModifierHandakutenSecondTapCharacters: Set<Character> = [
        "ば", "び", "ぶ", "べ", "ぼ"
    ]

    private static let postModifierKaomojiCharacters: Set<Character> = [
        "な", "に", "ぬ", "ね", "の",
        "ま", "み", "む", "め", "も",
        "ん"
    ]

    private static let postModifierDakutenSecondTapMap: [Character: Character] = [
        "ぅ": "ゔ",
        "っ": "づ"
    ]

    private static let postModifierHandakutenSecondTapMap: [Character: Character] = [
        "ば": "ぱ",
        "び": "ぴ",
        "ぶ": "ぷ",
        "べ": "ぺ",
        "ぼ": "ぽ"
    ]

    private static let latinFlickRows: [[FlickKanaSet]] = [
        [
            FlickKanaSet(label: "@", center: "@", up: "#", right: "/", down: "&", left: "_"),
            FlickKanaSet(label: "a", center: "a", up: "b", right: "c", down: "", left: ""),
            FlickKanaSet(label: "d", center: "d", up: "e", right: "f", down: "", left: "")
        ],
        [
            FlickKanaSet(label: "g", center: "g", up: "h", right: "i", down: "", left: ""),
            FlickKanaSet(label: "j", center: "j", up: "k", right: "l", down: "", left: ""),
            FlickKanaSet(label: "m", center: "m", up: "n", right: "o", down: "", left: "")
        ],
        [
            FlickKanaSet(label: "p", center: "p", up: "q", right: "r", down: "", left: "s"),
            FlickKanaSet(label: "t", center: "t", up: "u", right: "v", down: "", left: ""),
            FlickKanaSet(label: "w", center: "w", up: "x", right: "y", down: "", left: "z")
        ],
        [
            shiftKey(position: .left),
            FlickKanaSet(label: "'", center: "'", up: "(", right: ")", down: "%", left: "\""),
            FlickKanaSet(label: ".", center: ".", up: "?", right: "!", down: "-", left: ",")
        ]
    ]

    private static let qwertyRows: [String] = [
        "qwertyuiop",
        "asdfghjkl",
        "zxcvbnm"
    ]

    private static let azertyRows: [String] = [
        "azertyuiop",
        "qsdfghjklm",
        "wxcvbn"
    ]

    private static let latinLongPressCandidateMap: [Character: [String]] = [
        "a": ["a", "à", "á", "â", "ä", "æ", "ã", "å", "ā", "ă", "ą"],
        "c": ["c", "ç", "ć", "č", "ĉ", "ċ"],
        "d": ["d", "ď", "đ"],
        "e": ["e", "è", "é", "ê", "ë", "ē", "ė", "ę", "ě"],
        "g": ["g", "ğ", "ĝ", "ģ", "ġ"],
        "h": ["h", "ĥ", "ħ"],
        "i": ["i", "ì", "í", "î", "ï", "ī", "į", "ı"],
        "j": ["j", "ĵ"],
        "k": ["k", "ķ"],
        "l": ["l", "ł", "ľ", "ĺ", "ļ"],
        "n": ["n", "ñ", "ń", "ň", "ņ"],
        "o": ["o", "ò", "ó", "ô", "ö", "œ", "ø", "ō", "õ", "ő"],
        "r": ["r", "ř", "ŕ", "ŗ"],
        "s": ["s", "ß", "ś", "š", "ŝ", "ş"],
        "t": ["t", "ť", "ţ", "ŧ"],
        "u": ["u", "ù", "ú", "û", "ü", "ū", "ů", "ű", "ų"],
        "w": ["w", "ŵ"],
        "y": ["y", "ÿ", "ý", "ŷ"],
        "z": ["z", "ž", "ź", "ż"]
    ]

    private static func latinRows(from sourceRows: [String], profile: FlickDirectionProfile, layoutMode: LatinLayoutMode) -> [[FlickKanaSet]] {
        sourceRows.enumerated().map { rowIndex, row in
            var sets = row.map { latinLetterSet(for: $0).remapped(for: profile) }

            if rowIndex == 2 {
                switch layoutMode {
                case .qwerty:
                    sets.insert(shiftKey(position: .left), at: 0)
                case .azerty:
                    sets.insert(shiftKey(position: .left), at: 0)
                    sets.append(shiftKey(position: .right))
                default:
                    break
                }
            }

            return sets
        }
    }

    private enum ShiftPosition {
        case left
        case right
    }

    private static func shiftKey(position: ShiftPosition) -> FlickKanaSet {
        let label: String = {
            switch position {
            case .left: return "__latin_shift_left__"
            case .right: return "__latin_shift_right__"
            }
        }()

        return FlickKanaSet(
            label: label,
            center: latinShiftKeyToken,
            up: "",
            right: "",
            down: "",
            left: ""
        )
    }

    private static func latinLetterSet(for letter: Character) -> FlickKanaSet {
        let center = String(letter)

        return FlickKanaSet(
            label: center,
            center: center,
            up: "",
            right: "",
            down: "",
            left: ""
        )
    }

    private static func numberSet(
        center: String,
        left: String,
        up: String,
        right: String,
        down: String,
        profile: FlickDirectionProfile,
        preservesAppleDirectionalOrder: Bool = false
    ) -> FlickKanaSet {
        let usesProfileDependentGuideOrder = !preservesAppleDirectionalOrder

        if profile == .apple || preservesAppleDirectionalOrder {
            return FlickKanaSet(
                label: center,
                center: center,
                up: up,
                right: right,
                down: down,
                left: left,
                usesProfileDependentGuideOrder: usesProfileDependentGuideOrder
            )
        }

        // ecritu mode order: tap, up, right, left, down
        return FlickKanaSet(
            label: center,
            center: center,
            up: left,
            right: up,
            down: down,
            left: right,
            usesProfileDependentGuideOrder: usesProfileDependentGuideOrder
        )
    }

    private static func characterMap(for mode: DiacriticMode) -> [Character: Character]? {
        switch mode {
        case .none:
            return nil
        case .dakuten:
            return dakutenMap
        case .handakuten:
            return handakutenMap
        case .smallKana:
            return smallKanaMap
        }
    }

    static func postfixModifiedCharacter(
        from character: Character,
        mode: DiacriticMode
    ) -> Character? {
        guard let map = characterMap(for: mode) else {
            return nil
        }

        if let replaced = map[character] {
            return replaced
        }

        // Katakana is committed in kana mode too; convert through hiragana map.
        let source = String(character)

        guard let hiragana = source.applyingTransform(.hiraganaToKatakana, reverse: true),
                hiragana.count == 1,
                let hiraganaCharacter = hiragana.first,
                let replacedHiragana = map[hiraganaCharacter] else {
            return nil
        }

        let replacedHiraganaText = String(replacedHiragana)
        let replacedKatakanaText = replacedHiraganaText.applyingTransform(
            .hiraganaToKatakana,
            reverse: false
        ) ?? replacedHiraganaText

        return replacedKatakanaText.first
    }

    static func postModifierButtonState(
        contextBeforeInput: String?
    ) -> KanaPostModifierButtonState {
        guard let contextBeforeInput,
                let lastCharacter = contextBeforeInput.last,
                let normalized = normalizedHiraganaKana(lastCharacter) else {
            return .kaomoji
        }

        if postModifierHandakutenSecondTapCharacters.contains(normalized) {
            return .handakuten
        }

        if postModifierDakutenSecondTapCharacters.contains(normalized) {
            return .dakuten
        }

        if postModifierSmallPriorityCharacters.contains(normalized) {
            return .smallKana
        }

        if postModifierDakutenPriorityCharacters.contains(normalized) {
            return .dakuten
        }

        if postModifierKaomojiCharacters.contains(normalized) {
            return .kaomoji
        }

        return .kaomoji
    }

    static func postfixModifiedCharacter(
        from character: Character,
        for buttonState: KanaPostModifierButtonState
    ) -> Character? {
        switch buttonState {
        case .smallKana:
            return postfixModifiedCharacter(from: character, mode: .smallKana)
        case .dakuten:
            if let mapped = transformedPostModifierSecondTapCharacter(
                from: character,
                map: postModifierDakutenSecondTapMap
            ) {
                return mapped
            }

            return postfixModifiedCharacter(from: character, mode: .dakuten)
        case .handakuten:
            if let mapped = transformedPostModifierSecondTapCharacter(
                from: character,
                map: postModifierHandakutenSecondTapMap
            ) {
                return mapped
            }

            return postfixModifiedCharacter(from: character, mode: .handakuten)
        case .kaomoji:
            return nil
        }
    }

    private static func transformedPostModifierSecondTapCharacter(
        from character: Character,
        map: [Character: Character]
    ) -> Character? {
        guard let normalized = normalizedHiraganaKana(character),
                let replacedHiragana = map[normalized] else {
            return nil
        }

        return convertedKanaCharacter(replacedHiragana, toMatch: character)
    }

    private static func normalizedHiraganaKana(_ character: Character) -> Character? {
        let source = String(character)
        let transformed = source.applyingTransform(.hiraganaToKatakana, reverse: true) ?? source

        guard transformed.count == 1,
                let normalized = transformed.first else {
            return nil
        }

        return normalized
    }

    private static func convertedKanaCharacter(
        _ hiragana: Character,
        toMatch original: Character
    ) -> Character? {
        guard isKatakana(original) else {
            return hiragana
        }

        let katakana = String(hiragana).applyingTransform(.hiraganaToKatakana, reverse: false) ?? String(hiragana)
        return katakana.first
    }

    private static func isKatakana(_ character: Character) -> Bool {
        guard let scalar = String(character).unicodeScalars.first else {
            return false
        }

        return (0x30A0...0x30FF).contains(scalar.value)
    }

    private static func applyingMap(_ map: [Character: Character], to set: FlickKanaSet) -> FlickKanaSet {
        FlickKanaSet(
            label: transform(set.label, with: map),
            center: transform(set.center, with: map),
            up: transform(set.up, with: map),
            right: transform(set.right, with: map),
            down: transform(set.down, with: map),
            left: transform(set.left, with: map)
        )
    }

    private static func transform(_ text: String, with map: [Character: Character]) -> String {
        guard text.count == 1,
                let character = text.first,
                let replaced = map[character] else {
            return text
        }

        return String(replaced)
    }
}
