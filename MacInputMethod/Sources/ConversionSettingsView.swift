import EcrituConversion
import SwiftUI

// 設定画面の中身(X.1〜X.13)。見出し・選択肢・説明は iPhone のアプリ(App/SettingsSectionViews+Conversion.swift の
// 各カード)と同じ文。数字と日本語の間の空白だけ詰めた。変えるとすぐ ConversionSettingsModel が ConversionService へ渡す

struct ConversionSettingsView: View {
    @ObservedObject var model: ConversionSettingsModel

    var body: some View {
        Form {
            candidateSourceModeSection
            historicalKanaSection
            iterationMarkSection
            scriptVariantModeSection(
                title: "X.4 カタカナ強調表記の候補",
                selection: $model.settings.katakanaEmphasisMode,
                footnote: "辞書が収穫した『ウマイ/コレ/ばかリ』のような読みのカタカナ化表記の扱いです。抑制=候補に出さない(3つの初期設定とも)、リスト後方=候補の末尾に回す、同列に使う=通常の順位。パンやアンケートのような外来語のカタカナは対象外です。"
            )
            scriptVariantModeSection(
                title: "X.5 交ぜ書きの候補",
                selection: $model.settings.mixedScriptMode,
                footnote: "『まん延(蔓延)』『作ひん(作品)』のような、漢字の一部をかなに開いた交ぜ書き表記の扱いです。抑制=候補に出さない(3つの初期設定とも)、リスト後方=候補の末尾に回す、同列に使う=通常の順位。『子ども』など定着した表記は対象外です。"
            )
            scriptVariantSuppressionSection
            kanaSpellingSection
            kanjiRewriteSection
            lateStandardizedRewriteSection
            kaCounterVariantSection
            inflectionalKanaVariantSection
            meSuffixSection
            numeralStyleSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 360)
    }

    // MARK: - X.1〜X.5

    /// X.1 の選択肢の並びと表示名(iOS: App/SettingsModels.swift の KanaKanjiCandidateSourceModeOption)
    private static let candidateSourceModes: [(mode: KanaKanjiCandidateSourceMode, title: String)] = [
        (.normalise, "normalisé"), (.surface, "surface"), (.lesDeux, "les deux"),
    ]

