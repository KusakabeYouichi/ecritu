import Foundation

enum AppleEmojiCatalog {
    // 顔と人。サブグループごとに区切り線を挟む。
    static let peopleSections: [[String]] = [
        // スマイリー・感情
        ["😀", "😃", "😄", "😁", "😆", "🥹", "😅", "😂", "🤣", "🥲", "☺️", "😊", "😇", "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗", "😙", "😚", "😋", "😛", "😝", "😜", "🤪", "🤨", "🧐", "🤓", "😎", "🥸", "🤩", "🥳", "🙂‍↕️", "😏", "😒", "🙂‍↔️", "😞", "😔", "😟", "😕", "🙁", "☹️", "😣", "😖", "😫", "😩", "🥺", "😢", "😭", "😤", "😠", "😡", "🤬", "🤯", "😳", "🥵", "🥶", "😶‍🌫️", "😱", "😨", "😰", "😥", "😓", "🤗", "🤔", "🫣", "🤭", "🫢", "🫡", "🤫", "🫠", "🤥", "😶", "🫥", "😐", "🫤", "😑", "🫨", "😬", "🙄", "😯", "😦", "😧", "😮", "😲", "🥱", "🫩", "🫪", "😴", "🤤", "😪", "😮‍💨", "😵", "😵‍💫", "🤐", "🥴", "🤢", "🤮", "🤧", "😷", "🤒", "🤕", "🤑", "🤠"],
        // 悪魔・モンスター
        ["😈", "👿", "👹", "👺", "🤡", "💩", "👻", "💀", "☠️", "👽", "👾", "🤖", "🎃"],
        // 猫の顔
        ["😺", "😸", "😹", "😻", "😼", "😽", "🙀", "😿", "😾"],
        // 手・ジェスチャー
        ["🫶", "🤲", "👐", "🙌", "👏", "🤝", "👍", "👎", "👊", "✊", "🤛", "🤜", "🫷", "🫸", "🤞", "✌️", "🫰", "🤟", "🤘", "👌", "🤌", "🤏", "🫳", "🫴", "👈", "👉", "👆", "👇", "☝️", "✋", "🤚", "🖐️", "🖖", "👋", "🤙", "🫲", "🫱", "💪", "🦾", "🖕", "✍️", "🙏", "🫵"],
        // 体のパーツ
        ["🦶", "🦵", "🦿", "💄", "💋", "👄", "🫦", "🦷", "👅", "👂", "🦻", "👃", "🫆", "👣", "👁️", "👀", "🫀", "🫁", "🧠", "🗣️", "👤", "👥", "🫂"],
        // 人物(年齢・髪型)
        ["👶", "👧", "🧒", "👦", "👩", "🧑", "👨", "👩‍🦱", "🧑‍🦱", "👨‍🦱", "👩‍🦰", "🧑‍🦰", "👨‍🦰", "👱‍♀️", "👱", "👱‍♂️", "👩‍🦳", "🧑‍🦳", "👨‍🦳", "👩‍🦲", "🧑‍🦲", "👨‍🦲", "🧔‍♀️", "🧔", "🧔‍♂️", "👵", "🧓", "👴", "👲", "👳‍♀️", "👳", "👳‍♂️", "🧕"],
        // 職業
        ["👮‍♀️", "👮", "👮‍♂️", "👷‍♀️", "👷", "👷‍♂️", "💂‍♀️", "💂", "💂‍♂️", "🕵️‍♀️", "🕵️", "🕵️‍♂️", "👩‍⚕️", "🧑‍⚕️", "👨‍⚕️", "👩‍🌾", "🧑‍🌾", "👨‍🌾", "👩‍🍳", "🧑‍🍳", "👨‍🍳", "👩‍🎓", "🧑‍🎓", "👨‍🎓", "👩‍🎤", "🧑‍🎤", "👨‍🎤", "👩‍🏫", "🧑‍🏫", "👨‍🏫", "👩‍🏭", "🧑‍🏭", "👨‍🏭", "👩‍💻", "🧑‍💻", "👨‍💻", "👩‍💼", "🧑‍💼", "👨‍💼", "👩‍🔧", "🧑‍🔧", "👨‍🔧", "👩‍🔬", "🧑‍🔬", "👨‍🔬", "👩‍🎨", "🧑‍🎨", "👨‍🎨", "👩‍🚒", "🧑‍🚒", "👨‍🚒", "👩‍✈️", "🧑‍✈️", "👨‍✈️", "👩‍🚀", "🧑‍🚀", "👨‍🚀", "👩‍⚖️", "🧑‍⚖️", "👨‍⚖️"],
        // 婚礼・王族・ファンタジー
        ["👰‍♀️", "👰", "👰‍♂️", "🤵‍♀️", "🤵", "🤵‍♂️", "👸", "🫅", "🤴", "🥷", "🦸‍♀️", "🦸", "🦸‍♂️", "🦹‍♀️", "🦹", "🦹‍♂️", "🤶", "🧑‍🎄", "🎅", "🧙‍♀️", "🧙", "🧙‍♂️", "🧝‍♀️", "🧝", "🧝‍♂️", "🧌", "🧛‍♀️", "🧛", "🧛‍♂️", "🧟‍♀️", "🧟", "🧟‍♂️", "🧞‍♀️", "🧞", "🧞‍♂️", "🧜‍♀️", "🧜", "🧜‍♂️", "🧚‍♀️", "🧚", "🧚‍♂️", "👼"],
        // 妊娠・育児
        ["🤰", "🫄", "🫃", "🤱", "👩‍🍼", "🧑‍🍼", "👨‍🍼"],
        // 全身ジェスチャー・動作
        ["🙇‍♀️", "🙇", "🙇‍♂️", "💁‍♀️", "💁", "💁‍♂️", "🙅‍♀️", "🙅", "🙅‍♂️", "🙆‍♀️", "🙆", "🙆‍♂️", "🙋‍♀️", "🙋", "🙋‍♂️", "🧏‍♀️", "🧏", "🧏‍♂️", "🤦‍♀️", "🤦", "🤦‍♂️", "🤷‍♀️", "🤷", "🤷‍♂️", "🙎‍♀️", "🙎", "🙎‍♂️", "🙍‍♀️", "🙍", "🙍‍♂️", "💇‍♀️", "💇", "💇‍♂️", "💆‍♀️", "💆", "💆‍♂️", "🧖‍♀️", "🧖", "🧖‍♂️", "💅", "🤳", "💃", "🕺", "🧑‍🩰", "👯‍♀️", "👯", "👯‍♂️", "🕴️", "👩‍🦽", "🧑‍🦽", "👨‍🦽", "👩‍🦽‍➡️", "🧑‍🦽‍➡️", "👨‍🦽‍➡️", "👩‍🦼", "🧑‍🦼", "👨‍🦼", "👩‍🦼‍➡️", "🧑‍🦼‍➡️", "👨‍🦼‍➡️", "🚶‍♀️", "🚶", "🚶‍♂️", "🚶‍♀️‍➡️", "🚶‍➡️", "🚶‍♂️‍➡️", "👩‍🦯", "🧑‍🦯", "👨‍🦯", "👩‍🦯‍➡️", "🧑‍🦯‍➡️", "👨‍🦯‍➡️", "🧎‍♀️", "🧎", "🧎‍♂️", "🏃‍♀️", "🏃", "🏃‍♂️", "🏃‍♀️‍➡️", "🏃‍➡️", "🏃‍♂️‍➡️", "🧎‍♀️‍➡️", "🧎‍➡️", "🧎‍♂️‍➡️", "🧍‍♀️", "🧍", "🧍‍♂️"],
        // カップル・人間関係
        ["👫", "👭", "👬", "👩‍❤️‍👨", "👩‍❤️‍👩", "💑", "👨‍❤️‍👨", "👩‍❤️‍💋‍👨", "👩‍❤️‍💋‍👩", "💏", "👨‍❤️‍💋‍👨"],
        // 衣類・小物
        ["🪢", "🧶", "🧵", "🪡", "🧥", "🥼", "🦺", "👚", "👕", "👖", "🩲", "🩳", "👔", "👗", "👙", "🩱", "👘", "🥻", "🩴", "🥿", "👠", "👡", "👢", "👞", "👟", "🥾", "🧦", "🧤", "🧣", "🎩", "🧢", "👒", "🎓", "⛑️", "🪖", "👑", "💍", "👝", "👛", "👜", "💼", "🎒", "🧳", "👓", "🕶️", "🥽", "🌂"],
    ]

