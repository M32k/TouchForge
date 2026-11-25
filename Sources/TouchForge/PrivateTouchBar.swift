import AppKit

/// Apple 비공개 API 래퍼.
/// - DFRFoundation.framework 의 C 함수 (dlopen/dlsym 으로 런타임 로드)
/// - NSTouchBar / NSTouchBarItem 의 비공개 클래스 메서드 (ObjC 런타임으로 호출)
///
/// 비공개 API 라서 macOS 업데이트로 사라질 수 있다. 그래서 모든 호출은
/// "없으면 로그만 남기고 넘어가는" 방식으로 작성했다.
enum PrivateTouchBar {
    private static let dfrHandle: UnsafeMutableRawPointer? = {
        let candidates = [
            "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation",
            "/System/Library/PrivateFrameworks/DFRFoundation.framework/Versions/A/DFRFoundation",
        ]
        for path in candidates {
            if let handle = dlopen(path, RTLD_NOW) {
                return handle
            }
        }
        Log.error("DFRFoundation 을 불러오지 못했습니다.")
        return nil
    }()

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = dfrHandle, let sym = dlsym(handle, name) else {
            Log.error("비공개 함수 \(name) 을 찾지 못했습니다.")
            return nil
        }
        return unsafeBitCast(sym, to: type)
    }

    private static let presentWithPlacement = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
    private static let presentSimple = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")

    /// 시스템 전체 터치바 API 를 쓸 수 있는지
    static var isAvailable: Bool {
        guard dfrHandle != nil else { return false }
        return class_getClassMethod(NSTouchBar.self, presentWithPlacement) != nil
            || class_getClassMethod(NSTouchBar.self, presentSimple) != nil
    }

    // MARK: DFRFoundation C 함수

    /// 컨트롤 스트립(오른쪽 시스템 영역)에 우리 아이콘을 보이거나 숨긴다.
    static func setControlStripPresence(_ identifier: NSTouchBarItem.Identifier, present: Bool) {
        typealias Fn = @convention(c) (NSString, Bool) -> Void
        symbol("DFRElementSetControlStripPresenceForIdentifier", as: Fn.self)?(identifier.rawValue as NSString, present)
    }

    /// 시스템 모달 터치바 왼쪽에 붙는 (x) 닫기 버튼 표시 여부
    static func setShowsCloseBoxWhenFrontMost(_ shows: Bool) {
        typealias Fn = @convention(c) (Bool) -> Void
        symbol("DFRSystemModalShowsCloseBoxWhenFrontMost", as: Fn.self)?(shows)
    }

    // MARK: NSTouchBarItem 비공개 클래스 메서드

    static func addSystemTrayItem(_ item: NSTouchBarItem) {
        callClassMethod(NSTouchBarItem.self, "addSystemTrayItem:", item)
    }

    static func removeSystemTrayItem(_ item: NSTouchBarItem) {
        callClassMethod(NSTouchBarItem.self, "removeSystemTrayItem:", item)
    }

    // MARK: NSTouchBar 비공개 클래스 메서드

    /// 터치바를 시스템 전체(모든 앱 위)에 띄운다.
    /// - hideControlStrip: true 면 오른쪽 컨트롤 스트립까지 덮어서 터치바 전체를 사용
    static func present(_ bar: NSTouchBar, trayIdentifier: NSTouchBarItem.Identifier, hideControlStrip: Bool) {
        let cls: AnyClass = NSTouchBar.self
        if let method = class_getClassMethod(cls, presentWithPlacement) {
            typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar, Int64, NSString) -> Void
            let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
            fn(cls as AnyObject, presentWithPlacement, bar, hideControlStrip ? 1 : 0, trayIdentifier.rawValue as NSString)
            return
        }
        if let method = class_getClassMethod(cls, presentSimple) {
            typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar, NSString) -> Void
            let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
            fn(cls as AnyObject, presentSimple, bar, trayIdentifier.rawValue as NSString)
            return
        }
        Log.error("presentSystemModalTouchBar 를 찾지 못했습니다. 이 macOS 에서는 시스템 터치바 API 가 막혔을 수 있습니다.")
    }

    /// 우리 터치바를 접고 원래 시스템 터치바를 보여준다 (컨트롤 스트립 아이콘으로 다시 열 수 있음)
    static func minimize(_ bar: NSTouchBar) {
        callClassMethod(NSTouchBar.self, "minimizeSystemModalTouchBar:", bar)
    }

    static func dismiss(_ bar: NSTouchBar) {
        callClassMethod(NSTouchBar.self, "dismissSystemModalTouchBar:", bar)
    }

    private static func callClassMethod(_ cls: AnyClass, _ selectorName: String, _ argument: AnyObject) {
        let selector = NSSelectorFromString(selectorName)
        guard let method = class_getClassMethod(cls, selector) else {
            Log.error("비공개 메서드 +\(selectorName) 을 찾지 못했습니다.")
            return
        }
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        fn(cls as AnyObject, selector, argument)
    }
}

enum Log {
    static func info(_ message: String) { NSLog("[TouchForge] %@", message) }
    static func error(_ message: String) { NSLog("[TouchForge] ⚠️ %@", message) }
}