    private var candidateSourceModeSection: some View {
        Section {
            Picker("かな漢字候補モード", selection: $model.settings.candidateSourceMode) {
                ForEach(Self.candidateSourceModes, id: \.mode) { option in
                    Text(option.title).tag(option.mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            SettingsSectionHeader(title: "X.1 かな漢字候補モード")
        } footer: {
            Footnote("システム辞書候補の採用基準を切り替えます。surface / normalisé / les deux を選べます。初期設定は3つとも surface です。")
        }
    }

    private var historicalKanaSection: some View {
        Section {
            Toggle("旧仮名遣いの候補を含める", isOn: $model.settings.historicalKanaAllowed)
                .toggleStyle(.switch)
        } header: {
            SettingsSectionHeader(title: "X.2 旧仮名遣い候補")
        } footer: {
            Footnote("『かえる→変へる』『なおさら→なほ更』のような歴史的仮名遣いの表記を変換結果に含めるかを切り替えます。人名と、都をどり のような固有名詞はオフでも出します。初期設定は3つともオフ(現代仮名遣いのみ)です。")
        }
    }

    private var iterationMarkSection: some View {
        Section {
            Toggle("仮名の踊り字の候補を含める", isOn: $model.settings.iterationMarkAllowed)
                .toggleStyle(.switch)
        } header: {
            SettingsSectionHeader(title: "X.3 仮名の踊り字候補")
        } footer: {
            Footnote("かな踊り字(繰り返し記号 ゝ/ゞ/ヽ/ヾ。いゝ/こゝ/バナヽ 等)を含む表記を変換結果に含めるかを切り替えます。初期設定は3つともオフです。追加語彙・学習語彙の語(祇園 さゝ木 等)は設定に関わらず出ます。※漢字の々(人々/時々 等)は常に有効です。")
        }
    }

    /// X.4・X.5 の選択肢の並びと表示名(iOS: App/SettingsModels.swift の ScriptVariantModeOption)
    private static let scriptVariantModes: [(mode: ScriptVariantCandidateMode, title: String)] = [
        (.suppress, "抑制"), (.demote, "リスト後方"), (.normal, "同列に使う"),
    ]

    private func scriptVariantModeSection(
        title: String,
        selection: Binding<ScriptVariantCandidateMode>,
        footnote: String
    ) -> some View {
        Section {
            Picker(title, selection: selection) {
                ForEach(Self.scriptVariantModes, id: \.mode) { option in
                    Text(option.title).tag(option.mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            SettingsSectionHeader(title: title)
        } footer: {
            Footnote(footnote)
        }
    }

    // MARK: - X.6・X.7

    private var scriptVariantSuppressionSection: some View {
        Section {
            Toggle("旧字体を抑制\n(氣持→気持、會社→会社)", isOn: membership(\.suppressedScriptVariants, .kyujitai))
            Toggle("異体字を抑制\n(飜訳→翻訳、每日→毎日)", isOn: membership(\.suppressedScriptVariants, .itaiji))
            Toggle("見分けにくい字形を抑制\n(嚙む→噛む、吞む→呑む、讚歌→讃歌)", isOn: membership(\.suppressedScriptVariants, .lookalike))
            Toggle("略字を抑制\n(仝じ→同じ、卆→卒)", isOn: membership(\.suppressedScriptVariants, .ryakuji))
            Toggle("紛らわしい別字を抑制\n(聯合→連合)", isOn: membership(\.suppressedScriptVariants, .confusable))
            Toggle("人名で生きている異体字も抑制\n(邊→辺、龍→竜、嶋→島)", isOn: membership(\.suppressedScriptVariants, .personNameVariant))
        } header: {
            SettingsSectionHeader(title: "X.6 旧字体・異体字の候補")
        } footer: {
            Footnote("同じ読みに現代の標準字体の候補があるときだけ、古い字体の候補を出さないようにします。標準字体の候補が無い語(和氣あず未、國場組、守禮門、魚香肉絲 など)はそのまま出ます。人名の姓・名(小野澤、千惠、眞子)は設定に関わらず常に出ます。追加語彙に登録した語も対象外です。[見分けにくい字形]は旧字体・異体字のうち候補欄で標準字体と見分けられない字で、旧字体や異体字を出す設定にしても、これをオンにしておけば選び間違いを防げます。最後の項目は初期設定は3つともオフで、辺/邊 のように人名表記として生きている字を残します。")
        }
        .toggleStyle(.switch)
    }

    /// X.7 の例として並べる語の数(超えたら「など」。iOS の KanaSpellingSettingsSection.exampleLimit と同じ)
    private static let kanaSpellingExampleLimit = 12

    /// 仲間ごとの例(KanaSpellingTable の各仲間の先頭から、同じ表記を除いて並べる。iOS と同じ作り方)
    private static let kanaSpellingExamples: [KanaSpellingCategory: String] = Dictionary(
        uniqueKeysWithValues: KanaSpellingCategory.allCases.map { category in
            var seen = Set<String>()
            let surfaces = (KanaSpellingTable.entries[category] ?? []).map(\.surface).filter { seen.insert($0).inserted }
            let shown = surfaces.prefix(kanaSpellingExampleLimit).joined(separator: "、")
            return (category, surfaces.count > kanaSpellingExampleLimit ? shown + " など" : shown)
        }
    )

    private var kanaSpellingSection: some View {
        Section {
            ForEach(KanaSpellingCategory.allCases, id: \.self) { category in
                Toggle(
                    "\(category.title)を抑制\n(\(Self.kanaSpellingExamples[category] ?? ""))",
                    isOn: membership(\.suppressedKanaSpellings, category)
                )
            }
        } header: {
            SettingsSectionHeader(title: "X.7 かなで書く言葉の候補")
        } footer: {
            Footnote("漢字で書けるけれど、今の文章ではかなで書くことが多い言葉です。オンにした仲間は漢字の候補を出さず、かなだけを出します。オフにした仲間も、かなを先頭にして漢字はその後ろに並べます。『所謂風邪』『して下さい』のような続きの中の漢字もかなにします(1字の語は 事件・為替・時計 などを巻き込まないよう、その語だけを打ったときに限ります)。追加語彙に登録した語と、学習した語は対象外です。現代的初期設定と戦略的初期設定は 副詞(漢字も残す) だけがオフで、ほかの5つはオンです。保守的初期設定では形式名詞と指示語・代名詞もオフです。")
        }
        .toggleStyle(.switch)
    }

    // MARK: - X.8・X.9

    /// X.8 の例に並べる書きかえ前の語(iOS の KanjiRewriteSettingsSection.exampleBefores と同じ)。表に無い語は落とす
    private static let kanjiRewriteExampleBefores = [
        "醗酵", "廻転", "衣裳", "暗誦", "編輯", "叡智", "蒸溜", "交叉", "奇蹟", "註釈", "根柢", "洗滌", "刺戟", "綜合", "抒情",
        "障碍", "稀少", "史蹟", "防禦", "颱風", "煽情", "弘報", "熔接", "蒐集", "古稀", "下剋上", "掩護", "恩誼", "遺蹟",
    ].filter { KanjiRewriteTable.afterByBefore[$0] != nil }

    private static func kanjiRewriteSubtitle(for option: KanjiRewritePreference) -> String {
        switch option {
        case .beforeOnly:
            return kanjiRewriteExampleBefores.joined(separator: "、") + " など"
        case .afterOnly:
            return kanjiRewriteExampleBefores.compactMap { KanjiRewriteTable.afterByBefore[$0] }.joined(separator: "、") + " など"
        case .bothBeforeFirst:
            return "両方を出し、本来の漢字を先に(醗酵 → 発酵)"
        case .bothAfterFirst:
            return "両方を出し、常用漢字を先に(発酵 → 醗酵)"
        }
    }

    private var kanjiRewriteSection: some View {
        Section {
            KanjiRewriteOptionList(selection: $model.settings.kanjiRewrite, subtitle: Self.kanjiRewriteSubtitle(for:))
            Footnote("表外字を同じ音の常用漢字に置き換えた書き方(1956年 国語審議会報告『同音の漢字による書きかえ』の\(KanjiRewriteTable.switchablePairs.count)語)の扱いを選びます。『醗酵前』『蒸溜所』のような、その語を含む語にも効きます。1字単位の書きかえ(廻→回、智→知 など)は人名・地名を巻き込むので対象外です。報告にある 智慧→知恵 も対象外です(智慧 は仏教の語でもあり、字を替えただけの組ではないため)。報告の後に常用漢字に加わった字の組(臆測⇄憶測、肝腎⇄肝心、研磨⇄研摩 など)は X.9 で選びます。追加語彙に登録した語と、学習した語は対象外です。現代的初期設定は[両方(本来の漢字を先に)]、戦略的初期設定は[本来の漢字だけ]、保守的初期設定は[両方(常用漢字を先に)]です。この設定ができる前から使っている端末は、以前から本来の漢字を先頭にしていた語(醗酵・日蝕・棲息)を変えないよう[両方(本来の漢字を先に)]にしてあります。")
            Toggle("日常語は常用漢字を先に(例外)", isOn: $model.settings.kanjiRewriteEverydayException)
                .toggleStyle(.switch)
            Footnote("了解・了承・回復・連想・制御 のように、日常では常用漢字側ばかりを使う語(\(KanjiRewritePreference.everydayAfterFirstPairs.sorted().joined(separator: "・")))は、上の設定が『本来の漢字だけ』や『本来の漢字を先に』でも、常用漢字を先に出し、本来の漢字は後ろに出します。オフにすると、これらの語も上の設定どおりになります。現代的初期設定と保守的初期設定はオン、戦略的初期設定はオフです。")
        } header: {
            SettingsSectionHeader(title: "X.8 常用漢字による書きかえ")
        }
    }

    /// X.9 の例に並べる書きかえ前の語(iOS の LateStandardizedRewriteSettingsSection.exampleBefores と同じ)。表に無い語は落とす
    private static let lateStandardizedExampleBefores = ["臆測", "肝腎", "研磨"].filter { before in
        KanjiRewriteTable.lateStandardizedPairs.contains { $0.before == before }
    }

    private static func lateStandardizedSubtitle(for option: KanjiRewritePreference) -> String {
        switch option {
        case .beforeOnly:
            return lateStandardizedExampleBefores.joined(separator: "、") + " など"
        case .afterOnly:
            return lateStandardizedExampleBefores.compactMap { before in
                KanjiRewriteTable.lateStandardizedPairs.first { $0.before == before }?.after
            }.joined(separator: "、") + " など"
        case .bothBeforeFirst:
            return "両方を出し、本来の漢字を先に(臆測 → 憶測)"
        case .bothAfterFirst:
            return "両方を出し、常用漢字を先に(憶測 → 臆測)"
        }
    }

    private var lateStandardizedRewriteSection: some View {
        Section {
            KanjiRewriteOptionList(selection: $model.settings.lateStandardizedRewrite, subtitle: Self.lateStandardizedSubtitle(for:))
        } header: {
            SettingsSectionHeader(title: "X.9 常用漢字による書きかえ(後に追加)")
        } footer: {
            Footnote("1956年の報告『同音の漢字による書きかえ』の語のうち、報告の後に本来の漢字が常用漢字表に加わった組(甚・磨・妄は1981年、闇・臆・潰・毀・窟・腎・汎は2010年。\(KanjiRewriteTable.lateStandardizedPairs.count)組)の扱いを選びます。臆測⇄憶測、肝腎⇄肝心、研磨⇄研摩 のような組です。今はどちらの字も常用漢字なので、その字を含む別の語(肝腎症候群、研磨材 など)は書きかえません。追加語彙に登録した語と、学習した語は対象外です。現代的初期設定は[両方(本来の漢字を先に)]、戦略的初期設定は[本来の漢字だけ]、保守的初期設定は[両方(常用漢字を先に)]です。この設定ができる前から使っている端末は、以前と同じく両方を出すよう[両方(本来の漢字を先に)]にしてあります。")
        }
    }

    // MARK: - X.10・X.11

    private var kaCounterVariantSection: some View {
        Section {
            ForEach(Array(model.settings.kaCounterVariants.order.enumerated()), id: \.element) { index, variant in
                kaCounterVariantRow(variant, index: index)
            }
        } header: {
            SettingsSectionHeader(title: "X.10 助数詞型suffixe / 数詞類別suffixe – ka", subtitle: "un endroit, deux endroits, …")
        } footer: {
            Footnote("数を数える言い方の『か』(1か所、数か月、何か国 など)を、どの表記で、どの順に出すかを決めます。行の右の上下のボタンで順序が変わり、スイッチを切った表記は候補に出しません。現代的初期設定と保守的初期設定は か・箇・ヶ・カ を出し、戦略的初期設定は か だけを出します。並びの初期値は か → 箇 → ヶ → カ → ヵ → 個 → ケ です。\n\n公用文では『か所・か月』または『箇所・箇月』と書くのが標準で、新聞は『か所・か月』です。ここで決めた順は変換候補の並びの初期状態で、いつも選ぶ表記は学習によってその上に出ます。")
        }
    }

    /// 1行: 表記・上下へ移すボタン・出す/出さないのスイッチ。並べ替えはボタンで行なう
    /// (Form の中では行のドラッグで並べ替えられないため)
    private func kaCounterVariantRow(_ variant: KaCounterVariant, index: Int) -> some View {
        let preference = model.settings.kaCounterVariants
        let isEnabled = preference.enabled.contains(variant)
        return HStack(spacing: 8) {
            Text(variant.title)
                .foregroundStyle(isEnabled ? .primary : .secondary)
            Spacer(minLength: 0)
            Button {
                moveKaCounterVariant(at: index, by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("上へ")
            Button {
                moveKaCounterVariant(at: index, by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == preference.order.count - 1)
            .help("下へ")
            Toggle("", isOn: membership(\.kaCounterVariants.enabled, variant))
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private func moveKaCounterVariant(at index: Int, by offset: Int) {
        var preference = model.settings.kaCounterVariants
        let target = index + offset
        guard preference.order.indices.contains(index), preference.order.indices.contains(target) else {
            return
        }
        preference.order.swapAt(index, target)
        model.settings.kaCounterVariants = preference
    }

    private var inflectionalKanaVariantSection: some View {
        Section {
            ForEach(InflectionalKanaVariantGroup.allCases) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                    Text(group.examples)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Picker(group.title, selection: inflectionalModeBinding(for: group)) {
                        ForEach(InflectionalKanaVariantMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        } header: {
            SettingsSectionHeader(title: "X.11 送り仮名の許容形 – orthographe", subtitle: "送り仮名の付け方(1973年内閣告示)の許容")
        } footer: {
            Footnote("送り仮名には本則のほかに許容された書き方があります(終わる⇄終る、取り扱う⇄取扱う、届け⇄届)。許容形を候補に出すか、出すならどちらを先にするかをグループごとに決めます。現代的初期設定は語幹の中だけ本則だけで、ほかの2つは本則を先に許容形も出します。戦略的初期設定はどのグループも本則だけ、保守的初期設定はどのグループも本則を先に許容形も出します。\n\n慣用で送り仮名を付けない語(受付、取引、割引、申込、日付、番組、入口、締切 など)と、名詞として送らない語(話、光、係、組、次、隣 など)はここでの対象外で、常にそのまま出ます。学習した表記と追加語彙に登録した表記は、この設定に関わらず候補に出ます。出荷時の追加語彙には 行なう がこの例外として登録してあります(不要なら追加語彙から削除してください)。")
        }
    }

    private func inflectionalModeBinding(for group: InflectionalKanaVariantGroup) -> Binding<InflectionalKanaVariantMode> {
        Binding(
            get: { model.settings.inflectionalKanaVariants.mode(for: group) },
            set: { model.settings.inflectionalKanaVariants.modes[group] = $0 }
        )
    }

    // MARK: - X.12・X.13

    /// X.12 序数化の2択(iOS: App/SettingsSectionViews+Conversion.swift の OrdinalMePreferenceOption)
    private enum OrdinalMeOrder: Hashable {
        case kanji
        case kana
    }

    private var ordinalMeOrder: Binding<OrdinalMeOrder> {
        Binding(
            get: { model.settings.ordinalMeKanjiPreferred ? .kanji : .kana },
            set: { model.settings.ordinalMeKanjiPreferred = ($0 == .kanji) }
        )
    }

    private var meSuffixSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                SubsectionTitle("序数化 – première、deuxième、troisième、…")
                Picker("順序の『め/目』", selection: ordinalMeOrder) {
                    Text("目(漢字)が先").tag(OrdinalMeOrder.kanji)
                    Text("め(ひらがな)が先").tag(OrdinalMeOrder.kana)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Footnote("助数詞の後に付いて順序を表す『〜目』(二日目/三番目/7回目 など)で、漢字の『目』とひらがなの『め』のどちらを先に出すかを選びます。戦略的初期設定は『目(漢字)が先』、現代的初期設定と保守的初期設定は『め(ひらがな)が先』です。\n\n1973年の内閣告示第2号『送り仮名の付け方』の【通則4】の中に、助数詞の後に付いて順序を表す『二日目』、『三番目』などの言葉の例が挙げられ、『目』と漢字で書かれています。")
            }
            VStack(alignment: .leading, spacing: 8) {
                SubsectionTitle("形式名詞化 – nom vide")
                Toggle("形式名詞の『目』にひらがな『め』の候補も出す", isOn: $model.settings.formalNounMeKanaEnabled)
                    .toggleStyle(.switch)
                Footnote("経験や境遇を表す形式名詞の『目』(ひどい目に遭う/痛い目を見る/こんな目に など)で、ひらがなの『め』の候補(ひどいめ など)も出します。その場合も漢字の候補のほうが先です。オフにすると『め』の候補は出しません(読みをそのままひらがなにした候補は出ます)。現代的初期設定と戦略的初期設定はオン、保守的初期設定はオフです。")
            }
            VStack(alignment: .leading, spacing: 8) {
                SubsectionTitle("形状名詞化 / 傾向派生 – un peu …")
                Toggle("程度の『め』に漢字『目』の候補も出す", isOn: $model.settings.adjectiveMeKanjiEnabled)
                    .toggleStyle(.switch)
                Footnote("形容詞の語幹に付いて程度や傾向を表す『〜め』(多め/少なめ/固め など)で、漢字の『目』の候補(多目 など)も出します。その場合もひらがなの候補のほうが先です。オフにすると『目』の候補は出しません。現代的初期設定と保守的初期設定はオン、戦略的初期設定はオフです。\n\n1973年の内閣告示第2号『送り仮名の付け方』の【付表の語1(送り仮名を付ける語に関するもの)】の中に、形容詞の語幹に付いて程度や傾向を表す場合の『多め』、『少なめ』という言葉の例があげられ、そこでは『め』とひらがなになっています。")
            }
        } header: {
            SettingsSectionHeader(title: "X.12 suffixe – me (め/目)", subtitle: "序数化 / 形式名詞化 / 形状名詞化・傾向派生")
        }
    }

    private var numeralStyleSection: some View {
        Section {
            Picker("数詞の表記", selection: $model.settings.numeralStyle) {
                ForEach(NumeralStylePreference.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            SettingsSectionHeader(title: "X.13 数詞の表記 – chiffres", subtitle: "2枚 / 二枚")
        } footer: {
            Footnote("にまい・ひとけた・だいにかい のように数と助数詞を続けて打ったとき、アラビア数字の表記(2枚・1桁・第2回)と漢数字の表記(二枚・一桁・第二回)をどの順で出すか、片方だけにするかを決めます。辞書に語としてある 一枚・三本 はこの設定に関わらず出ます。\n\n助数詞の『か』の字(1か所 / 1箇所 / 1ヶ所)は X.10 で選びます。現代的初期設定は アラビア数字が先、戦略的初期設定は アラビア数字だけ、保守的初期設定は 漢数字が先 です。")
        }
    }

    // MARK: - 部品

    /// 集合に要素が入っているかを切り替えるスイッチ用(X.6・X.7 の小分類、X.10 の表記)
    private func membership<Element: Hashable>(
        _ keyPath: WritableKeyPath<ConversionSettings, Set<Element>>,
        _ element: Element
    ) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: keyPath].contains(element) },
            set: { isOn in
                if isOn {
                    model.settings[keyPath: keyPath].insert(element)
                } else {
                    model.settings[keyPath: keyPath].remove(element)
                }
            }
        )
    }
}

/// 項目の見出し(番号つきの題と、あれば副題)
private struct SettingsSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// X.12 の中の小見出し
private struct SubsectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
    }
}

/// 項目の説明文
private struct Footnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 書きかえの4択(X.8 と X.9 で共通)。iOS と同じく、選択肢と出る語を全部見せる
private struct KanjiRewriteOptionList: View {
    @Binding var selection: KanjiRewritePreference
    let subtitle: (KanjiRewritePreference) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(KanjiRewritePreference.allCases) { option in
                Button {
                    selection = option
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: selection == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selection == option ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                            Text(subtitle(option))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
    }
}