    static let people: [String] = peopleSections.flatMap { $0 }

    // 動物と自然。分類(動物の顔/ほ乳類/鳥/虫/爬虫類/海/植物/天体/天気)ごとに区切り線を挟む。
    static let natureSections: [[String]] = [
        // 動物の顔(定番)
        ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐻‍❄️", "🐨", "🐯", "🦁", "🐮", "🐷", "🐽", "🐸", "🐵", "🙈", "🙉", "🙊", "🐒", "🐺", "🐗", "🐴", "🦄"],
        // ほ乳類
        ["🫎", "🐅", "🐆", "🦓", "🦍", "🦧", "🫈", "🦣", "🐘", "🦛", "🦏", "🐪", "🐫", "🦒", "🦘", "🦬", "🐃", "🐂", "🐄", "🫏", "🐎", "🐖", "🐏", "🐑", "🦙", "🐐", "🦌", "🐕", "🐩", "🦮", "🐕‍🦺", "🐈", "🐈‍⬛", "🐇", "🦝", "🦨", "🦡", "🦫", "🦦", "🦥", "🐁", "🐀", "🐿️", "🦔", "🦇", "🐾"],
        // 鳥
        ["🐔", "🐧", "🐦", "🐤", "🐣", "🐥", "🪿", "🦆", "🐦‍⬛", "🦅", "🦉", "🪶", "🪽", "🐓", "🦃", "🦤", "🦚", "🦜", "🦢", "🦩", "🕊️"],
        // 虫
        ["🐝", "🪱", "🐛", "🦋", "🐌", "🐞", "🐜", "🪰", "🪲", "🪳", "🦟", "🦗", "🕷️", "🕸️", "🦂"],
        // 爬虫類・恐竜・竜
        ["🐢", "🐍", "🦎", "🦖", "🦕", "🐊", "🐉", "🐲", "🐦‍🔥"],
        // 海の生き物
        ["🐙", "🦑", "🪼", "🦐", "🦞", "🦀", "🐡", "🐠", "🐟", "🐬", "🐳", "🐋", "🫍", "🦈", "🦭", "🐚", "🪸"],
        // 植物・花
        ["🌵", "🎄", "🌲", "🌳", "🌴", "🪾", "🪵", "🌱", "🌿", "☘️", "🍀", "🎍", "🪴", "🎋", "🍃", "🍂", "🍁", "🪺", "🪹", "🍄", "🍄‍🟫", "🪨", "🛘", "🌾", "💐", "🌷", "🌹", "🥀", "🪻", "🪷", "🌺", "🌸", "🌼", "🌻"],
        // 天体
        ["🌞", "🌝", "🌛", "🌜", "🌚", "🌕", "🌖", "🌗", "🌘", "🌑", "🌒", "🌓", "🌔", "🌙", "🌎", "🌍", "🌏", "🪐", "💫", "⭐️", "🌟", "✨"],
        // 天気・自然現象
        ["⚡️", "☄️", "💥", "🔥", "🫯", "🌪️", "🌈", "☀️", "🌤️", "⛅️", "🌥️", "☁️", "🌦️", "🌧️", "⛈️", "🌩️", "🌨️", "❄️", "☃️", "⛄️", "🌬️", "💨", "💧", "💦", "🫧", "☔️", "☂️", "🌊", "🌫️"],
    ]

