import XCTest

// 初めて開いたときの 初期設定を選ぶ画面(3926)の決まりを、ソースの文字列で見る。アプリのモジュールはテストから import しない
// (SettingsKeyTableConsistencyTests と同じ方針)。画面の操作そのものはここでは確かめられない(実機で確認する)
final class InitialPresetChooserConsistencyTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        try String(contentsOfFile: "\(ecrituRepositoryRoot)/\(relativePath)", encoding: .utf8)
    }

    private func slice(_ text: String, from start: String, to end: String) throws -> String {
        let startRange = try XCTUnwrap(text.range(of: start), "\(start) が見つからない")
        let endRange = try XCTUnwrap(text.range(of: end, range: startRange.upperBound..<text.endIndex), "\(end) が見つからない")
        return String(text[startRange.lowerBound..<endRange.lowerBound])
    }

    // 関数 1 つぶんの本文(次の「\n    }\n」まで)
    private func functionBody(_ signature: String, in text: String) throws -> String {
        try slice(text, from: signature, to: "\n    }\n")
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func logoMenuSource() throws -> String {
        try source("App/ContentView+LogoMenu.swift")
    }

    // どの初期設定でも 連絡先の候補は「使わない」で始め、「使わないで始めた」印を立てる(審査ガイドライン 5.1.1)。
    // 戦略的も組み込みの値を明示して書く(値が無いと、次の起動で前から使っている人向けの値が書かれる)
    func testInitialChoiceValuesStartWithContactsOff() throws {
        let logoMenu = try logoMenuSource()
        let values = try functionBody("static func initialChoiceValues(for preset: SettingsBasePreset)", in: logoMenu)
        XCTAssertTrue(values.contains("values[SettingsKeys.contactCandidateDisplayMode] = ContactCandidateDisplayModeOption.off.rawValue"))
        XCTAssertTrue(values.contains("builtInDefaultValues.merging(presetValues(for: preset))"))

        let apply = try functionBody("func applyInitialChoice(_ preset: SettingsBasePreset)", in: logoMenu)
        XCTAssertTrue(apply.contains("applyPreset(Self.initialChoiceValues(for: preset))"))
        XCTAssertTrue(apply.contains("Self.recordBasePreset(preset, contactsStartedOff: true)"))
    }

    // 初めてのインストールの自動の適用も、選ぶ画面の完了も、当てる道は applyInitialChoice だけ。
    // メニュー用の適用や初期設定の表を直接当てない(保守的・現代的の表は連絡先を使う値)
    func testFreshInstallAndCompletionApplyOnlyThroughInitialChoice() throws {
        let logoMenu = try logoMenuSource()
        let fresh = try functionBody("func applyInitialPresetIfFreshInstall()", in: logoMenu)
        let complete = try functionBody("func completeInitialPresetChoice(_ preset: SettingsBasePreset)", in: logoMenu)
        XCTAssertTrue(fresh.contains("applyInitialChoice(.contemporary)"))
        XCTAssertTrue(complete.contains("applyInitialChoice(preset)"))
        for body in [fresh, complete] {
            for forbidden in ["applyPreset(", "recordBasePreset(", "PresetValues", "applyConservativePreset(", "applyStrategicDefaults("] {
                XCTAssertFalse(body.contains(forbidden), "applyInitialChoice 以外で当てない: \(forbidden)")
            }
        }
    }

    // 選ぶ画面を出す印を立てるのは、初めてのインストールと判定した後(既存の端末の guard の後、値を当てた後)の 1 か所だけ。
    // デバッグ版専用の「選ぶ画面を出す」は印を立てない(立てると、アプリを閉じても既存の端末に選ぶ画面が出続ける)
    func testPendingMarkIsSetOnlyAfterFreshInstallCheck() throws {
        let logoMenu = try logoMenuSource()
        let setTrue = "set(true, forKey: SettingsKeys.initialPresetChoicePending)"
        let fresh = try functionBody("func applyInitialPresetIfFreshInstall()", in: logoMenu)
        let guardRange = try XCTUnwrap(fresh.range(of: "guard !Self.isExistingInstall(defaults) else"))
        let applyRange = try XCTUnwrap(fresh.range(of: "applyInitialChoice(.contemporary)"))
        let setRange = try XCTUnwrap(fresh.range(of: setTrue))
        XCTAssertTrue(guardRange.upperBound < applyRange.lowerBound, "当てるのは既存の端末の判定の後")
        XCTAssertTrue(applyRange.upperBound < setRange.lowerBound, "印は値を当てた後で立てる")

        var total = 0
        for path in [
            "App/ContentView.swift", "App/ContentView+LogoMenu.swift", "App/ContentView+Bootstrap.swift",
            "App/InitialPresetChooserView.swift", "App/SettingsModels.swift",
        ] {
            total += occurrences(of: setTrue, in: try source(path))
        }
        XCTAssertEqual(total, 1, "印を立てる場所は 初めてのインストールの判定の後 の 1 つだけ")
    }

    // 選び終えたら印を下ろす。印が立っていないのに設定を書き換えない
    func testCompletionAppliesOnlyWhilePendingAndClearsTheMark() throws {
        let complete = try functionBody("func completeInitialPresetChoice(_ preset: SettingsBasePreset)", in: try logoMenuSource())
        let pendingGuard = try XCTUnwrap(complete.range(of: "defaults.bool(forKey: SettingsKeys.initialPresetChoicePending) else"))
        let applyRange = try XCTUnwrap(complete.range(of: "applyInitialChoice(preset)"))
        let clearRange = try XCTUnwrap(complete.range(of: "defaults.set(false, forKey: SettingsKeys.initialPresetChoicePending)"))
        XCTAssertTrue(pendingGuard.upperBound < applyRange.lowerBound, "印が立っているときだけ当てる")
        XCTAssertTrue(applyRange.upperBound < clearRange.lowerBound)
    }

    // 印は 初期設定を当てるときに消すキー(userSettingsKeys)に入れない
    func testPendingMarkIsNotAUserSettingKey() throws {
        let keys = try slice(try logoMenuSource(), from: "static let userSettingsKeys:", to: "\n    ]")
        XCTAssertFalse(keys.contains("initialPresetChoicePending"))
        XCTAssertFalse(keys.contains("initialPresetApplied"))
    }

    // 起動処理は、初めてのインストールの判定の後で、画面の状態を印に合わせる
    func testBootstrapSyncsChooserAfterFreshInstallCheck() throws {
        let bootstrap = try source("App/ContentView+Bootstrap.swift")
        let checkRange = try XCTUnwrap(bootstrap.range(of: "applyInitialPresetIfFreshInstall()"))
        let syncRange = try XCTUnwrap(bootstrap.range(of: "syncInitialPresetChooserWithPendingMark()"))
        XCTAssertTrue(checkRange.upperBound < syncRange.lowerBound)
    }

    // カードの文のうち 配列の 3 点(かな・ラテン文字・数字)が、初期設定の値と合っている。値を変えたら文も変える
    // (表記の文=かなで書く言葉・書きかえ は、ここでは突き合わせていない)
    func testCardLayoutTextsMatchPresetLayoutValues() throws {
        let logoMenu = try logoMenuSource()
        let chooser = try source("App/InitialPresetChooserView.swift")
        let points = try slice(chooser, from: "var chooserPoints: [String] {", to: "\n    }\n}")
        let tables: [(caseName: String, table: String)] = [
            ("contemporary", try slice(logoMenu, from: "static let contemporaryPresetValues:", to: "\n    ]")),
            ("conservative", try slice(logoMenu, from: "static let conservativePresetValues:", to: "\n    ]")),
            ("strategic", try slice(logoMenu, from: "static let builtInDefaultValues:", to: "\n    ]")),
        ]
        let displayNames: [String: String] = [
            "KanaLayoutOption.threeByThreePlusWa": "かなは 3×3+わ", "KanaLayoutOption.fiveByTwo": "かなは 5×2",
            "LatinLayoutOption.azerty": "ラテン文字は AZERTY", "LatinLayoutOption.flick": "ラテン文字も 3×3",
            "NumberLayoutOption.clavier": "数字は clavier", "NumberLayoutOption.telephone": "数字は téléphone",
            "NumberLayoutOption.calculette": "数字は calculette",
        ]
        for (index, entry) in tables.enumerated() {
            let next = index + 1 < tables.count ? "case .\(tables[index + 1].caseName):" : "\n        }"
            let cardText = try slice(points, from: "case .\(entry.caseName):", to: next)
            for key in ["kanaLayoutMode", "latinLayoutMode", "numberLayoutMode"] {
                let line = try XCTUnwrap(
                    entry.table.split(separator: "\n").first { $0.contains("SettingsKeys.\(key):") },
                    "\(entry.caseName) の \(key) が見つからない"
                )
                let option = try XCTUnwrap(displayNames.keys.first { line.contains($0 + ".rawValue") }, "知らない値: \(line)")
                XCTAssertTrue(cardText.contains(displayNames[option]!), "\(entry.caseName): カードに \(displayNames[option]!) が無い")
            }
        }
    }

    // カードの並びは、初期設定を 1 回ずつ全部並べる(初期設定が増減したら並びも直す)
    func testChooserOrderListsEveryPresetOnce() throws {
        let models = try source("App/SettingsModels.swift")
        let presetEnum = try slice(models, from: "enum SettingsBasePreset: String, CaseIterable {", to: "static let fallback")
        let caseNames = presetEnum.components(separatedBy: "\n    case ").dropFirst().compactMap { $0.split(separator: " ").first.map(String.init) }
        XCTAssertFalse(caseNames.isEmpty)
        let chooser = try source("App/InitialPresetChooserView.swift")
        let order = try slice(chooser, from: "static let presetOrder: [SettingsBasePreset] = [", to: "]")
        for name in caseNames {
            XCTAssertEqual(occurrences(of: ".\(name)", in: order), 1, "\(name) が並びに 1 回だけ出る")
        }
        XCTAssertEqual(occurrences(of: ".", in: order), caseNames.count)
    }
}
