import CoreGraphics
import Foundation

enum FlickDirection {
    case center
    case up
    case right
    case down
    case left
}

enum FlickGestureResolver {
    static func resolve(translation: CGSize, threshold: CGFloat = 18) -> FlickDirection {
        let dx = translation.width
        let dy = translation.height
        let distance = sqrt(dx * dx + dy * dy)

        guard distance >= threshold else {
            return .center
        }

        if abs(dx) > abs(dy) {
            return dx > 0 ? .right : .left
        }

        return dy > 0 ? .down : .up
    }
}

enum DiacriticMode {
    case none
    case dakuten
    case handakuten
    case smallKana
}

enum KanaModifierPlacementMode: String {
    case prefix
    case postfix
}

enum KanaPostModifierButtonState: Equatable {
    case smallKana
    case dakuten
    case handakuten
    case kaomoji
}

enum KeyboardInputMode {
    case kana
    case number
    case latin
    case emoji
}

enum KanaLayoutMode: String {
    case fiveByTwo
    case threeByThreePlusWa
}

enum LatinLayoutMode: String {
    case flick
    case qwerty
    case azerty
}

enum NumberLayoutMode: String {
    case calculette
    case telephone
}

enum FlickDirectionProfile: String {
    case apple
    case ecritu
}

struct FlickKanaSet: Identifiable, Hashable {
    let label: String
    let center: String
    let up: String
    let right: String
    let down: String
    let left: String
    let usesProfileDependentGuideOrder: Bool

    init(
        label: String,
        center: String,
        up: String,
        right: String,
        down: String,
        left: String,
        usesProfileDependentGuideOrder: Bool = true
    ) {
        self.label = label
        self.center = center
        self.up = up
        self.right = right
        self.down = down
        self.left = left
        self.usesProfileDependentGuideOrder = usesProfileDependentGuideOrder
    }

    var id: String { label }

    func output(for direction: FlickDirection) -> String {
        switch direction {
        case .center: return center
        case .up: return up
        case .right: return right
        case .down: return down
        case .left: return left
        }
    }

    func remapped(for profile: FlickDirectionProfile) -> FlickKanaSet {
        switch profile {
        case .ecritu:
            return self
        case .apple:
            guard usesProfileDependentGuideOrder else {
                return self
            }

            // Apple profile order is [left, up, right, down] while
            // ecritu profile order is [up, right, left, down].
            return FlickKanaSet(
                label: label,
                center: center,
                up: right,
                right: left,
                down: down,
                left: up,
                usesProfileDependentGuideOrder: usesProfileDependentGuideOrder
            )
        }
    }

    func orderedDirectionalGuideTexts(for profile: FlickDirectionProfile) -> [String] {
        let directionalOrder: [FlickDirection]

        if usesProfileDependentGuideOrder {
            switch profile {
            case .apple:
                directionalOrder = [.left, .up, .right, .down]
            case .ecritu:
                directionalOrder = [.up, .right, .left, .down]
            }
        } else {
            directionalOrder = [.left, .up, .right, .down]
        }

        var seen = Set<String>()

        return directionalOrder.compactMap { direction in
            let text = output(for: direction)

            guard !text.isEmpty,
                  text != center,
                  seen.insert(text).inserted else {
                return nil
            }

            return text
        }
    }
}