    static let nature: [String] = natureSections.flatMap { $0 }

    // 食べ物と飲み物。サブグループ(飲み物→果物→野菜→料理→お菓子→食器)ごとに区切り線を挟む。
    static let foodAndDrinkSections: [[String]] = [
        // 飲み物
        ["🍷", "🍾", "🥂", "🍺", "🍻", "🍸", "🍹", "🥃", "🍶", "🧊", "🍵", "☕️", "🫖", "🥤", "🍼", "🥛", "🫗", "🧃", "🧋", "🧉"],
        // 果物(ぶどうを先頭)
        ["🍇", "🍏", "🍎", "🍐", "🍊", "🍋", "🍋‍🟩", "🍌", "🍉", "🍓", "🫐", "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝"],
        // 野菜
        ["🍅", "🍆", "🥑", "🫛", "🥦", "🥬", "🥒", "🌶️", "🫑", "🌽", "🥕", "🫒", "🧄", "🧅", "🥔", "🫜", "🍠", "🫚"],
        // 料理(パン・卵・肉・麺・ご飯 など)
        ["🥐", "🥯", "🍞", "🥖", "🥨", "🧀", "🥚", "🍳", "🧈", "🥞", "🧇", "🥓", "🥩", "🍗", "🍖", "🦴", "🌭", "🍔", "🍟", "🍕", "🫓", "🥪", "🥙", "🧆", "🌮", "🌯", "🫔", "🥗", "🥘", "🫕", "🥫", "🫙", "🍝", "🍜", "🍲", "🍛", "🍣", "🍱", "🥟", "🦪", "🍤", "🍙", "🍚", "🍘", "🍥", "🥠", "🥮", "🍢", "🍡"],
        // お菓子・スイーツ
        ["🍧", "🍨", "🍦", "🥧", "🧁", "🍰", "🎂", "🍮", "🍭", "🍬", "🍫", "🍿", "🍩", "🍪", "🌰", "🥜", "🫘", "🍯"],
        // 食器・調味料
        ["🥄", "🍴", "🍽️", "🥣", "🥡", "🥢", "🧂"],
    ]

    static let foodAndDrink: [String] = foodAndDrinkSections.flatMap { $0 }

    // 行動。サブグループごとに区切り線を挟む。
    static let activitySections: [[String]] = [
        // スポーツ用具・ウィンター
        ["🎽", "🛹", "🛼", "🛷", "⛸️", "🥌", "🎿", "⛷️", "🏂", "🪂"],
        // 運動する人
        ["🏋️‍♀️", "🏋️", "🏋️‍♂️", "🤼‍♀️", "🤼", "🤼‍♂️", "🤸‍♀️", "🤸", "🤸‍♂️", "⛹️‍♀️", "⛹️", "⛹️‍♂️", "🤺", "🤾‍♀️", "🤾", "🤾‍♂️", "🏌️‍♀️", "🏌️", "🏌️‍♂️", "🏇", "🧘‍♀️", "🧘", "🧘‍♂️", "🏄‍♀️", "🏄", "🏄‍♂️", "🏊‍♀️", "🏊", "🏊‍♂️", "🤽‍♀️", "🤽", "🤽‍♂️", "🚣‍♀️", "🚣", "🚣‍♂️", "🧗‍♀️", "🧗", "🧗‍♂️", "🚵‍♀️", "🚵", "🚵‍♂️", "🚴‍♀️", "🚴", "🚴‍♂️"],
        // トロフィー・チケット
        ["🏆", "🥇", "🥈", "🥉", "🏅", "🎖️", "🏵️", "🎗️", "🎫", "🎟️"],
        // 舞台・アート
        ["🎪", "🤹‍♀️", "🤹", "🤹‍♂️", "🎭", "🩰", "🎨", "🫟", "🎬"],
        // 音楽・楽器
        ["🎤", "🎧", "🎼", "🎹", "🪇", "🥁", "🪘", "🎷", "🎺", "🪊", "🪗", "🎸", "🪕", "🪉", "🎻", "🪈"],
        // ゲーム
        ["🎲", "♟️", "🎯", "🎳", "🎮", "🎰", "🧩"],
    ]

    static let activity: [String] = activitySections.flatMap { $0 }

