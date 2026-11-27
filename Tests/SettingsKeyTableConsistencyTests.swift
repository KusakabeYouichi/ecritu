import XCTest

// コンテナーアプリの設定のキーは、次の表に別々に書かれている。片方だけ足すと、初期設定に戻しても
// 残る項目や、書き出しに出ない項目ができるので、集合が同じであることを見る(3830)。
//   1. ContentView.userSettingsKeys(設定画面の全項目)
//   2. builtInDefaultValues(組み込みの初期値)
//   3. conservativePresetValues / contemporaryPresetValues(初期設定は各々が完全な集合。3613)
//   4. ContentView の @AppStorage の宣言
//   5. settingsYAMLExportText(書き出し)
//   6. settingsSyncSignature(キーボードへ知らせる署名)
// アプリのモジュールはテストから import しない(モジュール名のアクセントが分解形で、ソースに書くと壊れやすい)。
// 4〜6 は実体が ContentView の中の式でもあるので、どれもソースの文字列から拾う
final class SettingsKeyTableConsistencyTests: XCTestCase {
    // 設定画面の項目ではない @AppStorage(初期設定に戻す対象にしない)
    private static let nonUserSettingStorageKeyNames: Set<String> = ["setupStepsDismissed"]

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOfFile: "\(ecrituRepositoryRoot)/\(relativePath)", encoding: .utf8)
    }

    private func captures(_ pattern: String, in text: String) throws -> [[String]] {
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
        }
    }

    private func slice(_ text: String, from start: String, to end: String) throws -> String {
        let startRange = try XCTUnwrap(text.range(of: start), "\(start) が見つからない")
        let endRange = try XCTUnwrap(text.range(of: end, range: startRange.upperBound..<text.endIndex), "\(end) が見つからない")
        return String(text[startRange.lowerBound..<endRange.lowerBound])
    }

    // SettingsKeys の定数名 → 保存キーの文字列
    private func settingsKeyValuesByName() throws -> [String: String] {
        let models = try source("App/SettingsModels.swift")
        let body = try slice(models, from: "enum SettingsKeys {", to: "\n}")
        var result: [String: String] = [:]
        for pair in try captures(#"static let (\w+) = "([^"]+)""#, in: body) {
            result[pair[0]] = pair[1]
        }
        return result
    }

    // @AppStorage の宣言: プロパティ名 → SettingsKeys の定数名
    private func storageKeyNamesByProperty() throws -> [String: String] {
        let contentView = try source("App/ContentView.swift")
        let pattern = #"@AppStorage\(\s*SettingsKeys\.(\w+)[^)]*\)(?:\s*//[^\n]*)*\s*(?:private\s+)?var\s+(\w+)"#
        var result: [String: String] = [:]
        for pair in try captures(pattern, in: contentView) {
            result[pair[1]] = pair[0]
        }
        return result
    }

    // 表(static let 名前 ... = [ 〜 ])に出てくる SettingsKeys の定数名
    private func keyNames(inTable name: String) throws -> [String] {
        let logoMenu = try source("App/ContentView+LogoMenu.swift")
        let body = try slice(logoMenu, from: "static let \(name):", to: "\n    ]")
        return try captures(#"SettingsKeys\.(\w+)"#, in: body).map { $0[0] }
    }

    private func userSettingsKeyNames() throws -> Set<String> {
        Set(try keyNames(inTable: "userSettingsKeys"))
    }

    func testPresetTablesCoverExactlyTheUserSettingsKeys() throws {
        let names = try keyNames(inTable: "userSettingsKeys")
        let nameSet = Set(names)
        XCTAssertGreaterThan(names.count, 80, "userSettingsKeys を拾えていない(書き方が変わった?)")
        XCTAssertEqual(names.count, nameSet.count, "userSettingsKeys に同じキーが 2 回ある")
        for table in ["builtInDefaultValues", "conservativePresetValues", "contemporaryPresetValues"] {
            let tableNames = try keyNames(inTable: table)
            XCTAssertEqual(tableNames.count, Set(tableNames).count, "\(table) に同じキーが 2 回ある(実行時に落ちる)")
            XCTAssertEqual(nameSet.subtracting(tableNames).sorted(), [], "\(table) に無いキー")
            XCTAssertEqual(Set(tableNames).subtracting(nameSet).sorted(), [], "\(table) にだけあるキー")
        }
    }

    // 保存キーの文字列そのものが重なっていないこと(定数名が違っても値が同じだと同じ保存先を奪い合う)
    func testSettingsKeyValuesAreUnique() throws {
        let valuesByName = try settingsKeyValuesByName()
        XCTAssertGreaterThan(valuesByName.count, 80)
        let namesByValue = Dictionary(grouping: valuesByName.keys, by: { valuesByName[$0] ?? "" })
        let duplicated = namesByValue.filter { $0.value.count > 1 }.map { $0.value.sorted().joined(separator: "=") }
        XCTAssertEqual(duplicated.sorted(), [])
    }

    func testAppStorageDeclarationsMatchUserSettingsKeys() throws {
        let declaredNames = Set(try storageKeyNamesByProperty().values)
            .subtracting(Self.nonUserSettingStorageKeyNames)
        XCTAssertGreaterThan(declaredNames.count, 80, "@AppStorage の宣言を拾えていない(書き方が変わった?)")
        let nameSet = try userSettingsKeyNames()
        XCTAssertEqual(nameSet.subtracting(declaredNames).sorted(), [], "@AppStorage の宣言が無いキー")
        XCTAssertEqual(declaredNames.subtracting(nameSet).sorted(), [], "userSettingsKeys に無い @AppStorage")
    }

    func testYAMLExportCoversExactlyTheUserSettingsKeys() throws {
        let contentView = try source("App/ContentView.swift")
        let body = try slice(contentView, from: "func settingsYAMLExportText()", to: "func copySettingsYAMLToPasteboard()")
        let exportedNames = try captures(#"SettingsKeys\.(\w+)"#, in: body).map { $0[0] }
        XCTAssertEqual(exportedNames.count, Set(exportedNames).count, "書き出しに同じキーが 2 回ある")
        let nameSet = try userSettingsKeyNames()
        XCTAssertEqual(nameSet.subtracting(exportedNames).sorted(), [], "書き出しに無いキー")
        XCTAssertEqual(Set(exportedNames).subtracting(nameSet).sorted(), [], "userSettingsKeys に無いキーを書き出している")
    }

    func testSyncSignatureCoversAllUserSettings() throws {
        let namesByProperty = try storageKeyNamesByProperty()
        let contentView = try source("App/ContentView.swift")
        let body = try slice(contentView, from: "private var settingsSyncSignature", to: ".joined(separator:")
        let identifiers = Set(try captures(#"([A-Za-z_]\w*)"#, in: body).map { $0[0] })
        let signedNames = Set(identifiers.compactMap { namesByProperty[$0] })
        let allNames = Set(namesByProperty.values).subtracting(Self.nonUserSettingStorageKeyNames)
        let missing = allNames.subtracting(signedNames)
        // 3837 で、入っていなかった 8 項目(放置で確定、未確定の方式、後置修飾の空タップなど)を足した
        XCTAssertEqual(missing.sorted(), [], "settingsSyncSignature に入っていない設定(変えてもキーボードへ知らせが飛ばない)")
    }

    // 関数 1 つぶんの本文(次の「\n    }\n」まで)
    private func functionBody(_ signature: String) throws -> String {
        try slice(try source("App/ContentView+LogoMenu.swift"), from: signature, to: "\n    }\n")
    }

    // 戦略的初期設定は、値を消すだけにせず 組み込みの値を全部明示して書く(3928)。値の無いキーが残ると、次の起動で
    // 「値が無い端末=前から使っている人」向けの処理が 書きかえ(X.8)・例外グループ・X.9 に別の値を書き、戦略的の値でなくなる
    func testStrategicPresetWritesEveryValueExplicitly() throws {
        let body = try functionBody("func applyStrategicDefaults()")
        XCTAssertTrue(body.contains("applyPreset(Self.builtInDefaultValues)"))
        XCTAssertFalse(body.contains("removeAllUserSettings()"), "値を消すだけにしない")
        XCTAssertTrue(body.contains("Self.recordBasePreset(.strategic)"))
    }

    // 値を全部消す処理(removeAllUserSettings)を呼ぶのは、消した直後に値を書く 2 つ(初期設定の適用、退避の復元)だけ
    func testOnlyPresetApplicationAndRestoreClearAllSettings() throws {
        let logoMenu = try source("App/ContentView+LogoMenu.swift")
        XCTAssertEqual(logoMenu.components(separatedBy: "removeAllUserSettings()").count - 1, 3, "定義 1 つと呼び出し 2 つ")
        XCTAssertTrue(try functionBody("func applyPreset(_ preset: [String: Any])").contains("removeAllUserSettings()"))
        XCTAssertTrue(try functionBody("func restoreStashedSettings() -> Bool").contains("removeAllUserSettings()"))
    }

    // 起動時に「値が無ければ、前から使っている人向けの値を書く」処理のキーは、3 つの初期設定の表すべてに値がある。
    // 初期設定を当てた直後に値が無いキーが残らないので、その処理が初期設定の値を書き換えない
    func testExistingInstallDefaultKeysHaveValuesInEveryPresetTable() throws {
        let logoMenu = try source("App/ContentView+LogoMenu.swift")
        let pattern = #"defaults\.object\(forKey: SettingsKeys\.(\w+)\) == nil else \{\s*return\s*\}"#
        let guardedKeys = Set(try captures(pattern, in: logoMenu).map { $0[0] })
        for expected in ["kanjiRewritePreference", "kanjiRewriteEverydayException", "lateStandardizedRewritePreference"] {
            XCTAssertTrue(guardedKeys.contains(expected), "\(expected) の処理が見つからない(書き方が変わったら、このテストの拾い方も直す)")
        }
        for table in ["builtInDefaultValues", "conservativePresetValues", "contemporaryPresetValues"] {
            let names = Set(try keyNames(inTable: table))
            XCTAssertEqual(guardedKeys.subtracting(names).sorted(), [], "\(table) に値が無いキー")
        }
    }

    // 戦略的初期設定を基準に退避した設定の復元は、値の無いキーに組み込みの値を明示して書く(3928)
    func testRestoreFillsMissingKeysOfStrategicStash() throws {
        let body = try functionBody("func restoreStashedSettings() -> Bool")
        let fill = try slice(body, from: "if stashedBase == .strategic {", to: "\n        }\n")
        XCTAssertTrue(fill.contains("for key in Self.userSettingsKeys where defaults.object(forKey: key) == nil"))
        XCTAssertTrue(fill.contains("Self.builtInDefaultValues[key]"))
    }
}
