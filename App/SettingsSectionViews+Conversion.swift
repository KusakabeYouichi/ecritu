import SwiftUI
import UIKit

// 変換・候補まわりの設定セクション(後置修飾/確定/候補ソース/連絡先/ユーザ辞書/部首/め接尾/絵文字顔文字/欧文/旧仮名/踊り字/表記変種)。SettingsSectionViews.swift(1737 行)から分割(2805 リファクタ)

struct KanaPostModifierFlickDakutenSettingsSection: View {
    @Binding var isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $isEnabled) {
                Text("後置修飾キーのフリックで濁点・半濁点")
                    .font(.headline)
            }

            Text("オンの場合、後置修飾キーを上フリックで濁点(゛)、右フリックで半濁点(゜)を強制します。オフにすると上/右フリックは中央タップと同じ扱いになり、誤って『つ→づ』になるのを抑止できます(2タップで『つ→っ→づ』は引き続き可能)。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct DelimiterAutoCommitCandidateSettingsSection: View {
    @Binding var selection: DelimiterAutoCommitCandidateOption

    var body: some View {
        SegmentedSettingsCard(
            title: "句読点入力時の自動確定候補",
            pickerTitle: "句読点入力時の自動確定候補",
            selection: $selection,
            options: Array(DelimiterAutoCommitCandidateOption.allCases),
            optionTitle: { $0.title },
            footnote: "未確定状態で句読点・記号を入力して自動確定するときに、どの候補を確定するかです。初期設定は『先頭の変換候補』です。『未変換かな』は入力したひらがなをそのまま確定します(確定キーは設定に関わらず常に未変換かなを確定します)。"
        )
    }
}

struct KanaKanjiCandidateSourceModeSettingsSection: View {
    @Binding var selection: KanaKanjiCandidateSourceModeOption

    var body: some View {
        SegmentedSettingsCard(
            title: "かな漢字候補モード",
            pickerTitle: "かな漢字候補モード",
            selection: $selection,
            options: Array(KanaKanjiCandidateSourceModeOption.allCases),
            optionTitle: { $0.title },
            footnote: "システム辞書候補の採用基準を切り替えます。surface(初期設定) / normalisé / les deux を選べます。"
        )
    }
}

struct ContactCandidateDisplaySettingsSection: View {
    @Binding var selection: ContactCandidateDisplayModeOption

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iOSの連絡先の姓、名、会社名")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(ContactCandidateDisplayModeOption.allCases) { option in
                    let isSelected = selection == option

                    Button {
                        selection = option
                    } label: {
                        HStack(alignment: .top, spacing: 9) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(option.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(
                                    isSelected
                                        ? Color.accentColor
                                        : AppTheme.subduedIcon
                                )
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    isSelected
                                        ? AppTheme.selectedControlBackground
                                        : AppTheme.controlBackground
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    isSelected
                                        ? AppTheme.emphasisBorder
                                        : AppTheme.subtleBorder,
                                    lineWidth: isSelected ? 1.2 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.cardInnerBackground)
            )
        }
        .settingsCardStyle()
    }
}

struct UserDictionaryCandidateDisplaySettingsSection: View {
    @Binding var selection: UserDictionaryCandidateDisplayModeOption

    var body: some View {
        SegmentedSettingsCard(
            title: "iOSのユーザ辞書の単語",
            pickerTitle: "iOSのユーザ辞書の単語",
            selection: $selection,
            options: Array(UserDictionaryCandidateDisplayModeOption.allCases),
            optionTitle: { $0.title },
            footnote: "iOSの[設定]-[一般]-[キーボード]-[ユーザ辞書]に登録された候補を使うかどうかを切り替えます。"
        )
    }
}

struct RadicalStrokeCountSettingsSection: View {
    // 共有 defaults に入る1本の文字列("140:4,162:3" 形式)。旧設定 modern/traditional も読める
    @Binding var rawValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("部首の画数の数え方")
                .font(.headline)