    // 旅行と場所。サブグループごとに区切り線を挟む。
    static let travelAndPlacesSections: [[String]] = [
        // 車・道路の乗り物
        ["🚗", "🚕", "🚙", "🚌", "🚎", "🏎️", "🚓", "🚑", "🚒", "🚐", "🛻", "🚚", "🚛", "🚜", "🦯", "🦽", "🦼", "🩼", "🛴", "🚲", "🛵", "🏍️", "🛺", "🛞", "🚨", "🚔", "🚍", "🚘", "🚖"],
        // 鉄道・ロープウェイ
        ["🚡", "🚠", "🚟", "🚃", "🚋", "🚞", "🚝", "🚄", "🚅", "🚈", "🚂", "🚆", "🚇", "🚊", "🚉"],
        // 飛行機・宇宙
        ["✈️", "🛫", "🛬", "🛩️", "💺", "🛰️", "🚀", "🛸", "🚁"],
        // 船・海
        ["🛶", "⛵️", "🚤", "🛥️", "🛳️", "⛴️", "🚢", "🛟", "⚓️", "🪝"],
        // 道路設備・地図
        ["⛽️", "🚧", "🚦", "🚥", "🚏", "🗺️"],
        // ランドマーク・遊園地
        ["🗿", "🗽", "🗼", "🏰", "🏯", "🏟️", "🎡", "🎢", "🎠", "⛲️"],
        // 自然の場所
        ["⛱️", "🏖️", "🏝️", "🏜️", "🌋", "⛰️", "🏔️", "🗻", "🏕️", "⛺️", "🛖"],
        // 建物
        ["🏠", "🏡", "🏘️", "🏚️", "🏗️", "🏭", "🏢", "🏬", "🏣", "🏤", "🏥", "🏦", "🏨", "🏪", "🏫", "🏩", "💒", "🏛️", "⛪️", "🕌", "🕍", "🛕", "🕋", "⛩️"],
        // 風景・夜景
        ["🛤️", "🛣️", "🗾", "🎑", "🏞️", "🌅", "🌄", "🌠", "🎇", "🎆", "🌇", "🌆", "🏙️", "🌃", "🌌", "🌉", "🌁"],
    ]

    static let travelAndPlaces: [String] = travelAndPlacesSections.flatMap { $0 }

    static let objects: [String] = [
        "📻",
        "🎙️",
        "🎚️",
        "🎛️",
        "🧭",
        "⏱️",
        "⏲️",
        "⏰",
        "🕰️",
        "⌛️",
        "⏳",
        "📡",
        "🔋",
        "🪫",
        "🔌",
        "💡",
        "🔦",
        "🕯️",
        "🪔",
        "🧯",
        "🛢️",
        "💸",
        "💵",
        "💴",
        "💶",
        "💷",
        "🪙",
        "💰",
        "💳",
        "🪪",
        "💎",
        "🪎",
        "⚖️",
        "🪜",
        "🧰",
        "🪛",
        "🔧",
        "🔨",
        "⚒️",
        "🛠️",
        "⛏️",
        "🪏",
        "🪚",
        "🔩",
        "⚙️",
        "🪤",
        "🧱",
        "⛓️",
        "⛓️‍💥",
        "🧲",
        "🔫",
        "💣",
        "🧨",
        "🪓",
        "🔪",
        "🗡️",
        "⚔️",
        "🛡️",
        "🚬",
        "⚰️",
        "🪦",
        "⚱️",
        "🏺",
        "🔮",
        "📿",
        "🧿",
        "🪬",
        "💈",
        "⚗️",
        "🔭",
        "🔬",
        "🕳️",
        "🩻",
        "🩹",
        "🩺",
        "💊",
        "💉",
        "🩸",
        "🧬",
        "🦠",
        "🧫",
        "🧪",
        "🌡️",
        "🧹",
        "🪠",
        "🧺",
        "🧻",
        "🚽",
        "🚰",
        "🚿",
        "🛁",
        "🛀",
        "🧼",
        "🪥",
        "🪒",
        "🪮",
        "🧽",
        "🪣",
        "🧴",
        "🛎️",
        "🔑",
        "🗝️",
        "🚪",
        "🪑",
        "🛋️",
        "🛏️",
        "🛌",
        "🧸",
        "🪆",
        "🖼️",
        "🪞",
        "🪟",
        "🛍️",
        "🛒",
        "🎁",
        "🎈",
        "🎏",
        "🎀",
        "🪄",
        "🪅",
        "🎊",
        "🎉",
        "🎎",
        "🪭",
        "🏮",
        "🎐",
        "🪩",
        "🧧",
        "✉️",
        "📩",
        "📨",
        "📧",
        "💌",
        "📥",
        "📤",
        "📦",
        "🏷️",
        "🪧",
        "📪",
        "📫",
        "📬",
        "📭",
        "📮",
        "📯",
        "📜",
        "📃",
        "📄",
        "📑",
        "🧾",
        "📊",
        "📈",
        "📉",
        "🗒️",
        "🗓️",
        "📆",
        "📅",
        "🗑️",
        "📇",
        "🗃️",
        "🗳️",
        "🗄️",
        "📋",
        "📁",
        "📂",
        "🗂️",
        "🗞️",
        "📰",
        "📓",
        "📔",
        "📒",
        "📕",
        "📗",
        "📘",
        "📙",
        "📚",
        "📖",
        "🔖",
        "🧷",
        "🔗",
        "📎",
        "🖇️",
        "📐",
        "📏",
        "🧮",
        "📌",
        "📍",
        "✂️",
        "🖊️",
        "🖋️",
        "✒️",
        "🖌️",
        "🖍️",
        "📝",
        "✏️",
        "🔍",
        "🔎",
        "🔏",
        "🔐",
        "🔒",
        "🔓",
    ]

