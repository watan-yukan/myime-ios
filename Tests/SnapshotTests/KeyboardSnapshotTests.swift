import XCTest
import UIKit
import IMECore

/// 鍵盤外觀截圖（Issue #32）。
///
/// 在 iOS 模擬器裡把真實的鍵盤元件畫成 PNG：每個主題一張，包含淺 / 深色、字母頁、數字頁、
/// 組字與候選列、按下放大預覽、橫向。CI 會把圖片上傳為 Artifact，讓外觀問題在上機前就能被看見。
@MainActor
final class KeyboardSnapshotTests: XCTestCase {

    private var bundle: Bundle { Bundle(for: KeyboardSnapshotTests.self) }

    private lazy var layout: KeyboardLayoutFile = {
        guard let file = LayoutCatalog.iphone(bundle: bundle) else {
            preconditionFailure("找不到 iphone.json")
        }
        return file
    }()

    private var outputDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("keyboard-snapshots", isDirectory: true)
    }

    // MARK: - 組出一個完整的鍵盤畫面（與 KeyboardViewController 相同的元件與版面）

    private struct Scene {
        var page = "alpha"
        var landscape = false
        var width: CGFloat = 430
        var dark = false
        var composing: String?
        var candidates: [String] = []
        var pressed: String?
        var uppercase = false
        var mode = InputMode.chinese
    }

    private func content(for key: LayoutKey, scene: Scene) -> KeyContent {
        switch key.type {
        case .char:
            let base = key.output ?? ""
            let isLetter = base.first?.isLetter == true
            return KeyContent(text: isLetter ? (scene.uppercase ? base.uppercased() : base) : base)
        case .shift: return KeyContent(symbol: scene.uppercase ? "shift.fill" : "shift")
        case .backspace: return KeyContent(symbol: "delete.left")
        case .space: return KeyContent()
        case .returnKey: return KeyContent(symbol: "return")
        case .page: return KeyContent(text: key.label, isFunctionText: true)
        case .langToggle: return KeyContent(text: scene.mode == .chinese ? "中" : "英", isFunctionText: true)
        default: return KeyContent()
        }
    }

    private func makeKeyboard(theme: Theme, scene: Scene) -> UIView {
        let palette = theme.palette(isDark: scene.dark)
        let metrics = layout.metrics.metrics(landscape: scene.landscape)
        let page = layout.page(scene.page)!
        let keysHeight = LayoutEngine.frames(
            for: page, metrics: metrics, containerWidth: scene.width, landscape: scene.landscape).size.height
        let barHeight: CGFloat = 44

        let root = UIView(frame: CGRect(x: 0, y: 0, width: scene.width, height: barHeight + keysHeight))
        root.backgroundColor = palette[.keyboardBackground].uiColor

        let bar = CandidateBarView(frame: CGRect(x: 0, y: 0, width: scene.width, height: barHeight))
        bar.applyTheme(palette: palette, metrics: theme.metrics)
        if let code = scene.composing {
            bar.update(
                state: ComposerState(code: code, candidates: scene.candidates, status: scene.candidates.isEmpty ? .invalid : .matched),
                hint: nil, candidateLimit: 0)
        } else {
            bar.update(state: .idle, hint: nil, candidateLimit: 0)
        }
        root.addSubview(bar)

        let keys = KeyboardKeysView(frame: CGRect(x: 0, y: barHeight, width: scene.width, height: keysHeight))
        keys.previewHeadroom = barHeight
        keys.contentProvider = { [unowned self] key in self.content(for: key, scene: scene) }
        keys.configure(page: page, metrics: metrics, landscape: scene.landscape)
        keys.applyTheme(palette: palette, metrics: theme.metrics)
        root.addSubview(keys)

        root.layoutIfNeeded()
        keys.layoutIfNeeded()
        bar.layoutIfNeeded()
        if let pressed = scene.pressed { keys.simulatePress(ofKeyWithOutput: pressed) }
        return root
    }

    private func image(of view: UIView) -> UIImage {
        UIGraphicsImageRenderer(bounds: view.bounds).image { context in
            view.layer.render(in: context.cgContext)
        }
    }

    // MARK: - 拼成一張大圖

    private func sheet(title: String, items: [(label: String, view: UIView)], columns: Int) -> UIImage {
        let margin: CGFloat = 16
        let labelHeight: CGFloat = 24
        let titleHeight: CGFloat = 40
        let cellWidth = items.map { $0.view.bounds.width }.max() ?? 0
        let rows = (items.count + columns - 1) / columns
        var rowHeights: [CGFloat] = []
        for row in 0..<rows {
            let slice = items[(row * columns)..<min(items.count, (row + 1) * columns)]
            rowHeights.append((slice.map { $0.view.bounds.height }.max() ?? 0) + labelHeight)
        }
        let size = CGSize(
            width: margin + CGFloat(columns) * (cellWidth + margin),
            height: titleHeight + rowHeights.reduce(0) { $0 + $1 + margin } + margin)

        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(white: 0.55, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            (title as NSString).draw(
                at: CGPoint(x: margin, y: 10),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.white])

            var y = titleHeight
            for row in 0..<rows {
                for column in 0..<columns {
                    let index = row * columns + column
                    guard index < items.count else { continue }
                    let x = margin + CGFloat(column) * (cellWidth + margin)
                    (items[index].label as NSString).draw(
                        at: CGPoint(x: x, y: y),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.white])
                    let origin = CGPoint(x: x, y: y + labelHeight)
                    context.cgContext.saveGState()
                    context.cgContext.translateBy(x: origin.x, y: origin.y)
                    items[index].view.layer.render(in: context.cgContext)
                    context.cgContext.restoreGState()
                }
                y += rowHeights[row] + margin
            }
        }
    }

    private func save(_ image: UIImage, name: String) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        guard let data = image.pngData() else { return XCTFail("無法輸出 PNG：\(name)") }
        try data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - 每個主題一張

    func testThemeSheets() throws {
        for theme in ThemeCatalog.all(bundle: bundle) {
            var items: [(label: String, view: UIView)] = []
            for dark in [false, true] {
                let mode = dark ? "深色" : "淺色"
                items.append(("字母頁（\(mode)）", makeKeyboard(theme: theme, scene: Scene(dark: dark))))
                items.append(("數字頁（\(mode)）", makeKeyboard(theme: theme, scene: Scene(page: "numbers", dark: dark))))
                items.append((
                    "組字與候選（\(mode)）",
                    makeKeyboard(theme: theme, scene: Scene(dark: dark, composing: "ab", candidates: ["米", "粎", "籾", "糵", "糜", "糕", "糊", "糖"]))))
                items.append(("按住 F（\(mode)）", makeKeyboard(theme: theme, scene: Scene(dark: dark, pressed: "f"))))
                items.append(("按住 Q（第一列、貼邊，\(mode)）", makeKeyboard(theme: theme, scene: Scene(dark: dark, pressed: "q"))))
                items.append(("英文模式 Shift（\(mode)）", makeKeyboard(theme: theme, scene: Scene(dark: dark, uppercase: true, mode: .english))))
            }
            try save(sheet(title: "主題：\(theme.name)（iPhone 直向 430 pt）", items: items, columns: 2), name: "theme-\(theme.id)")
        }
    }

    func testLandscapeSheet() throws {
        let theme = ThemeCatalog.theme(id: "native", bundle: bundle)
        var items: [(label: String, view: UIView)] = []
        for dark in [false, true] {
            let mode = dark ? "深色" : "淺色"
            items.append(("橫向字母頁（\(mode)）", makeKeyboard(theme: theme, scene: Scene(landscape: true, width: 932, dark: dark))))
            items.append(("橫向數字頁（\(mode)）", makeKeyboard(theme: theme, scene: Scene(page: "numbers", landscape: true, width: 932, dark: dark))))
        }
        try save(sheet(title: "iPhone 橫向 932 pt", items: items, columns: 1), name: "landscape-native")
    }

    func testNarrowWidths() throws {
        let theme = ThemeCatalog.theme(id: "native", bundle: bundle)
        var items: [(label: String, view: UIView)] = []
        for width: CGFloat in [320, 375, 390, 402, 440] {
            items.append(("寬 \(Int(width)) pt", makeKeyboard(theme: theme, scene: Scene(width: width))))
        }
        try save(sheet(title: "不同螢幕寬度", items: items, columns: 2), name: "widths-native")
    }

    func testPanels() throws {
        let theme = ThemeCatalog.theme(id: "native", bundle: bundle)
        var items: [(label: String, view: UIView)] = []
        for dark in [false, true] {
            let mode = dark ? "深色" : "淺色"
            let palette = theme.palette(isDark: dark)

            let emoji = EmojiPanelView(frame: CGRect(x: 0, y: 0, width: 430, height: 225))
            emoji.applyTheme(palette: palette)
            emoji.reload()
            emoji.layoutIfNeeded()
            items.append(("表情符號頁（\(mode)）", emoji))

            let panel = CandidatePanelView(frame: CGRect(x: 0, y: 0, width: 430, height: 225))
            panel.applyTheme(palette: palette)
            panel.layoutIfNeeded()
            panel.show(candidates: (1...40).map { "字\($0)" }, startIndex: 6)
            panel.layoutIfNeeded()
            items.append(("展開候選表（\(mode)）", panel))

            let idle = makeKeyboard(theme: theme, scene: Scene(dark: dark))
            items.append(("沒在組字：工具列（\(mode)）", idle))
        }
        try save(sheet(title: "面板", items: items, columns: 2), name: "panels-native")
    }

    func testHighContrastPressedState() throws {
        let theme = ThemeCatalog.theme(id: "high-contrast", bundle: bundle)
        var items: [(label: String, view: UIView)] = []
        for dark in [false, true] {
            items.append(("高對比：按住 G（\(dark ? "深" : "淺")色）", makeKeyboard(theme: theme, scene: Scene(dark: dark, pressed: "g"))))
        }
        try save(sheet(title: "高對比按下效果", items: items, columns: 2), name: "high-contrast-pressed")
    }
}
