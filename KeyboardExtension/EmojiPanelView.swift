import UIKit
import IMECore

/// 表情符號資料：分類與符號。不含搜尋與膚色選擇（FR-U24，搜尋列為後續）。
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


/// 表情符號頁（FR-U24），比照原生：
/// - 所有類別接成一條**橫向**捲動的長列，左右滑會連續經過各類別
/// - 最下面一排：「中」（回鍵盤）、最近使用與各類別圖示、⌫；捲動時目前類別的圖示跟著亮起，點圖示跳到該類別
final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onInsert: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onClose: (() -> Void)?

    private var palette: ThemePalette?
    /// 顯示期間固定的「最近使用」快照，避免點了之後整列跳動（重新開啟才更新）。
    private var recents: [String] = []
    /// 目前亮起的類別：0 = 最近使用，1... = EmojiCatalog.categories
    private var selectedCategory = 1
    /// 點類別圖示觸發的捲動進行中，不要被捲動事件改掉亮起的圖示。
    private var isJumping = false

    private let categoryButtons: [UIButton]
    private let flowLayout = UICollectionViewFlowLayout()
    private let collectionView: UICollectionView
    private let closeButton = UIButton(type: .system)
    private let backspaceButton = UIButton(type: .system)
    private let emptyLabel = UILabel()

    private let bottomBarHeight: CGFloat = 44
    private let rowCount: CGFloat = 4  // 比照原生：一欄 4 個
    private let sectionGap: CGFloat = 16
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

        flowLayout.scrollDirection = .horizontal
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.minimumLineSpacing = 0
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)

        super.init(frame: frame)

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.register(EmojiCell.self, forCellWithReuseIdentifier: cellID)
        addSubview(collectionView)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        for (index, button) in categoryButtons.enumerated() {
            button.setPreferredSymbolConfiguration(symbolConfig, forImageIn: .normal)
            button.addAction(UIAction { [weak self] _ in self?.jump(to: index) }, for: .touchUpInside)
            addSubview(button)
        }

        closeButton.setTitle("中", for: .normal)  // 回到中文鍵盤
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 17)
        closeButton.accessibilityLabel = "回到鍵盤"
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

    /// 每次顯示時重新讀取最近使用；有最近使用就從頭（最近使用）開始，否則從第一個分類開始。
    func reload() {
        recents = RecentEmojiStore.load()
        selectedCategory = recents.isEmpty ? 1 : 0
        updateButtonColors()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        collectionView.setContentOffset(.zero, animated: false)
        emptyLabel.isHidden = true
    }

    // MARK: - 類別

    private func emojis(in section: Int) -> [String] {
        section == 0 ? recents : EmojiCatalog.categories[section - 1].emojis
    }

    /// 某類別在長列中的起點 x（空的類別沒有起點）。
    private func startX(of section: Int) -> CGFloat? {
        guard !emojis(in: section).isEmpty,
              let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: section))
        else { return nil }
        return attributes.frame.minX
    }

    private func jump(to section: Int) {
        selectedCategory = section
        updateButtonColors()
        guard let x = startX(of: section) else {
            // 最近使用是空的：留在原處，顯示提示
            emptyLabel.isHidden = section != 0
            return
        }
        emptyLabel.isHidden = true
        let maxX = max(0, collectionView.contentSize.width - collectionView.bounds.width)
        let target = min(max(0, x - sectionGap / 2), maxX)
        isJumping = true
        collectionView.setContentOffset(CGPoint(x: target, y: 0), animated: false)
        isJumping = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isJumping else { return }
        emptyLabel.isHidden = true
        // 畫面左邊三分之一處落在哪個類別，那個類別的圖示就亮起
        let probe = scrollView.contentOffset.x + scrollView.bounds.width / 3
        var current = selectedCategory
        for section in 0..<categoryButtons.count {
            guard let x = startX(of: section) else { continue }
            if x <= probe { current = section } else { break }
        }
        // 捲到最右邊時，最後一個類別可能短到到不了探測點，直接亮最後一個
        if scrollView.contentSize.width > scrollView.bounds.width,
           scrollView.contentOffset.x >= scrollView.contentSize.width - scrollView.bounds.width - 1 {
            current = categoryButtons.count - 1
        }
        if current != selectedCategory {
            selectedCategory = current
            updateButtonColors()
        }
    }

    private func updateButtonColors() {
        guard let palette else { return }
        let normal = palette[.keySecondaryText].uiColor
        let selected = palette[.keyText].uiColor
        for (index, button) in categoryButtons.enumerated() {
            let isSelected = index == selectedCategory
            button.tintColor = isSelected ? selected : normal
            button.backgroundColor = isSelected ? palette[.keyBackground].uiColor : .clear
        }
        closeButton.setTitleColor(palette[.keyText].uiColor, for: .normal)
        backspaceButton.tintColor = palette[.keyText].uiColor
    }

    // MARK: - 排版

    override func layoutSubviews() {
        super.layoutSubviews()
        let gridHeight = max(0, bounds.height - bottomBarHeight)
        collectionView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: gridHeight)

        // 一欄 rowCount 個（直的），一欄一欄往右接
        let cellHeight = max(1, floor((gridHeight - 8) / rowCount))
        let cellWidth = max(cellHeight, floor(bounds.width / 8.4))  // 約 8 欄，右邊露出一點提示可以滑
        let size = CGSize(width: cellWidth, height: cellHeight)
        if flowLayout.itemSize != size {
            flowLayout.itemSize = size
            flowLayout.sectionInset = UIEdgeInsets(top: 4, left: sectionGap / 2, bottom: 4, right: sectionGap / 2)
            flowLayout.invalidateLayout()
        }
        emptyLabel.frame = collectionView.frame

        // 最下面一排：中 ｜ 類別圖示 ｜ ⌫
        let barY = bounds.height - bottomBarHeight
        let sideWidth: CGFloat = 56
        closeButton.frame = CGRect(x: 4, y: barY, width: sideWidth, height: bottomBarHeight)
        backspaceButton.frame = CGRect(x: bounds.width - sideWidth - 4, y: barY, width: sideWidth, height: bottomBarHeight)
        let iconsLeft = closeButton.frame.maxX
        let iconWidth = max(0, backspaceButton.frame.minX - iconsLeft) / CGFloat(categoryButtons.count)
        let iconSide = min(iconWidth, 32)
        for (index, button) in categoryButtons.enumerated() {
            let centerX = iconsLeft + iconWidth * (CGFloat(index) + 0.5)
            button.frame = CGRect(x: centerX - iconSide / 2, y: barY + (bottomBarHeight - iconSide) / 2,
                                  width: iconSide, height: iconSide)
            button.layer.cornerRadius = iconSide / 2
        }
    }

    // MARK: - 資料

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        categoryButtons.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        emojis(in: section).count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellID, for: indexPath)
        (cell as? EmojiCell)?.label.text = emojis(in: indexPath.section)[indexPath.item]
        return cell
    }

    /// 空的類別（例如還沒有最近使用）不留邊距，避免最左邊空一段。
    func collectionView(
        _ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        emojis(in: section).isEmpty ? .zero : flowLayout.sectionInset
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let emoji = emojis(in: indexPath.section)[indexPath.item]
        RecentEmojiStore.add(emoji)
        onInsert?(emoji)
    }
}

private final class EmojiCell: UICollectionViewCell {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = UIFont.systemFont(ofSize: 32)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
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