    static let symbols: [String] = [
        "🩷",
        "❤️",
        "🧡",
        "💛",
        "💚",
        "🩵",
        "💙",
        "💜",
        "🖤",
        "🩶",
        "🤍",
        "🤎",
        "💔",
        "❤️‍🔥",
        "❤️‍🩹",
        "❣️",
        "💕",
        "💞",
        "💓",
        "💗",
        "💖",
        "💘",
        "💝",
        "💟",
        "☮️",
        "✝️",
        "☪️",
        "🕉️",
        "☸️",
        "🪯",
        "✡️",
        "🔯",
        "🕎",
        "☯️",
        "☦️",
        "🛐",
        "⛎",
        "♈️",
        "♉️",
        "♊️",
        "♋️",
        "♌️",
        "♍️",
        "♎️",
        "♏️",
        "♐️",
        "♑️",
        "♒️",
        "♓️",
        "🆔",
        "⚛️",
        "🉑",
        "☢️",
        "☣️",
        "📴",
        "📳",
        "🈶",
        "🈚️",
        "🈸",
        "🈺",
        "🈷️",
        "✴️",
        "🆚",
        "💮",
        "🉐",
        "㊙️",
        "㊗️",
        "🈴",
        "🈵",
        "🈹",
        "🈲",
        "🅰️",
        "🅱️",
        "🆎",
        "🆑",
        "🅾️",
        "🆘",
        "❌",
        "⭕️",
        "🛑",
        "⛔️",
        "📛",
        "🚫",
        "💯",
        "💢",
        "♨️",
        "🚷",
        "🚯",
        "🚳",
        "🚱",
        "🔞",
        "📵",
        "🚭",
        "❗️",
        "❕",
        "❓",
        "❔",
        "‼️",
        "⁉️",
        "🔅",
        "🔆",
        "〽️",
        "⚠️",
        "🚸",
        "🔱",
        "⚜️",
        "🔰",
        "♻️",
        "✅",
        "🈯️",
        "💹",
        "❇️",
        "✳️",
        "❎",
        "🌐",
        "💠",
        "Ⓜ️",
        "🌀",
        "💤",
        "🏧",
        "🚾",
        "♿️",
        "🅿️",
        "🛗",
        "🈳",
        "🈂️",
        "🛂",
        "🛃",
        "🛄",
        "🛅",
        "🛜",
        "🚹",
        "🚺",
        "🚼",
        "🧑‍🧑‍🧒",
        "🧑‍🧑‍🧒‍🧒",
        "🧑‍🧒",
        "🧑‍🧒‍🧒",
        "⚧️",
        "🚻",
        "🚮",
        "🎦",
        "📶",
        "🈁",
        "🔣",
        "ℹ️",
        "🔤",
        "🔡",
        "🔠",
        "🆖",
        "🆗",
        "🆙",
        "🆒",
        "🆕",
        "🆓",
        "0️⃣",
        "1️⃣",
        "2️⃣",
        "3️⃣",
        "4️⃣",
        "5️⃣",
        "6️⃣",
        "7️⃣",
        "8️⃣",
        "9️⃣",
        "🔟",
        "🔢",
        "#️⃣",
        "*️⃣",
        "⏏️",
        "▶️",
        "⏸️",
        "⏯️",
        "⏹️",
        "⏺️",
        "⏭️",
        "⏮️",
        "⏩️",
        "⏪️",
        "⏫️",
        "⏬️",
        "◀️",
        "🔼",
        "🔽",
        "➡️",
        "⬅️",
        "⬆️",
        "⬇️",
        "↗️",
        "↘️",
        "↙️",
        "↖️",
        "↕️",
        "↔️",
        "↪️",
        "↩️",
        "⤴️",
        "⤵️",
        "🔀",
        "🔁",
        "🔂",
        "🔄",
        "🔃",
        "🎵",
        "🎶",
        "➕",
        "➖",
        "➗",
        "✖️",
        "🟰",
        "♾️",
        "💲",
        "💱",
        "™️",
        "©️",
        "®️",
        "👁️‍🗨️",
        "🔚",
        "🔙",
        "🔛",
        "🔝",
        "🔜",
        "〰️",
        "➰",
        "➿",
        "✔️",
        "☑️",
        "🔘",
        "🔴",
        "🟠",
        "🟡",
        "🟢",
        "🔵",
        "🟣",
        "⚫️",
        "⚪️",
        "🟤",
        "🔺",
        "🔻",
        "🔸",
        "🔹",
        "🔶",
        "🔷",
        "🔳",
        "🔲",
        "▪️",
        "▫️",
        "◾️",
        "◽️",
        "◼️",
        "◻️",
        "🟥",
        "🟧",
        "🟨",
        "🟩",
        "🟦",
        "🟪",
        "⬛️",
        "⬜️",
        "🟫",
        "🔈",
        "🔇",
        "🔉",
        "🔊",
        "🔔",
        "🔕",
        "📣",
        "📢",
        "💬",
        "💭",
        "🗯️",
        "♠️",
        "♣️",
        "♥️",
        "♦️",
        "🃏",
        "🎴",
        "🀄️",
        "🕐",
        "🕑",
        "🕒",
        "🕓",
        "🕔",
        "🕕",
        "🕖",
        "🕗",
        "🕘",
        "🕙",
        "🕚",
        "🕛",
        "🕜",
        "🕝",
        "🕞",
        "🕟",
        "🕠",
        "🕡",
        "🕢",
        "🕣",
        "🕤",
        "🕥",
        "🕦",
        "🕧",
    ]

