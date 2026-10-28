import XCTest

// 書式化数値の規則(FormattedNumberFormatting の純関数と FormattedNumberState)。
// 期待値はビューにあった頃の挙動(段 3 設計の期待表)から決めた具体値
@MainActor
final class FormattedNumberStateTests: XCTestCase {
    // 共有 suite の formattedNumber.* を退避して、テスト後に元へ戻す(保存を伴うメソッドがあるため)
    private var savedSharedValues: [String: Any] = [:]

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: KeyboardViewController.SharedDefaultsKeys.appGroupID)
    }

    override func setUp() async throws {
        try await super.setUp()
        savedSharedValues = sharedDefaults?.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("formattedNumber.") } ?? [:]
    }

    override func tearDown() async throws {
        if let defaults = sharedDefaults {
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("formattedNumber.") {
                defaults.removeObject(forKey: key)
            }
            for (key, value) in savedSharedValues {
                defaults.set(value, forKey: key)
            }
        }
        try await super.tearDown()
    }

    // 何も設定していないときの書式設定(区切り=空白、小数点=".", 4 桁は例外、積=中点、リットル=l)
    private func defaultSettings() -> FormattedNumberFormatSettings {
        FormattedNumberFormatSettings(
            thousandsSeparator: " ",
            decimalSeparator: ".",
            groupsFourDigits: false,
            unitProductSeparator: "\u{00B7}",
            litreSymbol: "l",
            degreeStyle: .composed,
            dateStyle: .japanese
        )
    }

    private func makeState(category: FormattedNumberCategory, buffer: String = "") -> FormattedNumberState {
        let state = FormattedNumberState()
        state.selectedCategory = category
        state.buffer = buffer
        state.groupingEnabled = true
        state.unitSelection = [:]
        state.prefixSelection = [:]
        state.currencySymbolBefore = true
        state.unitSpacing = false
        state.dateFormatTemplate = "m月j日"
        return state
    }

    private func appending(_ tokens: [String], to buffer: String = "") -> String {
        tokens.reduce(buffer) {
            FormattedNumberFormatting.appendingToken($1, to: $0, maxDigits: FormattedNumberFormatting.maxDigits)
        }
    }

    // MARK: - 書式設定の読み込み

    func testLoadingFromEmptyDefaultsGivesInitialSettings() {
        let suiteName = "FormattedNumberStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)
        defer { defaults?.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(FormattedNumberFormatSettings.load(from: defaults), defaultSettings())
        XCTAssertEqual(FormattedNumberFormatSettings.load(from: nil), defaultSettings())
    }

    func testLoadingReadsEachSharedSetting() throws {
        let suiteName = "FormattedNumberStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("dot", forKey: KeyboardViewController.SharedDefaultsKeys.numberThousandsSeparator)
        defaults.set("comma", forKey: KeyboardViewController.SharedDefaultsKeys.numberDecimalSeparator)
        defaults.set(true, forKey: KeyboardViewController.SharedDefaultsKeys.numberGroupFourDigits)
        defaults.set("dotOperator", forKey: KeyboardViewController.SharedDefaultsKeys.numberUnitProductSeparator)
        defaults.set("script", forKey: KeyboardViewController.SharedDefaultsKeys.numberLitreSymbol)
        defaults.set("compat", forKey: DegreeSymbolStyle.sharedDefaultsKey)
        defaults.set("british", forKey: KeyboardViewController.SharedDefaultsKeys.dateFormatStyle)

        let settings = FormattedNumberFormatSettings.load(from: defaults)

        XCTAssertEqual(settings, FormattedNumberFormatSettings(
            thousandsSeparator: ".",
            decimalSeparator: ",",
            groupsFourDigits: true,
            unitProductSeparator: "\u{22C5}",
            litreSymbol: "\u{2113}",
            degreeStyle: .compat,
            dateStyle: .british
        ))
    }

    // MARK: - 数値の表示

    func testGroupsSevenDigitsWithSpace() {
        XCTAssertEqual(
            FormattedNumberFormatting.displayString(buffer: "1234567", groupingEnabled: true, settings: defaultSettings()),
            "1 234 567"
        )
    }

    func testFourDigitsAreNotGroupedUnlessSettingIsOn() {
        var settings = defaultSettings()
        XCTAssertEqual(
            FormattedNumberFormatting.displayString(buffer: "1234", groupingEnabled: true, settings: settings),
            "1234"
        )
        settings.groupsFourDigits = true
        XCTAssertEqual(
            FormattedNumberFormatting.displayString(buffer: "1234", groupingEnabled: true, settings: settings),
            "1 234"
        )
    }

    func testCommaSeparator() {
        var settings = defaultSettings()
        settings.thousandsSeparator = ","
        XCTAssertEqual(
            FormattedNumberFormatting.displayString(buffer: "12345", groupingEnabled: true, settings: settings),
            "12,345"
        )
    }

    func testNegativeDecimalWithContinentalSeparators() {
        var settings = defaultSettings()
        settings.thousandsSeparator = "."
        settings.decimalSeparator = ","
        settings.groupsFourDigits = true
        XCTAssertEqual(
            FormattedNumberFormatting.displayString(buffer: "-1234.5", groupingEnabled: true, settings: settings),
            "-1.234,5"
        )
    }

    func testGroupingOffKeepsDigitsAsIs() {
        XCTAssertEqual(
            FormattedNumberFormatting.displayString(buffer: "1234567", groupingEnabled: false, settings: defaultSettings()),
            "1234567"
        )
    }

    func testTrailingDecimalPointIsShown() {
        XCTAssertEqual(
            FormattedNumberFormatting.displayString(buffer: "12.", groupingEnabled: true, settings: defaultSettings()),
            "12."
        )
    }

    // MARK: - テンキーの入力

    func testDecimalPointIsAcceptedOnlyOnce() {
        XCTAssertEqual(appending(["1", ".", "5", "."]), "1.5")
    }

    func testDigitsStopAtEight() {
        XCTAssertEqual(appending(["1", "2", "3", "4", "5", "6", "7", "8", "9"]), "12345678")
    }

    func testSignAndDecimalPointDoNotCountAsDigits() {
        XCTAssertEqual(
            appending(["±", "1", "2", "3", "4", ".", "5", "6", "7", "8", "9"]),
            "-1234.5678"
        )
    }

    func testSignTogglesMinus() {
        XCTAssertEqual(appending(["±"], to: "5"), "-5")
        XCTAssertEqual(appending(["±", "±"], to: "5"), "5")
    }

    func testModelAppendAndDelete() {
        let state = makeState(category: .siBase)
        state.appendToken("4")
        state.appendToken("2")
        XCTAssertEqual(state.buffer, "42")
        state.deleteBackward()
        XCTAssertEqual(state.buffer, "4")
        state.deleteBackward()
        state.deleteBackward()
        XCTAssertEqual(state.buffer, "")
    }

    func testResetBufferEmptiesIt() {
        let state = makeState(category: .siBase, buffer: "123")
        state.resetBuffer()
        XCTAssertEqual(state.buffer, "")
    }

    // MARK: - 単位記号

    func testUnitProductSeparatorFollowsSetting() {
        var settings = defaultSettings()
        XCTAssertEqual(FormattedNumberFormatting.displayUnitSymbol("N\u{00B7}m", settings: settings), "N\u{00B7}m")
        settings.unitProductSeparator = "\u{22C5}"
        XCTAssertEqual(FormattedNumberFormatting.displayUnitSymbol("N\u{00B7}m", settings: settings), "N\u{22C5}m")
        settings.unitProductSeparator = " "
        XCTAssertEqual(FormattedNumberFormatting.displayUnitSymbol("N\u{00B7}m", settings: settings), "N m")
    }

    func testLitreSymbolFollowsSetting() {
        var settings = defaultSettings()
        XCTAssertEqual(FormattedNumberFormatting.displayUnitSymbol("L", settings: settings), "l")
        settings.litreSymbol = "L"
        XCTAssertEqual(FormattedNumberFormatting.displayUnitSymbol("L", settings: settings), "L")
        settings.litreSymbol = "\u{2113}"
        XCTAssertEqual(FormattedNumberFormatting.displayUnitSymbol("L", settings: settings), "\u{2113}")
    }

    func testDegreeSymbolFollowsSetting() {
        var settings = defaultSettings()
        XCTAssertEqual(FormattedNumberFormatting.displayUnitSymbol("\u{00B0}C", settings: settings), "\u{00B0}C")
        settings.degreeStyle = .compat
        XCTAssertEqual(FormattedNumberFormatting.displayUnitSymbol("\u{00B0}C", settings: settings), "\u{2103}")
    }

    func testPrefixIsPutBeforeSIUnit() {
        let state = makeState(category: .siBase)
        state.unitSelection = [FormattedNumberCategory.siBase.rawValue: "g"]
        state.prefixSelection = [FormattedNumberCategory.siBase.rawValue: "k"]
        XCTAssertEqual(state.currentUnitSymbol(settings: defaultSettings()), "kg")
    }

    func testCurrencyIgnoresPrefix() {
        let state = makeState(category: .currency)
        state.unitSelection = [FormattedNumberCategory.currency.rawValue: "$"]
        state.prefixSelection = [FormattedNumberCategory.currency.rawValue: "k"]
        XCTAssertEqual(state.currentUnitSymbol(settings: defaultSettings()), "$")
    }

    func testUnselectedOrUnknownUnitFallsBackToFirstOfCategory() {
        let state = makeState(category: .siBase)
        XCTAssertEqual(state.selectedBaseSymbol, "m")
        state.unitSelection = [FormattedNumberCategory.siBase.rawValue: "zz"]
        XCTAssertEqual(state.selectedBaseSymbol, "m")
    }

    // MARK: - 数値と単位の連結

    func testCurrencyBeforePutsMinusFirst() {
        XCTAssertEqual(
            FormattedNumberFormatting.join(number: "-100", unit: "¥", category: .currency, currencySymbolBefore: true, unitSpacing: false),
            "-¥100"
        )
        XCTAssertEqual(
            FormattedNumberFormatting.join(number: "100", unit: "¥", category: .currency, currencySymbolBefore: true, unitSpacing: false),
            "¥100"
        )
    }

    func testCurrencyAfterAppendsSymbol() {
        XCTAssertEqual(
            FormattedNumberFormatting.join(number: "-100", unit: "¥", category: .currency, currencySymbolBefore: false, unitSpacing: true),
            "-100¥"
        )
    }

    func testSIUnitSpacing() {
        XCTAssertEqual(
            FormattedNumberFormatting.join(number: "100", unit: "N", category: .siNamed, currencySymbolBefore: true, unitSpacing: true),
            "100 N"
        )
        XCTAssertEqual(
            FormattedNumberFormatting.join(number: "100", unit: "N", category: .siNamed, currencySymbolBefore: true, unitSpacing: false),
            "100N"
        )
        XCTAssertEqual(
            FormattedNumberFormatting.join(number: "100", unit: "", category: .siNamed, currencySymbolBefore: true, unitSpacing: true),
            "100"
        )
    }

    // MARK: - 確定とプレビュー

    func testCommitWithEmptyBufferInUnitCategoryGivesNothing() {
        let state = makeState(category: .siBase)
        XCTAssertNil(state.takeCommitText(settings: defaultSettings()))
        XCTAssertEqual(state.buffer, "")
    }

    func testCommitReturnsOutputAndEmptiesBuffer() {
        let state = makeState(category: .siBase, buffer: "12345")
        state.unitSelection = [FormattedNumberCategory.siBase.rawValue: "g"]
        state.prefixSelection = [FormattedNumberCategory.siBase.rawValue: "k"]
        state.unitSpacing = true
        XCTAssertEqual(state.takeCommitText(settings: defaultSettings()), "12 345 kg")
        XCTAssertEqual(state.buffer, "")
    }

    func testCommitInCurrencyFollowsPlacement() {
        let state = makeState(category: .currency, buffer: "-1500")
        state.unitSelection = [FormattedNumberCategory.currency.rawValue: "€"]
        state.currencySymbolBefore = false
        XCTAssertEqual(state.takeCommitText(settings: defaultSettings()), "-1500€")
    }

    func testCommitInCalendarWithEmptyBufferGivesDate() throws {
        let state = makeState(category: .calendar)
        state.date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 12)))
        state.dateFormatTemplate = "m月j日(jjj)"
        XCTAssertEqual(state.takeCommitText(settings: defaultSettings()), "3月4日(水)")
    }

    func testPreviewOfEmptyBufferShowsZeroWithUnit() {
        let state = makeState(category: .siBase)
        state.unitSelection = [FormattedNumberCategory.siBase.rawValue: "g"]
        XCTAssertEqual(state.previewString(settings: defaultSettings()), "0g")
    }

    // MARK: - カテゴリーと単位の選択(共有 suite へ保存する。値は tearDown で戻す)

    func testSelectingCurrencyFollowsCurrencyConventionAndIsSaved() {
        let state = makeState(category: .siBase)
        state.unitSelection = [FormattedNumberCategory.currency.rawValue: "€"]
        state.currencySymbolBefore = true

        XCTAssertFalse(state.selectCategory(.currency))

        XCTAssertEqual(state.selectedCategory, .currency)
        XCTAssertFalse(state.currencySymbolBefore)
        XCTAssertEqual(FormattedNumberPreferences.lastCategory(), .currency)
    }

    func testCrossingCalendarBoundaryIsReported() {
        let state = makeState(category: .siBase)
        XCTAssertTrue(state.selectCategory(.calendar))
        XCTAssertTrue(state.selectCategory(.currency))
        XCTAssertFalse(state.selectCategory(.siNamed))
    }

    func testSelectingCurrencyUnitFollowsItsConvention() {
        let state = makeState(category: .currency)
        state.selectUnit("€")
        XCTAssertFalse(state.currencySymbolBefore)
        XCTAssertEqual(FormattedNumberPreferences.loadUnitSelection()[FormattedNumberCategory.currency.rawValue], "€")
        state.selectUnit("$")
        XCTAssertTrue(state.currencySymbolBefore)
    }

    func testSelectingPrefixAndSpacingIsSaved() {
        let state = makeState(category: .siDerived)
        state.selectPrefix("M")
        XCTAssertEqual(state.selectedPrefix, "M")
        XCTAssertEqual(FormattedNumberPreferences.loadPrefixSelection()[FormattedNumberCategory.siDerived.rawValue], "M")

        state.unitSpacing = false
        state.toggleUnitSpacing()
        XCTAssertTrue(state.unitSpacing)
        XCTAssertTrue(FormattedNumberPreferences.lastUnitSpacing())
    }

    // MARK: - 日付

    func testTemplateOutsideStyleFallsBackToFirst() {
        XCTAssertEqual(FormattedNumberFormatting.effectiveDateTemplate("m月j日", style: .british), "j/m/aaaa")
        XCTAssertEqual(FormattedNumberFormatting.effectiveDateTemplate("mm月jj日", style: .japanese), "mm月jj日")
    }

    func testRenderedDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 12)))

        XCTAssertEqual(
            FormattedNumberFormatting.renderedDate(date, template: "aaaa年mm月jj日 jjjj", style: .japanese, calendar: calendar),
            "2026年03月04日 水曜日"
        )
        XCTAssertEqual(
            FormattedNumberFormatting.renderedDate(date, template: "j mmm aaaa", style: .british, calendar: calendar),
            "4 March 2026"
        )
    }
}
