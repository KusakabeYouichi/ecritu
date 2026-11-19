import Foundation

// 生成ファイル。tools/build_wine_script_table.py が references/vin.plist から作る。手で直さない(3846)
// 同じ読みにラテン文字とカタカナの両方の表記があるワインの語。ワインの語はカタカナの形を先にする(ユーザ指定 3846)
public enum WineScriptTable {
    // 読み → (ラテン文字の表記, カタカナの表記)。初めて使うときに下の文字列から作る
    public static let surfacesByReading: [String: (latin: [String], katakana: [String])] = {
        var result: [String: (latin: [String], katakana: [String])] = [:]
        for line in table.split(separator: "\n") {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count == 3 else { continue }
            result[String(columns[0])] = (columns[1].split(separator: "|").map(String.init), columns[2].split(separator: "|").map(String.init))
        }
        return result
    }()
    // 読みの長さの最大(前方一致を試す上限)
    public static let maxReadingCount: Int = surfacesByReading.keys.map(\.count).max() ?? 0

    static let table = """
    あい	Aÿ	アイ
    あいす	Ice	アイス
    あいすばいん	Eiswein	アイスバイン
    あいぜんべるく	Eisenberg	アイゼンベルク
    あいだに	Aidani	アイダニ
    あいだほ	Idaho	アイダホ
    あいびーえむぴー	IBMP	アイビーエムピー
    あいれん	Airén	アイレン
    あいんしゅとぅーふんぐ	Einstufung	アインシュトゥーフング
    あいんつぇるらーげ	Einzellage	アインツェルラーゲ
    あうぐすとゔぃるへるむふらいへるふぉんばーぼ	August Wilhelm Freiherr von Babo	アウグスト・ヴィルヘルム・フライヘル・フォン・バーボ
    あうすとらる	Austral	アウストラル
    あうすれーぜ	Auslese	アウスレーゼ
    あぎおるぎてぃこ	Agiorgitiko	アギオルギティコ
    あくあぱんな	ACQUA PANNA	アクアパンナ
    あくあゔぃっと	Aquavit	アクアヴィット
    あぐりかるちゃらるいんだすとりーえしかるとれーどあそしえーしょん	Agricultural Industry Ethical Trade Association	アグリカルチャラル・インダストリー・エシカル・トレード・アソシエーション
    あぐりきゅるちゅーるびおろじっく	Agriculture biologique	アグリキュルチュール・ビオロジック
    あこらーじゅ	Accolage	アコラージュ
    あこんかぐあ	Aconcagua	アコンカグア
    あこんかぐあゔぁれー	Aconcagua Valley	アコンカグア・ヴァレー
    あさーど	Asado	アサード
    あしでゅれ	Acidulée	アシデュレ
    あしゅっと	Asciutto	アシュット
    あしょー	à chaud	ア・ショー
    あしるてぃこ	Assyrtiko	アシルティコ
    あじあーご	Asiago	アジアーゴ
    あじみぬ	Aziminu	アジミヌ
    あじゃくしお	Ajaccio	アジャクシオ
    あじゃら	Adjara	アジャラ
    あすてぃ	Asti	アスティ
    あすとぅりあす	Asturias	アストゥリアス
    あすとりんじぇんと	Astringent	アストリンジェント
    あすぱらごびあんこでぃばっさーの	Asparago Bianco di Bassano	アスパラゴ・ビアンコ・ディ・バッサーノ
    あすまんずはうぜん	Assmannshausen	アスマンズハウゼン
    あすー	Aszú	アスー
    あせのふぐらーど	Asenovgrad	アセノフグラード
    あぜるりどー	Azay-le-Rideau	アゼ・ル・リドー
    あそーれす	Açores	アソーレス
    あぞーろぷろせっこ	Asolo Prosecco	アゾーロ・プロセッコ
    あたかま	Atacama	アタカマ
    あたらんぎくろーん	Ata Rangi clone	アタランギ・クローン
    あちぇとばるさみことらでぃつぃおなーれでぃもでな	Aceto Balsamico Tradizionale di Modena	アチェト・バルサミコ・トラディツィオナーレ・ディ・モデナ
    あっさむ	Assam	アッサム
    あっさんぶらーじゅ	Assemblage	アッサンブラージュ
    あっぱーはどそん	Upper Hudson	アッパー・ハドソン
    あっぷるたいざー	Appletiser®	アップルタイザー
    あっぺんつぇらー	Appenzeller®️|Appenzeller®	アッペンツェラー
    あっぺんつぇる	Appenzell	アッペンツェル
    あっぼっかーと	Abboccato	アッボッカート
    あてぃえでぃ	Attiédi	アティエディ
    あでれーどひるず	Adelaide Hills	アデレード・ヒルズ
    あとらすぴーく	Atlas Peak	アトラス・ピーク
    あとらんてぃか	Atlantica	アトランティカ
    あどゔぉかーと	Advocaat	アドヴォカート
    あにぇほ	Añejo	アニェホ
    あにぜ	Anisés	アニゼ
    あにゃーだ	Añada	アニャーダ
    あにょーどぽいやっく	Agneau de Pauillac	アニョー・ド・ポイヤック
    あばっきおあっろすこったでぃーと	Abbacchio allo Scottadito	アバッキオ・アッロ・スコッタディート
    あぱっしめんと	Appassimento	アパッシメント
    あぱらちあんはいかんとりー	Appalachian High Country	アパラチアン・ハイ・カントリー
    あぱらちあんふっとひるず	Appalachian Foothills	アパラチアン・フットヒルズ
    あふるーる	à fleurs	ア・フルール
    あふろわ	à froid	ア・フロワ
    あぶさん	Absinthe	アブサン
    あぶはじあ	Abkhazia	アブハジア
    あぶらはむぺろるど	Abraham Perold	アブラハム・ペロルド
    あぶりこ	Abricot	アブリコ
    あぶるっつぉ	Abruzzo	アブルッツォ
    あぷてぃぐらん	à Petits Grains	ア・プティ・グラン
    あぷてぃぐらんぶらん	à Petits Grains Blancs	ア・プティ・グラン・ブラン
    あぷてぃぐらんろーず	à Petits Grains Roses	ア・プティ・グラン・ローズ
    あべいどもん	Abbaye de Mont	アベイ・ド・モン
    あぺら	Apera	アペラ
    あぺらしおんどりじーぬこんとろーれ	Appellation d'Origine Contrôlée	アペラシオン・ドリジーヌ・コントローレ
    あぺりてぃふ	Apéritif	アペリティフ
    あぼな	Abona	アボナ
    あぼんだんす	Abondance	アボンダンス
    あまれっと	Amaretto	アマレット
    あまろーね	Amarone	アマローネ
    あまろーねでっらゔぁるぽりちぇっら	Amarone della Valpolicella	アマローネ・デッラ・ヴァルポリチェッラ
    あまーびれ	Amabile	アマービレ
    あまーろ	Amaro	アマーロ
    あみでおん	Amydeon	アミデオン
    あみんでお	Amyntaio|Amynteo	アミンデオ
    あみーにゅ	Amigne	アミーニュ
    あむとりっひぇぷりゅーふんぐすぬんまー	Amtliche Prüfungsnummer	アムトリッヒェ・プリューフングスヌンマー
    あめりかんゔぃてぃかるちゅらるえりあず	American Viticultural Areas	アメリカン・ヴィティカルチュラル・エリアズ
    あもんてぃりゃーど	Amontillado	アモンティリャード
    あらごねす	Aragonez	アラゴネス
    あらごん	Aragón	アラゴン
    あらぶるぎにょんぬ	à la Bourguignonne	ア・ラ・ブルギニョンヌ
    あらべさ	Alavesa	アラベサ
    あらぼるどれーず	à la Bordelaise	ア・ラ・ボルドレーズ
    あらもん	Aramon	アラモン
    ありあげ	Harriague	アリアゲ
    ありあにこ	Aglianico	アリアニコ
    ありあにこでるたぶるの	Aglianico del Taburno	アリアニコ・デル・タブルノ
    ありあにこでるゔるとぅれすぺりおーれ	Aglianico del Vulture Superiore	アリアニコ・デル・ヴルトゥレ・スペリオーレ
    ありかんて	Alicante	アリカンテ
    ありかんてぶーしぇ	Alicante Bouschet	アリカンテ・ブーシェ
    ありかんとぶすけ	Alicante Bouschet	アリカント・ブスケ
    ありかんとぶーしぇ	Alicante Bouschet	アリカント・ブーシェ
    ありごて	Aligoté	アリゴテ
    ありそすきゃにおん	Alisos Canyon	アリソス・キャニオン
    ありなるのあ	Arinarnoa	アリナルノア
    ありべす	Arribes	アリベス
    ありんと	Arinto	アリント
    あるがるゔぇ	Algarve	アルガルヴェ
    あるこほりっくふぁーめんていしょん	Alcoholic fermentation	アルコホリック・ファーメンテイション
    あるこーるあんどたばこたっくすあんどとれいどびゅーろー	Alcohol and Tobacco Tax and Trade Bureau	アルコール・アンド・タバコ・タックス・アンド・トレイド・ビューロー
    あるざす	Alsace	アルザス
    あるざすぐらんくりゅ	Alsace Grand Cru	アルザス・グラン・クリュ
    あるざすろれーぬ	Alsace-Lorraine	アルザス・ロレーヌ
    あるじゃんくらす	Argent classe	アルジャン・クラス
    あるじょえす	Arjões	アルジョエス
    あるぜんちん	Argentina	アルゼンチン
    あるたらんが	Alta Langa	アルタ・ランガ
    あるてす	Altesse	アルテス
    あるてみすどめーぬ	Artemis Domaine	アルテミス・ドメーヌ
    あるてんべるくどべるくはいむ	Altenberg de Bergheim	アルテンベルク・ド・ベルクハイム
    あるねいす	Arneis	アルネイス
    あるば	Alba	アルバ
    あるばりーにょ	Albariño	アルバリーニョ
    あるばろーら	Albarola	アルバローラ
    あるばんぬ	Arbanne	アルバンヌ
    あるばーな	Albana	アルバーナ
    あるぼわ	Arbois	アルボワ
    あるまにゃっく	Armagnac	アルマニャック
    あるまにゃっくてなれーず	Armagnac-Ténarèze	アルマニャック・テナレーズ
    あるものわーる	Harmo Noir	アルモ・ノワール
    あるんすぶるがー	Arnsburger	アルンスブルガー
    あるゔぁりーにょ	Alvarinho	アルヴァリーニョ
    あるーだ	Arruda	アルーダ
    あれくさんだーゔぁれー	Alexander Valley	アレクサンダー・ヴァレー
    あれった	Aletta	アレッタ
    あれんてじゃーの	Alentejano	アレンテジャーノ
    あれんてーじょ	Alentejo	アレンテージョ
    あれーりゃ	Alella	アレーリャ
    あろーすこるとん	Aloxe-Corton	アロース・コルトン
    あわてれゔぁれー	Awatere Valley	アワテレ・ヴァレー
    あんころーる	incolore	アンコロール
    あんごるな	Angolna	アンゴルナ
    あんじぇりゅす	Angélus	アンジェリュス
    あんじゅー	Anjou	アンジュー
    あんじゅーがめい	Anjou Gamay	アンジュー・ガメイ
    あんじゅーぶりさっく	Anjou Brissac	アンジュー・ブリサック
    あんじゅーむすー	Anjou Mousseux	アンジュー・ムスー
    あんじゅーゔぃらーじゅ	Anjou Villages	アンジュー・ヴィラージュ
    あんせすとらるめそっど	Ancestral Method	アンセストラル・メソッド
    あんそにか	Ansonica	アンソニカ
    あんだるしあ	Andalucía	アンダルシア
    あんだーそんゔぁれー	Anderson Valley	アンダーソン・ヴァレー
    あんとるこーと	Entrecôte	アントルコート
    あんとるどめーる	Entre-Deux-Mers	アントル・ド・メール
    あんとるどめーるおーぶのーじゅ	Entre-Deux-Mers Haut-Benauge	アントル・ド・メール・オー・ブノージュ
    あんとれーぐるふぇる	Entraygues-Le Fel	アントレーグ・ル・フェル
    あんどぅいえっと	Andouillette	アンドゥイエット
    あんばうげびーと	Anbaugebiet|Ambaugebiet	アンバウゲビート
    あんばー	Amber	アンバー
    あんぶていやーじゅ	Embouteillage	アンブテイヤージュ
    あんぶれ	Ambré	アンブレ
    あんぺりある	Impérial	アンペリアル
    あんぼね	Ambonnay	アンボネ
    あんぼわーず	Amboise	アンボワーズ
    あゔぁん	à vin	ア・ヴァン
    あゔぃーず	Avize	アヴィーズ
    あーおーせー	A.O.C.	アーオーセー
    あーさーふぃりっぷ	Arthur Phillip	アーサー・フィリップ
    あーぺーぬまー	A.P. Nr.|A.P.Nr.	アー・ペー・ヌマー
    あーる	Ahr	アール
    あーるがう	Aargau	アールガウ
    あーろーえれでとめぐいぇるれーしゅ	álló eredetmegjelölés	アーロー・エレデトメグイェルレーシュ
    あーろーふぇるどらいじいぇるぜーしゅ	álló földrajzi jelzés	アーロー・フェルドライジ・イェルゼーシュ
    いぇーがーまいすたー	Jägermeister	イェーガーマイスター
    いおど	Iode	イオド
    いおにあんあいらんず	Ionian Islands	イオニアン・アイランズ
    いじゃーきあらにしゃーるふぇへーる	Izsáki Arany Sárfehér	イジャーキ・アラニ・シャールフェヘール
    いすとりあ	Istria	イストリア
    いすらすかなりあす	Islas Canarias	イスラス・カナリアス
    いすらすばれあれす	Islas Baleares	イスラス・バレアレス
    いずぼるなべるば	Izborna berba	イズボルナ・ベルバ
    いずぼるなべるばぼびつぁ	Izborna berba bobica	イズボルナ・ベルバ・ボビツァ
    いたたゔぁれー	Itata Valley	イタタ・ヴァレー
    いたりあ	Italy|Italia	イタリア
    いでぃあさばる	Idiazábal	イディアサバル
    いめれてぃ	Imereti	イメレティ
    いらんしー	Irancy	イランシー
    いるれぎー	Irouléguy	イルレギー
    いんぐらんど	England	イングランド
    いんぐりっしゅわいん	English Wine	イングリッシュ・ワイン
    いんすてぃとぅーとなしおなるでびてぃびにくるとぅーら	Instituto Nacional de Vitivinicultura	インスティトゥート・ナシオナル・デ・ビティビニクルトゥーラ
    いんたーなしょなるぴののわーるせれぶれーしょん	International Pinot Noir Celebration	インターナショナル・ピノ・ノワール・セレブレーション
    いんたーなしょなるぶれんず	International Blends	インターナショナル・ブレンズ
    いんたーなしょなるぶれんど	International Blend	インターナショナル・ブレンド
    いんつぉりあ	Inzolia	インツォリア
    いんてぐれーてっどぷろだくしょんおゔわいん	Integrated Production of Wine	インテグレーテッド・プロダクション・オヴ・ワイン
    いんふろれっせんす	Inflorescence	インフロレッセンス
    いんらんどゔぁれーず	Inland Valleys	インランド・ヴァレーズ
    いんゔぉいす	Invoice	インヴォイス
    いーすとけろうなすろーぷす	East Kelowna Slopes	イースト・ケロウナ・スロープス
    いーすとさせっくす	East Sussex	イースト・サセックス
    うあすこゔぁれー	Huasco Valley	ウアスコ・ヴァレー
    うぃらめっとゔぁれー	Willamette Valley	ウィラメット・ヴァレー
    うぃーん	Wien|Vienna	ウィーン
    ういすきー	whisky	ウイスキー
    ういやーじゅ	Ouillage	ウイヤージュ
    ういゆどぺるどり	Œil de Perdrix	ウイユ・ド・ペルドリ
    うぇすたんおーすとらりあ	Western Australia	ウェスタン・オーストラリア
    うぇすたんけーぷ	Western Cape	ウェスタン・ケープ
    うぇすとかんとりーふぁーむはうすちぇだーちーず	West Country Farmhouse Cheddar Cheese	ウェスト・カントリー・ファームハウス・チェダー・チーズ
    うぇすとさせっくす	West Sussex	ウェスト・サセックス
    うぇりんとん	Wellington	ウェリントン
    うぇるしゅわいん	Welsh Wine	ウェルシュ・ワイン
    うぇるすとらくちゃーど	Well-structured	ウェルス・トラクチャード
    うぇーるず	Wales	ウェールズ
    うえすとそのまこーすと	West Sonoma Coast	ウエスト・ソノマ・コースト
    うぉっか	Vodka	ウォッカ
    うぉーかーべい	Walker Bay	ウォーカー・ベイ
    うぉーたーゔぇいる	Watervale	ウォーターヴェイル
    うぉーむ	Warm	ウォーム
    うすたー	Worcester	ウスター
    うてぃえるれけーな	Utiel-Requena	ウティエル・レケーナ
    うでど	udedo	ウデド
    うふあんむれっと	Oeuf en Meurette	ウフ・アン・ムレット
    うまーにゅぶらん	Humagne Blanc	ウマーニュ・ブラン
    うまーにゅるーじゅ	Humagne Rouge	ウマーニュ・ルージュ
    うむしゅたっと	Umstadt	ウムシュタット
    うるぐあい	Uruguay	ウルグアイ
    うるでりぇぶれ	Ull de Llebre	ウル・デ・リェブレ
    うんすとるーと	Unstrut	ウンストルート
    うんぶりあ	Umbria	ウンブリア
    うゔぁ	Uva	ウヴァ
    うーぞ	Ouzo	ウーゾ
    えあつぉいがーあぷふゅるんぐ	Erzeugerabfüllung	エアツォイガーアプフュルング
    えいえっくすあーるいち	AXR#1	エイエックスアールイチ
    えいおーしー	A.O.C.	エイオーシー
    えいおーぴー	A.O.P.	エイオーピー
    えいじんぐ	Aging|aging	エイジング
    えいゔいえい	A.V.A.	エイヴイエイ
    えくすとらあにぇほ	Extra Añejo	エクストラ・アニェホ
    えくすとらせこ	Extra Seco	エクストラ・セコ
    えくすとらせっく	Extra Sec|Extra sec	エクストラ・セック
    えくすとらせっこ	Extra Secco	エクストラ・セッコ
    えくすとらとろっけん	Extra Trocken	エクストラ・トロッケン
    えくすとらどらい	Extra Dry	エクストラ・ドライ
    えくすとらぶりゅっと	Extra Brut	エクストラ・ブリュット
    えくすとられせるば	Extra Reserva	エクストラ・レセルバ
    えくすれ	Öchsle|Oechsle	エクスレ
    えくすわーくす	Ex Works	エクス・ワークス
    えぐらぱーじゅ	Égrappage	エグラパージュ
    えぐりびかゔぇーる	Egri Bikavér	エグリ・ビカヴェール
    えげる	Eger	エゲル
    えしぇぞー	Echezeaux	エシェゾー
    えすおーとぅー	SO2|SO₂	エスオートゥー
    えすおーふぉー	SO4	エスオーフォー
    えすかべーちぇ	Escabeche	エスカベーチェ
    えすかるご	Escargots	エスカルゴ
    えすたらいひ	Österreich	エスタライヒ
    えすたん	Estaing	エスタン
    えすていとぼとるど	Estate Bottled	エステイト・ボトルド
    えすてるはーじーとるて	Esterhazy Torte	エステルハージー・トルテ
    えすとぅーふぁ	Estufa	エストゥーファ
    えすとえすとえすとでぃもんてふぃあすこーね	Est! Est!! Est!!! di Montefiascone	エスト・エスト・エスト・ディ・モンテフィアスコーネ
    えすとれまどぅーら	Extremadura	エストレマドゥーラ
    えすぷもーそ	Espumoso	エスプモーソ
    えすぷもーそでかりだー	Espumoso de Calidad	エスプモーソ・デ・カリダー
    えすぷりどこにゃっく	Esprit de Cognac	エスプリ・ド・コニャック
    えせっくす	Essex	エセックス
    えせんつぃあ	Eszencia	エセンツィア
    えでんゔぁれー	Eden Valley	エデン・ヴァレー
    えとな	Etna	エトナ
    えのこっかすえに	Oenococcus oeni	エノコッカス・エニ
    えのこーい	oenochooi	エノコーイ
    えのろじー	Enology	エノロジー
    えぴるす	Epirus	エピルス
    えぽわす	Epoisses	エポワス
    えみりあ	Emilia	エミリア
    えみりあろまーにゃ	Emilia Romagna	エミリア・ロマーニャ
    えみーるぷらんしょん	Émile Planchon	エミール・プランション
    えむえるえふ	M.L.F.	エムエルエフ
    えむさんいちぜろ	M310	エムサンイチゼロ
    えめんたーらー	Emmentaler|Emmentaler®️	エメンターラー
    えるいえろ	El Hierro	エル・イエロ
    えるき	Elqui	エルキ
    えるきゔぁれー	Elqui Valley	エルキ・ヴァレー
    えるぎん	Elgin	エルギン
    えるすてすげべっくす	Erstes Gewächs	エルステス・ゲベックス
    えるすてらーげ	Erste Lage	エルステ・ラーゲ
    えるで	Erde	エルデ
    えるどらど	El Dorado	エル・ドラド
    えるばあれあてぃこぱっしーと	Elba Aleatico Passito	エルバ・アレアティコ・パッシート
    えるばまっと	Erbamat	エルバマット
    えるばるーちぇ	Erbaluce	エルバルーチェ
    えるばるーちぇでぃかるーそ	Erbaluce di Caluso	エルバルーチェ・ディ・カルーソ
    えるぶりんぐ	Elbling	エルブリング
    えるぷえるとでさんたまりあ	El Puerto de Santa María	エル・プエルト・デ・サンタ・マリア
    えるべ	Elbe	エルベ
    えるみたーじゅ	Hermitage	エルミタージュ
    えるらこ	El Laco	エル・ラコ
    えるゔぁーじゅ	Élevage	エルヴァージュ
    えるゔぁーじゅあんとのー	Élevage en tonneau	エルヴァージュ・アン・トノー
    えんくるざーど	Encruzado	エンクルザード
    えんとれこるでぃじぇらす	Entre Cordilleras	エントレ・コルディジェラス
    えんぱなーだ	Empanada	エンパナーダ
    えんふぉるかど	Enforcado	エンフォルカド
    えんぽるだ	Empordà	エンポルダ
    えんらま	En Rama	エン・ラマ
    えーえるでぃーえいち	ALDH	エーエルディーエイチ
    えーおーしー	A.O.C.	エーオーシー
    えーでぃーえいち	ADH	エーディーエイチ
    えーでしゅ	Édes	エーデシュ
    えーでしゅさもろどに	Édes Szamorodni	エーデシュ・サモロドニ
    えーでるつびっかー	Edelzwicker	エーデルツビッカー
    おいげのーる	Eugenol	オイゲノール
    おいでぃうむ	Oïdium	オイディウム
    おおさか	Osaka	オオサカ
    おかながんふぉーるず	Okanagan Falls	オカナガン・フォールズ
    おかながんゔぁれー	Okanagan Valley	オカナガン・ヴァレー
    おじぇ	Oger	オジェ
    おすもーずあんゔぇるす	Osmose inverse	オスモーズ・アンヴェルス
    おそゆーす	Osoyoos	オソユース
    おそるのゔぁれー	Osorno Valley	オソルノ・ヴァレー
    おっそぶーこ	Osso Buco|Ossobuco	オッソブーコ|オッソ・ブーコ
    おっそーいらてぃ	Ossau-Iraty	オッソー・イラティ
    おっふぃーだ	Offida	オッフィーダ
    おらすりずりんぐ	Olasz Rizling	オラス・リズリング
    おらんじゅ	Orange	オランジュ
    おりじんてぃー	Origin Tea	オリジン・ティー
    おりふぁんつりゔぁー	Olifants River	オリファンツ・リヴァー
    おりゔぃえ	Olivier	オリヴィエ
    おるたろむあらっと	Oltalom alatt	オルタロム・アラット
    おるつたいる	Ortsteil	オルツタイル
    おるつばいん	Ortswein	オルツバイン
    おるとれぽぱゔぇーぜ	Oltrepò Pavese	オルトレポ・パヴェーゼ
    おるびれーる	Ollwiller	オルビレール
    おるへい	Orhei	オルヘイ
    おるめあすこ	Ormeasco	オルメアスコ
    おるれあん	Orléans	オルレアン
    おるれあんくれりー	Orléans-Cléry	オルレアン・クレリー
    おるゔぃえと	Orvieto	オルヴィエト
    おれごん	Oregon	オレゴン
    おれごんてぃるす	Oregon Tilth	オレゴン・ティルス
    おれっきえってこんちーめでぃらーぱ	Orecchiette con Cime di Rapa	オレッキエッテ・コン・チーメ・ディ・ラーパ
    おれんじぺこー	Orange Pekoe	オレンジ・ペコー
    おろろそ	Oloroso	オロロソ
    おわすりー	Oisly	オワスリー
    おわりー	Oiry	オワリー
    おんたりお	Ontario	オンタリオ
    おんだらびすり	Hondarrabi Zuri	オンダラビ・スリ
    おんだらびべるつぁ	Hondarrabi Beltza	オンダラビ・ベルツァ
    おー	Haut	オー
    おーあるまにゃっく	Haut-Armagnac	オー・アルマニャック
    おーくせいでゅれす	Auxey-Duresses	オークセイ・デュレス
    おーくらんど	Auckland	オークランド
    おーくゔぃる	Oakville	オークヴィル
    おーすとらりあ	Australia	オーストラリア
    おーすとらりあんぴののわーるちゃれんじ	Australian Pinot Noir Challenge	オーストラリアン・ピノ・ノワール・チャレンジ
    おーせろわ	Auxerrois	オーセロワ
    おーぞんぬ	Ausone	オーゾンヌ
    おーたん	Autan	オータン
    おーどゔぃー	Eaux-de-Vie|eau-de-vie	オー・ド・ヴィー
    おーどゔぃーどあぶりこ	Eaux-de-vie de Abricot	オー・ド・ヴィー・ド・アブリコ
    おーどゔぃーどくぇっちゅ	Eaux-de-vie de Quetsche	オー・ド・ヴィー・ド・クェッチュ
    おーどゔぃーどふらんぼわーず	Eaux-de-vie de Framboise	オー・ド・ヴィー・ド・フランボワーズ
    おーどゔぃーどふりゅい	Eaux-de-vie de Fruits	オー・ド・ヴィー・ド・フリュイ
    おーどゔぃーどぽわーるうぃりあむす	Eaux-de-vie de Poire Williams	オー・ド・ヴィー・ド・ポワール・ウィリアムス
    おーどゔぃーどみらべる	Eaux-de-vie de Mirabelle	オー・ド・ヴィー・ド・ミラベル
    おーどゔぃーどみるてぃーゆ	Eaux-de-vie de Myrtille	オー・ド・ヴィー・ド・ミルティーユ
    おーばいい	Haut-Bailly	オー・バイイ
    おーばたいえ	Haut-Batailley	オー・バタイエ
    おーばーじゅりべらる	Haut-Bages-Libéral	オー・バージュ・リベラル
    おーばーもーぜる	Obermosel	オーバーモーゼル
    おーぱすわん	Opus One	オーパス・ワン
    おーぶのーじゅ	Haut-Benauge	オー・ブノージュ
    おーぶりおん	Haut-Brion	オー・ブリオン
    おーべーぬ	Aubaine	オーベーヌ
    おーぽわとぅー	Haut-Poitou	オー・ポワトゥー
    おーまるこんそーる	Aux Malconsorts	オー・マルコンソール
    おーめどっく	Haut-Médoc	オー・メドック
    おーるこーとどーる	hors Côte d’Or	オール・コート・ドール
    おーるだーじゅ	Hors d'Âge	オール・ダージュ
    おーるどれせるば	Old Reserva	オールド・レセルバ
    おーるどゔぁいんぷろじぇくと	Old Vine Project	オールド・ヴァイン・プロジェクト
    おーゔぁーへっどゔぁいんとれーにんぐ	Overhead vine training	オーヴァーヘッド・ヴァイン・トレーニング
    かいざーしゅとぅーる	Kaiserstuhl	カイザーシュトゥール
    かいのわーる	Kai Noir	カイ・ノワール
    かいゆ	Caillou	カイユ
    かうてぃんゔぁれー	Cautin Valley	カウティン・ヴァレー
    かうら	Cowra	カウラ
    かうんてぃ	County	カウンティ
    かおーる	Cahors	カオール
    かくてる	cocktail	カクテル
    かこゔぉすとのゔぃの	Kakovostno vino	カコヴォストノ・ヴィノ
    かさぶらんか	Casablanca	カサブランカ
    かさぶらんかゔぁれー	Casablanca Valley	カサブランカ・ヴァレー
    かしす	Cassis	カシス
    かすたーにゃ	Castagna	カスターニャ
    かすて	Castets	カステ
    かすてぃよん	Castillon	カスティヨン
    かすてぃよんこーとどぼるどー	Castillon Côtes de Bordeaux	カスティヨン・コート・ド・ボルドー
    かすてぃーりゃいれおん	Castilla y León	カスティーリャ・イ・レオン
    かすてぃーりゃらまんちゃ	Castilla La Mancha|Castilla-La Mancha	カスティーリャ・ラ・マンチャ
    かすてっりでぃいえーじゔぇるでぃっきおりぜるゔぁ	Castelli di Jesi Verdicchio Riserva	カステッリ・ディ・イエージ・ヴェルディッキオ・リゼルヴァ
    かすてらぉん	Castelão	カステラォン
    かすてるでるもんて	Castel del Monte	カステル・デル・モンテ
    かすてるでるもんてねーろでぃとろいありぜるゔぁ	Castel del Monte Nero di Troia Riserva	カステル・デル・モンテ・ネーロ・ディ・トロイア・リゼルヴァ
    かすてるでるもんてぼんびーのねーろ	Castel del Monte Bombino Nero	カステル・デル・モンテ・ボンビーノ・ネーロ
    かすてるでるもんてろっそりぜるゔぁ	Castel del Monte Rosso Riserva	カステル・デル・モンテ・ロッソ・リゼルヴァ
    かすてるまーにょ	Castelmagno	カステルマーニョ
    かすなべるば	Kasna berba	カスナ・ベルバ
    かすれ	Cassoulet	カスレ
    かたまるか	Catamarca	カタマルカ
    かたらっと	Catarratto	カタラット
    かたるーにゃ	Cataluña	カタルーニャ
    かだすとろ	Cadastro	カダストロ
    かだるか	Kadarka	カダルカ
    かちゃぽある	Cachapoal	カチャポアル
    かちゃぽあるゔぁれー	Cachapoal Valley	カチャポアル・ヴァレー
    かちょかゔぁっろしらーの	Caciocavallo Silano	カチョカヴァッロ・シラーノ
    かっさーたしちりあーな	Cassata Siciliana	カッサータ・シチリアーナ
    かっぷこるす	Cap Corse	カップ・コルス
    かっぷどむーるらん	Cap de Mourlin	カップ・ド・ムールラン
    かっりかんて	Carricante	カッリカンテ
    かでぃやっく	Cadillac	カディヤック
    かでぃやっくこーとどぼるどー	Cadillac Côtes de Bordeaux	カディヤック・コート・ド・ボルドー
    かどーじゃっく	Cadaujac	カドージャック
    かないおーろ	Canaiolo	カナイオーロ
    かないおーろねーろ	Canaiolo Nero	カナイオーロ・ネーロ
    かなだ	Canada	カナダ
    かなでぃあんわいん	Canadian Wine	カナディアン・ワイン
    かぬれ	Canelé	カヌレ
    かねすとらーとぷりえーぜ	Canestrato Pugliese	カネストラート・プリエーゼ
    かねっり	Canelli	カネッリ
    かねろねす	Canelones	カネロネス
    かのん	Canon	カノン
    かのんふろんさっく	Canon Fronsac	カノン・フロンサック
    かのんらがふりえーる	Canon La Gaffelière	カノン・ラ・ガフリエール
    かば	Cava	カバ
    かばぐらんれせるば	Cava Gran Reserva	カバ・グラン・レセルバ
    かばでぐあるだ	Cava de Guarda	カバ・デ・グアルダ
    かばでぱらへかりふぃかーど	Cava de Paraje Calificado	カバ・デ・パラヘ・カリフィカード
    かばる	Kabar	カバル
    かばるです	Cabardès	カバルデス
    かばれせるば	Cava Reserva	カバ・レセルバ
    かびねっと	Kabinett	カビネット
    かふる	Cahul	カフル
    かぶられす	Cabrales	カブラレス
    かへてぃ	Kakheti	カヘティ
    かべるねそーゔぃによん	Cabernet Sauvignon	カベルネ・ソーヴィニヨン
    かべるねだんじゅ	Cabernet d'Anjou	カベルネ・ダンジュ
    かべるねふらん	Cabernet Franc	カベルネ・フラン
    かぽなーた	Caponata	カポナータ
    かまんさっく	Camensac	カマンサック
    かゆがれいく	Cayuga Lake	カユガ・レイク
    からどっく	Caladoc	カラドック
    からぶりあ	Calabria	カラブリア
    からぶれーぜ	Calabrese	カラブレーゼ
    からまん	Calamin	カラマン
    かりすとが	Calistoga	カリストガ
    かりつどるぷ	Calitzdorp	カリツドルプ
    かりにぇな	Cariñena	カリニェナ
    かりにゃん	Carignan	カリニャン
    かりふぃかーど	Calificado	カリフィカード
    かりふぉるにあ	California	カリフォルニア
    かるかそんぬ	Carcassonne	カルカソンヌ
    かるかゔぇろす	Carcavelos	カルカヴェロス
    かるでなひ	Kardenakhi	カルデナヒ
    かるといしゃ	Cartoixa	カルトイシャ
    かるとり	Kartli	カルトリ
    かるぬんとぅむ	Carnuntum	カルヌントゥム
    かるぷふぇんぶらう	Karpfen blau	カルプフェン・ブラウ
    かるぼにっくませれいしょん	Carbonic maceration	カルボニック・マセレイション
    かるぼにゅー	Carbonnieux	カルボニュー
    かるみにゃーの	Carmignano	カルミニャーノ
    かるみん	Carmine	カルミン
    かるめねーる	Carmenère	カルメネール
    かるゔぁどす	Calvados	カルヴァドス
    かるーそ	Caluso	カルーソ
    かろし	Kalosi	カロシ
    かろんせぎゅーる	Calon-Ségur	カロン・セギュール
    かんきな	Quinquina	カンキナ
    かんしー	Quincy	カンシー
    かんたぶりあ	Cantabria	カンタブリア
    かんたべりー	Canterbury	カンタベリー
    かんたる	Cantal	カンタル
    かんたろす	kantharos	カンタロス
    かんていろ	Canteiro	カンテイロ
    かんとなっくぶらうん	Cantenac Brown	カントナック・ブラウン
    かんとめるる	Cantemerle	カントメルル
    かんねっりーのでぃふらすかーてぃ	Cannellino di Frascati	カンネッリーノ・ディ・フラスカーティ
    かんのなう	Cannonau	カンノナウ
    かんのーり	Cannoli	カンノーリ
    かんぱり	Campari	カンパリ
    かんぱーにあ	Campania	カンパーニア
    かんぷたーる	Kamptal	カンプタール
    かんぽでぼるは	Campo de Borja	カンポ・デ・ボルハ
    かゔぁど	Cávado	カヴァド
    かーねろす	Carneros	カーネロス
    かーる	Curl	カール
    かーるどしょーむ	Quarts de Chaume	カール・ド・ショーム
    がいやっく	Gaillac	ガイヤック
    がってぃなーら	Gattinara	ガッティナーラ
    がまれ	Gamaret	ガマレ
    がむざ	Gamza	ガムザ
    がめい	Gamay	ガメイ
    がらのわーる	Garanoir	ガラノワール
    がりあーの	Galliano	ガリアーノ
    がりおっぽ	Gaglioppo	ガリオッポ
    がりしあ	Galicia	ガリシア
    がるがねが	Garganega	ガルガネガ
    がるだ	Garda	ガルダ
    がるなっちゃ	Garnacha	ガルナッチャ
    がるなっちゃてぃんた	Garnacha Tinta	ガルナッチャ・ティンタ
    がるなっちゃぶらんか	Garnacha Blanca	ガルナッチャ・ブランカ
    がるふあいらんず	Gulf Islands	ガルフ・アイランズ
    がーねっと	Garnet	ガーネット
    がーゔぃ	Gavi	ガーヴィ
    きあんてぃ	Chianti	キアンティ
    きあんてぃくらっしこ	Chianti Classico	キアンティ・クラッシコ
    きあゔぇんなすか	Chiavennasca	キアヴェンナスカ
    きゃっぷくらしっく	Cap Classique	キャップ・クラシック
    きゃめるゔぁれーゔぃんやーど	Camel Valley Vineyard	キャメル・ヴァレー・ヴィンヤード
    きゃんべるあーりー	Campbell Early	キャンベル・アーリー
    きゅらそー	Curaçao	キュラソー
    きゅりくす	kylix	キュリクス
    きゅゔぇ	Cuvée	キュヴェ
    きゅゔぇぷれすてぃーじゅ	Cuvée Prestige	キュヴェ・プレスティージュ
    きゅーば	Cuba	キューバ
    きりまんじゃろ	Kilimanjaro	キリマンジャロ
    きるしゅ	Kirsch	キルシュ
    きるひべるくどばーる	Kirchberg de Barr	キルヒベルク・ド・バール
    きるゔぁん	Kirwan	キルヴァン
    きんずまらうり	Kindzmarauli	キンズマラウリ
    きーまん	Keemun	キーマン
    きーる	Kir	キール
    ぎずぼーん	Gisborne	ギズボーン
    ぎぶすとんゔぁれー	Gibbston Valley	ギブストン・ヴァレー
    ぎむれっとぐらゔぇるずでぃすとりくと	Gimblett Gravels District	ギムレット・グラヴェルズ・ディストリクト
    ぎよ	Guyot	ギヨ
    ぎよさんぷる	Guyot Simple	ギヨ・サンプル
    ぎよどぅーぶる	Guyot Double	ギヨ・ドゥーブル
    ぎろー	Guiraud	ギロー
    くいーんずらんど	Queensland	クイーンズランド
    くしの	Xino	クシノ
    くしのまゔろ	Xinomavro	クシノマヴロ
    くすくすでぃぺーしぇ	Cous Cous di Pesce	クスクス・ディ・ペーシェ
    くばりてーつしゃうむばいん	Qualitätsschaumwein	クバリテーツシャウムバイン
    くばりてーつばいん	Qualitätswein	クバリテーツバイン
    くめう	Kumeu	クメウ
    くらいす	Currais	クライス
    くらいんかるー	Klein Karoo	クライン・カルー
    くらうんごーる	Crown gall	クラウン・ゴール
    くらしっく	Classic	クラシック
    くらしゅきてらん	Kraški Teran	クラシュキ・テラン
    くらす	Kras	クラス
    くらすまん	classement	クラスマン
    くらっしゅ	Crush	クラッシュ
    くらまん	Cramant	クラマン
    くられて	Clarete	クラレテ
    くらゔらん	Clavelin	クラヴラン
    くりあんさ	Crianza	クリアンサ
    くりおえくすとらくしょん	Cryo-extraction	クリオ・エクストラクション
    くりおじゃ	Criolla	クリオジャ
    くりおじゃぐらんで	Criolla Grande	クリオジャ・グランデ
    くりおじゃちか	Criolla Chica	クリオジャ・チカ
    くりおばたーるもんらっしぇ	Criots-Bâtard-Montrachet	クリオ・バタール・モンラッシェ
    くりおーじゃちか	Criolla Chica	クリオージャ・チカ
    くりこゔぁ	Cricova	クリコヴァ
    くりこゔぁれー	Curicó Valley	クリコ・ヴァレー
    くりしゃな	Crişana	クリシャナ
    くりすたるがいざー	Crystal Geyser	クリスタル・ガイザー
    くりまんす	Climens	クリマンス
    くりみさ	krimisa	クリミサ
    くりゅ	Crus|Cru	クリュ
    くりゅでゅぼーじょれ	Crus du Beaujolais	クリュ・デュ・ボージョレ
    くりゅーる	Coulure	クリュール
    くりーひぇるる	Kriecherl	クリーヒェルル
    くりーむ	Cream	クリーム
    くるら	Kouloura	クルラ
    くれあゔぁれー	Clare Valley	クレア・ヴァレー
    くれすたるぜぃう	Cules târziu	クレス・タルゼィウ
    くれすらうんのびられあぼあべろる	Cules la înnobilarea boabelor	クレス・ラ・ウンノビラレア・ボアベロル
    くれすらまとぅりたてでぷりな	Cules la maturitate deplină	クレス・ラ・マトゥリタテ・デプリナ
    くれた	Crete	クレタ
    くれまん	Crémant	クレマン
    くれまんだるざす	Crémant d'Alsace	クレマン・ダルザス
    くれまんでゅじゅら	Crémant du Jura	クレマン・デュ・ジュラ
    くれまんどさゔぉわ	Crémant de Savoie	クレマン・ド・サヴォワ
    くれまんどでぃ	Crémant de Die	クレマン・ド・ディ
    くれまんどぶるごーにゅ	Crémant de Bourgogne	クレマン・ド・ブルゴーニュ
    くれまんどぼるどー	Crémant de Bordeaux	クレマン・ド・ボルドー
    くれまんどりむー	Crémant de Limoux	クレマン・ド・リムー
    くれまんどろわーる	Crémant de Loire	クレマン・ド・ロワール
    くれむすたーる	Kremstal	クレムスタール
    くれれっと	Clairette	クレレット
    くれれっとでゅらんぐどっく	Clairette du Languedoc	クレレット・デュ・ラングドック
    くれれっとどでぃー	Clairette de Die	クレレット・ド・ディー
    くれれっとどでぃーめとーどあんせすとらる	Clairette de Die Méthode Ancestrale	クレレット・ド・ディー・メトード・アンセストラル
    くれれっとどべるがるど	Clairette de Bellegarde	クレレット・ド・ベルガルド
    くれゔなー	Clevner	クレヴナー
    くれゔねーる	Klevner	クレヴネール
    くれーるみろん	Clerc-Milon	クレール・ミロン
    くろあちあ	Croatia	クロアチア
    くろあてぃあんあっぷらんず	Croatian Uplands	クロアティアン・アップランズ
    くろあてぃあんだにゅーぶ	Croatian Danube	クロアティアン・ダニューブ
    くろあてぃーな	Croatina	クロアティーナ
    くろくまず	Crocmaz	クロクマズ
    くろさんじゃっく	Clos Saint-Jacques	クロ・サン・ジャック
    くろさんじゅりあん	Clos Saint-Julien	クロ・サン・ジュリアン
    くろさんどに	Clos Saint-Denis	クロ・サン・ドニ
    くろすてぃーに	Crostini	クロスティーニ
    くろたみぞ	Clos Tamisot	クロ・タミゾ
    くろたんどしゃゔぃにょる	Crottin de Chavignol	クロタン・ド・シャヴィニョル
    くろであべい	Clos des Abbayes	クロ・デ・アベイ
    くろでむーしゅ	Clos des Mouches	クロ・デ・ムーシュ
    くろでめ	Clos des Meix	クロ・デ・メ
    くろでもわーぬ	Clos des Moines	クロ・デ・モワーヌ
    くろでゅろわ	Clos du Roi	クロ・デュ・ロワ
    くろでゅゔぁる	Clos du Val	クロ・デュ・ヴァル
    くろでらんぶれ	Clos des Lambrays	クロ・デ・ランブレ
    くろでりゅしょっと	Clos des Ruchottes	クロ・デ・リュショット
    くろでれあ	Clos des Réas	クロ・デ・レア
    くろどたーる	Clos de Tart	クロ・ド・タール
    くろどらろっしゅ	Clos de la Roche	クロ・ド・ラ・ロッシュ
    くろどゔーじょー	Clos de Vougeot	クロ・ド・ヴージョー
    くろわぜばーじゅ	Croizet-Bages	クロワゼ・バージュ
    くろーずえるみたーじゅ	Crozes-Hermitage	クローズ・エルミタージュ
    くろーどげい	Claude Gay	クロード・ゲイ
    くわずるなたーる	Kwazulu Natal	クワズル・ナタール
    くんしゃーぐ	Kunság	クンシャーグ
    くゔぁりててぅのゔぃーのさこんとぅろりらにむぽどぅりえとぅろむ	Kvalitetno vino s kontroliranim podrijetlom	クヴァリテテゥノ・ヴィーノ・サ・コントゥロリラニム・ポドゥリエトゥロム
    くゔぁりてーつしゃうむばいんべーあー	Qualitätsschaumwein b.A.	クヴァリテーツシャウムバイン・ベー・アー
    くゔぁるねる	Kvarner	クヴァルネル
    くゔぇーるすーるー	Kövérszőlő	クヴェールスールー
    くーあん	Couhins	クーアン
    くーあんりゅるとん	Couhins-Lurton	クーアン・リュルトン
    くーぐろふ	Kouglof	クーグロフ
    くーて	Coutet	クーテ
    くーてねいず	Kootenays	クーテネイズ
    くーなわら	Coonawarra	クーナワラ
    くーのわーず	Counoise	クーノワーズ
    くーむずゔぃる	Coombsville	クームズヴィル
    くーよ	Cuyo	クーヨ
    くーる	Cool	クール
    くーるしゅゔぇるにー	Cour Cheverny	クール・シュヴェルニー
    くーるまいよーる	COURMAYEUR	クールマイヨール
    くーれどせらん	Coulée de Serrant	クーレ・ド・セラン
    くーゔぁんでじゃこばん	Couvent des Jacobins	クーヴァン・デ・ジャコバン
    ぐめにっさ	Goumenissa	グメニッサ
    ぐやーしゅれゔぇしゅ	Gulyásleves	グヤーシュレヴェシュ
    ぐらうあーぶるぐんだー	Grauer Burgunder	グラウアー・ブルグンダー
    ぐらうびゅんでん	Graubünden	グラウビュンデン
    ぐらうぶるぐんだー	Grauburgunder	グラウブルグンダー
    ぐらさでことなり	Grasă de Cotnari	グラサ・デ・コトナリ
    ぐらしぇゔぃな	Graševina	グラシェヴィナ
    ぐらしおさ	Graciosa	グラシオサ
    ぐらせ	Glacé	グラセ
    ぐらっどすとーん	Gladstone	グラッドストーン
    ぐらっぱ	Grappa	グラッパ
    ぐらなだ	Granada	グラナダ
    ぐらめるぽがっちぇるる	Grammelpogatscherl	グラメルポガッチェルル
    ぐらん	Grand	グラン
    ぐらんあにゃーだ	Gran Añada	グラン・アニャーダ
    ぐらんおーせろわ	Grand Auxerrois	グラン・オーセロワ
    ぐらんかなりあ	Gran Canaria	グラン・カナリア
    ぐらんくりゅ	Grand Cru	グラン・クリュ|グランクリュ
    ぐらんくりゅくらっせ	Grands Cru Classés	グラン・クリュ・クラッセ
    ぐらんじ	Grange	グランジ
    ぐらんどしゃんぱーにゅ	Grande Champagne	グランド・シャンパーニュ
    ぐらんびにゃくらしふぃかーだ	Gran Viña Clasificada	グラン・ビニャ・クラシフィカーダ
    ぐらんぴゅいでゅかす	Grand-Puy-Ducasse	グラン・ピュイ・デュカス
    ぐらんぴゅいらこすと	Grand-Puy-Lacoste	グラン・ピュイ・ラコスト
    ぐらんるーしょん	Grand Roussillon	グラン・ルーション
    ぐらんれせるば	Gran Reserva	グラン・レセルバ
    ぐらーしゅ	Gulasch	グラーシュ
    ぐらーなぱだーの	Grana Padano	グラーナ・パダーノ
    ぐらーゔ	Graves	グラーヴ
    ぐらーゔしゅぺりえーる	Graves Supérieures	グラーヴ・シュペリエール
    ぐらーゔどゔぇいる	Graves de Vayres	グラーヴ・ド・ヴェイル
    ぐりえ	Grillet	グリエ
    ぐりおっとしゃんべるたん	Griotte-Chambertin	グリオット・シャンベルタン
    ぐりにゃんれざでまーる	Grignan-les-Adhémar	グリニャン・レ・ザデマール
    ぐりにょりーの	Grignolino	グリニョリーノ
    ぐりゅいえーる	Gruyère	グリュイエール
    ぐりゅおーらろーず	Gruaud Larose	グリュオー・ラローズ
    ぐりゅーなー	Grüner	グリューナー
    ぐりゅーなーふぇるとりーなー	Grüner Veltliner	グリューナー・フェルトリーナー
    ぐりゅーなーゔぇるとりーなー	Grüner Veltliner	グリューナー・ヴェルトリーナー
    ぐりーす	Greece	グリース
    ぐりーんあがゔぇ	Green agave	グリーン・アガヴェ
    ぐりーんてぃー	Green Tea	グリーン・ティー
    ぐるなっしゅ	Grenache	グルナッシュ
    ぐるなっしゅのわーる	Grenache Noir	グルナッシュ・ノワール
    ぐるなっしゅぶらん	Grenache Blanc	グルナッシュ・ブラン
    ぐるぬいゆ	Grenouilles	グルヌイユ
    ぐれいもーるど	Gray mold	グレイ・モールド
    ぐれかにこ	Grecanico	グレカニコ
    ぐれけっと	Grechetto	グレケット
    ぐれこーでぃとぅーふぉ	Greco di Tufo	グレコー・ディ・トゥーフォ
    ぐれーこ	Greco	グレーコ
    ぐれーこびあんこ	Greco Bianco	グレーコ・ビアンコ
    ぐれーとさざん	Great Southern	グレート・サザン
    ぐれーべす	Gräwes	グレーベス
    ぐれーら	Glera	グレーラ
    ぐろせっと	Grosset	グロセット
    ぐろっぺっろ	Groppello	グロッペッロ
    ぐろぷらん	Gros Plant	グロ・プラン
    ぐろぷらんでゅぺいなんて	Gros Plant du Pays Nantais	グロ・プラン・デュ・ペイ・ナンテ
    ぐろまんさん	Gros Manseng	グロ・マンサン
    ぐろろ	Groslot	グロロ
    ぐろろー	Grolleau	グロロー
    ぐろろーぐり	Grolleau Gris	グロロー・グリ
    ぐろーすらーげ	Großlage	グロースラーゲ
    ぐろーせすげべっくす	Großes Gewächs	グローセス・ゲベックス
    ぐろーせらーげ	Große Lage	グローセ・ラーゲ
    ぐーつばいん	Gutswein	グーツバイン
    ぐーとえーでる	Gutedel	グートエーデル
    けいじょせっらだえすとれーら	Queijo Serra da Estrela	ケイジョ・セッラ・ダ・エストレーラ
    けいぷさうすこーすと	Cape South Coast	ケイプ・サウス・コースト
    けいぷどくたー	Cape Doctor	ケイプ・ドクター
    けいんぷるーにんぐ	Cane pruning	ケイン・プルーニング
    けそててぃーじゃ	Queso Tetilla	ケソ・テティージャ
    けそでむるしああるびーの	Queso de Murcia al Vino	ケソ・デ・ムルシア・アル・ビーノ
    けそでらせれーな	Queso de la Serena	ケソ・デ・ラ・セレーナ
    けそまんちぇご	Queso Manchego	ケソ・マンチェゴ
    けっちゅ	Quetsche	ケッチュ
    けっふぇるこっぷふ	Kaefferkopf	ケッフェルコップフ
    けふぁろにあ	Cephalonia	ケファロニア
    けべっく	Québec	ケベック
    けらんぬ	Cairanne	ケランヌ
    けりけり	Kerikeri	ケリケリ
    けるかすあるば	Quercus Alba	ケルカス・アルバ
    けるかすすべーる	Quercus suber	ケルカス・スベール
    けるかすぺとらえあ	Quercus petraea	ケルカス・ペトラエア
    けるかすろぶーる	Quercus robur	ケルカス・ロブール
    けるなー	Kerner	ケルナー
    けれす	Xérès	ケレス
    けんと	Kent	ケント
    けーくおぽるとー	Kékoportó	ケークオポルトー
    けーくふらんこしゅ	Kékfrankos	ケークフランコシュ
    けーぷあがらす	Cape Agulhas	ケープ・アガラス
    けーぷさうすこーすと	Cape South Coast	ケープ・サウス・コースト
    けーぷたうん	Cape Town	ケープ・タウン|ケープタウン
    けーぷどくたー	Cape Doctor	ケープ・ドクター
    げしゅねっつぇるてす	Geschnetzeltes	ゲシュネッツェルテス
    げばっけねすかるぷすひるん	Gebackenes Kalbshirn	ゲバッケネス・カルプスヒルン
    げまいんで	Gemeinde	ゲマインデ
    げみしゅたーざっつ	Gemischter Satz	ゲミシュター・ザッツ
    げろるしゅたいなー	Gerol Steiner	ゲロルシュタイナー
    げんめ	Ghemme	ゲンメ
    げゔゅるつとらみねーる	Gewürztraminer	ゲヴュルツトラミネール
    げゔゅるつとらみねーるせれくしおんどぐらんのーぶる	Gewürztraminer Sélection de Grains Nobles	ゲヴュルツトラミネール・セレクシオン・ド・グラン・ノーブル
    げゔゅるつとらみねーるゔぁんだんじゅたるでぃーゔ	Gewürztraminer Vendanges Tardives	ゲヴュルツトラミネール・ヴァンダンジュ・タルディーヴ
    こあんとろー	Cointreau	コアントロー
    こいのきゅれーしょん	Co-inoculation	コ・イノキュレーション
    こうしゅう	Koshu	コウシュウ
    こうしゅうあそしえーしょん	Koshu Assosiaction	コウシュウ・アソシエーション
    こうしゅういんたーなしょなる	Koshu International	コウシュウ・インターナショナル
    こうしゅうおゔじゃぱん	Koshu of Japan	コウシュウ・オヴ・ジャパン
    こおぺらてぃーゔどまにぴゅらしおん	Coopérative de Manipulation	コオペラティーヴ・ド・マニピュラシオン
    こきんぼ	Coquimbo	コキンボ
    こすてぃえーるどにーむ	Costières de Nîmes	コスティエール・ド・ニーム
    こすてでっらせーじあ	Coste della Sesia	コステ・デッラ・セージア
    こすてるすでるせぐれ	Costers del Segre	コステルス・デル・セグレ
    こすですとぅるねる	Cos d'Estournel	コス・デストゥルネル
    こすとあんどふれいと	Cost and Freight	コスト・アンド・フレイト
    こすといんしゅらんすあんどふれいと	Cost, Insurance and Freight	コスト・インシュランス・アンド・フレイト
    こすとれったあっらみらねーぜ	Costoletta alla Milanese	コストレッタ・アッラ・ミラネーゼ
    こすとれったあっらゔぁるどすたーな	Costoletta alla Valdostana	コストレッタ・アッラ・ヴァルドスターナ
    こすらぼり	Cos-Labory	コス・ラボリ
    こっこーゔぁん	Coq au Vin	コッコー・ヴァン
    こっと	Côt	コット
    こっりえうがねいふぃおーるだらんちお	Colli Euganei Fior d'Arancio	コッリ・エウガネイ・フィオール・ダランチオ
    こっりおごりつぃあーの	Collio Goriziano	コッリオ・ゴリツィアーノ
    こっりおりえんたーりでるふりうーりぴこりっと	Colli Orientali del Friuli Picolit	コッリ・オリエンターリ・デル・フリウーリ・ピコリット
    こっりせねーじ	Colli Senesi	コッリ・セネージ
    こっりでぃこねりあーの	Colli di Conegliano	コッリ・ディ・コネリアーノ
    こっりでぃるーに	Colli di Luni	コッリ・ディ・ルーニ
    こっりぼろにぇーじぴにょれっと	Colli Bolognesi Pignoletto	コッリ・ボロニェージ・ピニョレット
    こっりーねてらまーねもんてぷるちあーのだぶるっつぉ	Colline Teramane Montepulciano d'Abruzzo	コッリーネ・テラマーネ・モンテプルチアーノ・ダブルッツォ
    ことれったあっらぼろねーぜ	Cotoletta alla Bolognese	コトレッタ・アッラ・ボロネーゼ
    ことーしゃんぷのわ	Coteaux Champenois	コトー・シャンプノワ
    ことーだんすに	Coteaux d'Ancenis	コトー・ダンスニ
    ことーでくさんぷろゔぁんす	Coteaux d'Aix-en-Provence	コトー・デクサン・プロヴァンス
    ことーでゅけるしー	Coteaux du Quercy	コトー・デュ・ケルシー
    ことーでゅじぇのわ	Coteaux du Giennois	コトー・デュ・ジェノワ
    ことーでゅとりかすたん	Coteaux du Tricastin	コトー・デュ・トリカスタン
    ことーでゅれいよん	Coteaux du Layon	コトー・デュ・レイヨン
    ことーでゅゔぁんどもわ	Coteaux du Vendômois	コトー・デュ・ヴァンドモワ
    ことーど	Coteaux de	コトー・ド
    ことーどそみゅーる	Coteaux de Saumur	コトー・ド・ソミュール
    ことーどでぃー	Coteaux de Die	コトー・ド・ディー
    ことーどろーばんす	Coteaux de l'Aubance	コトー・ド・ローバンス
    ことーぶるぎにょん	Coteaux Bourguignons	コトー・ブルギニョン
    ことーゔぁろわあんぷろゔぁんす	Coteaux Varois-en-Provence	コトー・ヴァロワ・アン・プロヴァンス
    こどぅる	Codru	コドゥル
    こな	Kona	コナ
    こなこーひー	Konaコーヒー	コナコーヒー
    こにゃっく	Cognac	コニャック
    こねりあーのぷろせっこ	Conegliano-Prosecco	コネリアーノ・プロセッコ
    こねりあーのゔぁるどっびあーでねぷろせっこ	Conegliano Valdobbiadene-Prosecco	コネリアーノ・ヴァルドッビアーデネ・プロセッコ
    こぴあぽゔぁれー	Copiapó Valley	コピアポ・ヴァレー
    こみさおでゔぃてぃくるとぅらだれじあおどすゔぃにょすゔぇるです	Comissão de Viticultura da Região dos Vinhos Verdes	コミサオ・デ・ヴィティクルトゥラ・ダ・レジアオ・ドス・ヴィニョス・ヴェルデス
    こみてあんてるぷろふぇしおねるでゅゔぁんどしゃんぱーにゅ	Comité Interprofessionnel du Vin de Champagne	コミテ・アンテルプロフェシオネル・デュ・ヴァン・ド・シャンパーニュ
    こみゅーん	Commune	コミューン
    こもんうぇるすおゔゔぁーじにあ	Commonwealth of Virginia	コモンウェルス・オヴ・ヴァージニア
    こられす	Colares	コラレス
    こらーじゅ	Collage	コラージュ
    こりうーる	Collioure	コリウール
    こりぇいた	Colheita	コリェイタ
    こりねれどぶろじぇい	Colinele Dobrogei	コリネレ・ドブロジェイ
    こるくすくりゅー	Corkscrew	コルクスクリュー
    こるす	Corse	コルス
    こるすかるゔぃ	Corse Calvi	コルス・カルヴィ
    こるすことーでゅかっぷこるす	Corse Coteaux du Cap Corse	コルス・コトー・デュ・カップ・コルス
    こるすさるてーぬ	Corse Sartène	コルス・サルテーヌ
    こるすふぃがり	Corse Figari	コルス・フィガリ
    こるちゃぐあ	Colchagua	コルチャグア
    こるちゃぐあゔぁれー	Colchagua Valley	コルチャグア・ヴァレー
    こるてーぜ	Cortese	コルテーゼ
    こるてーぜでぃがゔぃ	Cortese di Gavi	コルテーゼ・ディ・ガヴィ
    こるとん	Corton	コルトン
    こるとんしゃるるまーにゅ	Corton-Charlemagne	コルトン・シャルルマーニュ
    こるどんろわや	Cordon Royat	コルドン・ロワヤ
    こるなす	Cornas	コルナス
    こるならん	Cornalin	コルナラン
    こるばん	Corbin	コルバン
    こるびえーる	Corbières	コルビエール
    こるびえーるぶーとなっく	Corbières Boutenac	コルビエール・ブートナック
    こるぴなっと	Corpinnat	コルピナット
    こるゔぃーな	Corvina	コルヴィーナ
    こるゔぃーなゔぇろねーぜ	Corvina Veronese	コルヴィーナ・ヴェロネーゼ
    ころにあ	Colonia	コロニア
    ころんばーる	Colombard	コロンバール
    ころんびあゔぁれー	Columbia Valley	コロンビア・ヴァレー
    こんかでばるべら	Conca de Barberà	コンカ・デ・バルベラ
    こんこーど	Concord	コンコード
    こんさゔぇいしょんちゃんぴおんず	Conservation Champions	コンサヴェイション・チャンピオンズ
    こんすたんしあ	Constantia	コンスタンシア
    こんて	Comté	コンテ
    こんとれっくす	Contrex	コントレックス
    こんどりゅー	Condrieu	コンドリュー
    こんふぃどかなーる	Confit de Canard	コンフィ・ド・カナール
    こんぷれーたー	Completer	コンプレーター
    こー	Côt	コー
    こーすたるりーじょん	Coastal Region	コースタル・リージョン
    こーだでぃゔぉるぺ	Coda di Volpe	コーダ・ディ・ヴォルペ
    こーと	Côtes	コート
    こーとしゃろねーず	Côte Chalonnaise	コート・シャロネーズ
    こーとでばーる	Côte des Bar	コート・デ・バール
    こーとでぶらん	Côte des Blancs	コート・デ・ブラン
    こーとでゅじゅら	Côtes du Jura	コート・デュ・ジュラ
    こーとでゅるーしょん	Côtes du Roussillon	コート・デュ・ルーション
    こーとでゅるーしょんゔぃらーじゅ	Côtes du Roussillon Villages	コート・デュ・ルーション・ヴィラージュ
    こーとでゅるーしょんゔぃらーじゅからまにー	Côtes du Roussillon Villages Caramany	コート・デュ・ルーション・ヴィラージュ・カラマニー
    こーとでゅるーしょんゔぃらーじゅれざすぷる	Côtes du Roussillon Villages Les Aspres	コート・デュ・ルーション・ヴィラージュ・レ・ザスプル
    こーとでゅるーしょんゔぃらーじゅれすけるど	Côtes du Roussillon Villages Lesquerde	コート・デュ・ルーション・ヴィラージュ・レスケルド
    こーとでゅろーぬ	Côtes du Rhône	コート・デュ・ローヌ
    こーとでゅろーぬゔぃらーじゅ	Côtes du Rhône Villages	コート・デュ・ローヌ・ヴィラージュ
    こーとでゅゔぃゔぁれ	Côte du Vivarais	コート・デュ・ヴィヴァレ
    こーとど	Côtes de	コート・ド
    こーとどとぅーる	Côtes de Toul	コート・ド・トゥール
    こーとどにゅい	Côte de Nuits	コート・ド・ニュイ
    こーとどにゅいゔぃらーじゅ	Côte de Nuits-Villages	コート・ド・ニュイ・ヴィラージュ
    こーとどぶらい	Côtes de Blaye	コート・ド・ブライ
    こーとどぶるいー	Côte de Brouilly	コート・ド・ブルイー
    こーとどぶーる	Côtes de Bourg	コート・ド・ブール
    こーとどぷろゔぁんす	Côtes de Provence	コート・ド・プロヴァンス
    こーとどぷろゔぁんすさんとゔぃくとわーる	Côtes de Provence Sainte-Victoire	コート・ド・プロヴァンス・サント・ヴィクトワール
    こーとどぷろゔぁんすのーとるだむでざんじゅ	Côtes de Provence Notre-Dame des Anges	コート・ド・プロヴァンス・ノートルダム・デ・ザンジュ
    こーとどぷろゔぁんすぴえるふ	Côtes de Provence Pierrefeu	コート・ド・プロヴァンス・ピエルフ
    こーとどぷろゔぁんすふれじゅす	Côtes de Provence Fréjus	コート・ド・プロヴァンス・フレジュス
    こーとどぷろゔぁんすらろんど	Côtes de Provence La Londe	コート・ド・プロヴァンス・ラ・ロンド
    こーとどべるじゅらっく	Côtes de Bergerac	コート・ド・ベルジュラック
    こーとどぼるどー	Côtes de Bordeaux	コート・ド・ボルドー
    こーとどぼるどーさんまけーる	Côtes de Bordeaux Saint-Macaire	コート・ド・ボルドー・サン・マケール
    こーとどぼーぬ	Côte de Beaune	コート・ド・ボーヌ
    こーとどぼーぬゔぃらーじゅ	Côte de Beaune-Villages	コート・ド・ボーヌ・ヴィラージュ
    こーとどむーず	Côtes de Meuse	コート・ド・ムーズ
    こーとどろるぶ	Côtes-de-l'Orbe	コート・ド・ロルブ
    こーとどーゔぇるにゅ	Côtes d'Auvergne	コート・ドーヴェルニュ
    こーとろあねーず	Côte Roannaise	コート・ロアネーズ
    こーとろてぃ	Côte-Rôtie	コート・ロティ
    こーねろ	Cònero	コーネロ
    こーるど	Cold	コールド
    こーんうぉーる	Cornwall	コーンウォール
    ごでーりょ	Godello	ゴデーリョ
    ごびーびー	5BB	ゴビービー
    ごぶれ	Gobelet	ゴブレ
    ごるごんぞーら	Gorgonzola	ゴルゴンゾーラ
    ごるでーる	Goldert	ゴルデール
    ごるとりーすりんぐ	Goldriesling	ゴルトリースリング
    ごーるでんくいーん	Golden Queen	ゴールデン・クイーン
    ごーるでんまいるすろーぷす	Golden Mile Slopes	ゴールデン・マイル・スロープス
    ごーるでんまいるべんち	Golden Mile Bench	ゴールデン・マイル・ベンチ
    ごーるばーんゔぁれー	Goulburn Valley	ゴールバーン・ヴァレー
    さうすあいらんず	South Islands	サウス・アイランズ
    さうすあふりか	South Africa	サウス・アフリカ
    さうすおーすとらりあ	South Australia	サウス・オーストラリア
    さうすけろうなすろーぷす	South Kelowna Slopes	サウス・ケロウナ・スロープス
    さうすこーすと	South Coast	サウス・コースト
    さぐらんてぃーの	Sagrantino	サグランティーノ
    さけ	saké	サケ
    さざんおれごん	Southern Oregon	サザン・オレゴン
    さざんかりふぉるにあ	Southern California	サザン・カリフォルニア
    さざんかんふぉーと	Southern Comfort	サザン・カンフォート
    さざんゔぁれー	Southern Valley	サザン・ヴァレー
    さざーらんどかるー	Sutherland-Karoo	サザーランド・カルー
    さすてなぶるいんぷろぐれす	Sustainable in Progress	サステナブル・イン・プログレス
    させっくす	Sussex	サセックス
    させっくすわいん	Sussex Wine	サセックス・ワイン
    さっかろみせすせれゔぃしえ	Saccharomyces cerevisiae	サッカロミセス・セレヴィシエ
    さっしかいあ	Sassicaia	サッシカイア
    さっぷぶりーでぃんぐ	Sap bleeding	サップ・ブリーディング
    さつなへり	Satsnakheli	サツナヘリ
    さてぃにー	Satigny	サティニー
    さぷる	Supple	サプル
    さぺらゔぃ	Saperavi	サペラヴィ
    さぺらゔぃはしみ	Saperavi Khashmi	サペラヴィ・ハシミ
    さぺらゔぃはしゅみ	Saperavi Khashmi	サペラヴィ・ハシュミ
    さまーぷるーにんぐ	Summer pruning	サマー・プルーニング
    さまーらんどべんち	Summerland Bench	サマーランド・ベンチ
    さまーらんどれいくふろんと	Summerland Lakefront	サマーランド・レイクフロント
    さまーらんどゔぁれーず	Summerland Valleys	サマーランド・ヴァレーズ
    さみゅえるまーすでん	Samuel Marsden	サミュエル・マースデン
    さむそ	Samsó	サムソ
    さもす	Samos	サモス
    さもろどに	Szamorodni	サモロドニ
    さらどにそわーず	Salade Niçoise	サラド・ニソワーズ
    さりー	Surrey	サリー
    さるた	Salta	サルタ
    さるでーにゃ	Sardegna	サルデーニャ
    さるまなざーる	Salmanazar	サルマナザール
    さるまーれ	Sarmale	サルマーレ
    さるゔぁにゃん	Salvagnin	サルヴァニャン
    さろんどこうしゅう	Salon de Koshu	サロン・ド・コウシュウ
    さんあんとにおゔぁれー	San Antonio Valley	サン・アントニオ・ヴァレー
    さんえむえいち	3MH	サンエムエイチ
    さんえむえいちえー	3MHA	サンエムエイチエー
    さんかるろす	San Carlos	サン・カルロス
    さんぐりあ	Sangria	サングリア
    さんざるくーる	sans alcool	サン・ザルクール
    さんしにあん	Saint-Chinian	サン・シニアン
    さんじゅりあん	Saint-Julien	サン・ジュリアン
    さんじょぜふ	Saint-Joseph	サン・ジョゼフ
    さんじょべーぜ	Sangiovese	サンジョベーゼ
    さんじょるじゅさんてみりおん	Saint-Georges Saint-Émilion	サンジョルジュ・サンテミリオン
    さんじょゔぇーぜ	Sangiovese	サンジョヴェーゼ
    さんせーる	Sancerre	サンセール
    さんそー	Cinsault|Cinsaut	サンソー
    さんたいねずゔぁれー	Santa Ynez Valley	サンタ・イネズ・ヴァレー
    さんたくらら	Santa Clara	サンタ・クララ
    さんたくららかうんてぃ	Santa Clara County	サンタ・クララ・カウンティ
    さんたくるーずかうんてぃ	Santa Cruz County	サンタ・クルーズ・カウンティ
    さんたくるーずまうんてん	Santa Cruz Mountains	サンタ・クルーズ・マウンテン
    さんたにおる	Sant Aniol	サンタニオル
    さんたばーばらかうんてぃ	Santa Barbara County	サンタ・バーバラ・カウンティ
    さんたまりあゔぁれー	Santa Maria Valley	サンタ・マリア・ヴァレー
    さんたむーる	Saint-Amour	サン・タムール
    さんたんてぃも	Sant'Antimo	サンタンティモ
    さんてすてふ	Saint-Estèphe	サン・テステフ
    さんてみりおん	Saint-Émilion	サン・テミリオン|サンテミリオン
    さんてみりおんぐらんくりゅ	Saint-Émilion Grand Cru	サン・テミリオン・グラン・クリュ
    さんてみりおんでしゃらんと	Saint-Émilion des Charentes	サン・テミリオン・デ・シャラント
    さんでぃえご	San Diego	サン・ディエゴ
    さんでぃえごかうんてぃ	San Diego County	サン・ディエゴ・カウンティ
    さんとくろわでゅもん	Sainte-Croix-du-Mont	サント・クロワ・デュ・モン
    さんとさどぅるにだのいあ	Sant Sadurní d'Anoia	サント・サドゥルニ・ダノイア
    さんとねー	Santenay	サントネー
    さんとふぉわ	Sainte-Foy	サント・フォワ
    さんとふぉわこーとどぼるどー	Sainte-Foy Côtes de Bordeaux	サント・フォワ・コート・ド・ボルドー
    さんともーるどとぅーれーぬ	Sainte-Maure de Touraine	サント・モール・ド・トゥーレーヌ
    さんとりーに	Santorini	サントリーニ
    さんとるろわーる	Centre Loire	サントル・ロワール
    さんとーばん	Saint-Aubin	サン・トーバン
    さんにこらどぶるぐいゆ	Saint Nicolas de Bourgueil	サン・ニコラ・ド・ブルグイユ
    さんねくてーる	Saint-Nectaire	サン・ネクテール
    さんぴえーる	Saint-Pierre	サン・ピエール
    さんふあん	San Juan	サン・フアン
    さんふらんしすこべい	San Francisco Bay	サン・フランシスコ・ベイ
    さんぶり	Saint-Bris	サン・ブリ
    さんぺれぐりの	S.Pellegrino	サンペレグリノ
    さんぺれー	Saint-Péray	サン・ペレー
    さんぺれーむーすー	Saint-Péray Mousseux	サン・ペレー・ムースー
    さんほせ	San José	サン・ホセ
    さんらふぁえる	San Rafael	サン・ラファエル
    さんるいすおびすぽかうんてぃ	San Luis Obispo County	サン・ルイス・オビスポ・カウンティ
    さんるくらすまん	Sans le Classement	サン・ル・クラスマン
    さんるーかるでばらめだ	Sanlúcar de Barrameda	サンルーカル・デ・バラメダ
    さんれおなーる	Saint-Léonard	サン・レオナール
    さんろまん	Saint-Romain	サン・ロマン
    さんゔぇらん	Saint-Véran	サン・ヴェラン
    さゔぁてぃあの	Savatiano	サヴァティアノ
    さゔぁにゃん	Savagnin	サヴァニャン
    さゔぃにーれぼーぬ	Savigny-lès-Beaune	サヴィニー・レ・ボーヌ
    さゔぉわ	Savoie	サヴォワ
    さゔにえーる	Savennières	サヴニエール
    さーもんせーふ	Salmon Safe	サーモン・セーフ
    さーらず	Száraz	サーラズ
    さーらずさもろどに	Száraz Szamorodni	サーラズ・サモロドニ
    ざうまーげん	Saumagen	ザウマーゲン
    ざきんとす	Zakynthos	ザキントス
    ざくせん	Sachsen	ザクセン
    ざごりえむじむりえ	Zagorje-Medimurje	ザゴリエ・ムジムリエ
    ざはんぷとんず	The Hamptons	ザ・ハンプトンズ
    ざわーくらうと	Sauerkraut	ザワークラウト
    ざんくとらうれんと	Sankt Laurent	ザンクト・ラウレント
    ざーる	Saar	ザール
    ざーれ	Saale	ザーレ
    ざーれうんすとるーと	Saale-Unstrut	ザーレ・ウンストルート
    しぇいく	Shake	シェイク
    しぇなす	Chénas	シェナス
    しぇなんどーゔぁれー	Shenandoah Valley	シェナンドー・ヴァレー
    しぇりー	Sherry	シェリー
    しぇりーふぃの	Sherry Fino	シェリー・フィノ
    しぇんげん	Schengen	シェンゲン
    しぇーゔる	Chèvre	シェーヴル
    しえらふっとひるず	Sierra Foothills	シエラ・フットヒルズ
    しちりあ	Sicilia	シチリア
    してぃあ	Sitia	シティア
    しとらすだるまうんてん	Citrusdal Mountain	シトラスダル・マウンテン
    しとらすだるゔぁれー	Citrusdal Valley	シトラスダル・ヴァレー
    しのん	Chinon	シノン
    しまこるご	Cima Corgo	シマ・コルゴ
    しまらむれしゅ	şi Maramureş	シ・マラムレシュ
    しみるかみーんゔぁれー	Similkameen Valley	シミルカミーン・ヴァレー
    しゃうむばいん	Schaumwein	シャウムバイン
    しゃうるす	Chaource	シャウルス
    しゃかれっろ	Sciacarello	シャカレッロ
    しゃさーにゅもんらっしぇ	Chassagne-Montrachet	シャサーニュ・モンラッシェ
    しゃすら	Chasselas	シャスラ
    しゃたー	Shatter	シャター
    しゃっけとら	Sciacchetrà	シャッケトラ
    しゃてぃよんあんでぃおわ	Châtillon en Diois	シャティヨン・アン・ディオワ
    しゃてるどん	CHATELDON	シャテルドン
    しゃとー	Château	シャトー
    しゃとーあんじぇりゅす	Château Angélus	シャトー・アンジェリュス
    しゃとーおりゔぃえ	Château Olivier	シャトー・オリヴィエ
    しゃとーおーぞんぬ	Château Ausone	シャトー・オーゾンヌ
    しゃとーおーばいい	Château Haut-Bailly	シャトー・オー・バイイ
    しゃとーおーばたいえ	Château Haut-Batailley	シャトー・オー・バタイエ
    しゃとーおーばーじゅりべらる	Château Haut-Bages-Libéral	シャトー・オー・バージュ・リベラル
    しゃとーおーぶりおん	Château Haut-Brion	シャトー・オー・ブリオン
    しゃとーかいゆ	Château Caillou	シャトー・カイユ
    しゃとーかっぷどむーるらん	Château Cap de Mourlin	シャトー・カップ・ド・ムールラン
    しゃとーかのん	Château Canon	シャトー・カノン
    しゃとーかのんらがふりえーる	Château Canon La Gaffelière	シャトー・カノン・ラ・ガフリエール
    しゃとーかるぼにゅー	Château Carbonnieux	シャトー・カルボニュー
    しゃとーかろんせぎゅーる	Château Calon-Ségur	シャトー・カロン・セギュール
    しゃとーかんとなっくぶらうん	Château Cantenac Brown	シャトー・カントナック・ブラウン
    しゃとーかんとめるる	Château Cantemerle	シャトー・カントメルル
    しゃとーきるゔぁん	Château Kirwan	シャトー・キルヴァン
    しゃとーぎろー	Château Guiraud	シャトー・ギロー
    しゃとーくりまんす	Château Climens	シャトー・クリマンス
    しゃとーくれーるみろん	Château Clerc-Milon	シャトー・クレール・ミロン
    しゃとーくろわぜばーじゅ	Château Croizet-Bages	シャトー・クロワゼ・バージュ
    しゃとーくーあん	Château Couhins	シャトー・クーアン
    しゃとーくーあんりゅるとん	Château Couhins-Lurton	シャトー・クーアン・リュルトン
    しゃとーくーて	Château Coutet	シャトー・クーテ
    しゃとーぐらんぴゅいでゅかす	Château Grand-Puy-Ducasse	シャトー・グラン・ピュイ・デュカス
    しゃとーぐらんぴゅいらこすと	Château Grand-Puy-Lacoste	シャトー・グラン・ピュイ・ラコスト
    しゃとーぐりえ	Château-Grillet	シャトー・グリエ
    しゃとーぐりゅおーらろーず	Château Gruaud Larose	シャトー・グリュオー・ラローズ
    しゃとーこすですとぅるねる	Château Cos d'Estournel	シャトー・コス・デストゥルネル
    しゃとーこすらぼり	Château Cos-Labory	シャトー・コス・ラボリ
    しゃとーこるばん	Château Corbin	シャトー・コルバン
    しゃとーさんぴえーる	Château Saint-Pierre	シャトー・サン・ピエール
    しゃとーしゃろん	Château-Chalon	シャトー・シャロン
    しゃとーしゅゔぁるぶらん	Château Cheval Blanc	シャトー・シュヴァル・ブラン
    しゃとーじすくーる	Château Giscours	シャトー・ジスクール
    しゃとーすお	Château Suau	シャトー・スオ
    しゃとーすたーる	Château Soutard	シャトー・スタール
    しゃとーすでゅいろー	Château Suduiraut	シャトー・スデュイロー
    しゃとーすみすおーらふぃっと	Château Smith-Haut-Lafitte	シャトー・スミス・オー・ラフィット
    しゃとーたるぼ	Château Talbot	シャトー・タルボ
    しゃとーだっそー	Château Dassault	シャトー・ダッソー
    しゃとーだらまん	Château d'Allaman	シャトー・ダラマン
    しゃとーだるしゅ	Château d'Arche	シャトー・ダルシュ
    しゃとーだるまいやっく	Château d'Armailhac	シャトー・ダルマイヤック
    しゃとーでぃけむ	Château d'Yquem	シャトー・ディケム
    しゃとーでぃっさん	Château d'Issan	シャトー・ディッサン
    しゃとーですみらいゆ	Château Desmirail	シャトー・デスミライユ
    しゃとーでゅあーるみろんろーとしると	Château Duhart-Milon-Rothschild	シャトー・デュアール・ミロン・ロートシルト
    しゃとーでゅくりゅぼーかいゆ	Château Ducru-Beaucaillou	シャトー・デュクリュ・ボーカイユ
    しゃとーでゅてるとる	Château du Tertre	シャトー・デュ・テルトル
    しゃとーでゅるふぉーるゔぃゔぁん	Château Durfort-Vivens	シャトー・デュルフォール・ヴィヴァン
    しゃとーとろろんもんど	Château Troplong Mondot	シャトー・トロロン・モンド
    しゃとーどかまんさっく	Château de Camensac	シャトー・ド・カマンサック
    しゃとーどふゅーざる	Château de Fieuzal	シャトー・ド・フューザル
    しゃとーどまる	Château de Malle	シャトー・ド・マル
    しゃとーどわじーでゅぶろか	Château Doisy-Dubroca	シャトー・ドワジー・デュブロカ
    しゃとーどわじーでーぬ	Château Doisy Daëne	シャトー・ドワジー・デーヌ
    しゃとーどゔぉーぬろまね	Château de Vosne-Romanée	シャトー・ド・ヴォーヌ・ロマネ
    しゃとーどゔゅふらん	Château de Vufflens	シャトー・ド・ヴュフラン
    しゃとーどーざっく	Château Dauzac	シャトー・ドーザック
    しゃとーぬふでゅぱぷ	Châteauneuf-du-Pape	シャトーヌフ・デュ・パプ
    しゃとーねらっく	Château Nairac	シャトー・ネラック
    しゃとーばたいえ	Château Batailley	シャトー・バタイエ
    しゃとーぱぷくれまん	Château Pape Clément	シャトー・パプ・クレマン
    しゃとーぱるめ	Château Palmer	シャトー・パルメ
    しゃとーぱゔぃ	Château Pavie	シャトー・パヴィ
    しゃとーぱゔぃまかん	Château Pavie Macquin	シャトー・パヴィ・マカン
    しゃとーぴしょんろんぐゔぃるこんてすどららんど	Château Pichon Longueville Comtesse de Lalande	シャトー・ピション・ロングヴィル・コンテス・ド・ラランド
    しゃとーぴしょんろんぐゔぃるばろん	Château Pichon-Longueville Baron	シャトー・ピション・ロングヴィル・バロン
    しゃとーふぃじゃっく	Château Figeac	シャトー・フィジャック
    しゃとーふぃろ	Château Filhot	シャトー・フィロ
    しゃとーふぇりえーる	Château Ferrière	シャトー・フェリエール
    しゃとーふぉじぇーる	Château Faugères	シャトー・フォジェール
    しゃとーぶすこー	Château Bouscaut	シャトー・ブスコー
    しゃとーぶらねーるでゅくりゅ	Château Branaire-Ducru	シャトー・ブラネール・デュクリュ
    しゃとーぶらーぬかんとなっく	Château Brane-Cantenac	シャトー・ブラーヌ・カントナック
    しゃとーぶるーすて	Château Broustet	シャトー・ブルーステ
    しゃとーぷりゅーれりしーぬ	Château Prieuré-Lichine	シャトー・プリューレ・リシーヌ
    しゃとーぷーじぇ	Château Pouget	シャトー・プージェ
    しゃとーべいしゅゔぇる	Château Beychevelle	シャトー・ベイシュヴェル
    しゃとーべるぐらーゔ	Château Belgrave	シャトー・ベルグラーヴ
    しゃとーべるゔゅー	Château Bellvue	シャトー・ベルヴュー
    しゃとーぺですくろー	Château Pédesclaux	シャトー・ペデスクロー
    しゃとーぺとりゅす	Château Petrus	シャトー・ペトリュス
    しゃとーぼいどかんとなっく	Château Boyd-Cantenac	シャトー・ボイド・カントナック
    しゃとーぼーせじゅーるべこ	Château Beau-Séjour-Bécot	シャトー・ボーセ・ジュールベコ
    しゃとーぽんてかね	Château Pontet-Canet	シャトー・ポンテ・カネ
    しゃとーまらるてぃっくらぐらゔぃえーる	Château Malartic-Lagravière	シャトー・マラルティック・ラグラヴィエール
    しゃとーまるきだれーむべっかー	Château Marquis d'Alesme-Becker	シャトー・マルキ・ダレーム・ベッカー
    しゃとーまるきどてるむ	Château Marquis de Terme	シャトー・マルキ・ド・テルム
    しゃとーまるごー	Château Margaux	シャトー・マルゴー
    しゃとーまれすこさんてぐじゅぺり	Château Malescot Saint-Exupéry	シャトー・マレスコ・サンテグジュペリ
    しゃとーむーとんばろんぬふぃりっぷ	Château Mouton Baronne Philippe	シャトー・ムートン・バロンヌフィリッ・プ
    しゃとーむーとんろーとしると	Château Mouton Rothschild	シャトー・ムートン・ロートシルト
    しゃとーもんてれーな	Château Montelena	シャトー・モンテレーナ
    しゃとーもんぶすけ	Château Monbousquet	シャトー・モンブスケ
    しゃとーもんりす	Château Montlisse	シャトー・モンリス
    しゃとーもんろーず	Château Montrose	シャトー・モンローズ
    しゃとーらぐらんじゅ	Château Lagrange	シャトー・ラグランジュ
    しゃとーらすこんぶ	Château Lascombes	シャトー・ラスコンブ
    しゃとーらとぅーる	Château Latour	シャトー・ラトゥール
    しゃとーらとぅーるおーぶりおん	Château La Tour-Haut-Brion	シャトー・ラ・トゥール・オー・ブリオン
    しゃとーらとぅーるかるね	Château La Tour-Carnet	シャトー・ラ・トゥール・カルネ
    しゃとーらとぅーるふぃじゃっく	Château La Tour Figeac	シャトー・ラ・トゥール・フィジャック
    しゃとーらとぅーるまるてぃやっく	Château Latour Martillac	シャトー・ラトゥール・マルティヤック
    しゃとーらふぃっとろーとしると	Château Lafite-Rothschild	シャトー・ラフィット・ロートシルト
    しゃとーらふぉんろしぇ	Château Lafon-Rochet	シャトー・ラフォン・ロシェ
    しゃとーらみっしょんおーぶりおん	Château La Mission-Haut-Brion	シャトー・ラ・ミッション・オー・ブリオン
    しゃとーらもっとぎにゃーる	Château Lamothe-Guignard	シャトー・ラモット・ギニャール
    しゃとーららぎゅーぬ	Château La Lagune	シャトー・ラ・ラギューヌ
    しゃとーらるしでゅかす	Château Larcis Ducasse	シャトー・ラルシ・デュカス
    しゃとーらろーず	Château Laroze	シャトー・ラローズ
    しゃとーらんごあばるとん	Château Langoa-Barton	シャトー・ランゴア・バルトン
    しゃとーらんしゅばーじゅ	Château Lynch-Bages	シャトー・ランシュ・バージュ
    しゃとーらんしゅむーさ	Château Lynch-Moussas	シャトー・ランシュ・ムーサ
    しゃとーらゔぃるおーぶりおん	Château Laville Haut-Brion	シャトー・ラヴィル・オー・ブリオン
    しゃとーりゅーせっく	Château Rieussec	シャトー・リューセック
    しゃとーれおゔぃるばるとん	Château Léoville-Barton	シャトー・レオヴィル・バルトン
    しゃとーれおゔぃるぽわふぇれ	Château Léoville-Poyferré	シャトー・レオヴィル・ポワフェレ
    しゃとーれおゔぃるらすかーず	Château Léoville-Las Cases	シャトー・レオヴィル・ラス・カーズ
    しゃとーろーざんがしー	Château Rauzan-Gassies	シャトー・ローザン・ガシー
    しゃとーろーざんせぐら	Château Rauzan-Ségla	シャトー・ローザン・セグラ
    しゃとーゔぁらんどろー	Château Valandraud	シャトー・ヴァランドロー
    しゃぶり	Chablis	シャブリ
    しゃぶりぐらんくりゅ	Chablis Grand Cru	シャブリ・グラン・クリュ
    しゃぶりぷるみえくりゅ	Chablis Premier Cru	シャブリ・プルミエ・クリュ
    しゃぶれ	Chablais	シャブレ
    しゃぷたりざしおん	Chaptalisation	シャプタリザシオン
    しゃぺるしゃんべるたん	Chapelle-Chambertin	シャペル・シャンベルタン
    しゃもぞん	Chamoson	シャモゾン
    しゃるつほーふべるく	Scharzhofberg	シャルツホーフベルク
    しゃるとりゅーず	Chartreuse	シャルトリューズ
    しゃるとりゅーずじょーぬ	Chartreuse Jaune	シャルトリューズ・ジョーヌ
    しゃるとりゅーずゔぇると	Chartreuse Verte	シャルトリューズ・ヴェルト
    しゃるどね	Chardonnay	シャルドネ
    しゃるどねろーず	Chardonnay rose	シャルドネ・ローズ
    しゃるむしゃんべるたん	Charmes-Chambertin	シャルム・シャンベルタン
    しゃるるまーにゅ	Charlemagne	シャルルマーニュ
    しゃるるるふらん	Charles Le Franc|Charles Lefranc	シャルル・ル・フラン|シャルル・ルフラン
    しゃろれ	Charolais	シャロレ
    しゃろん	Chalon	シャロン
    しゃろーん	Chalone	シャローン
    しゃんとね	Chantonnay	シャントネ
    しゃんぱーにゅ	Champagne	シャンパーニュ
    しゃんぱーにゅぐらんくりゅ	Champagne Grand Cru	シャンパーニュ・グラン・クリュ
    しゃんぱーにゅぐらんどきゅゔぇ	Champagne Grande Cuvée	シャンパーニュ・グランド・キュヴェ
    しゃんぶるさん	Chambourcin	シャンブルサン
    しゃんぶれ	Chambré	シャンブレ
    しゃんぷれいんゔぁれーおゔにゅーよーく	Champlain Valley of New York	シャンプレイン・ヴァレー・オヴ・ニューヨーク|シャンプレイン・ヴァレー・オヴ・ニュー・ヨーク
    しゃんべるたん	Chambertin	シャンベルタン
    しゃんべるたんくろどべーず	Chambertin Clos-de-Bèze	シャンベルタン・クロ・ド・ベーズ
    しゃんぼーるみゅじにー	Chambolle-Musigny	シャンボール・ミュジニー
    しゃゔぃにょる	Chavignol	シャヴィニョル
    しゃーるがむしゅこたーい	Sárgamuskotály	シャールガムシュコターイ
    しゅいい	Chouilly	シュイイ
    しゅくめるり	Shkmeruli	シュクメルリ
    しゅくるーと	Choucroute	シュクルート
    しゅすわっぷ	Shuswap	シュスワップ
    しゅたいあーまるく	Steiermark	シュタイアーマルク
    しゅたいがーばると	Steigerwald	シュタイガーバルト
    しゅたいるらーげ	Steillage	シュタイルラーゲ
    しゅたいんふぇーだー	Steinfeder	シュタインフェーダー
    しゅたいんべるく	Steinberg	シュタインベルク
    しゅたっとぶれでぃむす	Stadtbredims	シュタットブレディムス
    しゅっどうえすと	Sud-Ouest	シュッド・ウエスト
    しゅてふぁんゔぉだ	Ştefan Vodă	シュテファン・ヴォダ
    しゅてるつぇ	Stelze	シュテルツェ
    しゅとぅるむ	Sturm	シュトゥルム
    しゅとりゅーでる	Strüdel	シュトリューデル
    しゅとろーばいん	Strohwein	シュトローバイン
    しゅなん	Chenin	シュナン
    しゅなんぶらん	Chenin Blanc	シュナン・ブラン
    しゅのんそー	Chenonceaux	シュノンソー
    しゅぺりゅーる	Supérieur	シュペリュール
    しゅぺーとぶるぐんだー	Spätburgunder	シュペートブルグンダー
    しゅぺーとれーぜ	Spätlese	シュペートレーゼ
    しゅぺーとろーと	Spätrot	シュペートロート
    しゅめぐ	Sümeg	シュメグ
    しゅろすふぉるらーつ	Schloss Vollrads	シュロス・フォルラーツ
    しゅろすよはにすべるく	Schloss Johannisberg	シュロス・ヨハニスベルク
    しゅろすらいひゃるつはうぜん	Schloss Reichartshausen	シュロス・ライヒャルツハウゼン
    しゅゔぁりえもんらっしぇ	Chevalier-Montrachet	シュヴァリエ・モンラッシェ
    しゅゔぁるつりーすりんぐ	Schwarzriesling	シュヴァルツリースリング
    しゅゔぁるぶらん	Cheval Blanc	シュヴァル・ブラン
    しゅゔぇるにー	Cheverny	シュヴェルニー
    しゅーるりー	Sur Lie|Sur lie	シュール・リー
    しょいれーべ	Scheurebe	ショイレーベ
    しょうこうし	Shokoshi	ショウコウシ
    しょぷろん	Sopron	ショプロン
    しょれーれぼーぬ	Chorey-lès-Beaune	ショレー・レ・ボーヌ
    しょー	Chaud	ショー
    しらー	Syrah	シラー
    しらーず	Shiraz	シラーズ
    しらーゔぁいん	Schillerwein	シラーヴァイン
    しりあ	Síria	シリア
    しるひゃー	Schilcher	シルヒャー
    しるべすとれおちゃがびあ	Silvestre Ochagavia	シルベストレ・オチャガビア
    しるりー	Sillery	シルリー
    しるゔぁねーる	Sylvaner	シルヴァネール
    しるゔぁーなー	Silvaner|Sylvaner	シルヴァーナー
    しるーぶる	Chiroubles	シルーブル
    しろかめるにしゅかろざ	Shiroka Melnishka Loza	シロカ・メルニシュカ・ロザ
    しんぐるきんたゔぃんてーじぽーと	Single Quinta Vintage Port	シングル・キンタ・ヴィンテージ・ポート
    しゔぃぴの	Sivi Pinot	シヴィ・ピノ
    しゔぇどさんぐりえ	Civet de Sanglier	シヴェ・ド・サングリエ
    しーいち	C-Ⅰ	シー・イチ
    しーえふ	C&amp;F	シーエフ
    しーずにんぐ	Seasoning|seasoning	シーズニング
    しーど	Seed	シード
    しーどる	Cidre	シードル
    しーらー	Schieler	シーラー
    じあいりーゔぃんやーず	The Eyrie Vineyards	ジ・アイリー・ヴィンヤーズ
    じぇりー	Jelly	ジェリー
    じぇろぼあむ	Jéroboam	ジェロボアム
    じぇーむずばずびー	James Busby	ジェームズ・バズビー
    じぇーる	Gers	ジェール
    じおぐらふぃかるいんでぃけーしょん	Geographical Indication	ジオグラフィカル・インディケーション
    じおぐらふぃかるいんでぃけーしょんず	Geographical Indications	ジオグラフィカル・インディケーションズ
    じおぐらふぃかるゆにっと	Geographical Unit	ジオグラフィカル・ユニット
    じおぐらーふ	Geographe	ジオグラーフ
    じごだにょーあんくるーと	Gigot d'Agneau en Croûte	ジゴ・ダニョー・アン・クルート
    じごんだす	Gigondas	ジゴンダス
    じすくーる	Giscours	ジスクール
    じびっぼ	Zibibbo	ジビッボ
    じぶり	Givry	ジブリ
    じみーわとそんとろふぃー	Jimmy Watson Trophy	ジミー・ワトソン・トロフィー
    じゃえん	Jaen	ジャエン
    じゃけーる	Jacquère	ジャケール
    じゃこんだ	Giaconda	ジャコンダ
    じゃにえーる	Jasnières	ジャニエール
    じゃぽん	Japon	ジャポン
    じゃんあんとわーぬしゃぷたる	Jean Antoine Chaptal	ジャン・アントワーヌ・シャプタル
    じゃんてぃ	Gentil	ジャンティ
    じゃんぼんせっくどこるす	Jambon Sec de Corse	ジャンボン・セック・ド・コルス
    じゃんぼんぺるしえ	Jambon Persillé	ジャンボン・ペルシエ
    じゅぬゔりえーる	Genevrières	ジュヌヴリエール
    じゅねーゔ	Genève	ジュネーヴ
    じゅら	Jura	ジュラ
    じゅらさゔぉわ	Jura-Savoie	ジュラ・サヴォワ
    じゅらんそん	Jurançon	ジュランソン
    じゅらんそんせっく	Jurançon Sec	ジュランソン・セック
    じゅれ	Gelé	ジュレ
    じゅゔれしゃんべるたん	Gevrey-Chambertin	ジュヴレ・シャンベルタン
    じゅーる	Jules	ジュール
    じゅーるぎよ	Jules Guyot	ジュール・ギヨ
    じょあぉんでさんたれん	João de Santarém	ジョアォン・デ・サンタレン
    じょせふるいげいりゅさっく	Joseph Louis Gay-Lussac	ジョセフ・ルイ・ゲイ・リュサック
    じょん	John	ジョン
    じょんしらー	John Schiller	ジョン・シラー
    じょんぶるずゔぃんやーど	John Bull's Vineyards	ジョン・ブルズ・ヴィンヤード
    じょーじあ	Georgia	ジョージア
    じょーぬ	Jaune	ジョーヌ
    じょーぬぱーる	Jaune pâle	ジョーヌ・パール
    じるゔぁーなー	Silvaner	ジルヴァーナー
    じろんぐ	Geelong	ジロング
    じん	Gin	ジン
    じんふぁんでる	Zinfandel	ジンファンデル
    じゔり	Givry	ジヴリ
    じーあいぞーん	G.I. Zone	ジーアイ・ゾーン
    すいぇゔぇるなだるまちあ	Sjeverna Dalmacija	スイェヴェルナ・ダルマチア
    すいすろまんど	Suisse Romande	スイス・ロマンド
    すいっつぁーらんど	Switzerland	スイッツァーランド
    すいーと	Sweet	スイート
    すいーとしぇりー	Sweet Sherry	スイート・シェリー
    すお	Suau	スオ
    すかはべんち	Skaha Bench	スカハ・ベンチ
    すきあーゔぁ	Schiava	スキアーヴァ
    すきおっぺってぃーの	Schioppettino	スキオッペッティーノ
    すきんこんたくと	Skin contact	スキンコンタクト
    すこっとらんど	Scotland	スコットランド
    すたっぐすりーぷでぃすとりくと	Stags Leap District	スタッグス・リープ・ディストリクト
    すたっぐすりーぷわいんせらーず	Stag's Leap Wine Cellars	スタッグス・リープ・ワイン・セラーズ
    すたーる	Soutard	スタール
    すっぷりでぃりーぞ	Supplì di Riso	スップリ・ディ・リーゾ
    すてあ	Stir	ステア
    すてぃるとん	Stilton	スティルトン
    すてぃるとんちーず	Stilton Cheese	スティルトン・チーズ
    すてぃるわいん	Still wine	スティル・ワイン|スティルワイン
    すてぃーん	Steen	スティーン
    すてぃーゔんすぱりゅあ	Steven Spurrier	スティーヴン・スパリュア
    すてむ	Stem	ステム
    すてるゔぁん	STELVIN	ステルヴァン
    すてるゔぃん	Stelvin	ステルヴィン
    すてれんぼっしゅ	Stellenbosch	ステレンボッシュ
    すでゅいろー	Suduiraut	スデュイロー
    すとるのゔぃーの	Stolno vino	ストルノ・ヴィーノ
    すとるのゔぃーのさこんとろりらにむぽどりえとろむ	Stolno vino s kontroliranim podrijetlom	ストルノ・ヴィーノ・サ・コントロリラニム・ポドリエトロム
    すとるまゔぁれー	Struma Valley	ストルマ・ヴァレー
    すとろーからーど	Straw-colored	ストロー・カラード
    すねいくりゔぁーゔぁれー	Snake River Valley	スネイク・リヴァー・ヴァレー
    すねーくりゔぁーゔぁれー	Snake River Valley	スネーク・リヴァー・ヴァレー
    すぱげってぃあっらかるぼなーら	Spaghetti alla Carbonara	スパゲッティ・アッラ・カルボナーラ
    すぱげってぃあっれゔぉんごーれ	Spaghetti alle Vongole	スパゲッティ・アッレ・ヴォンゴーレ
    すぱげってぃこんいるたるとぅーふぉねーろ	Spaghetti con il Tartufo Nero	スパゲッティ・コン・イル・タルトゥーフォ・ネーロ
    すぱんな	Spanna	スパンナ
    すぱーくりんぐわいん	Sparkling wine	スパークリング・ワイン|スパークリングワイン
    すぱーぷるーにんぐ	Spur Pruning	スパー・プルーニング
    すぴりてゅー	spiritueux	スピリテュー
    すふぉるつぁーと	Sforzato	スフォルツァート
    すふぉるつぁーとでぃゔぁるてっりーな	Sforzato di Valtellina	スフォルツァート・ディ・ヴァルテッリーナ
    すぶりんつ	Sbrinz	スブリンツ
    すぷまんて	Spumante	スプマンテ
    すぷりんぐまうんてんでぃすとりくと	Spring Mountain District	スプリング・マウンテン・ディストリクト
    すぺいん	Spain	スペイン
    すぺしゃるれせるば	Special Reserva	スペシャル・レセルバ
    すぺりおーる	Superior	スペリオール
    すぺりおーれ	Superiore	スペリオーレ
    すまらくと	Smaragd	スマラクト
    すみすおーらふぃっと	Smith-Haut-Lafitte	スミス・オー・ラフィット
    すむーず	Smooth	スムーズ
    すらゔぉにあ	Slavonia	スラヴォニア
    すらゔぉにや	Slavonija	スラヴォニヤ
    すらゔぉにやいふるゔぁつこぽどぅなゔりぇ	Slavonija i Hrvatsko Podunavlje	スラヴォニヤ・イ・フルヴァツコ・ポドゥナヴリェ
    すれでぃにゃいゆじゅなだるまちあ	Srednja I Južna Dalmacija	スレディニャ・イ・ユジュナ・ダルマチア
    すろゔぇにあ	Slovenia	スロヴェニア
    すろーぷすおゔめりとん	Slopes of Meliton	スロープス・オヴ・メリトン
    すわんでぃすとりくと	Swan District	スワン・ディストリクト
    すわんひる	Swan Hill	スワン・ヒル
    すわーとらんど	Swartland	スワートランド
    すわーとらんどいんでぃぺんでんとぷろでゅーさーず	Swartland Independent Producers	スワートランド・インディペンデント・プロデューサーズ
    すゔぃつぇらいたりあーな	Svizzera Italiana	スヴィツェラ・イタリアーナ
    すゔぃり	Sviri	スヴィリ
    すゔぇれーと	Suvereto	スヴェレート
    すーず	Suze	スーズ
    すーてぃらーじゅ	Soutirage	スーティラージュ
    すーふる	Soufre	スーフル
    すーぶしょん	Sous-bouchon	スー・ブション
    すーぼわ	Sous bois	スー・ボワ
    ずぃつぁ	Zitsa	ズィツァ
    ずゅーす	Süß	ズュース
    ずゅーすれぜるゔぇ	Süßreserve	ズュースレゼルヴェ
    ずゅーとしゅたいやーまるく	Südsteiermark	ズュートシュタイヤーマルク
    ずらふてぃな	Žlahtina	ズラフティナ
    せいせる	Seyssel	セイセル
    せいべる	Seibel 4461|Seibel 4986|Seibel 5455|Seibel 5656|Seibel 6905|Seibel 9110|Seibel	セイベル
    せいべるごせんろっぴゃくごじゅうろく	Seibel 5656	セイベル・ゴセンロッピャクゴジュウロク
    せいゔぁる	Seyval	セイヴァル
    せいゔぁるぶらん	Seyval Blanc	セイヴァル・ブラン|セイヴァルブラン
    せかーのいんてりおーる	Secano Interior	セカーノ・インテリオール
    せくさーるど	Szekszárd	セクサールド
    せこ	Seco	セコ
    せしゃーじゅなちゅれる	Séchage naturel|séchage naturel	セシャージュ・ナチュレル
    せっく	Sec|sec	セック
    せっこ	Secco	セッコ
    せとぅーばる	Setúbal	セトゥーバル
    せとりんぐ	Settling	セトリング
    せにえ	Saignée	セニエ
    せねかれいく	Seneca Lake	セネカ・レイク
    せぱーじゅ	cépage	セパージュ
    せびーちぇ	Ceviche	セビーチェ
    せみじぇねりっく	Semi-Generic	セミ・ジェネリック
    せみせこ	Semi Seco|Semiseco	セミ・セコ|セミセコ
    せみせっこ	Semi Secco	セミ・セッコ
    せみどぅるせ	Semidulce	セミドゥルセ
    せみよん	Sémillon	セミヨン
    せらるんがだるば	Serralunga d'Alba	セラルンガ・ダルバ
    せりーぬ	Sérine	セリーヌ
    せるしある	Sercial	セルシアル
    せるしゅーるしぇーる	Selles-sur-Cher	セル・シュール・シェール
    せるゔぁどぅ	Servadou	セルヴァドゥ
    せるゔぃす	service	セルヴィス
    せれくしおんどぐらんのーぶる	Sélection de Grains Nobles	セレクシオン・ド・グラン・ノーブル
    せれさ	Cereza	セレサ
    せろんす	Cérons	セロンス
    せんしべる	Cencibel	センシベル
    せんとへれな	St. Helena	セント・ヘレナ
    せんとらるおたご	Central Otago	セントラル・オタゴ
    せんとらるおたごぴののわーるせれぶれーしょん	Central Otago Pinot Noir Celebration	セントラル・オタゴ・ピノ・ノワール・セレブレーション
    せんとらるぐりーす	Central Greece	セントラル・グリース
    せんとらるこーすと	Central Coast	セントラル・コースト
    せんとらるほーくすべい	Central Hawke's Bay	セントラル・ホークス・ベイ
    せんとらるゔぁれー	Central Valley	セントラル・ヴァレー
    ぜくと	Sekt	ゼクト
    ぜくとおーすとりあ	Sekt Austria	ゼクト・オーストリア
    ぜくとおーすとりあぐろっせれぜるゔぇ	Sekt Austria Grosse Reserve	ゼクト・オーストリア・グロッセ・レゼルヴェ
    ぜくとおーすとりあれぜるゔぇ	Sekt Austria Reserve	ゼクト・オーストリア・レゼルヴェ
    ぜくとべーあー	Sekt b.A.	ゼクト・ベーアー
    ぜむぷれーん	Zemplén	ゼムプレーン
    ぜんこうじ	Zenkoji	ゼンコウジ
    ぜーた	Zéta	ゼータ
    そあゔぇ	Soave	ソアヴェ
    そあゔぇすぺりおーれ	Soave Superiore	ソアヴェ・スペリオーレ
    そうざぉん	Sousão	ソウザォン
    そかるこす	Socalcos	ソカルコス
    そしえてどれこるたん	Société de Récoltants	ソシエテ・ド・レコルタン
    そっとちぇねーり	Sottoceneri	ソットチェネーリ
    そとろん	Sotolon	ソトロン
    そのまかうんてぃ	Sonoma County	ソノマ・カウンティ
    そのまこーすと	Sonoma Coast	ソノマ・コースト
    そぱであほ	Sopa de Ajo	ソパ・デ・アホ
    そぶれたぶら	Sobretabla	ソブレタブラ
    そぷらちぇねーり	Sopraceneri	ソプラチェネーリ
    そむりえーる	Sommelière	ソムリエール
    そもんたーの	Somontano	ソモンターノ
    そらーの	Solano	ソラーノ
    そるてぃどっぐ	Salty Dog	ソルティ・ドッグ
    そんだ	Zonda	ソンダ
    そー	Seau	ソー
    そーしにゃっく	Saussignac	ソーシニャック
    そーてぃんぐ	Sorting	ソーティング
    そーてるぬ	Sauternes	ソーテルヌ
    そーてるぬぷるみえくりゅ	Sauternes Premiers Cru	ソーテルヌ・プルミエ・クリュ
    そーみゅーる	Saumur	ソーミュール
    そーみゅーるしゃんぴにー	Saumur-Champigny	ソーミュール・シャンピニー
    そーみゅーるぴゅいのーとるだむ	Saumur Puy-Notre-Dame	ソーミュール・ピュイ・ノートル・ダム
    そーゔぃにゃっく	Sauvignac	ソーヴィニャック
    そーゔぃによなす	Sauvignonasse	ソーヴィニヨナス
    そーゔぃによん	Sauvignon	ソーヴィニヨン
    そーゔぃによんぐり	Sauvignon Gris	ソーヴィニヨン・グリ
    そーゔぃによんぶらん	Sauvignon Blanc	ソーヴィニヨン・ブラン
    そーゔぃによんゔぇーる	Sauvignon Vert	ソーヴィニヨン・ヴェール
    ぞっつぇんべるく	Zotzenberg	ゾッツェンベルク
    ぞんだ	Zonda	ゾンダ
    ぞーん	Zone	ゾーン
    ぞーんえー	Zone A	ゾーン・エー
    ぞーんしーいち	Zone C-Ⅰ	ゾーン・シー・イチ
    ぞーんびー	Zone B	ゾーン・ビー
    たい	Tai	タイ
    たいいんぐ	Tying	タイイング
    たいだるべい	Tidal Bay	タイダル・ベイ
    たいゆ	Taille	タイユ
    たうらーじ	Taurasi	タウラージ
    たころんてあせんてほ	Tacoronte-Acentejo	タコロンテ・アセンテホ
    たすとゔぁん	Tastevin	タストヴァン
    たすまにあ	Tasmania	タスマニア
    たっつぇれんげ	Tazzelenghe	タッツェレンゲ
    たな	Tannat	タナ
    たまよあさろまねあすか	Tămâioasă Românească	タマヨアサ・ロマネアスカ
    たやりん	Tajarin	タヤリン
    たらがんて	Talagante	タラガンテ
    たらごーな	Tarragona	タラゴーナ
    たらんす	Talence	タランス
    たるとぅーふぉねーろ	Tartufo Nero	タルトゥーフォ・ネーロ
    たるとぅーふぉびあんこだるば	Tartufo Bianco d'Alba	タルトゥーフォ・ビアンコ・ダルバ
    たるとたたん	Tarte Tatin	タルト・タタン
    たるとふらんべ	Tarte Flambée	タルトフランベ
    たるばっは	Tulbagh	タルバッハ
    たるぼ	Talbot	タルボ
    たれっじょ	Taleggio	タレッジョ
    たんくめそっど	Tank Method	タンク・メソッド
    たんばらんば	Tumbarumba	タンバランバ
    たんぺれ	Tempéré	タンペレ
    たゔぇる	Tavel	タヴェル
    たゔぉらゔぁろーざ	Távora-Varosa	タヴォラ・ヴァローザ
    たーびるく	Tahbilk	タービルク
    たーふぇるしゅぴっつ	Tafelspitz	ターフェルシュピッツ
    だいあせちる	Diacetyl	ダイアセチル
    だいやもんどまうんてんでぃすとりくと	Diamond Mountain District	ダイヤモンド・マウンテン・ディストリクト
    だうにーみるでゅー	Downy mildew	ダウニー・ミルデュー
    だすと	Dust	ダスト
    だっそー	Dassault	ダッソー
    だにゅーぶぷれいん	Danube Plain	ダニューブ・プレイン
    だにゅーぶぷれいんぴーじーあい	Danube Plain P.G.I.	ダニューブ・プレイン・ピージーアイ
    だふねす	Dafnes	ダフネス
    だぶるまぐなむ	Double-magnum	ダブル・マグナム
    だらまん	d'Allaman	ダラマン
    だるしゅ	d'Arche	ダルシュ
    だるまいやっく	d'Armailhac	ダルマイヤック
    だるまちあ	Dalmacija	ダルマチア
    だるまてぃあ	Dalmatia	ダルマティア
    だん	Dão	ダン
    だんでぃひるず	Dundee Hills	ダンディ・ヒルズ
    だーじりん	Darjeeling	ダージリン
    だーにぼーる	Darnibole	ダーニボール
    だーにぼーるわいん	Darnibole Wine	ダーニボール・ワイン
    だーりん	Darling	ダーリン
    ちぇざねーぜ	Cesanese	チェザネーゼ
    ちぇざねーぜでるぴーりお	Cesanese del Piglio	チェザネーゼ・デル・ピーリオ
    ちぇだー	Cheddar	チェダー
    ちぇだーちーず	Cheddar Cheese	チェダーチーズ
    ちぇらすおーろでぃゔぃっとーりあ	Cerasuolo di Vittoria	チェラスオーロ・ディ・ヴィットーリア
    ちぇるせぎふゅーせれしゅ	Cserszegi Fűszeres	チェルセギ・フューセレシュ
    ちちゃ	Chicha	チチャ
    ちなーる	Cynar	チナール
    ちびーと	Chivito	チビート
    ちゃいるずゔぁれー	Chiles Valley	チャイルズ・ヴァレー
    ちゃこり	Chacolí	チャコリ
    ちゃこりでげたりあ	Chacolí de Getaria	チャコリ・デ・ゲタリア
    ちゃちゃ	Chacha	チャチャ
    ちゃぺるだうん	Chapel Down	チャペル・ダウン
    ちゃれっろ	Xarel·lo	チャレッロ
    ちゅあらてぃんひるず	Tualatin Hills	チュアラティン・ヒルズ
    ちゅっぴん	Ciuppin	チュッピン
    ちゅまい	Ciumai	チュマイ
    ちゅり	Churi	チュリ
    ちゅーりっひ	Zürich	チューリッヒ
    ちょあぱゔぁれー	Choapa Valley	チョアパ・ヴァレー
    ちょんぐらーど	Csongrád	チョングラード
    ちょーくひる	Chalk Hill	チョーク・ヒル
    ちり	Chile	チリ
    ちるど	Chilled	チルド
    ちろ	Cirò	チロ
    ちろーす	tyloses	チロース
    ちんくえてっれ	Cinque Terre	チンクエ・テッレ
    ちんくえてっれしゃっけとら	Cinque Terre Sciacchetrà	チンクエ・テッレ・シャッケトラ
    ちんざーの	Cinzano	チンザーノ
    ちゔぃちぇっく	Cviček	チヴィチェック
    ちーぼ	cibo	チーボ
    つぁめとふか	Zametovka	ツァメトフカ
    つぃあふぁんどらー	Zierfandler	ツィアファンドラー
    つぃつか	Tsitska	ツィツカ
    つぇりになっくかしゅてらんすき	Crljenak Kastelanski	ツェリニナック・カシュテランスキ
    つぉりこうり	Tsolikouri	ツォリコウリ
    つびーべるくーへん	Zwiebelkuchen	ツビーベルクーヘン
    つるのゔぃーの	crno vino	ツルノ・ヴィーノ
    つゔぁいげると	Zweigelt	ツヴァイゲルト
    てぃあ	Tear	ティア
    てぃえど	Tiède	ティエド
    てぃおぺぺ	TIO PEPE	ティオ・ペペ
    てぃちーの	Ticino	ティチーノ
    てぃゆーる	Tilleul	ティユール
    てぃらーじゅ	Tirage	ティラージュ
    てぃんたあまれら	Tinta Amarela	ティンタ・アマレラ
    てぃんたでとろ	Tinta de Toro	ティンタ・デ・トロ
    てぃんたでまどりーど	Tinta de Madrid	ティンタ・デ・マドリード
    てぃんたでるぱいす	Tinta del País	ティンタ・デル・パイス
    てぃんたねぐら	Tinta Negra	ティンタ・ネグラ
    てぃんたばろっか	Tinta Barroca	ティンタ・バロッカ
    てぃんたろりす	Tinta Roriz	ティンタ・ロリス
    てぃんてぃりあ	Tintilia	ティンティリア
    てぃんとふぃの	Tinto Fino	ティント・フィノ
    てぃー	Tea	ティー
    てぃーるぶしょん	Tire-bouchon	ティール・ブション
    てぃーれみったんす	T Remittance	ティー・レミッタンス
    ていまーゔぁれー	Tamar Valley	テイマー・ヴァレー
    てきーら	Tequila	テキーラ
    てっとどもわんぬ	Tête de Moine	テット・ド・モワンヌ
    てっれあるふぃえーり	Terre Alfieri	テッレ・アルフィエーリ
    てっれとっれーじ	Terre Tollesi	テッレ・トッレージ
    てぴっど	Tepid	テピッド
    てゅるさん	Tursan	テュルサン
    てらあるた	Terra Alta	テラ・アルタ
    てらすだべいら	Terras da Beira	テラス・ダ・ベイラ
    てらすでゅらるざっく	Terrasses du Larzac	テラス・デュ・ラルザック
    てらすどだん	Terras do Dão	テラス・ド・ダン
    てらっせんもーぜる	Terassenmosel	テラッセンモーゼル
    てらん	Teran	テラン
    てらんてす	Terrantez	テランテス
    てりあに	Teliani	テリアニ
    てるとる	Tertre	テルトル
    てるめんれぎおん	Thermenregion	テルメンレギオン
    てるもめーとる	Thermomètre	テルモメートル
    てれのわーる	Terret Noir	テレ・ノワール
    てろるでご	Teroldego	テロルデゴ
    てんぷらにーりょ	Tempranillo	テンプラニーリョ
    てんぺれーと	Temperate	テンペレート
    てーじょ	Tejo	テージョ
    であるりれもるどゔぇい	Dealurile Moldovei	デアルリレ・モルドヴェイ
    でぃけむ	d'Yquem	ディケム
    でぃじぇすてぃふ	Digestif	ディジェスティフ
    でぃじょんくろーん	Dijon clone	ディジョン・クローン
    でぃすごーじめんと	Disgorgement	ディスゴージメント
    でぃすてむ	Destem	ディステム
    でぃすとりくと	District	ディストリクト
    でぃすとりくとぅすふんがりくすこんとろっらーとぅす	Districtus Hungaricus Controllatus	ディストリクトゥス・フンガリクス・コントロッラートゥス
    でぃすとりくとわいんず	District Wines	ディストリクト・ワインズ
    でぃそあーゔぇ	di Soave	ディ・ソアーヴェ
    でぃぞるゔどおきしじぇん	Dissolved Oxygen	ディゾルヴド・オキシジェン
    でぃっさん	d'Issan	ディッサン
    でぃっぺくーへん	Dippekuchen	ディッペクーヘン
    でぃひりんぐ	Dehilling	ディヒリング
    でぃみゃっと	Dimyat	ディミャット
    でぃんぶら	Dimbula	ディンブラ
    でぃゔぃん	Divin	ディヴィン
    でぃーあーるしー	drc	ディーアールシー
    でぃーおー	D.O.	ディーオー
    でぃーおーしー	D.O.C.	ディーオーシー
    でぃーおーしーえい	D.O.Ca.	ディーオーシーエイ
    でぃーおーしーしーあいびー	D.O.C.-CIB	ディーオーシー・シーアイビー
    でぃーおーしーしーえむてぃー	D.O.C.-CMT	ディーオーシー・シーエムティー
    でぃーおーしーしーえむでぃー	D.O.C.-CMD	ディーオーシー・シーエムディー
    でぃーおーしーしーてぃー	D.O.C.-CT	ディーオーシー・シーティー
    でぃーおーしーじー	D.O.C.G.	ディーオーシージー
    でぃーおーぴー	D.O.P.	ディーオーピー
    でぃーぷるーつこーありしょん	Deep Roots Coalition	ディープ・ルーツ・コーアリション
    でかんたー	Decanter	デカンター
    でぎゅすたしおん	dégustation	デギュスタシオン
    でごるじゅまん	Dégorgement	デゴルジュマン
    でざれ	Dézaley	デザレ
    でしゃらんと	des Charentes	デ・シャラント
    でじぇうのゔぃの	Deželno vino	デジェウノ・ヴィノ
    ですみらいゆ	Desmirail	デスミライユ
    でだぜ	dedaze	デダゼ
    でぬみれでおりじねこんとろらた	Denumire de Origine Controlată	デヌミレ・デ・オリジネ・コントロラタ
    でのみなさうんでおりじぇんこんとろらだ	Denominação de Origem Controlada	デノミナサウン・デ・オリジェン・コントロラダ
    でのみなしおんでおりへん	Denominación de Origen	デノミナシオン・デ・オリヘン
    でのみなしおんでおりへんかりふぃかだ	Denominación de Origen Calificada	デノミナシオン・デ・オリヘン・カリフィカダ
    でのみなしおんでおりへんこんとろらだ	Denominacion de Origen Controlada	デノミナシオン・デ・オリヘン・コントロラダ
    でのみなつぃおーねでぃおりじねこんとろっらーた	Denominazione di Origine Controllata	デノミナツィオーネ・ディ・オリジネ・コントロッラータ
    でのみなつぃおーねでぃおりじねこんとろっらーたえがらんてぃーた	Denominazione di Origine Controllata e Garantita	デノミナツィオーネ・ディ・オリジネ・コントロッラータ・エ・ガランティータ
    でびな	Debina	デビナ
    でびゅたーじゅ	Débuttage	デビュタージュ
    でぶるばーじゅ	Débourbage	デブルバージュ
    でぶーるまん	Débourrement	デブールマン
    でゅあーるみろんろーとしると	Duhart-Milon-Rothschild	デュアール・ミロン・ロートシルト
    でゅくりゅぼーかいゆ	Ducru-Beaucaillou	デュクリュ・ボーカイユ
    でゅしぇでゅぜす	Duché d'Uzès	デュシェ・デュゼス
    でゅぼね	Dubonnet	デュボネ
    でゅらす	Duras	デュラス
    でゅるふぉーるゔぃゔぁん	Durfort-Vivens	デュルフォール・ヴィヴァン
    でらうぇあ	Delaware	デラウェア
    でれくみるん	Derek Milne	デレク・ミルン
    でゔぉん	Devon	デヴォン
    とぅいる	Tuile	トゥイル
    とぅいれ	Tuilé	トゥイレ
    とぅっるむ	Tullum	トゥッルム
    とぅとぅべんゔぁれー	Tutuvén Valley	トゥトゥベン・ヴァレー
    とぅぬやん	Tunuyán	トゥヌヤン
    とぅぷんがーと	Tupungato	トゥプンガート
    とぅらんがわえわえ	Turangawaewae	トゥランガワエワエ
    とぅりがなしおなる	Touriga Nacional	トゥリガ・ナシオナル
    とぅるそー	Trousseau	トゥルソー
    とぅるぶりゃん	Trbljan	トゥルブリャン
    とぅーふぉ	Tufo	トゥーフォ
    とぅーるがう	Thurgau	トゥールガウ
    とぅーるしゅーるまるぬ	Tours sur Marne	トゥール・シュール・マルヌ
    とぅーれーぬ	Touraine	トゥーレーヌ
    とぅーれーぬむすー	Touraine Mousseux	トゥーレーヌ・ムスー
    とうりがなしょなる	Touriga Nacional	トウリガ・ナショナル
    とうりがふらんか	Touriga Franca	トウリガ・フランカ
    とうりがふらんせーざ	Touriga Francesa	トウリガ・フランセーザ
    とかい	Tokaj	トカイ
    とかいあすー	Tokaj Aszú	トカイ・アスー
    とかいふりうらーの	Tocai Friulano	トカイ・フリウラーノ
    とかいへじゃいや	Tokaj-hegyalja	トカイ・ヘジャイヤ
    とすかーな	Toscana	トスカーナ
    とすかーの	Toscano	トスカーノ
    とのー	Tonneau	トノー
    とぱーく	Topaque	トパーク
    とらきあゔぁれー	Thracian Valley	トラキア・ヴァレー
    とらじゃ	Traja	トラジャ
    とらでぃしょなるめそっど	Traditional Method	トラディショナル・メソッド
    とらみなっつ	Traminac	トラミナッツ
    とらみねーるあろまてぃこ	Traminer Aromatico	トラミネール・アロマティコ
    とらんすふぁーめそっど	Transfer Method	トランスファー・メソッド
    とらんすもんたーの	Transmontano	トランスモンターノ
    とりあーじゅでれざん	Triage des raisins	トリアージュ・デ・レザン
    とりえすて	Trieste	トリエステ
    とりびどらぐ	Tribidrag	トリビドラグ
    とるじゃーの	Torgiano	トルジャーノ
    とるじゃーのろっそりぜるゔぁ	Torgiano Rosso Riserva	トルジャーノ・ロッソ・リゼルヴァ
    とるな	Tolna	トルナ
    とれいしゃどぅーら	Treixadura	トレイシャドゥーラ
    とれいーぞ	Treiso	トレイーゾ
    とれすゔぇどらす	Torres Vedras	トレス・ヴェドラス
    とれっびあーの	Trebbiano	トレッビアーノ
    とれっびあーのあぶるっつぇーぜ	Trebbiano Abruzzese	トレッビアーノ・アブルッツェーゼ
    とれっびあーのとすかーの	Trebbiano Toscano	トレッビアーノ・トスカーノ
    とれっびあーのろまにょーろ	Trebbiano Romagnolo	トレッビアーノ・ロマニョーロ
    とれぱっと	Trepat	トレパット
    とれべりん	Trevelin	トレベリン
    とれんてぃーの	Trentino	トレンティーノ
    とれんてぃーのあるとあーでぃじぇ	Trentino-Alto Adige	トレンティーノ・アルト・アーディジェ
    とれんと	Trento	トレント
    とろ	Toro	トロ
    とろっけん	Trocken	トロッケン
    とろっけんべーれんあうすれーぜ	Trockenbeerenauslese	トロッケンベーレンアウスレーゼ
    とろりんがー	Trollinger	トロリンガー
    とろろんもんど	Troplong Mondot	トロロン・モンド
    とろわざべいゆ	trois abeilles	トロワ・ザベイユ
    とろわぜとわーる	Trois Etoiles	トロワ・ゼトワール
    とろわぽむ	Trois Pommes	トロワ・ポム
    とろんてす	Torrontés	トロンテス
    とろんてすりおはーの	Torrontés Riojano	トロンテス・リオハーノ
    とーたるぱっけーじおきしじぇん	Total Package Oxygen	トータル・パッケージ・オキシジェン
    とーにー	Tawny	トーニー
    どいちゃーぜくと	Deutscher Sekt	ドイチャー・ゼクト
    どいちゅしゅゔぁいつ	Deutschschweiz	ドイチュシュヴァイツ
    どいちゅらんと	Deutschland	ドイチュラント
    どぅざべいゆ	deux abeilles	ド・ゥザベイユ
    どぅじえむくりゅ	Deuxièmes Cru	ドゥジエム・クリュ
    どぅな	Duna	ドゥナ
    どぅなてぃさくずぃ	Duna-Tisza közi|Duna-Tisza Közi	ドゥナ・ティサ・クズィ
    どぅなーんとぅーり	Dunántúli	ドゥナーントゥーリ
    どぅなーんとぅーる	Dunántúl	ドゥナーントゥール
    どぅみせっく	Demi-Sec	ドゥミ・セック
    どぅりえんせ	Duriense	ドゥリエンセ
    どぅるせ	Dulce	ドゥルセ
    どぅー	Doux	ドゥー
    どぅーじえーむふぇるまんたしおんあんぶていゆ	Deuxième Fermentation en Bouteille	ドゥージエーム・フェルマンタシオン・アン・ブテイユ
    どぅーすのわーる	Douce Noire	ドゥース・ノワール
    どうろ	Douro	ドウロ
    どうろすぺりおーる	Douro Superior	ドウロ・スペリオール
    どくたー	Doctor	ドクター
    どさーじゅ	Dosage	ドサージュ
    どさーじゅぜろ	Dosage Zéro	ドサージュ・ゼロ
    どてーじょ	Do Tejo	ド・テージョ
    どなうぷれいん	Danube Plain	ドナウ・プレイン
    どなうりーすりんぐ	Donauriesling	ドナウリースリング
    どなうゔぇるとりーなー	Donauveltliner	ドナウヴェルトリーナー
    どぶりちっち	Dobricic|Dobričić	ドブリチッチ
    どみな	Domina	ドミナ
    どみぶていゆ	Demi-Bouteille	ドミ・ブテイユ
    どめーぬたかひこ	Domaine Takahiko	ドメーヌ・タカヒコ
    どめーぬどしゅゔぁりえ	Domaine de Chevalier	ドメーヌ・ド・シュヴァリエ
    どめーぬどらろまねこんてぃ	Domaine de la Romanée-Conti	ドメーヌ・ド・ラ・ロマネ・コンティ
    どめーぬぶろんずぺーるえふぃす	Domaine Bronze Père et Fils	ドメーヌ・ブロンズ・ペール・エ・フィス
    どめーぬもん	Domaine Mont	ドメーヌ・モン
    どもんたーにゅ	Deux-Montagnes	ド・モンターニュ
    どらい	Dry	ドライ
    どらいいんぐ	drying	ドライイング
    どらいくりーくゔぁれー	Dry Creek Valley	ドライ・クリーク・ヴァレー
    どらいしぇりー	Dry Sherry	ドライ・シェリー
    どらいゔぇるもっと	Dry Vermouth	ドライ・ヴェルモット
    どらん	Dorin	ドラン
    どらんぶい	Drambuie	ドランブイ
    どりあーに	Dogliani	ドリアーニ
    どりっぷいりげーしょん	Drip Irrigation	ドリップ・イリゲーション
    どるちぇ	Dolce	ドルチェ
    どるちぇっと	Dolcetto	ドルチェット
    どるんふぇるだー	Dornfelder	ドルンフェルダー
    どわじーでゅぶろか	Doisy-Dubroca	ドワジー・デュブロカ
    どわじーでーぬ	Doisy Daëne	ドワジー・デーヌ
    どーざっく	Dauzac	ドーザック
    どーせっと	Dorset	ドーセット
    どーる	Dôle	ドール
    どーるぶらんしゅ	Dôle Blanche	ドール・ブランシュ
    ないあがら	Niagara	ナイアガラ
    ないあがらえすかーぷめんと	Niagara Escarpment	ナイアガラ・エスカープメント
    ないあがらおんざれいく	Niagara-on-the-Lake	ナイアガラ・オン・ザ・レイク
    ないあがらぺにんしゅら	Niagara Peninsula	ナイアガラ・ペニンシュラ
    ないあがらりゔぁー	Niagara River	ナイアガラ・リヴァー
    ないあがられいくしょあ	Niagara Lakeshore	ナイアガラ・レイクショア
    ないつゔぁれー	Knights Valley	ナイツ・ヴァレー
    ないてぃんばー	Nyetimber	ナイティンバー
    なうさ	Naoussa	ナウサ
    ながの	Nagano	ナガノ
    なちゅれ	Naturé	ナチュレ
    なとぅーあへるぷ	Naturherb	ナトゥーアヘルプ
    なばーら	Navarra	ナバーラ
    なぱ	Napa	ナパ
    なぱかうんてぃ	Napa County	ナパ・カウンティ
    なぱゔぁれー	Napa Valley	ナパ・ヴァレー
    なびゅこどのぞーる	Nabuchodonosor	ナビュコドノゾール
    なぽれおん	Napoléon	ナポレオン
    なみずのゔぃーの	Namizno vino	ナミズノ・ヴィーノ
    ならまたべんち	Naramata Bench	ナラマタ・ベンチ
    なーえ	Nahe	ナーエ
    にえるっちょ	Nielluccio	ニエルッチョ
    にくてり	Nychteri	ニクテリ
    にっつぁ	Nizza	ニッツァ
    にゅいさんじょるじゅ	Nuits-Saint-Georges	ニュイ・サン・ジョルジュ
    にゅるんべるがーぶらーとぶるすと	Nürnberger Bratwurst	ニュルンベルガー・ブラートブルスト
    にゅーいんぐらんどおーすとらりあ	New England Australia	ニュー・イングランド・オーストラリア
    にゅーさうすうぇーるず	New South Wales	ニュー・サウス・ウェールズ
    にゅーじーらんど	New Zealand	ニュージーランド
    にゅーよーく	New York	ニューヨーク
    にょら	Ñora	ニョラ
    にーす	Nice	ニース
    にーだーえすたーらいひ	Niederösterreich	ニーダーエスターライヒ
    にーるしゅたいん	Nierstein	ニールシュタイン
    ぬえぞん	Nouaison	ヌエゾン
    ぬーしゃてる	Neuchâtel	ヌーシャテル
    ぬーしゃてるのんふぃるとれ	Neuchâtel Non Filtré	ヌーシャテル・ノン・フィルトレ
    ぬーふしゃてる	Neufchâtel	ヌーフシャテル
    ぬーゔぉー	Nouveau	ヌーヴォー
    ねいゔぇ	Neive	ネイヴェ
    ねぐらもる	Negramoll	ネグラモル
    ねぐるでどらがしゃに	Negru de Drăgăşani	ネグル・デ・ドラガシャニ
    ねぐれっと	Négrette	ネグレット
    ねぐろあまーろ	Negroamaro	ネグロアマーロ|ネグロ・アマーロ
    ねごしあんでぃすとりびゅとぅーる	Négociant-Distributeur	ネゴシアン・ディストリビュトゥール
    ねごしあんまにぴゅらん	Négociant-Manipulant	ネゴシアン・マニピュラン
    ねごすか	Negoska	ネゴスカ
    ねっびあ	Nebbia	ネッビア
    ねっびおーろ	Nebbiolo	ネッビオーロ
    ねめあ	Nemea	ネメア
    ねらっく	Nairac	ネラック
    ねるそん	Nelson	ネルソン
    ねれっろかっぷっちょ	Nerello Cappuccio	ネレッロ・カップッチョ
    ねれっろますかれーぜ	Nerello Mascarese	ネレッロ・マスカレーゼ
    ねろだゔぉら	Nero d'Avola	ネロ・ダヴォラ
    ねーろだゔぉら	Nero d'Avola	ネーロ・ダヴォラ
    ねーろでぃとろいあ	Nero di Troia	ネーロ・ディ・トロイア
    のいじーどらーぜー	Neusiedlersee	ノイジードラーゼー
    のいぶるがー	Neuburger	ノイブルガー
    のじおーら	Nosiola	ノジオーラ
    のまこるく	Nomacork	ノマコルク
    のるて	Norte	ノルテ
    のんみれじめ	Non Millésimé	ノン・ミレジメ
    のんゔぃんてーじ	Non Vintage	ノンヴィンテージ
    のゔぁすこーしあ	Nova Scotia	ノヴァ・スコーシア
    のーざんあいるらんど	Northern Ireland	ノーザン・アイルランド
    のーざんけーぷ	Northern Cape	ノーザン・ケープ
    のーすかんたべりー	North Canterbury	ノース・カンタベリー
    のーすこーすと	North Coast	ノース・コースト
    のーすふぉーくおゔろんぐあいらんど	North Fork of Long Island	ノース・フォーク・オヴ・ロング・アイランド
    のーすらんど	Northland	ノースランド
    のーとん	Norton	ノートン
    のーぶる	Noble	ノーブル
    はうあーぜくと	Hauersekt	ハウアーゼクト
    はうえるまうんてん	Howell Mountain	ハウエル・マウンテン
    はってんはいむ	Hattenheim	ハッテンハイム
    はどそんりゔぁーりーじょん	Hudson River Region	ハドソン・リヴァー・リージョン
    はらーすれー	Halászlé	ハラースレー
    はるぷとろっけん	Halbtrocken	ハルプトロッケン
    はんがりー	Hungary	ハンガリー
    はんぎ	Hangi	ハンギ
    はんたー	Hunter	ハンター
    はんたーせみよん	Hunter Semillon	ハンター・セミヨン
    はんたーゔぁれー	Hunter Valley	ハンター・ヴァレー
    はんとしゅとらいひ	Handstreich	ハントシュトライヒ
    はんぶるぐますかっと	Hamburg Muscat	ハンブルグ・マスカット
    はんぶるどん	Hambledon	ハンブルドン
    はんぷしゃー	Hampshire	ハンプシャー
    はーふぇる	Havel	ハーフェル
    はーるしゅれゔぇりゅー	Hárslevelű	ハールシュレヴェリュー
    はーゔぇすと	Harvest	ハーヴェスト
    ばあるまにゃっく	Bas-Armagnac	バ・アルマニャック
    ばいおだいゔぁーしてぃ	Biodiversity	バイオダイヴァーシティ
    ばいしょこるご	Baixo Corgo	バイショ・コルゴ
    ばいす	Weiß	バイス
    ばいらーだ	Bairrada	バイラーダ
    ばいらーだあとらんてぃこ	Bairrada Atlântico	バイラーダ・アトランティコ
    ばいんぐーと	Weingut	バイングート
    ばが	Baga	バガ
    ばこぶらん	Baco Blanc	バコ・ブラン
    ばじぇすかるちゃきえす	Valles Calchaquíes	バジェス・カルチャキエス
    ばじぇでうこ	Valle de Uco	バジェ・デ・ウコ
    ばじぇでかふぁやて	Valle de Cafayate	バジェ・デ・カファヤテ
    ばじりかーた	Basilicata	バジリカータ
    ばじりこじぇのゔぇーぜ	Basilico Genovese	バジリコ・ジェノヴェーゼ
    ばすたるど	Bastardo	バスタルド
    ばずびーくろーん	Busby clone	バズビー・クローン
    ばたいえ	Batailley	バタイエ
    ばたーるもんらっしぇ	Bâtard-Montrachet	バタール・モンラッシェ
    ばだちょにー	Badacsony	バダチョニー
    ばっかす	Bacchus	バッカス
    ばっくへんどぅる	Backhendl	バックヘンドゥル
    ばっさーびりっひ	Wasserbillig	バッサービリッヒ
    ばっどばーすと	Budburst	バッドバースト
    ばっふす	Bacchus	バッフス
    ばとなーじゅ	Bâtonnage	バトナージュ
    ばなと	Banat	バナト
    ばにゅるす	Banyuls	バニュルス
    ばにゅるすぐらんくりゅ	Banyuls Grand Cru	バニュルス・グラン・クリュ
    ばにゅるすぐらんくりゅおーるだーじゅ	Banyuls Grand Cru hors d'âge	バニュルス・グラン・クリュ・オール・ダージュ
    ばにゅるすぐらんくりゅらんしお	Banyuls Grand Cru Rancio	バニュルス・グラン・クリュ・ランシオ
    ばのん	Banon	バノン
    ばびっち	Babic	バビッチ
    ばべあすかねあぐら	Băbească Neagră	バベアスカ・ネアグラ
    ばめどっく	Bas Médoc	バ・メドック
    ばらか	Baraka	バラカ
    ばらとん	Balaton	バラトン
    ばらとんめっれーき	Balatonmelléki	バラトンメッレーキ
    ばりぇでらおろたば	Valle de la Orotava	バリェ・デ・ラ・オロタバ
    ばりっく	Barrique	バリック
    ばりーざーとろっけんふらいしゅ	Walliser Trockenfleisch	バリーザー・トロッケンフライシュ
    ばるさっく	Barsac	バルサック
    ばるたざーる	Balthazar	バルタザール
    ばるでおーらす	Valdeorras	バルデオーラス
    ばるでぺーにゃす	Valdepeñas	バルデペーニャス
    ばるどりーの	Bardolino	バルドリーノ
    ばるどりーのすぺりおーれ	Bardolino Superiore	バルドリーノ・スペリオーレ
    ばるばれすこ	Barbaresco	バルバレスコ
    ばるばろっさ	Barbarossa	バルバロッサ
    ばるぱらいそ	Valparaíso	バルパライソ
    ばるべーら	Barbera	バルベーラ
    ばるべーらだすてぃ	Barbera d'Asti	バルベーラ・ダスティ
    ばるべーらだるば	Barbera d'Alba	バルベーラ・ダルバ
    ばるべーらでるもんふぇっらーと	Barbera del Monferrato	バルベーラ・デル・モンフェッラート
    ばるべーらでるもんふぇっらーとすぺりおーれ	Barbera del Monferrato Superiore	バルベーラ・デル・モンフェッラート・スペリオーレ
    ばれる	Barrel	バレル
    ばれるふぁーめんていしょん	Barrel fermentation	バレル・ファーメンテイション
    ばれんしあ	Valencia	バレンシア
    ばろっさ	Barossa	バロッサ
    ばろっされんじ	Barossa Range	バロッサ・レンジ
    ばろっさゔぁれー	Barossa Valley	バロッサ・ヴァレー
    ばろーろ	Barolo	バローロ
    ばろーろきなーと	Barolo Chinato	バローロ・キナート
    ばろーろりぜるゔぁ	Barolo Riserva	バローロ・リゼルヴァ
    ばんどーる	Bandol	バンドール
    ばーくしゃー	Berkshire	バークシャー
    ばーでぃっしゅろーとごると	Badisch Rotgold	バーディッシュ・ロートゴルト
    ばーでん	Baden	バーデン
    ばーにゃかうだ	Bagna Cauda	バーニャ・カウダ
    ぱいさんどぅー	Paysandú	パイサンドゥー
    ぱいす	Pais	パイス
    ぱいすばすこ	País Vasco	パイス・バスコ
    ぱいゆ	Paille	パイユ
    ぱうあ	Paua	パウア
    ぱうだりーみるでゅー	Powdery mildew	パウダリー・ミルデュー
    ぱしゅらんくでゅゔぃくびる	Pacherenc du Vic-Bilh	パシュランク・デュ・ヴィク・ビル
    ぱしゅらんくでゅゔぃくびるせっく	Pacherenc du Vic-Bilh Sec	パシュランク・デュ・ヴィク・ビル・セック
    ぱすくあるありあげ	Pascual Harriague	パスクアル・アリアゲ
    ぱそろぶれす	Paso Robles	パソ・ロブレス
    ぱたごにあ	Patagonia	パタゴニア
    ぱたまれす	Patamares	パタマレス
    ぱっしーと	Passito	パッシート
    ぱっせりーな	Passerina	パッセリーナ
    ぱっどさうぇい	Padthaway	パッドサウェイ
    ぱとらす	Patras	パトラス
    ぱとりっくでゅくるのー	Patrick Ducournau	パトリック・デュクルノー
    ぱとりもにお	Patrimonio	パトリモニオ
    ぱどぜ	Pas Dosé	パ・ドゼ
    ぱにえ	Panier	パニエ
    ぱぶろもらんで	Pablo Morande	パブロ・モランデ
    ぱぷくれまん	Pape Clément	パプ・クレマン
    ぱぺゔぉーどわ	Papet Vaudois	パペ・ヴォードワ
    ぱみっど	Pamid	パミッド
    ぱらへ	Paraje	パラヘ
    ぱらる	Parral	パラル
    ぱるでぃーな	Pardina	パルディーナ
    ぱるぷ	Pulp	パルプ
    ぱるみじゃーのれっじゃーの	Parmigiano Reggiano	パルミジャーノ・レッジャーノ
    ぱるめ	Palmer	パルメ
    ぱるめら	Palmela	パルメラ
    ぱれっと	Palette	パレット
    ぱれりゃーだ	Parellada	パレリャーダ
    ぱろこるたーど	Palo Cortado	パロ・コルタード
    ぱろす	Paros	パロス
    ぱろみの	Palomino	パロミノ
    ぱろーつれゔぇしゅ	Palócleves	パローツレヴェシュ
    ぱんこんとまて	Pan con Tomate	パン・コン・トマテ
    ぱんさぶらんか	Pansa Blanca	パンサ・ブランカ
    ぱんちんぐだうん	Punching down	パンチング・ダウン
    ぱんてっれりあ	Pantelleria	パンテッレリア
    ぱんでぴす	Pain d'épices	パン・デピス
    ぱんのん	Pannon	パンノン
    ぱんぴんぐおーゔぁー	Pumping over	パンピング・オーヴァー
    ぱゔぃ	Pavie	パヴィ
    ぱゔぃまかん	Pavie Macquin	パヴィ・マカン
    ぱゔろーゔぁ	Pavlova	パヴローヴァ
    ぱーすひるず	Perth Hills	パース・ヒルズ
    ぱーる	Paarl	パール
    ひゅーます	Humus	ヒューマス
    ひりんぐ	Hilling	ヒリング
    ひるおゔぐれいす	Hill of Grace	ヒル・オヴ・グレイス
    ひんめるうんとえるで	Himmel und Erde	ヒンメル・ウント・エルデ
    ひーすこーと	Heathcote	ヒースコート
    びあんか	Bianca	ビアンカ
    びあんゔにゅばたーるもんらっしぇ	Bienvenues-Bâtard-Montrachet	ビアンヴニュ・バタール・モンラッシェ
    びうら	Viura	ビウラ
    びえほ	Viejo	ビエホ
    びえるそ	Bierzo	ビエルソ
    びえーる	bière	ビエール
    びおでぃなみー	Biodynamie	ビオディナミー
    びおびお	Biobío	ビオ・ビオ
    びおびおゔぁれー	Bío Bío Valley	ビオ・ビオ・ヴァレー
    びすきゅいろーずどらんす	Biscuit Rose de Reims	ビスキュイ・ローズ・ド・ランス
    びすこいとす	Biscoitos	ビスコイトス
    びすてっかあっらぴっつぁいおーら	Bistecca alla Pizzaiola	ビステッカ・アッラ・ピッツァイオーラ
    びすてっかあっらふぃおれんてぃーな	Bistecca alla Fiorentina	ビステッカ・アッラ・フィオレンティーナ
    びたーず	Bitters	ビターズ
    びにぇどしんぐらーる	Viñedo Singular	ビニェド・シングラール
    びにされむ	Binissalem	ビニサレム
    びのすでまどりーど	Vinos de Madrid	ビノス・デ・マドリード
    びふぇるの	Biferno	ビフェルノ
    びゅじぇ	Bugey	ビュジェ
    びゅじぇもんたにゅー	Bugey Montagnieu	ビュジェ・モンタニュー
    びゅぜ	Buzet	ビュゼ
    びゅたーじゅ	Buttage	ビュタージュ
    びるおゔれーでぃんぐ	Bill of Lading	ビル・オヴ・レーディング
    びるとしゅばいんぶらーてん	Wildschweinbraten	ビルトシュバインブラーテン
    びるど	Build	ビルド
    びんげん	Bingen	ビンゲン
    びんつぁー	Winzer	ビンツァー
    びんつぁーげのっせんしゃふと	Winzergenossenschaft	ビンツァーゲノッセンシャフト
    びーちわーす	Beechworth	ビーチワース
    びーなーしゅにっつぇる	Wiener Schnitzel	ビーナー・シュニッツェル
    びーにゃくらしふぃかーだ	Viña Clasificada	ビーニャ・クラシフィカーダ
    びーにょ	VIGNO	ビーニョ
    びーのがしふぃかーど	Vino Gasificado	ビーノ・ガシフィカード
    びーのこむん	Vino Común	ビーノ・コムン
    びーのこんぷえすと	Vino Compuesto	ビーノ・コンプエスト
    びーのすえすぷもーそす	Vinos Espumosos	ビーノス・エスプモーソス
    びーのすえすぺしあれす	Vinos Especiales	ビーノス・エスペシアレス
    びーのすこんぷえすと	Vinos Compuesto	ビーノス・コンプエスト
    びーのすへぬいーのす	Vinos Genuinos	ビーノス・ヘヌイーノス
    びーのであぐは	Vino de Aguja	ビーノ・デ・アグハ
    びーのでかりだーどこんいんでぃかしおんへおぐらーふぃか	Vino de Calidad con Indicación Geográfica	ビーノ・デ・カリダード・コン・インディカシオンヘオ・グラーフィカ
    びーのでかりだーどぷれふぇれんて	Vino de Calidad Preferente	ビーノ・デ・カリダード・プレフェレンテ
    びーのでぱご	Vino de Pago	ビーノ・デ・パゴ
    びーのでぱらへ	Vino de Paraje	ビーノ・デ・パラヘ
    びーのでびーじゃ	Vino de Villa	ビーノ・デ・ビージャ
    びーのでぷえぶろ	Vino de Pueblo	ビーノ・デ・プエブロ
    びーのでらてぃえら	Vino de la Tierra	ビーノ・デ・ラ・ティエラ
    ぴあちぇんてぃぬえんねーぜ	Piacentinu Ennese	ピアチェンティヌ・エンネーゼ
    ぴあーゔぇ	Piave	ピアーヴェ
    ぴえす	Pièce	ピエス
    ぴえもんて	Piemonte	ピエモンテ
    ぴえーるゔぇーる	Pierrevert	ピエールヴェール
    ぴかるだん	Picardan	ピカルダン
    ぴくぷーる	Piquepoul	ピクプール
    ぴくぷーるどぴね	Picpoul de Pinet	ピクプール・ド・ピネ
    ぴくぷーるのわーる	Piquepoul Noir	ピクプール・ノワール
    ぴこ	Pico	ピコ
    ぴこどん	Picodon	ピコドン
    ぴこりっと	Picolit	ピコリット
    ぴされんじ	Pisa Range	ピサ・レンジ
    ぴしょんろんぐゔぃるこんてすどららんど	Pichon Longueville Comtesse de Lalande	ピション・ロングヴィル・コンテス・ド・ラランド
    ぴしょんろんぐゔぃるばろん	Pichon-Longueville Baron	ピション・ロングヴィル・バロン
    ぴじゃーじゅ	Pigeage	ピジャージュ
    ぴすこ	Pisco	ピスコ
    ぴそっと	Pissotte	ピソット
    ぴっくさんるー	Pic-Saint-Loup	ピック・サン・ルー
    ぴっつぁまるげりーた	Pizza Margherita	ピッツァ・マルゲリータ
    ぴにょれっと	Pignoletto	ピニョレット
    ぴにょーろ	Pignolo	ピニョーロ
    ぴの	Pinot	ピノ
    ぴのぐり	Pinot Gris	ピノ・グリ
    ぴのぐりせれくしおんどぐらんのーぶる	Pinot Gris Sélection de Grains Nobles	ピノ・グリ・セレクシオン・ド・グラン・ノーブル
    ぴのぐりゔぁんだんじゅたるでぃーゔ	Pinot Gris Vendanges Tardives	ピノ・グリ・ヴァンダンジュ・タルディーヴ
    ぴのぐりーじょ	Pinot Grigio	ピノ・グリージョ
    ぴのしゔぃ	Pinot Sivi	ピノ・シヴィ
    ぴのたーじゅ	Pinotage	ピノタージュ
    ぴのつるに	Pinot Črni	ピノ・ツルニ
    ぴのねーろ	Pinot Nero	ピノ・ネーロ
    ぴののわーる	Pinot Noir	ピノ・ノワール
    ぴのびあんこ	Pinot Bianco	ピノ・ビアンコ
    ぴのびえり	Pinot Bijeli	ピノ・ビエリ
    ぴのぶらん	Pinot Blanc	ピノ・ブラン
    ぴのむにえ	Pinot Meunier	ピノ・ムニエ
    ぴのーでしゃらんと	Pineau des Charentes	ピノー・デ・シャラント
    ぴのーどらろわーる	Pineau de la Loire	ピノー・ド・ラ・ロワール
    ぴのーどーに	Pineau d'Aunis	ピノー・ドーニ
    ぴゅいじゅー	Puisieulx	ピュイジュー
    ぴゅいすがんさんてみりおん	Puisseguin Saint-Émilion	ピュイスガン・サンテミリオン
    ぴゅぴとる	Pupitre	ピュピトル
    ぴゅりにーもんらっしぇ	Puligny-Montrachet	ピュリニー・モンラッシェ
    ぴゅるぷ	Pulpe	ピュルプ
    ぴゅーじぇっとさうんど	Puget Sound	ピュージェット・サウンド
    ぴゅーじーゔぇいる	Pewsey Vale	ピュージー・ヴェイル
    ぴれねー	Pyrenees	ピレネー
    ぴんくしゃるどね	Pink Chardonnay	ピンク・シャルドネ
    ぴんちょす	Pinchos	ピンチョス
    ぴーあいぴーえい	PiPA	ピーアイピーエイ
    ぴーえいち	pH	ピーエイチ
    ぴーじーあいえりあわいん	P.G.I. Area Wine	ピージーアイ・エリア・ワイン
    ぴーじーあいえりあわいんず	P.G.I. Area Wines	ピージーアイ・エリア・ワインズ
    ぴーる	Peel	ピール
    ぴーゔぃ	PIWI	ピーヴィ
    ぴーゔぃー	PIWI	ピーヴィー
    ふぁいんへるぷ	Feinherb	ファインヘルプ
    ふぁかぴらう	Whakapirau	ファカピラウ
    ふぁるぐ	Fargues	ファルグ
    ふぁんだん	Fendant	ファンダン
    ふぁんねる	Funnel	ファンネル
    ふぁんぼわ	Fins Bois	ファン・ボワ
    ふぁーのーすかりふぉるにあ	Far North California	ファー・ノース・カリフォルニア
    ふぁーら	Fara	ファーラ
    ふぃあのでぃあゔぇっりの	Fiano di Avellino	フィアノ・ディ・アヴェッリノ
    ふぃあーの	Fiano	フィアーノ
    ふぃえふゔぁんであん	Fiefs Vendéens	フィエフ・ヴァンデアン
    ふぃおれんてぃーな	Fiorentina	フィオレンティーナ
    ふぃおーれさるど	Fiore Sardo	フィオーレ・サルド
    ふぃさん	Fixin	フィサン
    ふぃじゃっく	Figeac	フィジャック
    ふぃすぺるてるみねん	Visperterminen	フィスペルテルミネン
    ふぃっしゅふれんどりーふぁーみんぐ	Fish Friendly Farming	フィッシュ・フレンドリー・ファーミング
    ふぃとぅー	Fitou	フィトゥー
    ふぃにんぐ	Fining	フィニング
    ふぃの	Fino	フィノ
    ふぃるとらーじゅ	Filtrage	フィルトラージュ
    ふぃるとれいしょん	Filtration	フィルトレイション
    ふぃれどぺるしゅ	Filet de Perche	フィレ・ド・ペルシュ
    ふぃろ	Filhot	フィロ
    ふぃろきせら	Phylloxera	フィロキセラ
    ふぃんがーれいくす	Finger Lakes	フィンガー・レイクス
    ふぃーぬしゃんぱーにゅ	Fine Champagne	フィーヌ・シャンパーニュ
    ふいえぞん	Feuillaison	フイエゾン
    ふいゆもると	feuille morte	フイユ・モルト
    ふぇがーとあっらゔぇねつぃあーな	Fegato alla Veneziana	フェガート・アッラ・ヴェネツィアーナ
    ふぇた	Feta	フェタ
    ふぇてあすかあるば	Fetească Albă	フェテアスカ・アルバ
    ふぇてあすかねあぐら	Fetească Neagră	フェテアスカ・ネアグラ
    ふぇてあすかれがーら	Fetească Regală	フェテアスカ・レガーラ
    ふぇのりっく	phénolique	フェノリック
    ふぇられっれ	Ferrarelle	フェラレッレ
    ふぇりえーる	Ferrière	フェリエール
    ふぇるしぇーまじゃろるさーぐ	Felső-Magyarország	フェルシェー・マジャロルサーグ
    ふぇるぜんしゅぴーる	Felsenspiel	フェルゼンシュピール
    ふぇるなぉんぴれす	Fernão Pires	フェルナォン・ピレス
    ふぇるまんたしおんあるこりっく	Fermentation alcoolique	フェルマンタシオン・アルコリック
    ふぇるまんたしおんあんとのー	Fermentation en tonneau	フェルマンタシオン・アン・トノー
    ふぇるまんたしおんまろらくてぃっく	Fermentation Malolactique	フェルマンタシオン・マロラクティック
    ふぇーだーしゅぴーる	Federspiel	フェーダーシュピール
    ふぇーだーばいさー	Federweißer	フェーダーバイサー
    ふぇーだーばいす	Federweiss	フェーダーバイス
    ふぇーるせるゔぁどぅ	Fer Servadou	フェール・セルヴァドゥ
    ふぉくしーふれーゔぁー	Foxy flavor	フォクシー・フレーヴァー
    ふぉじぇーる	Faugères	フォジェール
    ふぉるでぃーたーしゅ	Fordítás	フォルディーターシュ
    ふぉるのわーる	Folle Noire	フォル・ノワール
    ふぉるぶらんしゅ	Folle Blanche	フォル・ブランシュ
    ふぉるぶーる	Vorbourg	フォルブール
    ふぉるむら	Formulae	フォルムラ
    ふぉわん	Foin	フォワン
    ふぉんてぃーな	Fontina	フォンティーナ
    ふぉんでぃよん	Fondillón	フォンディヨン
    ふぉーてぃふぁいど	Fortified	フォーティファイド
    ふぉーてぃふぁいどわいん	Fortified wine	フォーティファイド・ワイン
    ふぉーてぃふぁいどわいんず	fortified wines	フォーティファイド・ワインズ
    ふぉーとろすしーゔゅー	Fort Ross-Seaview	フォート・ロス・シーヴュー
    ふぉーるぶらんしゅ	Folle Blanche	フォール・ブランシュ
    ふみん	Fumin	フミン
    ふみーりゃ	Jumilla	フミーリャ
    ふゅめ	Fumé	フュメ
    ふゅーざる	Fieuzal	フューザル
    ふらしぇんげーるんぐ	Flaschengärung	フラシェンゲールング
    ふらじぇいえしぇぞー	Flagey-Echézeaux	フラジェイ・エシェゾー
    ふらじぇえしぇぞー	Flagey-Echézeaux	フラジェ・エシェゾー
    ふらすかてぃすぺりおーれ	Frascati Superiore	フラスカティ・スペリオーレ
    ふらすかーてぃ	Frascati	フラスカーティ
    ふらっぱーと	Frappato	フラッパート
    ふらっぺ	Frappé	フラッペ
    ふらわりんぐ	Flowering	フラワリング
    ふらんけん	Franken	フランケン
    ふらんこゔか	Frankovka	フランコヴカ
    ふらんこーとどぼるどー	Francs Côtes de Bordeaux	フラン・コート・ド・ボルドー
    ふらんしすこであぎーれ	Francisco de Aguirre	フランシスコ・デ・アギーレ
    ふらんしすこゔぃでぃえら	Francisco Vidiella	フランシスコ・ヴィディエラ
    ふらんしゅこんて	Franche-Comté	フランシュ・コンテ
    ふらんしゅふっく	Franschhoek	フランシュフック
    ふらんしゅふっくゔぁれー	Franschhoek Valley	フランシュフック・ヴァレー
    ふらんじぇりこ	Frangelico	フランジェリコ
    ふらんす	France	フランス
    ふらんちゃこるた	Franciacorta	フランチャコルタ
    ふらんぼわーず	Framboise	フランボワーズ
    ふらーじゅ	Foulage	フラージュ
    ふりうらーの	Friulano	フリウラーノ
    ふりうりゔぇねつぃあじゅりあ	Friuli-Venezia Giulia	フリウリ・ヴェネツィア・ジュリア
    ふりっつぁんて	Frizzante	フリッツァンテ
    ふりっつつゔぁいげると	Fritz Zweigelt	フリッツ・ツヴァイゲルト
    ふりぶーる	Fribourg	フリブール
    ふりゅーあーまりんぐれ	Früher Malingre	フリューアー・マリングレ
    ふりーおんぼーど	Free On Board	フリー・オン・ボード
    ふりーすてーと	Free State	フリー・ステート
    ふりーまんとるどくたー	Fremantle Doctor	フリーマントル・ドクター
    ふるふらーる	Furfural	フルフラール
    ふるみんと	Furmint	フルミント
    ふるむだんべーる	Fourme d'Ambert	フルム・ダンベール
    ふるゔぁつかいすとら	Hrvatska Istra	フルヴァツカ・イストラ
    ふるゔぁつかいすとらいくゔぁるねる	Hrvatska Istra i Kvarner	フルヴァツカ・イストラ・イ・クヴァルネル
    ふるゔぁつこぷりもりえ	Hrvatsko Primorje	フルヴァツコ・プリモリエ
    ふるゔぁつこぽどぅなゔりえ	Hrvatsko Podunavlje	フルヴァツコ・ポドゥナヴリエ
    ふるーつせっと	Fruit set	フルーツ・セット
    ふれ	Frais	フレ
    ふれいざーゔぁれー	Fraser Valley	フレイザー・ヴァレー
    ふれーゔぁーどてぃー	Flavored Tea	フレーヴァード・ティー
    ふれーゔぁーどわいん	Flavored wine	フレーヴァード・ワイン
    ふろっくどがすこーにゅ	Floc de Gascogne	フロック・ド・ガスコーニュ
    ふろまんとー	Fromenteau	フロマントー
    ふろまーじゅ	Fromage|fromage	フロマージュ
    ふろまーじゅあぱっとぷれっせきゅいっと	Fromage à pâte pressée cuite	フロマージュ・ア・パット・プレッセ・キュイット
    ふろまーじゅあぱっとぷれっせのんきゅいっと	Fromage à pâte pressée non cuite	フロマージュ・ア・パット・プレッセ・ノン・キュイット
    ふろまーじゅあぱっとぺるしえ	Fromage à pâte persillée	フロマージュ・ア・パット・ペルシエ
    ふろまーじゅあぱっともーるあくるーとふるーりー	Fromage à pâte molle à croûte fleurie	フロマージュ・ア・パット・モール・ア・クルート・フルーリー
    ふろまーじゅあぱっともーるあくるーとらゔぇ	Fromage à pâte molle à croûte lavée	フロマージュ・ア・パット・モール・ア・クルート・ラヴェ
    ふろまーじゅどえるゔ	Fromage de Herve	フロマージュ・ド・エルヴ
    ふろまーじゅどしぇーゔる	Fromage de chèvre	フロマージュ・ド・シェーヴル
    ふろまーじゅふれ	Fromage frais	フロマージュ・フレ
    ふろれぞん	Floraison	フロレゾン
    ふろんさっく	Fronsac	フロンサック
    ふろんてぃにゃん	Frontignan	フロンティニャン
    ふろんとん	Fronton	フロントン
    ふーるしょーむ	Fourchaume	フールショーム
    ぶいあーるてらすまでいれんせす	V.R.Terras Madeirenses	ブイアールテラス・マデイレンセス
    ぶいきゅーえー	V.Q.A	ブイキューエー
    ぶいやべーす	Bouillabaisse	ブイヤベース
    ぶえのすあいれす	Buenos Aires	ブエノスアイレス
    ぶかてぃーにあっらまとりちゃーな	Bucatini all'Amatriciana	ブカティーニ・アッラ・マトリチャーナ
    ぶけっととらうべ	Bukettraube	ブケットトラウベ
    ぶしゃーじゅ	Bouchage	ブシャージュ
    ぶすいおあかでぼほてぃん	Busuioacă de Bohotin	ブスイオアカ・デ・ボホティン
    ぶすいおく	busuioc	ブスイオク
    ぶすこー	Bouscaut	ブスコー
    ぶせらす	Bucelas	ブセラス
    ぶっしゅとれーにんぐ	Bush training	ブッシュ・トレーニング
    ぶていゆ	Bouteille	ブテイユ
    ぶどうりーふろーる	ブドウ・Leaf roll	ブドウ・リーフロール
    ぶふどばざす	Bœuf de Bazas	ブフ・ド・バザス
    ぶふぶるぎにょん	Boeuf Bourguignon	ブフ・ブルギニョン
    ぶら	Bra	ブラ
    ぶらい	Blaye	ブライ
    ぶらいこーとどぼるどー	Blaye Côtes de Bordeaux	ブライ・コート・ド・ボルドー
    ぶらいてんぐらーと	Breitengrad 51|Breitengrad	ブライテングラート
    ぶらうあーつゔぁいげると	Blauer Zweigelt	ブラウアー・ツヴァイゲルト
    ぶらうあーぶるぐんだー	Blauer Burgunder	ブラウアー・ブルグンダー
    ぶらうあーぽるとぅぎーざー	Blauer Portugieser	ブラウアー・ポルトゥギーザー
    ぶらうあーゔぃるとばっはー	Blauer Wildbacher	ブラウアー・ヴィルトバッハー
    ぶらうふれんきっしゅ	Blaufränkisch	ブラウフレンキッシュ
    ぶらうぶるがー	Blauburger	ブラウブルガー
    ぶらうぶるぐんだー	Blauburgunder	ブラウブルグンダー
    ぶらけ	Braquet	ブラケ
    ぶらけっと	Brachetto	ブラケット
    ぶらけっとだっくい	Brachetto d'Acqui	ブラケット・ダックイ
    ぶらさーじゅ	brassage	ブラサージュ
    ぶらざーと	Brasato	ブラザート
    ぶらっくあがゔぇ	Black agave	ブラック・アガヴェ
    ぶらっくくぃーん	Black Queen	ブラック・クィーン
    ぶらっくくいーん	Black Queen	ブラック・クイーン
    ぶらっくしー	Black Sea	ブラック・シー
    ぶらっくせーじべんち	Black Sage Bench	ブラック・セージ・ベンチ
    ぶらにー	Blagny	ブラニー
    ぶらねーるでゅくりゅ	Branaire-Ducru	ブラネール・デュクリュ
    ぶらん	Blanc|Brun	ブラン
    ぶらんあるじゃんて	Brun Argenté	ブラン・アルジャンテ
    ぶらんこ	Blanco	ブランコ
    ぶらんしゅあるまにゃっく	Blanche Armagnac	ブランシュ・アルマニャック
    ぶらんしょ	Blanchot	ブランショ
    ぶらんだーどどもりゅ	Brandade de Morue	ブランダード・ド・モリュ
    ぶらんどのわーる	Blanc de Noirs	ブラン・ド・ノワール
    ぶらんどぶらん	Blanc de Blancs	ブラン・ド・ブラン
    ぶらんどもるじぇえどらさる	Blanc de Morgex et de La Salle	ブラン・ド・モルジェ・エ・ド・ラ・サル
    ぶらんどもるじぇえどらさーる	Blanc de Morgex et de La Salle	ブラン・ド・モルジェ・エ・ド・ラ・サール
    ぶらんふゅめ	Blanc Fumé	ブラン・フュメ
    ぶらーぬかんとなっく	Brane-Cantenac	ブラーヌ・カントナック
    ぶりっじぱとらいあんぐる	Bridge Pa Triangle	ブリッジ・パ・トライアングル
    ぶりてぃっしゅころんびあ	British Columbia	ブリティッシュ・コロンビア
    ぶりてぃっしゅころんびあゔぃーきゅーえー	BC V.Q.A.	ブリティッシュ・コロンビア・ヴィー・キュー・エー
    ぶりてぃっしゅわいん	British Wine	ブリティッシュ・ワイン
    ぶりどむらん	Brie de Melun	ブリ・ド・ムラン
    ぶりどもー	Brie de Meaux	ブリ・ド・モー
    ぶりゅっと	Brut	ブリュット
    ぶりゅっとなちゅーる	Brut Nature	ブリュット・ナチュール
    ぶりりあんと	Brilliant	ブリリアント
    ぶりんぐゆあおうん	Bring Your Own	ブリング・ユア・オウン
    ぶりーどむらん	Brie de Melun	ブリー・ド・ムラン
    ぶりーどもー	Brie de Meaux	ブリー・ド・モー
    ぶりーどりゔぁーゔぁれー	Breede River Valley	ブリード・リヴァー・ヴァレー
    ぶるいい	Brouilly	ブルイイ
    ぶるがりあ	Bulgaria	ブルガリア
    ぶるくこっへむ	Burg Cochem	ブルク・コッヘム
    ぶるぐいゆ	Bourgueil	ブルグイユ
    ぶるぐんだー	Burgunder	ブルグンダー
    ぶるげんらんと	Burgenland	ブルゲンラント
    ぶるげんれんだーきぷふぇるる	Burgenländer Kipferl	ブルゲンレンダー・キプフェルル
    ぶるごーにゅ	Bourgogne	ブルゴーニュ
    ぶるごーにゅありごて	Bourgogne Aligoté	ブルゴーニュ・アリゴテ
    ぶるごーにゅおーとこーとどにゅい	Bourgogne Hautes-Côtes de Nuits	ブルゴーニュ・オート・コート・ド・ニュイ
    ぶるごーにゅがめい	Bourgogne Gamay	ブルゴーニュ・ガメイ
    ぶるごーにゅこーとしゃろねーず	Bourgogne Côte-Chalonnaise	ブルゴーニュ・コート・シャロネーズ
    ぶるごーにゅこーとどーる	Bourgogne Côte d'Or	ブルゴーニュ・コート・ドール
    ぶるごーにゅとねーる	Bourgogne Tonnerre	ブルゴーニュ・トネール
    ぶるごーにゅぱすとぅぐらん	Bourgogne Passe-Tout-Grains	ブルゴーニュ・パス・トゥ・グラン
    ぶるごーにゅむーすー	Bourgogne Mousseux	ブルゴーニュ・ムースー
    ぶるじょん	Bourgeon	ブルジョン
    ぶるすとばーれん	Wurstwaren	ブルストバーレン
    ぶるっくりんわいなりー	Brooklyn Winery	ブルックリン・ワイナリー
    ぶるとん	Breton	ブルトン
    ぶるねっろ	Brunello	ブルネッロ
    ぶるねっろでぃもんたるちーの	Brunello di Montalcino	ブルネッロ・ディ・モンタルチーノ
    ぶるぼあか	Bulboaca	ブルボアカ
    ぶるーあがゔぇ	Blue agave	ブルー・アガヴェ
    ぶるーすて	Broustet	ブルーステ
    ぶるーすてぃるとんちーず	Blue Stilton Cheese	ブルー・スティルトン・チーズ
    ぶるーでこーす	Bleu des Causses	ブルー・デ・コース
    ぶるーとぶるすと	Blutwurst	ブルートブルスト
    ぶるーどーゔぇるにゅ	Bleu d'Auvergne	ブルー・ドーヴェルニュ
    ぶるーまうんてん	Blue Mountain	ブルー・マウンテン
    ぶるーむ	Bloom	ブルーム
    ぶれむ	Brem	ブレム
    ぶれんでぃんぐ	Blending	ブレンディング
    ぶれんど	Blend	ブレンド
    ぶれーでくろーふ	Breedekloof	ブレーデクローフ
    ぶろしぇおぶーるぶらん	Brochet au Beurre Blanc	ブロシェ・オ・ブール・ブラン
    ぶろっちゅ	Brocciu	ブロッチュ
    ぶろんずくらす	Bronze classe	ブロンズ・クラス
    ぶろんなー	Bronner	ブロンナー
    ぶろーくんおれんじぺこー	Broken O.P.|B.O.P.|Broken Orange Pekoe	ブロークン・オレンジペコー|ブロークン・オレンジ・ペコー|ブロークンオレンジペコー
    ぶろーくんおれんじぺこーふぁにんぐす	B.O.P. Fannings	ブロークンオレンジペコー・ファニングス
    ぶゔぃやーる	Bouvillars	ブヴィヤール
    ぶーぐろ	Bougros	ブーグロ
    ぶーじー	Bouzy	ブージー
    ぶーずろん	Bouzeron	ブーズロン
    ぶーとなっく	Boutenac	ブートナック
    ぶーふぁら	Bufala	ブーファラ
    ぶーるぶーらん	Bourboulenc	ブールブーラン
    ぷいぃしゅーるろわーる	Pouilly sur Loire	プイィ・シュール・ロワール
    ぷいぃふゅいっせ	Pouilly-Fuissé	プイィ・フュイッセ
    ぷいぃふゅめ	Pouilly-Fumé	プイィ・フュメ
    ぷいぃろしぇ	Pouilly-Loché	プイィ・ロシェ
    ぷいぃゔぁんぜる	Pouilly-Vinzelles	プイィ・ヴァンゼル
    ぷしぺる	Pusipel	プシペル
    ぷてぃしゃぶり	Petit Chablis	プティ・シャブリ
    ぷてぃっとしゃんぱーにゅ	Petite Champagne	プティット・シャンパーニュ
    ぷてぃまんさん	Petit Manseng	プティ・マンサン
    ぷてぃめりえ	Petit Meslier	プティ・メリエ
    ぷてぃるーじゅ	Petit Rouge	プティ・ルージュ
    ぷてぃゔぇるど	Petit Verdot	プティ・ヴェルド
    ぷふぁるつ	Pfalz	プファルツ
    ぷふぃんぐすべるく	Pfingstberg	プフィングスベルク
    ぷらいじぇばんと	Pla i Llevant	プラ・イ・ジェバント
    ぷらでばじぇす	Pla de Bages	プラ・デ・バジェス
    ぷらゔぁっつまり	Plavac Mali	プラヴァッツ・マリ
    ぷりえぶらん	Prié Blanc	プリエ・ブラン
    ぷりおらーと	Priorato	プリオラート
    ぷりごりえびろごら	Prigorje-Bilogora	プリゴリエ・ビロゴラ
    ぷりちゅーるぐりーす	Pourriture grise	プリチュール・グリース
    ぷりみてぃーゔぉ	Primitivo	プリミティーヴォ
    ぷりみてぃーゔぉでぃまんどぅりあどるちぇなとぅらーれ	Primitivo di Manduria Dolce Naturale	プリミティーヴォ・ディ・マンドゥリア・ドルチェ・ナトゥラーレ
    ぷりむーる	Primeur	プリムール
    ぷりもるすか	Primorska	プリモルスカ
    ぷりゅいーぬ	Pruine	プリュイーヌ
    ぷりゅーず	Preuses	プリューズ
    ぷりゅーぬ	Prune	プリューヌ
    ぷりゅーれりしーぬ	Prieuré-Lichine	プリューレ・リシーヌ
    ぷりんすえどわーどかうんてぃ	Prince Edward County	プリンス・エドワード・カウンティ
    ぷるかり	Purcari	プルカリ
    ぷるにょーろじぇんてぃーれ	Prugnolo Gentile	プルニョーロ・ジェンティーレ
    ぷるみえくりゅ	Premier Cru|Premiers Cru	プルミエクリュ|プルミエ・クリュ
    ぷるみえくりゅしゅぺりゅーる	Premier Cru Supérieur	プルミエ・クリュ・シュペリュール
    ぷるみえぐらんくりゅ	Premier Grand Cru	プルミエ・グラン・クリュ
    ぷるみえぐらんくりゅくらっせ	Premier Grand Cru Classé|Premiers Grands Cru Classés	プルミエ・グラン・クリュ・クラッセ
    ぷるゔぉす	Boerewors	プルヴォス
    ぷるーにんぐ	Pruning	プルーニング
    ぷるーる	Pleurs	プルール
    ぷれしゅらーじゅ	Pressurage	プレシュラージュ
    ぷれしゅらーじゅでぃれくと	Pressurage direct	プレシュラージュ・ディレクト
    ぷれしゔぃつぁ	Plešivica	プレシヴィツァ
    ぷれす	Press	プレス
    ぷれでぃかーつばいん	Prädikatswein	プレディカーツバイン
    ぷれにゃっく	Preignac	プレニャック
    ぷろしゅっとでぃさんだにえーれ	Prosciutto di San Daniele	プロシュット・ディ・サン・ダニエーレ
    ぷろてくてっどでじぐねーしょんおゔおりじん	Protected Designation of Origin	プロテクテッド・デジグネーション・オヴ・オリジン
    ぷろどぅくとーれすいんでぺんでぃえんてすでぱらへあるたみら	Productores Independientes de Paraje Altamira	プロドゥクトーレス・インデペンディエンテス・デ・パラヘ・アルタミラ
    ぷろばいん	ProWein	プロバイン
    ぷろゔぁんす	Provence	プロヴァンス
    ぷろゔぁんすこるす	Provence-Corse	プロヴァンス・コルス
    ぷーじぇ	Pouget	プージェ
    ぷーりあ	Puglia	プーリア
    ぷーりにぃさんぴえーる	Pouligny-Saint-Pierre	プーリニィ・サン・ピエール
    ぷーるさーる	Poulsard	プールサール
    へいすてぃんぐすりゔぁー	Hastings River	ヘイスティングス・リヴァー
    へきせのーる	Hexenol	ヘキセノール
    へけいじょんせっらだえすとれーら	Requeijão Serra da Estrela	ヘケイジョン・セッラ・ダ・エストレーラ
    へっしっしぇべるくしゅとらーせ	Hessische Bergstraße	ヘッシッシェ・ベルクシュトラーセ
    へっどすぺーすおきしじぇん	Head Space Oxygen	ヘッド・スペース・オキシジェン
    へっどとれーにんぐ	Head training	ヘッド・トレーニング
    へりてーじ	Heritage	ヘリテージ
    へるふぇんしゅたいなー	Helfensteiner	ヘルフェンシュタイナー
    へれす	Jerez	ヘレス
    へれすけれすしぇりー	Jerez-Xérès-Sherry	ヘレス・ケレス・シェリー
    へれすけれすしぇりーいまんさにーりゃさんるーかるでばらめだ	Jerez-Xérès-Sherry y Manzanilla-Sanlúcar de Barrameda	ヘレス・ケレス・シェリー・イ・マンサニーリャ・サンルーカル・デ・バラメダ
    へれすでらふろんてーら	Jerez de la Frontera	ヘレス・デ・ラ・フロンテーラ
    へれんべるく	Höllenberg	ヘレンベルク
    へろるとれーべ	Heroldrebe	ヘロルトレーベ
    へろるどれーべ	Heroldrebe	ヘロルドレーベ
    へんぐすと	Hengst	ヘングスト
    へんちき	Henschke	ヘンチキ
    へんちきひるおゔぐれいす	Henschke Hill of Grace	ヘンチキ・ヒル・オヴ・グレイス
    へんてぃ	Henty	ヘンティ
    へゔぃーとーすと	Heavy toast	ヘヴィー・トースト
    べありゔぁー	Bear River	ベア・リヴァー
    べいしゅゔぇる	Beychevelle	ベイシュヴェル
    べいりー	Bailey	ベイリー
    べしゅてぃむてすあんばうげびーと	Bestimmtes Anbaugebiet	ベシュティムテス・アンバウゲビート
    べすへるむでおーるすぷろんぐすべなみんぐ	Beschermde Oorsprongsbenaming	ベスヘルムデ・オールスプロングスベナミング
    べっけおっふ	Baeckeoffe	ベッケオッフ
    べねっとゔぁれー	Bennett Valley	ベネット・ヴァレー
    べねでぃくてぃーぬ	Bénédictine	ベネディクティーヌ
    べらいひ	Bereich	ベライヒ
    べらいひざーる	Bereich Saar|ベライヒSaar	ベライヒ・ザール
    べらいひゔぇあだー	Bereich Werder	ベライヒ・ヴェアダー
    べるくばいん	Bergwein	ベルクバイン
    べるぐらーゔ	Belgrave	ベルグラーヴ
    べるじゅらっく	Bergerac	ベルジュラック
    べるでほ	Verdejo	ベルデホ
    べるめっと	Bermet	ベルメット
    べるらんでぃえり	berlandieri	ベルランディエリ
    べるん	Bern	ベルン
    べるんかすてる	Bernkastel	ベルンカステル
    べるんとぅーなーぜー	Bern Thunersee	ベルン・トゥーナーゼー
    べるんびーらーぜー	Bern Bielersee	ベルン・ビーラーゼー
    べるゔゅー	Bellvue	ベルヴュー
    べれ	Bellet	ベレ
    べんでぃご	Bendigo	ベンディゴ
    べーれんあうすれーぜ	Beerenauslese	ベーレンアウスレーゼ
    ぺいなんて	Pays Nantais	ペイ・ナンテ
    ぺこりーの	Pecorino	ペコリーノ
    ぺこりーのさるど	Pecorino Sardo	ペコリーノ・サルド
    ぺこりーのとすかーの	Pecorino Toscano	ペコリーノ・トスカーノ
    ぺこりーのろまーの	Pecorino Romano	ペコリーノ・ロマーノ
    ぺさっく	Pessac	ペサック
    ぺさっくれおにゃん	Pessac-Léognan	ペサック・レオニャン
    ぺざ	Peza	ペザ
    ぺしゃるまん	Pécharmant	ペシャルマン
    ぺじゅげー	Pezsgő	ペジュゲー
    ぺたるーまぎゃっぷ	Petaluma Gap	ペタルーマ・ギャップ
    ぺっとなっと	Pét-Nat	ペット・ナット
    ぺてぃやん	Pétillant	ペティヤン
    ぺでぃせる	Pédicelle	ペディセル
    ぺですくろー	Pédesclaux	ペデスクロー
    ぺでるなぁ	Pedernã	ペデルナァ
    ぺとりゅす	Petrus	ペトリュス
    ぺどぅんころろっそ	Peduncolo Rosso	ペドゥンコロ・ロッソ
    ぺどろひめねす	Pedro Giménez|Pedro Ximénez	ペドロ・ヒメネス|ペドロヒメネス
    ぺねです	Penedés	ペネデス
    ぺぱん	Pépin	ペパン
    ぺぶるずぷろじぇくと	Pebbles Project	ペブルズ・プロジェクト
    ぺりえ	Perrier	ペリエ
    ぺりえーる	Perrières	ペリエール
    ぺりきーた	Periquita	ペリキータ
    ぺるごら	Pergola	ペルゴラ
    ぺるなんゔぇるじゅれす	Pernand-Vergelesses	ペルナン・ヴェルジュレス
    ぺるの	Pernod	ペルノ
    ぺるらん	Perlan	ペルラン
    ぺるるゔぁいん	Perlwein	ペルルヴァイン
    ぺーるどらい	Pale Dry	ペール・ドライ
    ほいりげ	Heurige	ホイリゲ
    ほっかいどう	Hokkaido	ホッカイドウ
    ほっと	Hot	ホット
    ほべん	Joven	ホベン
    ほわいとあがゔぇ	White agave	ホワイト・アガヴェ
    ほわいとすてぃるとん	White Stilton	ホワイト・スティルトン
    ほわいとすてぃるとんちーず	White Stilton Cheese	ホワイト・スティルトン・チーズ
    ほーくすべい	Hawke's Bay	ホークス・ベイ
    ほーすへゔんひるず	Horse Heaven Hills	ホース・ヘヴン・ヒルズ
    ぼある	Boal	ボアル
    ぼいどかんとなっく	Boyd-Cantenac	ボイド・カントナック
    ぼすこ	Bosco	ボスコ
    ぼっく	Bock	ボック
    ぼったるが	Bottarga	ボッタルガ
    ぼとりてぃすしねれあ	Botrytis cinerea	ボトリティス・シネレア
    ぼとりんぐ	Bottling	ボトリング
    ぼなるだ	Bonarda	ボナルダ
    ぼばる	Bobal	ボバル
    ぼぼーてぃー	Bobotie	ボボーティー
    ぼるげりさっしかいあ	Bolgheri Sassicaia	ボルゲリ・サッシカイア
    ぼるげーり	Bolgheri	ボルゲーリ
    ぼるどりー	Borderies	ボルドリー
    ぼるどー	Bordeaux	ボルドー
    ぼるどーおーぶのーじゅ	Bordeaux Haut-Benauge	ボルドー・オー・ブノージュ
    ぼるどーくられっと	Bordeaux Claret	ボルドー・クラレット
    ぼるどーくれれ	Bordeaux Clairet	ボルドー・クレレ
    ぼるどーしゅぺりゅーる	Bordeaux Supérieur	ボルドー・シュペリュール
    ぼわおるでぃねーる	Bois Ordinaires	ボワ・オルディネール
    ぼわっそん	boissons	ボワッソン
    ぼんぬぞー	Bonnezeaux	ボンヌゾー
    ぼんぬまーる	Bonnes-Mares	ボンヌ・マール
    ぼんびーのねーろ	Bombino Nero	ボンビーノ・ネーロ
    ぼんびーのびあんこ	Bombino Bianco	ボンビーノ・ビアンコ
    ぼんぼわ	Bons Bois	ボン・ボワ
    ぼーじょれ	Beaujolais	ボージョレ
    ぼーじょれぬーゔぉー	Beaujolais Nouveau	ボージョレ・ヌーヴォー
    ぼーじょれゔぃらーじゅ	Beaujolais-Villages|Beaujolais Villages	ボージョレ・ヴィラージュ
    ぼーせじゅーるべこ	Beau-Séjour-Bécot	ボー・セジュール・ベコ
    ぼーぬ	Beaune	ボーヌ
    ぼーふぉーる	Beaufort	ボーフォール
    ぼーむどゔにーず	Beaumes de Venise	ボーム・ド・ヴニーズ
    ぼーもんしゅーるゔぇる	Beaumont sur Vesle	ボーモン・シュール・ヴェル
    ぼーんどらい	Bone Dry	ボーン・ドライ
    ぽいおす	Poios	ポイオス
    ぽいやっく	Pauillac	ポイヤック
    ぽくぷりえ	Pokuplje	ポクプリエ
    ぽさゔぃえ	Posavje	ポサヴィエ
    ぽでぃしゅるとらんしるゔぁにえい	Podişul Transilvaniei	ポディシュル・トランシルヴァニエイ
    ぽどらゔぃえ	Podravje	ポドラヴィエ
    ぽどれぎや	Podregija	ポドレギヤ
    ぽまーる	Pommard	ポマール
    ぽまーるくろーん	Pommard clone	ポマール・クローン
    ぽみーの	Pomino	ポミーノ
    ぽむろーる	Pomerol	ポムロール
    ぽもーどぶるたーにゅ	Pommeau de Bretagne	ポモー・ド・ブルターニュ
    ぽりっしゅひるりゔぁー	Polish Hill River	ポリッシュ・ヒル・リヴァー
    ぽるたれぐれ	Portalegre	ポルタレグレ
    ぽると	Porto	ポルト
    ぽるとぅぎーざー	Portugieser	ポルトゥギーザー
    ぽるとがる	Portugal	ポルトガル
    ぽるとぎざっつ	Portugizac	ポルトギザッツ
    ぽるとぎーざー	Portugieser	ポルトギーザー
    ぽわーる	Poire	ポワール
    ぽわーるうぃりあむす	Poire Williams	ポワール・ウィリアムス
    ぽんてかね	Pontet-Canet	ポンテ・カネ
    ぽんれゔぇっく	Pont-l'Évêque	ポン・レヴェック
    ぽーくかうんてぃ	Polk County	ポーク・カウンティ
    ぽーと	Port	ポート
    ぽーとわいん	Port wine	ポートワイン|ポート・ワイン
    まいすたーしゅてゅっく	Meisterstück	マイスターシュテュック
    まいせん	Meissen	マイセン
    まいぷー	Maipú	マイプー
    まいぽ	Maipo	マイポ
    まいぽゔぁれー	Maipo Valley	マイポ・ヴァレー
    まいるど	Mild	マイルド
    まいんどらいえっく	Maindreieck	マインドライエック
    まいんふぃーれっく	Mainviereck	マインフィーレック
    まいんふぃーれっくまいんどらいえっくしゅたいがーゔぁると	Mainviereck, Maindreieck, Steigerwald	マインフィーレック・マインドライエック・シュタイガーヴァルト
    まいーしゃんぱーにゅ	Mailly-Champagne	マイー・シャンパーニュ
    まうれ	Maule	マウレ
    まうれゔぁれー	Maule Valley	マウレ・ヴァレー
    まうんとはーらん	Mount Harlan	マウント・ハーラン
    まうんとばーかー	Mount Barker	マウント・バーカー
    まうんとぴすがー	Mt. Pisgah	マウント・ピスガー
    まうんとべんそん	Mount Benson	マウント・ベンソン
    まうんとろふてぃれんじず	Mount Lofty Ranges	マウント・ロフティ・レンジズ
    まうんとゔぃーだー	Mount Veeder	マウント・ヴィーダー
    まおんめのるか	Mahón Menorca	マオン・メノルカ
    まかべお	Macabeo	マカベオ
    まかろんどさんてみりおん	Macarons de Saint-Émilion	マカロン・ド・サン・テミリオン
    まくみんゔぃる	McMinnville	マクミンヴィル
    まくらーれんゔぇいる	McLaren Vale	マクラーレン・ヴェイル
    まくゔぁんでゅじゅら	Macvin du Jura	マクヴァン・デュ・ジュラ
    まぐなむ	Magnum	マグナム
    まけどにあ	Macedonia	マケドニア
    まこねー	Mâconnais	マコネー
    まこん	Mâcon	マコン
    まこんゔぃらーじゅ	Mâcon-Villages	マコン・ヴィラージュ
    まこー	Macau	マコー
    ましふさんとらる	Massif Central	マシフ・サントラル
    まじぇこゔぁれー	Malleco Valley	マジェコ・ヴァレー
    まじしゃんべるたん	Mazis-Chambertin	マジ・シャンベルタン
    まじー	Mudgee	マジー
    ますえろ	Mazuelo	マスエロ
    ますかっとおゔあれきさんどりあ	Muscat of Alexandria	マスカット・オヴ・アレキサンドリア
    ますかっとおゔけふぁろにあ	Muscat of Cephalonia	マスカット・オヴ・ケファロニア
    ますかっとおゔぱとらす	Muscat of Patras	マスカット・オヴ・パトラス
    ますかっとおゔりおぱとらす	Muscat of Rio Patras	マスカット・オヴ・リオ・パトラス
    ますかっとおゔりむのす	Muscat of Limnos	マスカット・オヴ・リムノス
    ますかっとおゔろどす	Muscat of Rhodes	マスカット・オヴ・ロドス
    ますかっとはんぶるぐ	Muscat Hamburg	マスカット・ハンブルグ
    ますかっとべいりーえい	Muscat Bailey A|マスカット・ベイリーA	マスカット・ベイリー・エイ
    ますたーとん	Masterton	マスタートン
    ませどんれんじず	Macedon Ranges	マセドン・レンジズ
    ませらしおん	macération|Macération	マセラシオン
    ませらしおんかるぼにっく	Macération carbonique	マセラシオン・カルボニック
    ませらしおんふぃなる	Macération finale	マセラシオン・フィナル
    ませらしおんぷれふぇるまんてーる	Macération préfermentaire	マセラシオン・プレフェルマンテール
    ませらしおんぺりきゅれーる	Macération pelliculaire	マセラシオン・ペリキュレール
    ませれいしょん	maceration	マセレイション
    まぞわいえーるしゃんべるたん	Mazoyères-Chambertin	マゾワイエール・シャンベルタン
    またかな	Matakana	マタカナ
    またろ	Mataro	マタロ
    まちゅらしおんしゅーるりー	Maturation sur lies	マチュラシオン・シュール・リー
    まちゅりて	Maturité	マチュリテ
    まっくすしゅーばーと	Max Schubert	マックス・シューバート
    まっけろーにあっらきたーら	Maccheroni alla Chitarra	マッケローニ・アッラ・キターラ
    まてゅざれむ	Mathusalem	マテュザレム
    までぃらん	Madiran	マディラン
    までいら	Madeira	マデイラ
    までら	Madeira|Madère	マデラ
    までーる	Madère	マデール
    まどりっど	Madrid	マドリッド
    まどれーぬろいやる	Madeleine Royale	マドレーヌ・ロイヤル
    まどれーぬろわいやる	Madeleine Royale	マドレーヌ・ロワイヤル
    まほがにー	Mahogany	マホガニー
    まらが	Málaga	マラガ
    まらすきーの	Maraschino	マラスキーノ
    まらに	Marani	マラニ
    まらるてぃっくらぐらゔぃえーる	Malartic-Lagravière	マラルティック・ラグラヴィエール
    まらん	Marin	マラン
    まらんじゅ	Maranges	マランジュ
    まりあごめす	Maria Gomes	マリア・ゴメス
    まりあーじゅ	mariage	マリアージュ
    まりれんくねーでる	Marillenknödel	マリレンクネーデル
    まる	Malle	マル
    まるいゆ	Mareuil	マルイユ
    まるきだれーむべっかー	Marquis d'Alesme-Becker	マルキ・ダレーム・ベッカー
    まるきどてるむ	Marquis de Terme	マルキ・ド・テルム
    まるくだしゅとぅーる	Marque d'Acheteur	マルク・ダシュトゥール
    まるけ	Marche	マルケ
    まるごー	Margaux	マルゴー
    まるさねー	Marsannay	マルサネー
    まるさら	Marsala	マルサラ
    まるさんぬ	Marsanne	マルサンヌ
    まるしやっく	Marcillac	マルシヤック
    まるすらん	Marselan	マルスラン
    まるせいゆ	Marseille	マルセイユ
    まるつぇみーの	Marzemino	マルツェミーノ
    まるてぃやっく	Martillac	マルティヤック
    まるてぃーに	Martini	マルティーニ
    まるどなーど	Maldonado	マルドナード
    まるべっく	Malbec	マルベック
    まるぺーる	Malepère	マルペール
    まるゔぁじあ	Malvasia	マルヴァジア
    まるゔぁじあいすとりあーな	Malvasia Istriana	マルヴァジア・イストリアーナ
    まるゔぁじあでっれりぱり	Malvasia delle Lipari	マルヴァジア・デッレ・リパリ
    まるゔぁじあでるきあんてぃ	Malvasia del Chianti	マルヴァジア・デル・キアンティ
    まるゔぁじあはんだかすかんでぃあ	Malvasia Handakas-Candia	マルヴァジア・ハンダカス・カンディア
    まるゔぁじあびあんか	Malvasia Bianca	マルヴァジア・ビアンカ
    まるゔぁじあびあんかでぃばじりかーた	Malvasia Bianca di Basilicata	マルヴァジア・ビアンカ・ディ・バジリカータ
    まるゔぁじあふぃな	Malvasia Fina	マルヴァジア・フィナ
    まるゔぁじや	Malvazija	マルヴァジヤ
    まるゔぉわじー	Malvoisie	マルヴォワジー
    まるゔぉわじーどこるす	Malvoisie de Corse	マルヴォワジー・ド・コルス
    まれすこさんてぐじゅぺり	Malescot Saint-Exupéry	マレスコ・サン・テグジュペリ
    まれーだーりんぐ	Murray Darling	マレー・ダーリング
    まろらくてぃっくふぁーめんていしょん	Malo-lactic fermentation	マロラクティック・ファーメンテイション
    まろわーる	Maroilles	マロワール
    まんさにーりゃ	Manzanilla	マンサニーリャ
    まんさにーりゃさんるーかるでばらめーだ	Manzanilla-Sanlúcar de Barrameda	マンサニーリャ・サンルーカル・デ・バラメーダ
    まんすてーる	Munster	マンステール
    まんすてーるじぇろめ	Munster Géromé	マンステール・ジェロメ
    まんちゅえら	Manchuela	マンチュエラ
    まんてぃにあ	Mantinia	マンティニア
    まんでりん	Mandheling	マンデリン
    まんとねぐろ	Manto Negro	マント・ネグロ
    まゔるっど	Mavrud	マヴルッド
    まゔるでぃ	Mavroudi	マヴルディ
    まゔろ	Mavro	マヴロ
    まゔろだふね	Mavrodaphne	マヴロダフネ
    まゔろだふねおゔけふぁろにあ	Mavrodaphne of Cephalonia	マヴロダフネ・オヴ・ケファロニア
    まゔろだふねおゔぱとらす	Mavrodaphne of Patras	マヴロダフネ・オヴ・パトラス
    まーがれっとりゔぁー	Margaret River	マーガレット・リヴァー
    まーしゅらーしゅ	Máslás	マーシュラーシュ
    まーてぃんばら	Martinborough	マーティンバラ
    まーてぃんぼろ	Martinborough	マーティンボロ
    まーる	Marc	マール
    まーるだるざすげゔゅるつとらみねる	Marc d'Alsace Gewürztraminer	マール・ダルザス・ゲヴュルツトラミネル
    まーるでゅじゅら	Marc du Jura	マール・デュ・ジュラ
    まーるどぶるごーにゅ	Marc de Bourgogne	マール・ド・ブルゴーニュ
    まーるどぷろゔぁんす	Marc de Provence	マール・ド・プロヴァンス
    まーるぼろ	Marlborough	マールボロ
    みくろおきしじぇなしおん	Micro-oxygénation	ミクロ・オキシジェナシオン
    みくろびゅらーじゅ	Micro-bullage	ミクロ・ビュラージュ
    みざんぶてぃゆおどめーぬ	Mis en bouteille au Domaine	ミ・ザン・ブティユ・オ・ドメーヌ
    みすけっと	Misket	ミスケット
    みすけっとちぇるゔぇん	Misket Cherven	ミスケット・チェルヴェン
    みっしょん	Mission	ミッション
    みってるはーるとどいちぇばいんしゅとらーせ	Mittelhaardt-Deutsche Weinstraße	ミッテルハールト・ドイチェ・バインシュトラーセ
    みってるぶるげんらんと	Mittelburgenland	ミッテルブルゲンラント
    みってるらいん	Mittelrhein	ミッテルライン
    みってるらいんりーすりんぐかるた	Mittelrhein Riesling Charta	ミッテルライン・リースリング・カルタ
    みでぃあむとーすと	Medium toast	ミディアム・トースト
    みでぃあむどらい	Medium Dry	ミディアム・ドライ
    みでぃあむぷらすとーすと	Medium plus toast	ミディアム・プラス・トースト
    みどり	MIDORI	ミドリ
    みどるばーぐゔぁーじにあ	Middleburg Virginia	ミドルバーグ・ヴァージニア
    みねすとろーね	Minestrone	ミネストローネ
    みねるゔぉわ	Minervois	ミネルヴォワ
    みもれっと	Mimolette	ミモレット
    みゅじにー	Musigny	ミュジニー
    みゅすか	Muscat	ミュスカ
    みゅすかあぷてぃぐらん	Muscat à Petits Grains	ミュスカ・ア・プティ・グラン
    みゅすかおっとねる	Muscat Ottonel	ミュスカ・オットネル
    みゅすかせれくしおんどぐらんのーぶる	Muscat Sélection de Grains Nobles	ミュスカ・セレクシオン・ド・グラン・ノーブル
    みゅすかで	Muscadet	ミュスカデ
    みゅすかでことーどらろわーる	Muscadet Coteaux de la Loire	ミュスカデ・コトー・ド・ラ・ロワール
    みゅすかでこーとどぐらんりゅー	Muscadet Côtes de Grandlieu	ミュスカデ・コート・ド・グランリュー
    みゅすかでせーゔるえめーぬ	Muscadet Sèvre et Maine	ミュスカデ・セーヴル・エ・メーヌ
    みゅすかでゅかっぷこるす	Muscat du Cap Corse	ミュスカ・デュ・カップ・コルス
    みゅすかでる	Muscadelle	ミュスカデル
    みゅすかどぼーむどゔにーず	Muscat de Beaumes de Venise	ミュスカ・ド・ボーム・ド・ヴニーズ
    みゅすかどみるゔぁる	Muscat de Mireval	ミュスカ・ド・ミルヴァル
    みゅすかどりゅねる	Muscat de Lunel	ミュスカ・ド・リュネル
    みゅすかぶらんあぷてぃぐらん	Muscat Blanc à Petit Grains	ミュスカ・ブラン・ア・プティ・グラン
    みゅすかるだん	Muscardin	ミュスカルダン
    みゅすかゔぁんだんじゅたるでぃーゔ	Muscat Vendanges Tardives	ミュスカ・ヴァンダンジュ・タルディーヴ
    みゅすかーど	Muscade	ミュスカード
    みゅずれ	Muselet	ミュズレ
    みゅたーじゅ	Mutage	ミュタージュ
    みゅらーとぅるがう	Müller-Thurgau	ミュラー・トゥルガウ
    みゅらーれーべ	Müllerrebe	ミュラーレーベ
    みらねーぜ	Milanese	ミラネーゼ
    みらの	Milano	ミラノ
    みらべる	Mirabelle	ミラベル
    みるてぃーゆ	Myrtille	ミルティーユ
    みるでぃう	Mildiou	ミルディウ
    みるれんにゅーむ	Millennium	ミルレンニューム
    みれじめ	Millésimé	ミレジメ
    みれらんだーじゅ	Millerandage	ミレランダージュ
    みーにょ	Minho	ミーニョ
    むさか	Moussaka	ムサカ
    むすかてらー	Muskateller	ムスカテラー
    むつゔぁねかふり	Mtsvane Kakhuri	ムツヴァネ・カフリ
    むにえ	Meunier	ムニエ
    むぬとぅーさろん	Menetou-Salon	ムヌトゥー・サロン
    むるしあ	Murcia	ムルシア
    むるそー	Meursault	ムルソー
    むろんだるぼわ	Melon d'Arbois	ムロン・ダルボワ
    むろんどぶるごーにゅ	Melon de Bourgogne	ムロン・ド・ブルゴーニュ
    むーてれひるず	Moutere Hills	ムーテレ・ヒルズ
    むーとんばろんぬふぃりっぷ	Mouton Baronne Philippe	ムートン・バロンヌフィリッ・プ
    むーとんろーとしると	Mouton Rothschild	ムートン・ロートシルト
    むーらんなゔぁん	Moulin-à-Vent	ムーラン・ナ・ヴァン
    むーりす	Moulis	ムーリス
    むーるゔぇーどる	Mourvèdre	ムールヴェードル
    むーんまうんてんでぃすとりくと	Moon Mountain District	ムーン・マウンテン・ディストリクト
    めすへてぃ	Meskheti	メスヘティ
    めぞるちーな	Mesolcina	メゾルチーナ
    めでぃえゔぁうでおうれん	Medieval de Ourém	メディエヴァウ・デ・オウレン
    めとろぽりたーな	Metropolitana	メトロポリターナ
    めとーどあんせすとらる	Méthode Ancestrale|Méthode ancestrale	メトード・アンセストラル
    めとーどきゃっぷくらしっく	Méthode Cap Classique	メトード・キャップ・クラシック
    めとーどしゃるま	Méthode charmat	メトード・シャルマ
    めとーどしゃんぷのわーず	Méthode champenoise	メトード・シャンプノワーズ
    めとーどとらでぃしょねる	Méthode traditionnelle	メトード・トラディショネル
    めとーどどとらんすふぇーる	Méthode de transfert	メトード・ド・トランスフェール
    めとーどりゅらる	Méthode rurale	メトード・リュラル
    めどっく	Médoc	メドック
    めらん	Mesland	メラン
    めりてーじ	Meritage	メリテージ
    めるきゅれー	Mercurey	メルキュレー
    めるてぃんぐ	melting	メルティング
    めるにっく	Melnik	メルニック
    めるろ	Merlot	メルロ
    めるろでるてぃちーの	Merlot del Ticino	メルロ・デル・ティチーノ
    めるろー	Merlot	メルロー
    めんしあ	Mencía	メンシア
    めんどしーの	Mendocino	メンドシーノ
    めんどしーのかうんてぃ	Mendocino County	メンドシーノ・カウンティ
    めんどーさ	Mendoza	メンドーサ
    めーるしゅぱいぜん	Mehlspeisen	メールシュパイゼン
    もか	Mocha	モカ
    もすかてる	Moscatel	モスカテル
    もすかてるであれはんどりあ	Moscatel de Alejandría	モスカテル・デ・アレハンドリア
    もすかてるであんぶるご	Moscatel de Hamburgo	モスカテル・デ・アンブルゴ
    もすかてるでせとぅーばる	Moscatel de Setúbal	モスカテル・デ・セトゥーバル
    もすかてるろっしょ	Moscatel Roxo	モスカテル・ロッショ
    もすかーと	Moscato	モスカート
    もすかーとじゃっろ	Moscato Giallo	モスカート・ジャッロ
    もすかーとでぃすかんつぉ	Moscato di Scanzo	モスカート・ディ・スカンツォ
    もすかーとびあんこ	Moscato Bianco	モスカート・ビアンコ
    もすこふぃれろ	Moschofilero	モスコフィレロ
    もすほふぃれろ	Moschofilero	モスホフィレロ
    もすらゔぃーな	Moslavina	モスラヴィーナ
    もぜる	Moselle	モゼル
    もっつぁれっら	Mozzarella	モッツァレッラ
    もっつぁれっらでぃぶふぁらかんぱーな	Mozzarella di Bufala Campana	モッツァレッラ・ディ・ブファラカンパーナ
    もどらふらんきにゃ	Modra Frankinja	モドラ・フランキニャ
    もなすとれる	Monastrell	モナストレル
    もりーぜ	Molise	モリーゼ
    もる	Moll	モル
    もるがーどでふぃーご	Morgado de Figo	モルガード・デ・フィーゴ
    もるごん	Morgon	モルゴン
    もるどゔぁ	Moldova	モルドヴァ
    もるびえ	Morbier	モルビエ
    もれさんどに	Morey-Saint-Denis	モレ・サン・ドニ
    もれっりーの	Morellino	モレッリーノ
    もれっりーのでぃすかんさーの	Morellino di Scansano	モレッリーノ・ディ・スカンサーノ
    もわるー	Moelleux	モワルー
    もわーぬ	Moines	モワーヌ
    もんさん	Montsant	モンサン
    もんたにー	Montagny	モンタニー
    もんたるちーの	Montalcino	モンタルチーノ
    もんたーにゅさんてみりおん	Montagne Saint-Émilion	モンターニュ・サンテミリオン
    もんたーにゅどらんす	Montagne de Reims	モンターニュ・ド・ランス
    もんてぃちぇっろ	Monticello	モンティチェッロ
    もんてぃる	Montils	モンティル
    もんてぃーりゃもりれす	Montilla-Moriles	モンティーリャ・モリレス
    もんてっろ	Montello	モンテッロ
    もんてっろろっそ	Montello Rosso	モンテッロ・ロッソ
    もんてびでお	Montevideo	モンテビデオ
    もんてふぁるこさぐらんてぃーの	Montefalco Sagrantino	モンテファルコ・サグランティーノ
    もんてぷるちあーの	Montepulciano	モンテプルチアーノ
    もんてぷるちあーのだぶるっつぉ	Montepulciano d'Abruzzo	モンテプルチアーノ・ダブルッツォ
    もんてりー	Monthélie	モンテリー
    もんてれーな	Montelena	モンテレーナ
    もんてゔぇろねーぜ	Monte Veronese	モンテ・ヴェロネーゼ
    もんでゅーず	Mondeuse	モンデューズ
    もんとれーかうんてぃ	Monterey County	モントレー・カウンティ
    もんどぅーず	Mondeuse	モンドゥーズ
    もんどーる	Mont d'Or	モンドール
    もんばじやっく	Monbazillac	モンバジヤック
    もんふぉるてだるば	Monforte d'Alba	モンフォルテ・ダルバ
    もんぶすけ	Monbousquet	モンブスケ
    もんらっしぇ	Montrachet	モンラッシェ
    もんらゔぇる	Montravel	モンラヴェル
    もんりす	Montlisse	モンリス
    もんりゅいざん	Monts Luisants	モン・リュイザン
    もんるいしゅーるろわーる	Montlouis sur Loire	モンルイ・シュール・ロワール
    もんるいしゅーるろわーるむーすー	Montlouis sur Loire Mousseux	モンルイ・シュール・ロワール・ムースー
    もんろーず	Montrose	モンローズ
    もーざっく	Mauzac	モーザック
    もーぜる	Mosel	モーゼル
    もーぜるとーる	Moseltor	モーゼルトール
    もーにんとんぺにんしゅら	Mornington Peninsula	モーニントン・ペニンシュラ
    もーにんとんぺにんしゅらいんたーなしょなるぴののわーるせれぶれーしょん	Mornington Peninsula International Pinot Noir Celebration	モーニントン・ペニンシュラ・インターナショナル・ピノ・ノワール・セレブレーション
    もーりー	Maury	モーリー
    もーりーせっく	Maury Sec	モーリー・セック
    もーりーらんしお	Maury Rancio	モーリー・ランシオ
    やきまゔぁれー	Yakima Valley	ヤキマ・ヴァレー
    やまがた	Yamagata	ヤマガタ
    やまさち	Yamasachi	ヤマサチ
    やまそーびにおん	Yama Sauvignon	ヤマ・ソービニオン
    やまそーゔぃによん	Yama Sauvignon	ヤマ・ソーヴィニヨン
    やまなし	Yamanashi	ヤマナシ
    やらゔぁれー	Yarra Valley	ヤラ・ヴァレー
    やんふぁんりーべっく	Jan van Riebeeck	ヤン・ファン・リーベック
    ゆないてっどきんぐだむ	United Kingdom	ユナイテッド・キングダム
    ゆないてっどすていつ	United States	ユナイテッド・ステイツ
    ゆなべいゆ	une abeille	ユナ・ベイユ
    ゆにぶらん	Ugni Blanc	ユニ・ブラン
    ゆるつぃひ	Ürzig	ユルツィヒ
    ゆーしーでぃーふぁいゔ	UCD5	ユーシーディーファイヴ
    よはにすべるく	Johannisberg	ヨハニスベルク
    よはん	Johann	ヨハン
    よはんしらー	Johann Schiller	ヨハン・シラー
    よんえむえむぴー	4MMP	ヨンエムエムピー
    よんとゔぃる	Yountville	ヨントヴィル
    らいたべるく	Leithaberg	ライタベルク
    らいととーすと	Light toast	ライト・トースト
    らいとどらいほわいとぽーと	Light Dry White Port	ライト・ドライホ・ワイト・ポート
    らいなー	Liner	ライナー
    らいひぇんしゅたいなー	Reichensteiner B13	ライヒェンシュタイナー
    らいぷにんぐ	Ripening	ライプニング
    らいぷろっと	Ripe rot	ライプ・ロット
    らいむすとーんこーすと	Limestone Coast	ライムストーン・コースト
    らいんがう	Rheingau	ラインガウ
    らいんすきりずりんぐ	Rajnski Rizling	ラインスキ・リズリング
    らいんへっせん	Rheinhessen	ラインヘッセン
    らいんりーすりんぐ	Rheinriesling	ラインリースリング
    らかでぃー	L'Acadie	ラカディー
    らきや	Rakiya	ラキヤ
    らくらっぷ	La Clape	ラ・クラップ
    らくれっと	Raclette	ラクレット
    らぐさーの	Ragusano	ラグサーノ
    らぐらんじゅ	Lagrange	ラグランジュ
    らぐらんどりゅ	La Grande Rue	ラ・グランド・リュ
    らぐれいん	Lagrein	ラグレイン
    らこーと	La Côte	ラ・コート
    らざぐれん	Rutherglen	ラザグレン
    らざふぉーど	Rutherford	ラザフォード
    らしゅきりーずりんぐ	Laski Rizling	ラシュキ・リーズリング
    らじど	Lajido	ラジド
    らすけーら	Raschera	ラスケーラ
    らすこんぶ	Lascombes	ラスコンブ
    らすとー	Rasteau	ラストー
    らたとぅいゆ	Ratatouille	ラタトゥイユ
    らたーしゅ	La Tâche	ラ・ターシュ
    らちゃ	Racha	ラチャ
    らっきんぐ	Racking	ラッキング
    らつぃお	Lazio	ラツィオ
    らとぅーる	Latour	ラトゥール
    らとぅーるおーぶりおん	La Tour-Haut-Brion	ラ・トゥール・オー・ブリオン
    らとぅーるかるね	La Tour-Carnet	ラ・トゥール・カルネ
    らとぅーるふぃじゃっく	La Tour Figeac	ラ・トゥール・フィジャック
    らとぅーるまるてぃやっく	Latour Martillac	ラトゥール・マルティヤック
    らとりしえーるしゃんべるたん	Latricières-Chambertin	ラトリシエール・シャンベルタン
    らとるすねいくひるず	Rattlesnake Hills	ラトルスネイク・ヒルズ
    らとるすねーくひるず	Rattlesnake Hills	ラトルスネーク・ヒルズ
    らどわ	Ladoix	ラドワ
    らどわせりにー	Ladoix-Serrigny	ラドワ・セリニー
    らぱるま	La Palma	ラ・パルマ
    らふぃっとろーとしると	Lafite-Rothschild	ラフィット・ロートシルト
    らふぉいんしゅ	Lafões	ラフォインシュ
    らふぉんろしぇ	Lafon-Rochet	ラフォン・ロシェ
    らふらんせさ	La Francesa	ラ・フランセサ
    らぶるすか	labrusca	ラブルスカ
    らぷさに	Rapsani	ラプサニ
    らぷらた	La Plata	ラ・プラタ
    らぺる	Rapel	ラペル
    らぺるゔぁれー	Rapel Valley	ラペル・ヴァレー
    らぼーぞ	Raboso	ラボーゾ
    らまだす	Ramadas	ラマダス
    らまんちゃ	La Mancha	ラ・マンチャ
    らまんどーろ	Ramandolo	ラマンドーロ
    らみっしょんおーぶりおん	La Mission-Haut-Brion	ラ・ミッション・オー・ブリオン
    らむ	Rum	ラム
    らむとんぬ	La Moutonne	ラ・ムトンヌ
    らもっとぎにゃーる	Lamothe-Guignard	ラモット・ギニャール
    らもっら	La Morra	ラ・モッラ
    らもんどっと	La Mondotte	ラ・モンドット
    ららぎゅーぬ	La Lagune	ラ・ラギューヌ
    ららねあぐら	Rară Neagră	ララ・ネアグラ
    ららんどどぽむろーる	Lalande-de-Pomerol	ラランド・ド・ポムロール
    らりおは	La Rioja	ラ・リオハ
    らりおはあるぜんちん	La Rioja Argentina	ラ・リオハ・アルゼンチン
    らりゔぃにえーる	La Livinière	ラ・リヴィニエール
    らるしでゅかす	Larcis Ducasse	ラルシ・デュカス
    らろまね	La Romanée	ラ・ロマネ
    らろーず	Laroze	ラローズ
    らん	Rhin	ラン
    らんぐどっく	Languedoc	ラングドック
    らんぐどっくるーしょん	Languedoc-Roussillon	ラングドック・ルーション
    らんぐほーんくりーく	Langhorne Creek	ラングホーン・クリーク
    らんぐまいるわいなりー	Langmeil Winery	ラングマイル・ワイナリー
    らんぐる	Langres	ラングル
    らんげ	Langhe	ランゲ
    らんごあばるとん	Langoa-Barton	ランゴア・バルトン
    らんさろて	Lanzarote	ランサロテ
    らんしゅばーじゅ	Lynch-Bages	ランシュ・バージュ
    らんしゅむーさ	Lynch-Moussas	ランシュ・ムーサ
    らんとばいん	Landwein	ラントバイン
    らんとばいんげびーて	Landweingebiete	ラントバインゲビーテ
    らんど	Lande	ランド
    らんぶるすこ	Lambrusco	ランブルスコ
    らんぶるすこでぃそるばーら	Lambrusco di Sorbara	ランブルスコ・ディ・ソルバーラ
    らんぷろわ	Lamproie	ランプロワ
    らゔぃるおーぶりおん	Laville Haut-Brion	ラヴィル・オー・ブリオン
    らゔぉー	Lavaux	ラヴォー
    りあすばいしゃす	Rías Baixas	リアス・バイシャス
    りえっとどとぅーる	Rillette de Tours	リエット・ド・トゥール
    りおおは	Río Oja	リオ・オハ
    りおねぐろ	Río Negro	リオ・ネグロ
    りおは	Rioja	リオハ
    りおはあらべさ	Rioja Alavesa	リオハ・アラベサ
    りおはあるた	Rioja Alta	リオハ・アルタ
    りおはおりえんたる	Rioja Oriental	リオハ・オリエンタル
    りおはばは	Rioja Baja	リオハ・バハ
    りかーる	Ricard	リカール
    りきゅーる	liqueur	リキュール
    りきゅーるとかい	Liqueur Tokay	リキュール・トカイ
    りきゅーるどてぃらーじゅ	Liqueur de Tirage	リキュール・ド・ティラージュ
    りぐーりあ	Liguria	リグーリア
    りこれっりゃ	Llicorella	リコレッリャ
    りごっとどこんどりゅー	Rigotte de Condrieu	リゴット・ド・コンドリュー
    りしゅぶーる	Richebourg	リシュブール
    りすたん	Listán	リスタン
    りすたんねぐろ	Listán Negro	リスタン・ネグロ
    りすたんぷりえと	Listán Prieto	リスタン・プリエト
    りすとらっく	Listrac	リストラック
    りすとらっくめどっく	Listrac-Médoc	リストラック・メドック
    りすぼあ	Lisboa	リスボア
    りぞん	Lison	リゾン
    りちゃーどすまーと	Richard Smart	リチャード・スマート
    りっじ	Ridge	リッジ
    りっじゔぃんやーど	Ridge Vineyards	リッジ・ヴィンヤード
    りとー	Liteau	リトー
    りどりんぐ	Riddling	リドリング
    りなろーる	Linalool	リナロール
    りばてーじょ	Ribatejo	リバテージョ
    りぱりあ	riparia	リパリア
    りべいらさくら	Ribeira Sacra	リベイラ・サクラ
    りべいろ	Ribeiro	リベイロ
    りべら	Rivera	リベラ
    りべらでるぐあでぃあな	Ribera del Guadiana	リベラ・デル・グアディアナ
    りべらでるどぅえろ	Ribera del Duero	リベラ・デル・ドゥエロ
    りぼっらじゃっら	Ribolla Gialla	リボッラ・ジャッラ
    りぼっりーた	Ribollita	リボッリータ
    りまり	Limarí	リマリ
    りまりゔぁれー	Limarí Valley	リマリ・ヴァレー
    りむにょ	Limnio	リムニョ
    りむー	Limoux	リムー
    りむーぶらんけっとどりむー	Limoux Blanquette de Limoux	リムー・ブランケット・ド・リムー
    りむーめとーどあんせすとらる	Limoux méthode ancestrale	リムー・メトード・アンセストラル
    りもんちぇっろ	Limoncello	リモンチェッロ
    りゃてぃこ	Liatiko	リャティコ
    りゅさっくさんてみりおん	Lussac Saint-Émilion	リュサック・サンテミリオン
    りゅしょっとしゃんべるたん	Ruchottes-Chambertin	リュショット・シャンベルタン
    りゅっとれぞね	Lutte raisonnée	リュット・レゾネ
    りゅび	Rubis	リュビ
    りゅべろん	Luberon	リュベロン
    りゅりー	Rully	リュリー
    りゅーせっく	Rieussec	リューセック
    りゅーでぃ	Lieu-dit	リュー・ディ
    りらっく	Lirac	リラック
    りりおりら	Liliorila	リリオリラ
    りるーえっと	Lillooet	リルーエット
    りれ	Lillet	リレ
    りゔぁねーる	Rivaner	リヴァネール
    りゔぁりーな	Riverina	リヴァリーナ
    りゔぁろ	Livarot	リヴァロ
    りゔぁーなー	Rivaner	リヴァーナー
    りゔぁーらんど	Riverland	リヴァーランド
    りゔぃえらりぐーれでぃぽねんて	Riviera Ligure di Ponente	リヴィエラ・リグーレ・デ・ィポネンテ
    りゔざると	Rivesaltes	リヴザルト
    りーじょなるわいんず	Regional Wines	リージョナル・ワインズ
    りーじょん	Region	リージョン
    りーすりんぐ	Riesling	リースリング
    りーすりんぐいたりこ	Riesling Italico	リースリング・イタリコ
    りーすりんぐせれくしおんどぐらんのーぶる	Riesling Sélection de Grains Nobles	リースリング・セレクシオン・ド・グラン・ノーブル
    りーすりんぐりおん	Riesling Lion	リースリング・リオン
    りーすりんぐゔぁんだんじゅたるでぃーゔ	Riesling Vendanges Tardives	リースリング・ヴァンダンジュ・タルディーヴ
    りーずすたーりんぐ	Lees stirring	リーズ・スターリング
    りーと	Ried	リート
    りーふぐろーす	Leaf growth	リーフ・グロース
    りーぷりっひ	Lieblich	リープリッヒ
    るいぃ	Reuilly	ルイィ
    るいすくらーくゔぁれー	Lewis-Clark Valley	ルイス・クラーク・ヴァレー
    るいぱすとぅーる	Louis Pasteur	ルイ・パストゥール
    るえだ	Rueda	ルエダ
    るかつぃてり	Rkatsiteli	ルカツィテリ
    るくさんぶーる	Luxembourg	ルクサンブール
    るくさんぶーるもーぜる	Luxembourg Mosel	ルクサンブール・モーゼル
    るけ	Ruchè	ルケ
    るけでぃかすたにょーれもんふぇっらーと	Ruchè di Castagnole Monferrato	ルケ・ディ・カスタニョーレ・モンフェッラート
    るすたーあうすぶるっふ	Ruster Ausbruch	ルスター・アウスブルッフ
    るどるふしゅたいなー	Rudolf Steiner	ルドルフ・シュタイナー
    るはんでくーよ	Luján de Cuyo	ルハン・デ・クーヨ
    るびん	Rubin	ルビン
    るびーかべるね	Ruby Cabernet	ルビー・カベルネ
    るぴあっく	Loupiac	ルピアック
    るふぃーな	Rufina	ルフィーナ
    るぶろしょん	Reblochon	ルブロション
    るぺすとりす	rupestris	ルペストリス
    るみゅあーじゅ	Remuage	ルミュアージュ
    るめにるしゅーろじぇ	Le Mesnil sur Oger	ル・メニル・シュー・ロジェ
    るもんたーじゅ	Remontage	ルモンタージュ
    るゔぉわ	Louvois	ルヴォワ
    るーさんぬ	Roussanne	ルーサンヌ
    るーしょん	Roussillon	ルーション
    るーじゅゔぃおれ	Rouge violet	ルージュ・ヴィオレ
    るーせっと	Roussette	ルーセット
    るーまにあ	Romania	ルーマニア
    るーむてんぱらちゃー	Room temperature	ルーム・テンパラチャー
    るーれんだー	Ruländer	ルーレンダー
    るーゔぁーたーる	Ruwertal	ルーヴァータール
    れあ	Rare	レア
    れいく	Lake	レイク
    れいくえりー	Lake Erie	レイク・エリー
    れいくえりーのーすしょあ	Lake Erie North Shore	レイク・エリー・ノース・ショア
    れいくかうんてぃ	Lake County	レイク・カウンティ
    れいくかんとりー	Lake Country	レイク・カントリー
    れいくさんぴえーる	Lake Saint-Pierre	レイク・サン・ピエール
    れいくどくたー	Lake Doctor	レイク・ドクター
    れいだ	Leyda	レイダ
    れいだゔぁれー	Leyda Valley	レイダ・ヴァレー
    れいとぼとるどゔぃんてーじぽーと	Late Bottled Vintage Port	レイト・ボトルド・ヴィンテージ・ポート
    れいとろん	Leytron	レイトロン
    れおにゃん	Léognan	レオニャン
    れおぼあむ	Réhoboam	レオボアム
    れおゔぃるばるとん	Léoville-Barton	レオヴィル・バルトン
    れおゔぃるぽわふぇれ	Léoville-Poyferré	レオヴィル・ポワフェレ
    れおゔぃるらすかーず	Léoville-Las Cases	レオヴィル・ラス・カーズ
    れかずてぃえ	Les Cazetiers	レ・カズティエ
    れくろ	Les Clos	レ・クロ
    れげんと	Regent	レゲント
    れこるたんこーぺらとぅーる	Récoltant-Coopérateur	レコルタン・コーペラトゥール
    れこるたんまにぴゅらん	Récoltant-Manipulant	レコルタン・マニピュラン
    れざむるーず	Les Amoureuses	レ・ザムルーズ
    れしゃるむ	Les Charmes	レ・シャルム
    れしゅしょ	Les Suchots	レ・シュショ
    れじぇんと	Regent	レジェント
    れすゔぇらとろーる	Resveratrol	レスヴェラトロール
    れせるば	Reserva	レセルバ
    れせるばえすぺしある	Reserva Especial	レセルバ・エスペシアル
    れせるばぷりばーだ	Reserva Privada	レセルバ・プリバーダ
    れぜるゔ	Réserve	レゼルヴ
    れぜるゔぁ	Rezervă	レゼルヴァ
    れちょーと	Recioto	レチョート
    れちょーとでぃがんべっらーら	Recioto di Gambellara	レチョート・ディ・ガンベッラーラ
    れちょーとでぃそあーゔぇ	Recioto di Soave	レチョート・ディ・ソアーヴェ
    れちょーとでっらゔぁるぽりちぇっら	Recioto della Valpolicella	レチョート・デッラ・ヴァルポリチェッラ
    れっどみすけっと	Red Misket	レッド・ミスケット
    れっどみるれんにゅーむ	Red Millennium	レッド・ミルレンニューム
    れっどみれにあむ	Red Millennium	レッド・ミレニアム
    れつぃーな	Retsina	レツィーナ
    れてぃゔぁ	L'Etivaz	レティヴァ
    れでのゔぃーの	Ledeno vino	レデノ・ヴィーノ
    れとわーる	L'Étoile	レトワール
    れにえ	Régnié	レニエ
    れぴゅせる	Les Pucelles	レ・ピュセル
    れふぉしゅく	Refošk	レフォシュク
    れふぉすこだるぺどぅんころろっそ	Refosco dal Peduncolo Rosso	レフォスコ・ダル・ペドゥンコロ・ロッソ
    れふりじぇれ	Réfrigéré	レフリジェレ
    れぼーどぷろゔぁんす	Les Baux de Provence	レ・ボー・ド・プロヴァンス
    れぽさーど	Reposado	レポサード
    れまるこね	Les Marconnets	レ・マルコネ
    れみっひ	Remich	レミッヒ
    れりゅじゃんば	Les Rugiens-Bas	レ・リュジャン・バ
    れんすきりーずりんぐ	Renski Rizling	レンスキ・リーズリング
    れんつもーざー	Lenz Moser	レンツ・モーザー
    れんべるがー	Lemberger	レンベルガー
    れゔぁだす	Levadas	レヴァダス
    ろいやるすろーぷ	Royal Slope	ロイヤル・スロープ
    ろうぺいろ	Roupeiro	ロウペイロ
    ろうれいろ	Loureiro	ロウレイロ
    ろえーろ	Roero	ロエーロ
    ろされほ	Rosalejo	ロサレホ
    ろざっつぉ	Rosazzo	ロザッツォ
    ろざりあ	Rosalia	ロザリア
    ろしあんりゔぁーゔぁれー	Russian River Valley	ロシアン・リヴァー・ヴァレー
    ろすかーねろす	Los Carneros	ロス・カーネロス
    ろすせろすでさんふあん	Los Cerros de San Juan	ロス・セロス・デ・サン・フアン
    ろぜだんじゅー	Rosé d'Anjou	ロゼ・ダンジュー
    ろぜっと	Rosette	ロゼット
    ろぜでりせー	Rosé des Riceys	ロゼ・デ・リセー
    ろぜどろわーる	Rosé de Loire	ロゼ・ド・ロワール
    ろぜばいん	Roséwein	ロゼバイン
    ろぜべんこゔぁっつ	Rosé Benkovac	ロゼ・ベンコヴァッツ
    ろぜぽると	Rose Port	ロゼ・ポルト
    ろたんどん	Rotundone	ロタンドン
    ろっくぱいる	Rockpile	ロックパイル
    ろっくふぉーる	Roquefort	ロックフォール
    ろっせーぜ	Rossese	ロッセーゼ
    ろっせーぜでぃどるちぇあくあ	Rossese di Dolceacqua	ロッセーゼ・ディ・ドルチェアクア
    ろっとえがろんぬ	Lot-et-Garonne	ロット・エ・ガロンヌ
    ろでぃてぃす	Roditis	ロディティス
    ろどす	Rhodes	ロドス
    ろにゃーじゅ	Rognage	ロニャージュ
    ろばーとそん	Robertson	ロバートソン
    ろびおらでぃろっかゔぇらーの	Robiola di Roccaverano	ロビオラ・ディ・ロッカヴェラーノ
    ろぼら	Robola	ロボラ
    ろぼらおゔけふぁろにあ	Robola of Cephalonia	ロボラ・オヴ・ケファロニア
    ろまねこんてぃ	Romanée-Conti	ロマネ・コンティ
    ろまねさんゔぃゔぁん	Romanée-Saint-Vivant	ロマネ・サン・ヴィヴァン
    ろまねしゅてぃ	Romăneşti	ロマネシュティ
    ろまーにゃあるばーな	Romagna Albana	ロマーニャ・アルバーナ
    ろもらんたん	Romorantin	ロモランタン
    ろれーぬ	Lorraine	ロレーヌ
    ろわーる	Loire	ロワール
    ろわーろんぐとむ	Lower Long Tom	ロワー・ロング・トム
    ろんぐあいらんど	Long Island	ロング・アイランド
    ろんとぅえゔぁれー	Lontué Valley	ロントゥエ・ヴァレー
    ろんどん	London	ロンドン
    ろんばるでぃあ	Lombardia	ロンバルディア
    ろーいんぷっとゔぃてぃかるちゃー	Low Input Viticulture	ロー・インプット・ヴィティカルチャー
    ろーぐゔぁれー	Rogue Valley	ローグ・ヴァレー
    ろーざんがしー	Rauzan-Gassies	ローザン・ガシー
    ろーざんせぐら	Rauzan-Ségla	ローザン・セグラ
    ろーたーふぇるとりーなー	Roter Veltliner	ローター・フェルトリーナー
    ろーたーゔぇるとりーなー	Roter Veltliner	ローター・ヴェルトリーナー
    ろーだい	Lodi	ローダイ
    ろーだいるーるず	Lodi Rules	ローダイ・ルールズ
    ろーとぎぷふらー	Rotgipfler	ロートギプフラー
    ろーとぶるがー	Rotburger	ロートブルガー
    ろーとりんぐ	Rotling	ロートリング
    ろーぬ	Rhône	ローヌ
    ろーる	Rolle	ロール
    ろーれらい	Loreley	ローレライ
    ろーれるうっどでぃすとりくと	Laurelwood District	ローレルウッド・ディストリクト
    ろーれんつもーざー	Laurenz Moser III	ローレンツ・モーザー
    わいたきゔぁれーのーすおたご	Waitaki Valley North Otago	ワイタキ・ヴァレー・ノース・オタゴ
    わいたんぎ	Waitangi	ワイタンギ
    わいぱらゔぁれー	Waipara Valley	ワイパラ・ヴァレー
    わいへけあいらんど	Waiheke Island	ワイヘケ・アイランド
    わいめあぷれいんず	Waimea Plains	ワイメア・プレインズ
    わいらうゔぁれー	Wairau Valley	ワイラウ・ヴァレー
    わいららぱ	Wairarapa	ワイララパ
    わいるどほーすゔぁれー	Wild Horse Valley	ワイルド・ホース・ヴァレー
    わいん	Wine	ワイン
    わいんあどゔぉけいと	Wine Advocate	ワイン・アドヴォケイト
    わいんいにしあてぃゔ	Wine Initiative	ワイン・イニシアティヴ
    わいんえんすーじあすと	Wine Enthusiast	ワイン・エンスージアスト
    わいんおゔおりじん	Wine of Origin	ワイン・オヴ・オリジン
    わいんおゔゆないてっどきんぐだむ	Wine of United Kingdom	ワイン・オヴ・ユナイテッド・キングダム
    わいんすぴりっつ	Wine Spirits	ワインスピリッツ
    わいんすぺくてーたー	Wine Spectator	ワイン・スペクテーター
    わしんとん	Washington	ワシントン
    わなか	Wanaka	ワナカ
    わらわらゔぁれー	Walla Walla Valley	ワラ・ワラ・ヴァレー
    わーど	Ward	ワード
    ゔぁいさーぶるぐんだー	Weißer Burgunder	ヴァイサー・ブルグンダー
    ゔぁいすぶるぐんだー	Weißburgunder	ヴァイスブルグンダー
    ゔぁいすへるぷすと	Weißherbst	ヴァイスヘルプスト
    ゔぁいよん	Vaillons	ヴァイヨン
    ゔぁいんふぃあてる	Weinviertel	ヴァインフィアテル
    ゔぁかれーず	Vaccarèse	ヴァカレーズ
    ゔぁきゅーむでぃすてぃれーしょん	Vacuum distillation	ヴァキューム・ディスティレーション
    ゔぁぐらむ	Wagram	ヴァグラム
    ゔぁけいらす	Vacqueyras	ヴァケイラス
    ゔぁしゅらんもんどーる	Vacherin Mont d'Or	ヴァシュラン・モン・ドール
    ゔぁっはう	Wachau	ヴァッハウ
    ゔぁっれだおすた	Valle d'Aosta	ヴァッレ・ダオスタ
    ゔぁらいえたる	Varietal	ヴァライエタル
    ゔぁらいえたるわいん	Varietal Wine	ヴァライエタル・ワイン
    ゔぁらんせ	Valençay	ヴァランセ
    ゔぁらんどろー	Valandraud	ヴァランドロー
    ゔぁりさーらくれっと	Walliser Raclette	ヴァリサー・ラクレット
    ゔぁるだるのでぃそぷら	Val d'Arno di Sopra	ヴァルダルノ・ディ・ソプラ
    ゔぁるてっりーなすぺりおーれ	Valtellina Superiore	ヴァルテッリーナ・スペリオーレ
    ゔぁるどろわーる	Val de Loire	ヴァル・ド・ロワール
    ゔぁるぽりちぇっら	Valpolicella	ヴァルポリチェッラ
    ゔぁるみゅーる	Valmur	ヴァルミュール
    ゔぁるるるいとらやん	Valul lui Traian	ヴァルル・ルイ・トラヤン
    ゔぁれでゅろーぬ	Vallée du Rhône	ヴァレ・デュ・ローヌ
    ゔぁれー	Valais	ヴァレー
    ゔぁれーどらまるぬ	Vallée de la Marne	ヴァレー・ド・ラ・マルヌ
    ゔぁん	vin	ヴァン
    ゔぁんくーゔぁーあいらんど	Vancouver Island	ヴァンクーヴァー・アイランド
    ゔぁんぐり	Vin Gris	ヴァン・グリ
    ゔぁんじょーぬ	Vin Jaune	ヴァン・ジョーヌ
    ゔぁんそーぶる	Vinsobres	ヴァンソーブル
    ゔぁんだんじゅ	Vendange	ヴァンダンジュ
    ゔぁんだんじゅたるでぃーゔ	Vendanges Tardives	ヴァンダンジュ・タルディーヴ
    ゔぁんでぐらしえ	Vin des Glaciers	ヴァン・デ・グラシエ
    ゔぁんとぅー	Ventoux	ヴァントゥー
    ゔぁんどぅーなちゅれる	Vin Doux Naturel|Vin doux naturel	ヴァン・ドゥー・ナチュレル
    ゔぁんどぐらす	vin de glace	ヴァン・ド・グラス
    ゔぁんどこるす	Vin de Corse	ヴァン・ド・コルス
    ゔぁんどこるすことーでゅかっぷこるす	Vin de Corse Coteaux du Cap Corse	ヴァン・ド・コルス・コトー・デュ・カップ・コルス
    ゔぁんどこるすふぃがり	Vin de Corse Figari	ヴァン・ド・コルス・フィガリ
    ゔぁんどこんすたんす	Vin de Constance	ヴァン・ド・コンスタンス
    ゔぁんどさゔぉわ	Vin de Savoie	ヴァン・ド・サヴォワ
    ゔぁんどたーぶる	Vin de Table	ヴァン・ド・ターブル
    ゔぁんどぱいゆ	Vin de Paille	ヴァン・ド・パイユ
    ゔぁんどふらんす	Vin de France	ヴァン・ド・フランス
    ゔぁんどぷりむーる	Vin de Primeur	ヴァン・ド・プリムール
    ゔぁんどぺい	Vin de Pays	ヴァン・ド・ペイ
    ゔぁんどりきゅーる	Vin de Liqueur	ヴァン・ド・リキュール
    ゔぁんびおろじっく	Vin biologique	ヴァン・ビオロジック
    ゔぁんりあすとす	Vin liastos	ヴァン・リアストス
    ゔぁーぐらむ	Wagram	ヴァーグラム
    ゔぁーじにあ	Virginia	ヴァージニア
    ゔぁーてぃかるしゅーとぽじしょん	Vertical Shoot Position	ヴァーティカル・シュート・ポジション
    ゔぃえいゆれぜるゔ	Vieille Réserve	ヴィエイユ・レゼルヴ
    ゔぃおにえ	Viognier	ヴィオニエ
    ゔぃおりか	Viorica	ヴィオリカ
    ゔぃおれ	Violet	ヴィオレ
    ゔぃくとりあ	Victoria	ヴィクトリア
    ゔぃぜう	Viseu	ヴィゼウ
    ゔぃだる	Vidal	ヴィダル
    ゔぃだるぶらん	Vidal Blanc	ヴィダル・ブラン
    ゔぃっくす	Vix	ヴィックス
    ゔぃってる	Vittel	ヴィッテル
    ゔぃっらーに	Villány	ヴィッラーニ
    ゔぃてぃすあむれんしす	Vitis amurensis	ヴィティス・アムレンシス
    ゔぃてぃすこわにてぃ	V. coignetiae|Vitis coignetiae	ヴィティス・コワニティ
    ゔぃてぃすだゔぃでぃ	Vitis davidii	ヴィティス・ダヴィディ
    ゔぃてぃすべるらんでぃえり	V. berlandieri|Vitis berlandieri	ヴィティス・ベルランディエリ
    ゔぃてぃすらぶるすか	Vitis labrusca	ヴィティス・ラブルスカ
    ゔぃてぃすりぱりあ	V. riparia|Vitis riparia	ヴィティス・リパリア
    ゔぃてぃするぺすとりす	V. rupestris|Vitis rupestris	ヴィティス・ルペストリス
    ゔぃてぃすゔぃにふぇら	Vitis vinifera	ヴィティス・ヴィニフェラ
    ゔぃてっろとんなーと	Vitello Tonnato	ヴィテッロ・トンナート
    ゔぃでぃえら	Vidiella	ヴィディエラ
    ゔぃにふぇら	vinifera	ヴィニフェラ
    ゔぃにゃどれすでかりにゃん	Vignadores de Carignan	ヴィニャドレス・デ・カリニャン
    ゔぃにゃん	Vinhão	ヴィニャン
    ゔぃのごりぇ	Vinogorje	ヴィノゴリェ
    ゔぃのろっく	Vinolok	ヴィノロック
    ゔぃらのーゔぁでがいあ	Vila Nova de Gaia	ヴィラ・ノーヴァ・デ・ガイア
    ゔぃるてぃんげん	Wiltingen	ヴィルティンゲン
    ゔぃれくれっせ	Viré-Clessé	ヴィレ・クレッセ
    ゔぃんける	Winkel	ヴィンケル
    ゔぃんさんと	Vin Santo|Vinsanto	ヴィンサント|ヴィン・サント
    ゔぃんてーじ	Vintage	ヴィンテージ
    ゔぃんてーじかば	Vintage Cava	ヴィンテージ・カバ
    ゔぃんてーじぽーと	Vintage Port	ヴィンテージポート|ヴィンテージ・ポート
    ゔぃんでゔぃのてか	Vin de vinotecă	ヴィン・デ・ヴィノテカ
    ゔぃんとぅなる	Vin tânăr	ヴィン・トゥナル
    ゔぃんとなーずくおりてぃあらいあんす	Vintners Quality Alliance	ヴィントナーズ・クオリティ・アライアンス
    ゔぃんゔぁりえたる	Vin Varietal	ヴィン・ヴァリエタル
    ゔぃーなーげみしゅたーさっつ	Wiener Gemischter Satz	ヴィーナー・ゲミシュター・サッツ
    ゔぃーにゃあおあると	Vinha ao alto	ヴィーニャ・アオ・アルト
    ゔぃーにょ	Vinho	ヴィーニョ
    ゔぃーにょれじょなる	Vinho Regional	ヴィーニョ・レジョナル
    ゔぃーにょゔぇるで	Vinho Verde	ヴィーニョ・ヴェルデ
    ゔぃーのあいんでぃかつぃおーねじぇおぐらーふぃかぷろてった	Vino a Indicazione Geografica Protetta	ヴィーノ・ア・インディカツィオーネジェオ・グラーフィカ・プロテッタ
    ゔぃーのあろまてぃっざーと	Vino Aromatizzato	ヴィーノ・アロマティッザート
    ゔぃーののびれでぃもんてぷるちあーの	Vino Nobile di Montepulciano	ヴィーノ・ノビレ・ディ・モンテプルチアーノ
    ゔぃーののゔぇっろ	Vino Novello	ヴィーノ・ノヴェッロ
    ゔぇすとしゅたいあーまるく	Weststeiermark	ヴェストシュタイアーマルク
    ゔぇすとしゅたいやーまるく	Weststeiermark	ヴェストシュタイヤーマルク
    ゔぇすーゔぃお	Vesuvio	ヴェスーヴィオ
    ゔぇずれー	Vézelay	ヴェズレー
    ゔぇとろ	Vétroz	ヴェトロ
    ゔぇねつぃあ	Venezia	ヴェネツィア
    ゔぇねと	Veneto	ヴェネト
    ゔぇりーおーるどしぇりー	Very Old Sherry	ヴェリー・オールド・シェリー
    ゔぇりーおーるどれあしぇりー	Very Old Rare Sherry	ヴェリー・オールド・レア・シェリー
    ゔぇるこりん	Velcorin®	ヴェルコリン
    ゔぇるしゅりーすりんぐ	Welschriesling	ヴェルシュリースリング
    ゔぇるじー	Verzy	ヴェルジー
    ゔぇるずねー	Verzenay	ヴェルズネー
    ゔぇるで	Verde	ヴェルデ
    ゔぇるであ	Verdea	ヴェルデア
    ゔぇるであとらでぃしょなるでじぐねーしょんおゔざきんとす	Verdea, Traditional Designation of Zakynthos	ヴェルデア・トラディショナル・デジグネーション・オヴ・ザキントス
    ゔぇるでぃっきお	Verdicchio	ヴェルディッキオ
    ゔぇるでぃっきおでぃまてりかりぜるゔぁ	Verdicchio di Matelica Riserva	ヴェルディッキオ・ディ・マテリカ・リゼルヴァ
    ゔぇるでほ	Verdejo	ヴェルデホ
    ゔぇるでーりょ	Verdelho	ヴェルデーリョ
    ゔぇると	Verte	ヴェルト
    ゔぇるどぅっつぉ	Verduzzo	ヴェルドゥッツォ
    ゔぇるどぅっつぉふりうらーの	Verduzzo Friulano	ヴェルドゥッツォ・フリウラーノ
    ゔぇるなっちゃでぃおりすたーの	Vernaccia di Oristano	ヴェルナッチャ・ディ・オリスターノ
    ゔぇるなっちゃでぃさんじみにゃーの	Vernaccia di San Gimignano	ヴェルナッチャ・ディ・サン・ジミニャーノ
    ゔぇるなっちゃでぃせっらぺとろーな	Vernaccia di Serrapetrona	ヴェルナッチャ・ディ・セッラペトローナ
    ゔぇるなっちゃねーら	Vernaccia Nera	ヴェルナッチャ・ネーラ
    ゔぇるむーと	Vermut	ヴェルムート
    ゔぇるむーとでぃとりーの	Vermut di Torino	ヴェルムート・ディ・トリーノ
    ゔぇるめんてぃーの	Vermentino	ヴェルメンティーノ
    ゔぇるめんてぃーのでぃがっるーら	Vermentino di Gallura	ヴェルメンティーノ・ディ・ガッルーラ
    ゔぇるもっと	Vermouth	ヴェルモット
    ゔぇれぞん	Véraison	ヴェレゾン
    ゔぇーでんすゔぃるくろーん	Wädenswil clone	ヴェーデンスヴィル・クローン
    ゔぉすあーてぃざん	Voss Artisan	ヴォス・アーティザン
    ゔぉるてぃす	Voltis	ヴォルティス
    ゔぉるねい	Volnay	ヴォルネイ
    ゔぉるゔぃっく	Volvic	ヴォルヴィック
    ゔぉんねがう	Wonnegau	ヴォンネガウ
    ゔぉー	Vaud	ヴォー
    ゔぉーでじーる	Vaudésir	ヴォーデジール
    ゔぉーぬろまね	Vosne-Romanée	ヴォーヌ・ロマネ
    ゔぉーぬろまねぐらんくりゅ	Vosne-Romanée Grand Cru	ヴォーヌ・ロマネ・グラン・クリュ
    ゔゅふらん	Vufflens	ヴュフラン
    ゔゅりー	Vully	ヴュリー
    ゔゅるつがるてん	Würzgarten	ヴュルツガルテン
    ゔゅるてんべるく	Württemberg	ヴュルテンベルク
    ゔゅー	Vieux	ヴュー
    ゔるふんすこ	Vrhunsko	ヴルフンスコ
    ゔるふんすこゔぃの	Vrhunsko vino	ヴルフンスコ・ヴィノ
    ゔるふんすこゔぃーのさこんとぅろりらにむぽどぅりえとぅろむ	Vrhunsko vino s kontroliranim podrijetlom	ヴルフンスコ・ヴィーノ・サ・コントゥロリラニム・ポドゥリエトゥロム
    ゔーじょ	Vougeot	ヴージョ
    ゔーゔれ	Vouvray	ヴーヴレ
    ゔーゔれぺてぃやん	Vouvray Pétillant	ヴーヴレ・ペティヤン
    ゔーゔれむすー	Vouvray Mousseux	ヴーヴレ・ムスー
    """
}
