import Foundation

enum KeyboardLayerZIndex {
    // Keep the right-edge utility column above idle keys.
    static let rightEdgeUtilityColumn: Double = 200

    // Bring the actively touched row above neighboring rows.
    static let activeRow: Double = 300

    // Keep touched flick keys and their directional preview above utility keys.
    static let touchingKey: Double = 500

    // Keep expanded overlays (e.g. long-press candidates) above everything else.
    static let floatingOverlay: Double = 600
}
