import AppKit

// 메뉴바 전용 앱 (Dock 아이콘 없음). Info.plist 의 LSUIElement 와 같은 효과.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
