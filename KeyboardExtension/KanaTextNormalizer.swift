import Foundation

enum KanaTextNormalizer {
    static func normalizedKanaCharacter(from text: String) -> Character? {
        guard text.count == 1 else {
            return nil
        }

        let source = text.precomposedStringWithCanonicalMapping
        let normalized = source.applyingTransform(.hiraganaToKatakana, reverse: true) ?? source

        guard normalized.count == 1,
              let character = normalized.first,
              isKanaCharacter(character) else {
            return nil
        }

        return character
    }

    static func normalizedReading(_ text: String) -> String {
        var normalized = ""

        for character in text {
            if let kanaCharacter = normalizedKanaCharacter(from: String(character)) {
                normalized.append(kanaCharacter)
            }
        }

        return normalized
    }

    private static func isKanaCharacter(_ character: Character) -> Bool {
        guard let scalar = String(character).unicodeScalars.first else {
            return false
        }

        if (0x3040...0x309F).contains(scalar.value) {
            return true
        }

        return scalar.value == 0x30FC
    }
}
