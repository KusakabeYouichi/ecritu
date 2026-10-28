import XCTest

// 顔文字パネルの選択規則(KaomojiPanelState)。期待値は段 4 設計の期待表から決めた具体値
@MainActor
final class KaomojiPanelStateTests: XCTestCase {
    private let searchCategory = KaomojiCategory(kind: .search)
    private let existingCategory = KaomojiCategory(kind: .existing)

    // 読みの候補と、その読みの結果が空でないものを 1 つ取る(カタログの語彙が変わっても成り立つように)
    private func sampleReading() throws -> String {
        let reading = KaomojiCatalog.readings(prefix: nil).first { !KaomojiCatalog.entries(forReading: $0).isEmpty }
        return try XCTUnwrap(reading)
    }

    func testInitialSelectionIsExistingWithoutSearchState() {
        let state = KaomojiPanelState()
        XCTAssertEqual(state.selectedCategory.id, "existing")
        XCTAssertNil(state.selectedReadingPrefix)
        XCTAssertNil(state.selectedReading)
    }

    func testCategoriesStartWithExistingShortcutSearch() {
        let ids = KaomojiPanelState.categories.map(\.id)
        XCTAssertEqual(Array(ids.prefix(3)), ["existing", "shortcut", "search"])
    }

    func testCategoriesPutDisplayOrderedImportedFirstThenRemainingInImportedOrder() {
        let ids = KaomojiPanelState.categories.map(\.id)
        let importedSet = Set(KaomojiCatalog.importedCategoryOrder)
        let ordered = KaomojiCatalog.displayCategoryOrder.filter { importedSet.contains($0) }
        let remaining = KaomojiCatalog.importedCategoryOrder.filter { !ordered.contains($0) }
        XCTAssertEqual(Array(ids.dropFirst(3)), (ordered + remaining).map { "imported:\($0)" })
        XCTAssertEqual(Array(ids[3..<6]), ["imported:rire", "imported:kawaii", "imported:timide"])
    }

    func testCategoryIDsAreUnique() {
        let ids = KaomojiPanelState.categories.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testSelectingSearchKeepsPrefixAndReading() {
        let state = KaomojiPanelState()
        state.selectCategory(searchCategory)
        state.selectReadingPrefix("か")
        state.selectReading("かお")
        state.selectCategory(searchCategory)
        XCTAssertEqual(state.selectedCategory.id, "search")
        XCTAssertEqual(state.selectedReadingPrefix, "か")
        XCTAssertEqual(state.selectedReading, "かお")
    }

    func testSelectingNonSearchCategoryClearsPrefixAndReading() {
        let state = KaomojiPanelState()
        state.selectCategory(searchCategory)
        state.selectReadingPrefix("か")
        state.selectReading("かお")
        state.selectCategory(existingCategory)
        XCTAssertEqual(state.selectedCategory.id, "existing")
        XCTAssertNil(state.selectedReadingPrefix)
        XCTAssertNil(state.selectedReading)
    }

    func testSelectReadingPrefixSetsPrefixAndClearsReading() {
        let state = KaomojiPanelState()
        state.selectReading("かお")
        state.selectReadingPrefix("さ")
        XCTAssertEqual(state.selectedReadingPrefix, "さ")
        XCTAssertNil(state.selectedReading)
    }

    func testSelectCategoryByIDChangesOnlyTheID() {
        let state = KaomojiPanelState()
        state.selectReadingPrefix("か")
        state.selectReading("かお")
        state.selectCategory(id: "imported:rire")
        XCTAssertEqual(state.selectedCategory.id, "imported:rire")
        XCTAssertEqual(state.selectedReadingPrefix, "か")
        XCTAssertEqual(state.selectedReading, "かお")
    }

    func testUnknownIDFallsBackToExisting() {
        let state = KaomojiPanelState()
        state.selectCategory(id: "imported:inexistant")
        XCTAssertEqual(state.selectedCategory.id, "existing")
    }

    func testClearReadingKeepsPrefix() {
        let state = KaomojiPanelState()
        state.selectReadingPrefix("か")
        state.selectReading("かお")
        state.clearReading()
        XCTAssertEqual(state.selectedReadingPrefix, "か")
        XCTAssertNil(state.selectedReading)
    }

    func testEntriesForShortcutReturnsGivenArray() {
        let state = KaomojiPanelState()
        state.selectCategory(id: "shortcut")
        XCTAssertEqual(state.entries(shortcutEntries: ["(a)", "(b)"]), ["(a)", "(b)"])
    }

    func testEntriesForExistingComeFromCatalog() {
        let state = KaomojiPanelState()
        XCTAssertFalse(KaomojiCatalog.existingEntries.isEmpty)
        XCTAssertEqual(state.entries(shortcutEntries: ["(a)"]), KaomojiCatalog.existingEntries)
    }

    func testEntriesForImportedComeFromCatalog() {
        let state = KaomojiPanelState()
        state.selectCategory(id: "imported:rire")
        let expected = KaomojiCatalog.entries(forImportedCategory: "rire")
        XCTAssertFalse(expected.isEmpty)
        XCTAssertEqual(state.entries(shortcutEntries: ["(a)"]), expected)
    }

    func testEntriesForSearchAreEmpty() {
        let state = KaomojiPanelState()
        state.selectCategory(searchCategory)
        XCTAssertEqual(state.entries(shortcutEntries: ["(a)"]), [])
    }

    func testSearchResultsAreEmptyWithoutReading() {
        let state = KaomojiPanelState()
        XCTAssertEqual(state.searchResults, [])
        state.selectReading("")
        XCTAssertEqual(state.searchResults, [])
    }

    func testSearchResultsForReadingComeFromCatalog() throws {
        let reading = try sampleReading()
        let state = KaomojiPanelState()
        state.selectReading(reading)
        XCTAssertFalse(state.searchResults.isEmpty)
        XCTAssertEqual(state.searchResults, KaomojiCatalog.entries(forReading: reading))
    }

    func testSearchReadingsFollowPrefix() {
        let state = KaomojiPanelState()
        XCTAssertEqual(state.searchReadings, KaomojiCatalog.readings(prefix: nil))
        state.selectReadingPrefix("か")
        XCTAssertEqual(state.searchReadings, KaomojiCatalog.readings(prefix: "か"))
    }

    func testIsShortcutCategorySelectedOnlyForShortcut() {
        let state = KaomojiPanelState()
        XCTAssertFalse(state.isShortcutCategorySelected)
        state.selectCategory(id: "shortcut")
        XCTAssertTrue(state.isShortcutCategorySelected)
        state.selectCategory(searchCategory)
        XCTAssertFalse(state.isShortcutCategorySelected)
        XCTAssertTrue(state.isSearchCategorySelected)
    }
}
