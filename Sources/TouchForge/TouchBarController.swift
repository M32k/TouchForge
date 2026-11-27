import AppKit

/// 시스템 전체 터치바를 만들고 띄우는 컨트롤러
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let trayIdentifier = NSTouchBarItem.Identifier("com.m32k.TouchForge.tray")

    private let touchBar = NSTouchBar()
    private var trayItem: NSCustomTouchBarItem?
    private var itemsByIdentifier: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
    private var widgets: [BarWidget] = []
    private var generation = 0

    private(set) var hideControlStrip = true
    /// 사용자가 접어 둔 상태인지 (앱 전환 때 마음대로 다시 펼치지 않기 위해)
    private(set) var isMinimized = false
    /// 지금 우리 터치바가 화면에 떠 있는지
    private(set) var isPresented = false
    /// false 면 아이템을 바꿔도 저절로 띄우지 않는다 (애플 터치바 유지 모드)
    var autoPresent = true

    /// 컨트롤 스트립에 끼워 넣은 작은 아이템들 (애플 터치바 유지 모드)
    private var stripItems: [NSTouchBarItem] = []
    private var stripWidgets: [BarWidget] = []

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

        if forcePresent || (autoPresent && !isMinimized) {
            present()
        }
    }

    /// 떠 있으면 접어서 애플 기본 터치바로 돌려준다
    func hideIfShown() {
        if isPresented { minimize() }
    }

    // MARK: 컨트롤 스트립 아이템

    /// 애플 터치바는 그대로 두고, 오른쪽 컨트롤 스트립에 작은 아이템을 붙인다
    func installStripItems(_ configs: [ItemConfig]) {
        removeStripItems()
        for (index, config) in configs.enumerated() {
            let identifier = NSTouchBarItem.Identifier("com.m32k.TouchForge.strip.\(index)")
            let built = ItemFactory.make(config, identifier: identifier)
            stripItems.append(built.item)
            if let widget = built.widget {
                stripWidgets.append(widget)
                widget.start()
            }
            PrivateTouchBar.addSystemTrayItem(built.item)
            PrivateTouchBar.setControlStripPresence(identifier, present: true)
        }
    }

    func removeStripItems() {
        stripWidgets.forEach { $0.stop() }
        stripWidgets.removeAll()
        for item in stripItems {
            PrivateTouchBar.setControlStripPresence(item.identifier, present: false)
            PrivateTouchBar.removeSystemTrayItem(item)
        }
        stripItems.removeAll()
    }

    /// 에러 메시지를 터치바에 빨간 글씨로 띄운다
    func showError(_ message: String) {
        show([.label("⚠️ TouchForge 설정 오류: \(message)", color: "#FF453A")], hideControlStrip: false, forcePresent: true)
    }

    func present() {
        PrivateTouchBar.present(touchBar, trayIdentifier: Self.trayIdentifier, hideControlStrip: hideControlStrip)
        isMinimized = false
        isPresented = true
    }

    func minimize() {
        PrivateTouchBar.minimize(touchBar)
        isMinimized = true
        isPresented = false
    }

    func shutdown() {
        stopWidgets()
        removeStripItems()
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
