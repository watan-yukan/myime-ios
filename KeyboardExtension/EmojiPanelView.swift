import UIKit
import IMECore

/// 表情符號資料：分類與符號。不含搜尋與膚色選擇（FR-U24，列為後續）。
enum EmojiCatalog {
    struct Category {
        let title: String
        let symbol: String
        let emojis: [String]
    }

    private static func split(_ text: String) -> [String] {
        text.map { String($0) }
    }

    static let categories: [Category] = [
        Category(title: "表情", symbol: "face.smiling", emojis: split(
            "😀😃😄😁😆😅😂🤣😊😇🙂🙃😉😌😍🥰😘😗😙😚😋😛😝😜🤪🤨🧐🤓😎🥸🤩🥳😏😒😞😔😟😕🙁😣😖😫😩🥺😢😭😤😠😡🤬🤯😳🥵🥶😱😨😰😥😓🤗🤔🤭🤫🤥😶😐😑😬🙄😯😦😧😮😲🥱😴🤤😪😵🤐🥴🤢🤮🤧😷🤒🤕🤑🤠😈👿👹👺🤡💩👻💀👽👾🤖🎃")),
        Category(title: "手勢", symbol: "hand.raised", emojis: split(
            "👋🤚🖐✋🖖👌🤌🤏🤞🤟🤘🤙👈👉👆👇👍👎✊👊🤛🤜👏🙌👐🤲🤝🙏💅🤳💪🦾🦵🦶👂🦻👃🧠👀👅👄")),
        Category(title: "動植物", symbol: "pawprint", emojis: split(
            "🐶🐱🐭🐹🐰🦊🐻🐼🐨🐯🦁🐮🐷🐸🐵🙈🙉🙊🐔🐧🐦🐤🦆🦅🦉🦇🐺🐗🐴🦄🐝🐛🦋🐌🐞🐜🦗🦂🐢🐍🦎🐙🦑🦐🦀🐡🐠🐟🐬🐳🐋🦈🐊🐅🐆🦓🦍🐘🦏🐪🐫🦒🦘🐃🐂🐄🐎🐖🐏🐑🐐🦌🐕🐩🐈🐓🦃🐇🐁🐀🦔🌵🎄🌲🌳🌴🌱🌿🍀🎍🍃🍂🍁🍄🌾💐🌷🌹🥀🌺🌸🌼🌻")),
        Category(title: "飲食", symbol: "fork.knife", emojis: split(
            "🍏🍎🍐🍊🍋🍌🍉🍇🍓🍈🍒🍑🥭🍍🥥🥝🍅🍆🥑🥦🥬🥒🌽🥕🧄🧅🥔🍠🥐🥯🍞🥖🥨🧀🥚🍳🧈🥞🧇🥓🥩🍗🍖🌭🍔🍟🍕🥪🥙🧆🌮🌯🥗🥘🥫🍝🍜🍲🍛🍣🍱🥟🍤🍙🍚🍘🍥🥠🥮🍢🍡🍧🍨🍦🥧🧁🍰🎂🍮🍭🍬🍫🍿🍩🍪🌰🥜🍯🥛🍼☕🍵🧃🥤🍶🍺🍻🥂🍷🥃🍸🍹🧉🍾")),
        Category(title: "活動", symbol: "figure.run", emojis: split(
            "⚽🏀🏈⚾🥎🎾🏐🏉🥏🎱🏓🏸🏒🏑🥍🏏🥅⛳🏹🎣🤿🥊🥋🎽🛹🛼🛷⛸🥌🎿🏂🏆🥇🥈🥉🏅🎖🎫🎟🎪🤹🎭🎨🎬🎤🎧🎼🎹🥁🎷🎺🎸🎻🎲🎯🎳🎮🎰🧩")),
        Category(title: "旅行", symbol: "car", emojis: split(
            "🚗🚕🚙🚌🚎🏎🚓🚑🚒🚐🚚🚛🚜🛴🚲🛵🏍🚨🚔🚍🚘🚖🚡🚠🚟🚃🚋🚞🚝🚄🚅🚈🚂🚆🚇🚊🚉🛫🛬🛩💺🛰🚀🛸🚁🛶⛵🚤🛥🛳⛴🚢⚓⛽🚧🚦🚥🚏🗺🗿🗽🗼🏰🏯🏟🎡🎢🎠⛲🏖🏝🏜🌋⛰🏔🗻🏕⛺🏠🏡🏘🏚🏗🏭🏢🏬🏣🏤🏥🏦🏨🏪🏫🏩💒🏛⛪🕌🕍")),
        Category(title: "物件", symbol: "lightbulb", emojis: split(
            "⌚📱📲💻🖥🖨🖱💽💾💿📀📷📸📹🎥📞📺📻🎙🧭⏰⌛⏳📡🔋🔌💡🔦🕯💸💵💴💶💷💰💳💎🧰🔧🔨🛠⚙🧱🧲💣🔪🛡🔮📿💈🔭🔬💊💉🧬🧪🌡🧹🧺🚽🚿🛁🧼🧴🔑🚪🪑🛋🛏🧸🖼🛍🛒🎁🎈🎀🎊🎉🎎🏮✉📩📨📧💌📦🏷📜📄📊📈📉📋📁📂📰📓📔📒📕📗📘📙📚📖🔖🔗📎📐📏📌📍✂🖊🖋🖌🖍📝🔍🔎🔒🔓")),
        Category(title: "符號", symbol: "heart", emojis: split(
            "❤🧡💛💚💙💜🖤🤍🤎💔💕💞💓💗💖💘💝💟☮✝☪🕉☸✡🔯☯🛐🆔⚛☢☣📴📳🆚💮㊙㊗🆎🆑🆘❌⭕🛑⛔📛🚫💯💢♨🚷🚯🚳🚱🔞📵🚭❗❕❓❔‼⁉🔅🔆⚠🚸🔱⚜🔰♻✅💹❇✳❎🌐💠🌀💤🏧♿🚹🚺🚼🚻🚮🎦📶🔣🔤🔡🔠🆖🆗🆙🆒🆕🆓🔟🔢▶⏸⏯⏹⏺⏭⏮⏩⏪🔼🔽➡⬅⬆⬇↗↘↙↖↕↔🔀🔁🔂🔄🎵🎶➕➖➗✖💲™©®➰➿🔚🔙🔛🔝🔜✔☑🔘🔴🟠🟡🟢🔵🟣⚫⚪🔺🔻🔸🔹🔶🔷⬛⬜🟥🟧🟨🟩🟦🟪")),
        Category(title: "旗幟", symbol: "flag", emojis: split(
            "🏁🚩🎌🏴🏳🇹🇼🇯🇵🇰🇷🇺🇸🇬🇧🇨🇦🇦🇺🇫🇷🇩🇪🇮🇹🇪🇸🇨🇳🇭🇰🇸🇬🇹🇭🇻🇳🇲🇾🇮🇳")),
    ]
}

