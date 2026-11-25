import XCTest

/// リポジトリー内の元の Info.plist(展開前の値)を読む検査(設計 B 7 章 P1〜P4)
final class InfoPlistTests: XCTestCase {
    private static let resourcesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources", isDirectory: true)

    private var plist: [String: Any] = [:]

    override func setUpWithError() throws {
        try super.setUpWithError()
        let data = try Data(contentsOf: Self.resourcesDirectory.appendingPathComponent("Info.plist"))
        plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private var modeDictionary: [String: Any] {
        plist["ComponentInputModeDict"] as? [String: Any] ?? [:]
    }

    private var modes: [String: [String: Any]] {
        modeDictionary["tsInputModeListKey"] as? [String: [String: Any]] ?? [:]
    }

    // P1
    func testControllerClassIsQualifiedByModuleName() {
        XCTAssertEqual(plist["InputMethodServerControllerClass"] as? String, "$(PRODUCT_MODULE_NAME).EcrituInputController")
    }

    // P2
    func testModeListHasJapaneseAndRomanInVisibleOrder() {
        XCTAssertEqual(Set(modes.keys), ["com.apple.inputmethod.Japanese", "com.apple.inputmethod.Roman"])
        XCTAssertEqual(
            modeDictionary["tsVisibleInputModeOrderedArrayKey"] as? [String],
            ["com.apple.inputmethod.Japanese", "com.apple.inputmethod.Roman"]
        )
    }

    // P3
    func testEachModeSourceIDStartsWithBundleIdentifier() {
        XCTAssertEqual(modes.count, 2)
        for (name, mode) in modes {
            let sourceID = mode["TISInputSourceID"] as? String ?? ""
            XCTAssertTrue(sourceID.hasPrefix("$(PRODUCT_BUNDLE_IDENTIFIER)"), "\(name): \(sourceID)")
        }
    }

    // P5
    func testRunsAsUIElementNotBackgroundOnly() {
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertNil(plist["LSBackgroundOnly"])
    }

    // P4
    func testIconKeysPointToFilesInResources() {
        var iconNames = [plist["tsInputMethodIconFileKey"] as? String ?? ""]
        for mode in modes.values {
            iconNames.append(mode["tsInputModeMenuIconFileKey"] as? String ?? "")
            // 純正の日本語入力と同じく、モードには通常の画像だけを指定する。
            // 選択中用(Alternate)やパレット用を指定すると、OS が文字のラベルでなく画像の組で描く
            XCTAssertNil(mode["tsInputModeAlternateMenuIconFileKey"])
            XCTAssertNil(mode["tsInputModePaletteIconFileKey"])
        }
        XCTAssertEqual(iconNames.count, 3)
        for name in iconNames {
            XCTAssertFalse(name.isEmpty)
            let path = Self.resourcesDirectory.appendingPathComponent(name).path
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), path)
        }
    }
}