    static let flags: [String] = [
        "🇫🇷",
        "🇮🇹",
        "🇪🇸",
        "🇩🇪",
        "🇦🇹",
        "🇵🇹",
        "🇬🇷",
        "🇨🇭",
        "🇭🇺",
        "🇬🇪",
        "🇬🇧",
        "🇭🇷",
        "🇧🇬",
        "🇸🇰",
        "🇲🇩",
        "🇷🇴",
        "🇸🇮",
        "🇱🇺",
        "🇯🇵",
        "🇺🇸",
        "🇦🇺",
        "🇳🇿",
        "🇨🇱",
        "🇦🇷",
        "🇨🇦",
        "🇿🇦",
        "🇺🇾",
        "🇮🇱",
        "🇮🇶",
        "🇮🇷",
        "🇮🇳",
        "🇮🇩",
        "🇺🇬",
        "🇺🇦",
        "🇺🇿",
        "🇪🇨",
        "🇪🇬",
        "🇪🇪",
        "🇸🇿",
        "🇪🇹",
        "🇪🇷",
        "🇸🇻",
        "🇴🇲",
        "🇳🇱",
        "🇬🇭",
        "🇨🇻",
        "🇬🇾",
        "🇰🇿",
        "🇶🇦",
        "🇬🇦",
        "🇨🇲",
        "🇬🇲",
        "🇰🇭",
        "🇬🇳",
        "🇬🇼",
        "🇨🇾",
        "🇨🇺",
        "🇰🇮",
        "🇰🇬",
        "🇬🇹",
        "🇰🇼",
        "🇨🇰",
        "🇬🇩",
        "🇰🇪",
        "🇨🇮",
        "🇨🇷",
        "🇰🇲",
        "🇨🇴",
        "🇨🇬",
        "🇨🇩",
        "🇸🇦",
        "🇼🇸",
        "🇸🇹",
        "🇿🇲",
        "🇸🇲",
        "🇸🇱",
        "🇩🇯",
        "🇯🇲",
        "🇸🇾",
        "🇸🇬",
        "🇿🇼",
        "🇸🇪",
        "🇸🇩",
        "🇸🇷",
        "🇱🇰",
        "🇸🇨",
        "🇸🇳",
        "🇷🇸",
        "🇰🇳",
        "🇻🇨",
        "🇱🇨",
        "🇸🇴",
        "🇸🇧",
        "🇹🇭",
        "🇹🇯",
        "🇹🇿",
        "🇨🇿",
        "🇹🇩",
        "🇹🇳",
        "🇹🇻",
        "🇩🇰",
        "🇹🇬",
        "🇩🇴",
        "🇩🇲",
        "🇹🇹",
        "🇹🇲",
        "🇹🇷",
        "🇹🇴",
        "🇳🇬",
        "🇳🇷",
        "🇳🇦",
        "🇳🇺",
        "🇳🇮",
        "🇳🇪",
        "🇳🇵",
        "🇳🇴",
        "🇧🇭",
        "🇭🇹",
        "🇵🇰",
        "🇻🇦",
        "🇵🇦",
        "🇻🇺",
        "🇧🇸",
        "🇵🇬",
        "🇵🇼",
        "🇵🇾",
        "🇧🇧",
        "🇵🇸",
        "🇧🇩",
        "🇫🇯",
        "🇵🇭",
        "🇫🇮",
        "🇧🇹",
        "🇧🇷",
        "🇧🇫",
        "🇧🇳",
        "🇧🇮",
        "🇻🇳",
        "🇧🇯",
        "🇻🇪",
        "🇧🇾",
        "🇧🇿",
        "🇵🇪",
        "🇧🇪",
        "🇵🇱",
        "🇧🇦",
        "🇧🇼",
        "🇧🇴",
        "🇭🇳",
        "🇲🇭",
        "🇲🇴",
        "🇲🇬",
        "🇲🇼",
        "🇲🇱",
        "🇲🇹",
        "🇲🇾",
        "🇫🇲",
        "🇲🇲",
        "🇲🇽",
        "🇲🇺",
        "🇲🇷",
        "🇲🇿",
        "🇲🇨",
        "🇲🇻",
        "🇲🇦",
        "🇲🇳",
        "🇲🇪",
        "🇯🇴",
        "🇱🇦",
        "🇱🇻",
        "🇱🇹",
        "🇱🇾",
        "🇱🇮",
        "🇱🇷",
        "🇷🇼",
        "🇱🇸",
        "🇱🇧",
        "🇷🇺",
        "🇰🇷",
        "🇭🇰",
        "🇬🇶",
        "🇹🇼",
        "🇨🇫",
        "🇨🇳",
        "🇹🇱",
        "🇸🇸",
        "🇲🇰",
        "🇰🇵",
        "🇼🇫",
        "🇦🇽",
        "🇧🇶",
        "🇬🇬",
        "🇨🇼",
        "🇬🇵",
        "🇬🇺",
        "🇬🇱",
        "🇨🇽",
        "🇰🇾",
        "🇨🇨",
        "🇬🇸",
        "🇧🇱",
        "🇵🇲",
        "🇬🇮",
        "🇯🇪",
        "🇸🇽",
        "🇸🇭",
        "🇹🇨",
        "🇮🇴",
        "🇹🇰",
        "🇳🇨",
        "🇳🇫",
        "🇧🇲",
        "🇵🇳",
        "🇵🇷",
        "🇫🇴",
        "🇫🇰",
        "🇾🇹",
        "🇲🇶",
        "🇮🇲",
        "🇲🇸",
        "🇷🇪",
        "🇻🇬",
        "🇪🇭",
        "🇦🇶",
        "🇬🇫",
        "🇵🇫",
        "🇹🇫",
        "🇻🇮",
        "🇦🇸",
        "🇲🇵",
        "🏴󠁧󠁢󠁷󠁬󠁳󠁿",
        "🇮🇨",
        "🇽🇰",
        "🇨🇶",
        "🇪🇺",
        "🎌",
    ]

    // 国旗の国名(フランス語)。長押し中に吹き出し表示する。以前は ISO 3166-1 の仏語短称を表として
    // 同梱していた(「Moldova, république de」の倒置形。ISO は一覧に権利を主張し、出所の記載も無かった)。
    // Foundation の Locale(fr_FR) から実行時に生成するので同梱データが無くなり、表記も自然になる
    // (Royaume-Uni / Moldavie / Cap-Vert)。2 文字の地域指示記号(🇦..🇿 のペア)を ISO コードに戻して引く。
    // 国・地域コードでない旗(🏴 系タグ列・🇪🇺・🎌 等)は flagNonCountryNames 側(2785)
    static let flagOfficialNames: [String: String] = {
        let locale = Locale(identifier: "fr_FR")
        var names: [String: String] = [:]
        for flag in flags where flagNonCountryNames[flag] == nil {
            guard let code = regionCode(forFlagEmoji: flag),
                let name = locale.localizedString(forRegionCode: code) else {
                continue
            }
            names[flag] = name
        }
        return names
    }()