            Text("漢字1文字ピッカー(モード切替キーの下フリック)の部首一覧を並べる画数です。流儀が分かれる部首だけ個別に選べます(艸/辵/食 は単独では6画/7画/9画で、ここの数字はその部首として数えるときの画数です)。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(AppRadicalStrokeChoices.orderedRadicals, id: \.self) { radical in
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppRadicalStrokeChoices.name(forRadical: radical))
                        .font(.subheadline)
                    Picker(
                        AppRadicalStrokeChoices.name(forRadical: radical),
                        selection: strokeBinding(forRadical: radical)
                    ) {
                        ForEach(AppRadicalStrokeChoices.options(forRadical: radical)) { option in
                            Text(option.title).tag(option.strokes)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Text("字の一覧に挟む総画数は Unihan の値をそのまま表示するので、ここの選択では変わりません(部首名の横に『総画数は3画で計算』のように基準を示します)。部首以外の部分は康熙字典の数え方なので、新字体で画数が減った字は日本の辞典より1画多くなることがあります(海=10画、漢=14画)。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("初期設定はいずれも左端(Unihan と同じ数え方)です。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }

    private func strokeBinding(forRadical radical: Int) -> Binding<Int> {
        Binding(
            get: { AppRadicalStrokeChoices.strokes(forRadical: radical, in: rawValue) },
            set: { newValue in
                rawValue = AppRadicalStrokeChoices.updating(
                    rawValue,
                    radical: radical,
                    strokes: newValue
                )
            }
        )
    }
}

enum OrdinalMePreferenceOption: String, CaseIterable {
    case kanji
    case kana

    var title: String {
        switch self {
        case .kanji: return "目(漢字)が先"
        case .kana: return "め(ひらがな)が先"
        }
    }
}

struct MeSuffixCandidateSettingsSection: View {
    @Binding var ordinalKanjiPreferred: Bool
    @Binding var adjectiveKanjiEnabled: Bool

    private var ordinalSelection: Binding<OrdinalMePreferenceOption> {
        Binding(
            get: { ordinalKanjiPreferred ? .kanji : .kana },
            set: { ordinalKanjiPreferred = ($0 == .kanji) }
        )
    }

    var body: some View {
        SegmentedSettingsCard(
            title: "première、deuxième、troisième、…",
            pickerTitle: "順序の『め/目』",
            selection: ordinalSelection,
            options: Array(OrdinalMePreferenceOption.allCases),
            optionTitle: { $0.title },
            footnote: "助数詞の後に付いて順序を表す『〜目』(二日目/三番目/7回目 など)で、漢字の『目』とひらがなの『め』のどちらを先に出すかを選びます。初期設定は『目(漢字)が先』です。\n\n1973年の内閣告示第2号『送り仮名の付け方』の【通則4】の中に、助数詞の後に付いて順序を表す『二日目』、『三番目』などの言葉の例が挙げられ、『目』と漢字で書かれています。"
        )

        VStack(alignment: .leading, spacing: 10) {
            Text("un peu …")
                .font(.headline)

            Toggle("程度の『め』に漢字『目』の候補も出す", isOn: $adjectiveKanjiEnabled)
                .toggleStyle(.switch)

            Text("形容詞の語幹に付いて程度や傾向を表す『〜め』(多め/少なめ/固め など)で、漢字の『目』の候補(多目 など)も出します。その場合もひらがなの候補のほうが先です。オフにすると『目』の候補は出しません。初期設定はオフです。\n\n1973年の内閣告示第2号『送り仮名の付け方』の【付表の語1(送り仮名を付ける語に関するもの)】の中に、形容詞の語幹に付いて程度や傾向を表す場合の『多め』、『少なめ』という言葉の例があげられ、そこでは『め』とひらがなになっています。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct EmojiKaomojiCandidateSettingsSection: View {
    @Binding var enablesEmojiCandidates: Bool
    @Binding var enablesKaomojiCandidates: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("emojis & les émoticônes")
                .font(.headline)

            VStack(spacing: 10) {
                Toggle("emoji 😀", isOn: $enablesEmojiCandidates)
                Toggle("émoticône (^_^)", isOn: $enablesKaomojiCandidates)
            }
            .toggleStyle(.switch)

            Text("かな漢字変換の候補に絵文字/顔文字を含めるかを切り替えます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct LatinLexiconSettingsSection: View {
    @Binding var enablesEnglish: Bool
    @Binding var enablesFrench: Bool
    @Binding var enablesGerman: Bool
    @Binding var enablesItalian: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("欧文サジェスチョンの言語")
                .font(.headline)

            VStack(spacing: 10) {
                Toggle("français (フランス語・15,000語)", isOn: $enablesFrench)
                Toggle("italiano (イタリア語・15,000語)", isOn: $enablesItalian)
                Toggle("Deutsch (ドイツ語・60,000語)", isOn: $enablesGerman)
                Toggle("anglais (英語・15,000語)", isOn: $enablesEnglish)
            }
            .toggleStyle(.switch)

            Text("欧文入力中のサジェスチョンに、同梱の頻度順語彙を使うかを言語別に切り替えます。ドイツ語は複合語が多いため深く収録しています。追加語彙・学習した語は常に優先して表示されます。初期設定はすべてオフです。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct HistoricalKanaCandidatesSettingsSection: View {
    @Binding var isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("旧仮名遣い候補")
                .font(.headline)

            Toggle("旧仮名遣いの候補を含める", isOn: $isEnabled)
                .toggleStyle(.switch)

            Text("『かえる→変へる』のような歴史的仮名遣い(ゐ/ゑ/ヰ/ヱ を含む表記)を変換結果に含めるかを切り替えます。初期設定はオフ(現代仮名遣いのみ)です。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct IterationMarkCandidatesSettingsSection: View {
    @Binding var isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("仮名の踊り字候補")
                .font(.headline)

            Toggle("仮名の踊り字の候補を含める", isOn: $isEnabled)
                .toggleStyle(.switch)

            Text("かな踊り字(繰り返し記号 ゝ/ゞ/ヽ/ヾ。いゝ/こゝ/バナヽ 等)を含む表記を変換結果に含めるかを切り替えます。初期設定はオフです。※漢字の々(人々/時々 等)は常に有効です。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}

struct ScriptVariantModeSettingsSection: View {
    let title: String
    @Binding var selectionRawValue: String
    let footnote: String

    private var selection: Binding<ScriptVariantModeOption> {
        Binding(
            get: { ScriptVariantModeOption(rawValue: selectionRawValue) ?? .suppress },
            set: { selectionRawValue = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Picker(title, selection: selection) {
                ForEach(ScriptVariantModeOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text(footnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .settingsCardStyle()
    }
}
