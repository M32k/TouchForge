import AppKit

/// 시스템 전체 터치바를 만들고 띄우는 컨트롤러
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let trayIdentifier = NSTouchBarItem.Identifier("com.m32k.TouchForge.tray")

    private let touchBar = NSTouchBar()
    private var trayItem: NSCustomTouchBarItem?
    private var itemsByIdentifier: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
    private var widgets: [Widget] = []
    private var generation = 0

    private(set) var hideControlStrip = true
    /// 사용자가 접어 둔 상태인지 (앱 전환 때 마음대로 다시 펼치지 않기 위해)
    private(set) var isMinimized = false

    override init() {
        super.init()
        touchBar.delegate = self
    }

    /// 컨트롤 스트립에 TouchForge 아이콘을 등록 (접었을 때 다시 여는 버튼)
    func installTrayItem() {
        let item = NSCustomTouchBarItem(identifier: Self.trayIdentifier)
        let image = NSImage(systemSymbolName: "rectangle.grid.1x2", accessibilityDescription: "TouchForge")
            ?? NSImage(named: NSImage.touchBarGoForwardTemplateName)!
        let button = NSButton(image: image, target: self, action: #selector(trayTapped))
        item.view = button
        trayItem = item

        PrivateTouchBar.addSystemTrayItem(item)
        PrivateTouchBar.setControlStripPresence(Self.trayIdentifier, present: true)
        PrivateTouchBar.setShowsCloseBoxWhenFrontMost(false)
    }

    func uninstallTrayItem() {
        PrivateTouchBar.setControlStripPresence(Self.trayIdentifier, present: false)
        if let trayItem { PrivateTouchBar.removeSystemTrayItem(trayItem) }
        trayItem = nil
    }

    @objc private func trayTapped() {
        present()
    }

    /// 아이템 목록으로 터치바를 새로 구성해서 띄운다
    func show(_ configs: [ItemConfig], hideControlStrip: Bool, forcePresent: Bool) {
        stopWidgets()
        itemsByIdentifier.removeAll()
        generation += 1

        var identifiers: [NSTouchBarItem.Identifier] = []
        for (index, config) in configs.enumerated() {
            switch config.type.lowercased() {
            case "flexiblespace", "flexible":
                identifiers.append(.flexibleSpace)
                continue
            case "smallspace":
                identifiers.append(.fixedSpaceSmall)
                continue
            case "largespace":
                identifiers.append(.fixedSpaceLarge)
                continue
            default:
                break
            }
            let identifier = NSTouchBarItem.Identifier("com.m32k.TouchForge.g\(generation).i\(index)")
            let built = ItemFactory.make(config, identifier: identifier)
            itemsByIdentifier[identifier] = built.item
            if let widget = built.widget { widgets.append(widget) }
            identifiers.append(identifier)
        }

        touchBar.defaultItemIdentifiers = identifiers
        self.hideControlStrip = hideControlStrip
        widgets.forEach { $0.start() }

        if forcePresent || !isMinimized {
            present()
        }
    }

    /// 에러 메시지를 터치바에 빨간 글씨로 띄운다
    func showError(_ message: String) {
        show([.label("⚠️ TouchForge 설정 오류: \(message)", color: "#FF453A")], hideControlStrip: false, forcePresent: true)
    }

    func present() {
        PrivateTouchBar.present(touchBar, trayIdentifier: Self.trayIdentifier, hideControlStrip: hideControlStrip)
        isMinimized = false
    }

    func minimize() {
        PrivateTouchBar.minimize(touchBar)
        isMinimized = true
    }

    func shutdown() {
        stopWidgets()
        PrivateTouchBar.dismiss(touchBar)
        uninstallTrayItem()
    }

    private func stopWidgets() {
        widgets.forEach { $0.stop() }
        widgets.removeAll()
    }

    // MARK: NSTouchBarDelegate

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        itemsByIdentifier[identifier]
    }
}
