import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = TouchBarController()
    private let store = ConfigStore()
    private var statusItem: NSStatusItem?

    private var config: TouchForgeConfig?
    private var configError: String?
    private var frontmostBundleID: String?
    private var currentPresetKey: String?

    // MARK: - 앱 생명주기

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        ActionRunner.minimizeHandler = { [weak self] in
            self?.controller.minimize()
        }

        guard PrivateTouchBar.isAvailable else {
            showAlert(
                title: "시스템 터치바 API를 찾지 못했어요",
                message: "이 Mac 또는 macOS 버전에서는 TouchForge 가 터치바를 바꿀 수 없습니다. 터치바가 있는 MacBook Pro 에서 실행했는지 확인해 주세요."
            )
            return
        }
        controller.installTrayItem()

        do {
            try store.ensureConfigExists()
        } catch {
            configError = "설정 폴더를 만들지 못함: \(error.localizedDescription)"
        }
        store.onChange = { [weak self] in
            self?.reloadConfig()
        }
        store.startWatching()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        reloadConfig()
        Log.info("시작 완료. 설정 파일: \(ConfigPaths.file.path)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    // MARK: - 설정 / 프리셋

    private func reloadConfig() {
        do {
            let loaded = try store.load()
            config = loaded
            configError = nil
            // 애플 터치바 유지 모드: 자동으로 덮지 않고, 컨트롤 스트립에 아이템만 붙인다
            controller.autoPresent = !loaded.isStripMode
            controller.installStripItems(loaded.isStripMode ? (loaded.strip ?? []) : [])
            if loaded.isStripMode { controller.hideIfShown() }
        } catch {
            configError = describeConfigError(error)
            Log.error("설정 읽기 실패: \(configError ?? "")")
        }
        applyPreset(reloaded: true)
    }

    @objc private func activeApplicationChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        frontmostBundleID = app.bundleIdentifier
        applyPreset(reloaded: false)
    }

    /// 앞에 있는 앱에 맞는 프리셋을 골라 터치바에 반영
    private func applyPreset(reloaded: Bool) {
        if let configError {
            controller.showError(configError)
            currentPresetKey = nil
            return
        }
        guard let config else { return }

        let key: String
        let items: [ItemConfig]
        if let bundleID = frontmostBundleID, let appItems = config.apps?[bundleID] {
            key = bundleID
            items = expandDefaults(appItems, defaults: config.defaultItems)
        } else {
            key = "default"
            items = config.defaultItems
        }
        let hideStrip = config.hideControlStrip ?? true

        // 애플 터치바 유지 모드: 프리셋은 미리 만들어만 두고(아이콘 누르면 열림),
        // 앱을 바꾸면 애플 터치바로 돌아간다
        if config.isStripMode {
            if reloaded || key != currentPresetKey {
                currentPresetKey = key
                controller.show(items, hideControlStrip: hideStrip, forcePresent: false)
            }
            if !reloaded { controller.hideIfShown() }
            return
        }

        // 전체 모드에서도 passthrough 앱에서는 애플 터치바를 보여준다
        if let bundleID = frontmostBundleID, config.passthrough?.contains(bundleID) == true {
            currentPresetKey = "passthrough:\(bundleID)"
            controller.hideIfShown()
            return
        }
        let comingBackFromPassthrough = currentPresetKey?.hasPrefix("passthrough:") == true

        // 같은 프리셋이면 다시 만들지 않고, 접어 둔 게 아니면 다시 띄우기만 한다
        if !reloaded && key == currentPresetKey {
            if !controller.isMinimized { controller.present() }
            return
        }
        currentPresetKey = key
        controller.show(items, hideControlStrip: hideStrip, forcePresent: reloaded || comingBackFromPassthrough)
    }

    /// 앱 프리셋 안의 { "type": "defaults" } 를 기본 아이템들로 펼친다
    private func expandDefaults(_ items: [ItemConfig], defaults: [ItemConfig]) -> [ItemConfig] {
        items.flatMap { item -> [ItemConfig] in
            item.type.lowercased() == "defaults" ? defaults : [item]
        }
    }

    // MARK: - 메뉴바

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "rectangle.grid.1x2", accessibilityDescription: "TouchForge") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "TF"
            }
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        addInfo(menu, "TouchForge \(version)")
        if !PrivateTouchBar.isAvailable {
            addInfo(menu, "⚠️ 시스템 터치바 API 없음")
        }
        if let configError {
            addInfo(menu, "⚠️ " + String(configError.prefix(70)))
        }
        let presetName: String
        if let key = currentPresetKey, key.hasPrefix("passthrough:") {
            presetName = "애플 기본 터치바"
        } else if let key = currentPresetKey, key != "default" {
            presetName = appName(for: key) ?? key
        } else {
            presetName = "기본"
        }
        addInfo(menu, "현재 프리셋: \(presetName)")
        addInfo(menu, config?.isStripMode == true ? "모드: 애플 터치바 유지 (아이콘을 누르면 열림)" : "모드: 항상 TouchForge 로 덮기")
        menu.addItem(.separator())

        addAction(menu, "터치바 보이기", #selector(showBar))
        addAction(menu, "터치바 접기", #selector(hideBar))
        menu.addItem(.separator())

        addAction(menu, "설정 다시 불러오기", #selector(reloadFromMenu), key: "r")
        addAction(menu, "설정 파일 열기", #selector(openConfigFile), key: ",")
        addAction(menu, "설정 폴더 열기", #selector(openConfigFolder))
        if let bundleID = frontmostBundleID {
            addAction(menu, "번들 ID 복사: \(bundleID)", #selector(copyFrontmostBundleID))
        }
        addAction(menu, "기본 설정으로 초기화…", #selector(resetConfig))
        menu.addItem(.separator())

        let trusted = ActionRunner.ensureAccessibility(prompt: false)
        addAction(menu, trusted ? "손쉬운 사용 권한 ✓" : "손쉬운 사용 권한 요청 (키 입력용)", #selector(requestAccessibility))
        let loginItem = addAction(menu, "로그인 시 자동 실행", #selector(toggleLaunchAtLogin))
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())

        addAction(menu, "종료", #selector(quit), key: "q")
    }

    private func addInfo(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    @discardableResult
    private func addAction(_ menu: NSMenu, _ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func appName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - 메뉴 동작

    @objc private func showBar() {
        controller.present()
    }

    @objc private func hideBar() {
        controller.minimize()
    }

    @objc private func reloadFromMenu() {
        currentPresetKey = nil
        reloadConfig()
    }

    @objc private func openConfigFile() {
        NSWorkspace.shared.open(ConfigPaths.file)
    }

    @objc private func openConfigFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([ConfigPaths.file])
    }

    @objc private func copyFrontmostBundleID() {
        guard let bundleID = frontmostBundleID else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bundleID, forType: .string)
    }

    @objc private func resetConfig() {
        let alert = NSAlert()
        alert.messageText = "기본 설정으로 초기화할까요?"
        alert.informativeText = "지금 설정은 config.backup.json 으로 보관됩니다."
        alert.addButton(withTitle: "초기화")
        alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.resetToDefault()
            reloadFromMenu()
        } catch {
            showAlert(title: "초기화 실패", message: error.localizedDescription)
        }
    }

    @objc private func requestAccessibility() {
        if !ActionRunner.ensureAccessibility(prompt: true) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(
                title: "로그인 항목 설정 실패",
                message: "\(error.localizedDescription)\n\n앱을 '응용 프로그램' 폴더로 옮긴 뒤 다시 시도해 보세요."
            )
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