    // 🇯🇵 → "JP"。地域指示記号(U+1F1E6〜U+1F1FF)2 個のみを国旗と見なす
    static func regionCode(forFlagEmoji emoji: String) -> String? {
        let scalars = Array(emoji.unicodeScalars)
        guard scalars.count == 2,
            scalars.allSatisfy({ (0x1F1E6...0x1F1FF).contains($0.value) }) else {
            return nil
        }
        return String(scalars.compactMap { UnicodeScalar($0.value - 0x1F1E6 + 0x41).map(Character.init) })
    }

    // 海外領土・属領(主権国の後ろ・その他の旗の前に区切り線で配置する)。
    static let flagOverseasTerritories: Set<String> = [
        "🇼🇫",
        "🇦🇽",
        "🇧🇶",
        "🇬🇬",
        "🇨🇼",
        "🇬🇵",
        "🇬🇺",
        "🇬🇱",
        "🇨🇽",
        "🇰🇾",
        "🇨🇨",
        "🇬🇸",
        "🇧🇱",
        "🇵🇲",
        "🇬🇮",
        "🇯🇪",
        "🇸🇽",
        "🇸🇭",
        "🇹🇨",
        "🇮🇴",
        "🇹🇰",
        "🇳🇨",
        "🇳🇫",
        "🇧🇲",
        "🇵🇳",
        "🇵🇷",
        "🇫🇴",
        "🇫🇰",
        "🇾🇹",
        "🇲🇶",
        "🇮🇲",
        "🇲🇸",
        "🇷🇪",
        "🇻🇬",
        "🇪🇭",
        "🇦🇶",
        "🇬🇫",
        "🇵🇫",
        "🇹🇫",
        "🇻🇮",
        "🇦🇸",
        "🇲🇵",
    ]

    // 国・地域(ISO)でない国旗の名称(仏語)。吹き出しは国旗とは別色で表示する。
    static let flagNonCountryNames: [String: String] = [
        "🏴󠁧󠁢󠁷󠁬󠁳󠁿": "Pays de Galles",
        "🇮🇨": "Îles Canaries",
        "🇽🇰": "Kosovo",
        "🇨🇶": "Sercq",
        "🇪🇺": "Union européenne",
        "🎌": "Drapeaux croisés",
    ]
}

#if canImport(UIKit)
import UIKit

/// 絵文字面の絵文字を画像ファイルから描くための置き場(3873)。
///
/// iOS の文字描画は、一度描いたカラー絵文字の展開画像(24pt を 3 倍の解像度で約 56KB)をプロセスが終わるまで持ち続ける。
/// キーボードで絵文字のカテゴリーを見て回ると、見た絵文字の数だけ footprint が増えた(実機 11-23: 390 個で +22MB)。
/// アプリ本体が絵文字を同じ大きさ・同じ解像度で画像にして共有フォルダーに置き、キーボードはそれを貼る。
/// キーボードのプロセスでは文字描画を通らないので、メモリは画面に見えているセルの分で頭打ちになる。
/// 画像が無い・古い(iOS の更新で絵文字の絵が変わった)ときは、今までどおり文字として描く。
enum EmojiTileStore {
    static let fontSize: CGFloat = 24
    /// 絵文字セルの高さ(pt。KeyboardRootView の compactEmojiKeyHeight と同じ)。画像はこの高さで作る
    static let cellHeight: CGFloat = 28
    static let formatVersion = 2

    struct Manifest: Codable, Equatable {
        var formatVersion: Int
        var systemVersion: String
        var scale: Int
        var fontSize: Int
        var cellHeight: Int
        var count: Int
    }

    /// 絵文字面に出る絵文字(カテゴリーの順、重複なし)。
    static let allEmojis: [String] = {
        var seen = Set<String>()
        return (AppleEmojiCatalog.people + AppleEmojiCatalog.nature + AppleEmojiCatalog.foodAndDrink + AppleEmojiCatalog.activity
            + AppleEmojiCatalog.travelAndPlaces + AppleEmojiCatalog.objects + AppleEmojiCatalog.symbols + AppleEmojiCatalog.flags)
            .filter { seen.insert($0).inserted }
    }()

    static func currentManifest(scale: CGFloat) -> Manifest {
        Manifest(
            formatVersion: formatVersion,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            scale: Int(scale.rounded()),
            fontSize: Int(fontSize),
            cellHeight: Int(cellHeight),
            count: allEmojis.count
        )
    }

    static func directory(container: URL) -> URL {
        container.appendingPathComponent("Library/Caches/EmojiTiles", isDirectory: true)
    }

    /// ファイル名は絵文字の符号位置を 16 進で並べたもの(1f600.png、1f1ef-1f1f5.png)。
    static func fileName(for emoji: String) -> String {
        emoji.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-") + ".png"
    }

    private static func manifestURL(in directory: URL) -> URL {
        directory.appendingPathComponent("manifest.json")
    }

    /// 置いてある画像が今の iOS・解像度・絵文字の一覧のものなら、そのフォルダーを返す。
    static func validDirectory(container: URL, scale: CGFloat) -> URL? {
        let directory = directory(container: container)
        guard let data = try? Data(contentsOf: manifestURL(in: directory)),
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
            manifest == currentManifest(scale: scale) else {
            return nil
        }
        return directory
    }