/// 最近使用的表情符號（存在 App Group，鍵盤與 App 共用）。
enum RecentEmojiStore {
    private static let key = "recentEmoji"
    private static let limit = 32

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroupResolver.resolvedID) ?? .standard
    }

    static func load() -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    static func add(_ emoji: String) {
        var list = load().filter { $0 != emoji }
        list.insert(emoji, at: 0)
        defaults.set(Array(list.prefix(limit)), forKey: key)
    }
}

/// 表情符號頁：分類切換、最近使用（FR-U24）。
final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onInsert: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onClose: (() -> Void)?

    private var palette: ThemePalette?
    private var recents: [String] = []
    /// 0 = 最近使用，1... = EmojiCatalog.categories
    private var selectedCategory = 1

    private let categoryButtons: [UIButton]
    private let collectionView: UICollectionView
    private let closeButton = UIButton(type: .system)
    private let backspaceButton = UIButton(type: .system)
    private let emptyLabel = UILabel()

    private let categoryBarHeight: CGFloat = 36
    private let bottomBarHeight: CGFloat = 40
    private let cellID = "emojiCell"

    override init(frame: CGRect) {
        let recentsButton = UIButton(type: .system)
        recentsButton.setImage(UIImage(systemName: "clock"), for: .normal)
        recentsButton.accessibilityLabel = "最近使用"
        var buttons = [recentsButton]
        for category in EmojiCatalog.categories {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: category.symbol), for: .normal)
            button.accessibilityLabel = category.title
            buttons.append(button)
        }
        categoryButtons = buttons

        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 44, height: 44)
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(frame: frame)

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.register(EmojiCell.self, forCellWithReuseIdentifier: cellID)
        addSubview(collectionView)

        for (index, button) in categoryButtons.enumerated() {
            button.addAction(UIAction { [weak self] _ in self?.select(category: index) }, for: .touchUpInside)
            addSubview(button)
        }

        closeButton.setTitle("ABC", for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        addSubview(closeButton)

        backspaceButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        backspaceButton.accessibilityLabel = "刪除"
        backspaceButton.addAction(UIAction { [weak self] _ in self?.onBackspace?() }, for: .touchUpInside)
        addSubview(backspaceButton)

        emptyLabel.text = "還沒有最近使用的表情符號"
        emptyLabel.font = UIFont.systemFont(ofSize: 14)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        addSubview(emptyLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme(palette: ThemePalette) {
        self.palette = palette
        backgroundColor = palette[.keyboardBackground].uiColor
        updateButtonColors()
        emptyLabel.textColor = palette[.keySecondaryText].uiColor
    }

    /// 每次顯示時重新讀取最近使用，並回到「最近使用」（有的話）或第一個分類。
    func reload() {
        recents = RecentEmojiStore.load()
        selectedCategory = recents.isEmpty ? 1 : 0
        updateButtonColors()
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
        emptyLabel.isHidden = true
    }

    private func select(category index: Int) {
        selectedCategory = index
        updateButtonColors()
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
        emptyLabel.isHidden = !(index == 0 && recents.isEmpty)
    }

    private func updateButtonColors() {
        guard let palette else { return }
        let normal = palette[.keySecondaryText].uiColor
        let selected = palette[.candidateHighlight].uiColor
        for (index, button) in categoryButtons.enumerated() {
            button.tintColor = index == selectedCategory ? selected : normal
        }
        closeButton.setTitleColor(palette[.keyText].uiColor, for: .normal)
        backspaceButton.tintColor = palette[.keyText].uiColor
    }

    private var currentEmojis: [String] {
        selectedCategory == 0 ? recents : EmojiCatalog.categories[selectedCategory - 1].emojis
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let buttonWidth = bounds.width / CGFloat(categoryButtons.count)
        for (index, button) in categoryButtons.enumerated() {
            button.frame = CGRect(x: CGFloat(index) * buttonWidth, y: 0, width: buttonWidth, height: categoryBarHeight)
        }
        collectionView.frame = CGRect(
            x: 0, y: categoryBarHeight, width: bounds.width,
            height: max(0, bounds.height - categoryBarHeight - bottomBarHeight))
        closeButton.frame = CGRect(x: 8, y: bounds.height - bottomBarHeight, width: 64, height: bottomBarHeight)
        backspaceButton.frame = CGRect(x: bounds.width - 72, y: bounds.height - bottomBarHeight, width: 64, height: bottomBarHeight)
        emptyLabel.frame = collectionView.frame
    }

    // MARK: - 資料

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        currentEmojis.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellID, for: indexPath)
        (cell as? EmojiCell)?.label.text = currentEmojis[indexPath.item]
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let emoji = currentEmojis[indexPath.item]
        RecentEmojiStore.add(emoji)
        onInsert?(emoji)
    }
}

private final class EmojiCell: UICollectionViewCell {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = UIFont.systemFont(ofSize: 30)
        label.textAlignment = .center
        contentView.addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }
}
