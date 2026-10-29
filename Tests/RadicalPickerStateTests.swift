import XCTest

// 部首ピッカーの選択と一覧の組み立て規則(RadicalPickerState / RadicalPickerListing)。
// 期待値は段 5 設計の期待表から決めた具体値
@MainActor
final class RadicalPickerStateTests: XCTestCase {
    private func makeForm(_ form: String, radical: Int, strokes: Int, traditional: Int? = nil) -> RadicalForm {
        RadicalForm(
            form: form, radical: radical, strokes: strokes, strokesTraditional: traditional,
            name: form, categories: ["偏"]
        )
    }

    private func makeEntry(_ character: String, total: Int) -> KanjiRadicalFileIndex.Entry {
        KanjiRadicalFileIndex.Entry(
            character: character, residualStrokes: 0, kuten: "", readings: "", totalStrokes: total
        )
    }

    private func markerStrokes(_ items: [(id: String, kind: RadicalListItem)]) -> [Int] {
        items.compactMap {
            if case .strokeMarker(let strokes) = $0.kind { return strokes }
            return nil
        }
    }

    // MARK: 選択

    func testInitialSelectionIsHenWithoutForm() {
        let state = RadicalPickerState()
        XCTAssertEqual(state.selectedCategory, .hen)
        XCTAssertNil(state.selectedForm)
    }

    func testSelectCategoryClearsOpenForm() {
        let state = RadicalPickerState()
        state.selectForm(makeForm("氵", radical: 85, strokes: 3))
        state.selectCategory(.kanmuri)
        XCTAssertEqual(state.selectedCategory, .kanmuri)
        XCTAssertNil(state.selectedForm)
    }

    func testSelectFormAndClearFormKeepCategory() {
        let state = RadicalPickerState()
        state.selectCategory(.ashi)
        let form = makeForm("灬", radical: 86, strokes: 4)
        state.selectForm(form)
        XCTAssertEqual(state.selectedForm, form)
        XCTAssertEqual(state.selectedCategory, .ashi)
        state.clearForm()
        XCTAssertNil(state.selectedForm)
        XCTAssertEqual(state.selectedCategory, .ashi)
    }

    // MARK: 字の一覧

    func testCharacterListItemsInsertMarkerWhenTotalChangesAndSkipUnknown() {
        let entries = [
            makeEntry("a", total: 3), makeEntry("b", total: 3), makeEntry("c", total: 4),
            makeEntry("d", total: 0), makeEntry("e", total: 5)
        ]
        let items = RadicalPickerListing.characterListItems(entries: entries)
        XCTAssertEqual(
            items.map(\.id),
            ["total-3", "char-a", "char-b", "total-4", "char-c", "char-d", "total-5", "char-e"]
        )
    }

    func testCharacterListItemsForTwoUnknownThenKnownMarkAtFirstKnownOnly() {
        let entries = [makeEntry("a", total: 0), makeEntry("b", total: 0), makeEntry("c", total: 7)]
        let items = RadicalPickerListing.characterListItems(entries: entries)
        XCTAssertEqual(items.map(\.id), ["char-a", "char-b", "total-7", "char-c"])
    }

    func testCharacterListItemsForEmptyEntriesIsEmpty() {
        XCTAssertTrue(RadicalPickerListing.characterListItems(entries: []).isEmpty)
    }

    // MARK: 部首の一覧

    func testRadicalListItemsInsertMarkerWhenStrokesChange() {
        let f1 = makeForm("A", radical: 1, strokes: 2)
        let f2 = makeForm("B", radical: 2, strokes: 2)
        let f3 = makeForm("C", radical: 3, strokes: 3)
        let items = RadicalPickerListing.radicalListItems(forms: [f1, f2, f3], strokeChoices: RadicalStrokeChoices())
        XCTAssertEqual(items.map(\.id), ["marker-2", f1.id, f2.id, "marker-3", f3.id])
    }

    func testRadicalListItemsForRealCatalogStartWithMarkerAndAscendingUniqueStrokes() throws {
        KanjiRadicalCatalog.resourceDirectoryURLOverride = URL(
            fileURLWithPath: "\(ecrituRepositoryRoot)/references", isDirectory: true
        )
        defer { KanjiRadicalCatalog.resourceDirectoryURLOverride = nil }
        let choices = RadicalStrokeChoices()
        let forms = KanjiRadicalCatalog.forms(in: .hen, choices: choices)
        XCTAssertFalse(forms.isEmpty)
        let items = RadicalPickerListing.radicalListItems(forms: forms, strokeChoices: choices)
        let first = try XCTUnwrap(items.first)
        guard case .strokeMarker = first.kind else {
            return XCTFail("先頭が区切りではない: \(first.id)")
        }
        let strokes = markerStrokes(items)
        XCTAssertEqual(strokes, Array(Set(strokes)).sorted())
        XCTAssertEqual(items.count, forms.count + strokes.count)
    }

    func testRadicalListItemsMoveMarkerWithStrokeChoice() {
        // 艹(部首 140): 3 画/4 画の数え方が分かれる。並びはカタログが設定ごとに返す順(画数昇順)
        let kusa = makeForm("艹", radical: 140, strokes: 3, traditional: 4)
        let three = makeForm("X", radical: 200, strokes: 3)
        let four = makeForm("Y", radical: 201, strokes: 4)

        let asThree = RadicalPickerListing.radicalListItems(
            forms: [kusa, three, four], strokeChoices: RadicalStrokeChoices(strokesByRadical: [140: 3])
        )
        XCTAssertEqual(asThree.map(\.id), ["marker-3", kusa.id, three.id, "marker-4", four.id])

        let asFour = RadicalPickerListing.radicalListItems(
            forms: [three, kusa, four], strokeChoices: RadicalStrokeChoices(strokesByRadical: [140: 4])
        )
        XCTAssertEqual(asFour.map(\.id), ["marker-3", three.id, "marker-4", kusa.id, four.id])
    }
}