    /// 画像を読む。システムの画像キャッシュに載らないよう、名前でなくファイルの中身から作る。
    static func image(for emoji: String, in directory: URL, scale: CGFloat) -> UIImage? {
        let url = directory.appendingPathComponent(fileName(for: emoji))
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        return UIImage(data: data, scale: scale)
    }

    /// 1 個の絵文字を、セルと同じ高さのラベルに文字として描いて画像にする。キーボードの絵文字セルと同じ描き方なので、
    /// 同じ絵になる(文字列を直接描くと、ラベルとは絵の縦の位置と大きさが 1 画素ほど違った)。メインスレッドで呼ぶ。
    static func makeRenderLabel() -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: fontSize)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = false
        return label
    }

    static func renderTile(_ emoji: String, scale: CGFloat, label: UILabel) -> UIImage? {
        label.text = emoji
        let width = ceil(label.intrinsicContentSize.width * scale) / scale
        guard width > 0 else {
            return nil
        }
        label.frame = CGRect(x: 0, y: 0, width: width, height: cellHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: label.bounds.size, format: format).image { context in
            label.layer.render(in: context.cgContext)
        }
    }

    /// 作り直しの準備: 古い画像を消してフォルダーを作る。そろっていて作り直しが要らなければ nil。
    static func prepareForGeneration(container: URL, scale: CGFloat) -> URL? {
        guard validDirectory(container: container, scale: scale) == nil else {
            return nil
        }
        let directory = directory(container: container)
        try? FileManager.default.removeItem(at: directory)
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        return directory
    }

    static func write(_ image: UIImage, for emoji: String, in directory: URL) {
        guard let data = image.pngData() else {
            return
        }
        try? data.write(to: directory.appendingPathComponent(fileName(for: emoji)), options: .atomic)
    }

    /// 目録を書く。目録は最後に書くので、途中で止められた半端な状態を「そろっている」と見なさない。
    @discardableResult
    static func finishGeneration(directory: URL, scale: CGFloat) -> Bool {
        guard let data = try? JSONEncoder().encode(currentManifest(scale: scale)) else {
            return false
        }
        return (try? data.write(to: manifestURL(in: directory), options: .atomic)) != nil
    }

    /// 画像が無い・古いときに、その場で全部作る(テスト用)。作ったら true。メインスレッドで呼ぶ。
    @discardableResult
    static func generateIfNeeded(container: URL, scale: CGFloat) -> Bool {
        guard let directory = prepareForGeneration(container: container, scale: scale) else {
            return false
        }
        let label = makeRenderLabel()
        for emoji in allEmojis {
            autoreleasepool {
                if let image = renderTile(emoji, scale: scale, label: label) {
                    write(image, for: emoji, in: directory)
                }
            }
        }
        return finishGeneration(directory: directory, scale: scale)
    }

    /// アプリ本体の側: 画像が無い・古いときに、少しずつ作る。描くのはメインスレッド(ラベルは UIKit の部品)で 1 回に少数だけ、
    /// PNG への変換と書き込みは裏で行ない、書き終えてから次の組を描く(画面の動きを止めない)。メインスレッドで呼ぶ。
    static func generateInBatchesIfNeeded(scale: CGFloat, batchSize: Int = 12, completion: @escaping (Bool) -> Void) {
        let queue = DispatchQueue(label: "emoji-tile-generation", qos: .utility)
        queue.async {
            guard let container = sharedContainer(), let directory = prepareForGeneration(container: container, scale: scale) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let emojis = allEmojis
            DispatchQueue.main.async {
                let label = makeRenderLabel()
                func renderBatch(from start: Int) {
                    let end = min(emojis.count, start + batchSize)
                    var rendered: [(String, UIImage)] = []
                    rendered.reserveCapacity(end - start)
                    for emoji in emojis[start..<end] {
                        if let image = renderTile(emoji, scale: scale, label: label) {
                            rendered.append((emoji, image))
                        }
                    }
                    queue.async {
                        for (emoji, image) in rendered {
                            autoreleasepool { write(image, for: emoji, in: directory) }
                        }
                        if end < emojis.count {
                            DispatchQueue.main.async { renderBatch(from: end) }
                        } else {
                            let finished = finishGeneration(directory: directory, scale: scale)
                            DispatchQueue.main.async { completion(finished) }
                        }
                    }
                }
                renderBatch(from: 0)
            }
        }
    }

    // キーボードの側: 画像のフォルダーはプロセスで 1 回だけ調べる(共有フォルダーの場所の問い合わせとファイル読みを
    // 絵文字面を開くたびに繰り返さない)。アプリ本体が後から作り直しても、このプロセスが終わるまでは前の判定のまま
    private static var keyboardDirectoryResolved = false
    private static var keyboardDirectoryCache: URL?

    static func keyboardDirectory(scale: CGFloat) -> URL? {
        if !keyboardDirectoryResolved {
            keyboardDirectoryResolved = true
            keyboardDirectoryCache = sharedContainer().flatMap { validDirectory(container: $0, scale: scale) }
        }
        return keyboardDirectoryCache
    }

    /// 共有フォルダー(App Group)。アプリ本体とキーボードの Info.plist に同じ ID が入っている。
    static func sharedContainer() -> URL? {
        guard let appGroupID = Bundle.main.object(forInfoDictionaryKey: "EcrituAppGroupIdentifier") as? String, !appGroupID.isEmpty else {
            return nil
        }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// 診断ログ用。
    static var keyboardStatusText: String {
        keyboardDirectoryResolved ? (keyboardDirectoryCache == nil ? "なし" : "あり") : "未確認"
    }
}

#endif
