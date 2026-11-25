import AppKit
import ApplicationServices

/// 버튼 동작 실행기
enum ActionRunner {
    /// "minimize" 동작이 불리면 실행할 콜백 (AppDelegate 가 연결)
    static var minimizeHandler: (() -> Void)?

    static func run(_ action: ActionConfig) {
        switch action.type.lowercased() {
        case "launch", "app":
            if let app = action.app { launch(app) }
        case "key":
            sendKey(action)
        case "media":
            if let key = action.key { sendMediaKey(key) }
        case "shell":
            if let command = action.command { Shell.run(command, completion: nil) }
        case "url", "open":
            if let raw = action.url { openURL(raw) }
        case "applescript":
            if let source = action.source { runAppleScript(source) }
        case "minimize", "close":
            minimizeHandler?()
        default:
            Log.error("알 수 없는 action type: \(action.type)")
        }
    }

    // MARK: 앱 실행

    static func launch(_ app: String) {
        let url: URL?
        if app.contains("/") {
            url = ConfigPaths.resolve(app)
        } else {
            url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app)
        }
        guard let appURL = url else {
            Log.error("앱을 찾지 못함: \(app)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error { Log.error("앱 실행 실패 \(app): \(error.localizedDescription)") }
        }
    }

    static func openURL(_ raw: String) {
        let url: URL?
        if raw.contains("://") {
            url = URL(string: raw)
        } else {
            url = ConfigPaths.resolve(raw)
        }
        if let url { NSWorkspace.shared.open(url) }
    }

    static func runAppleScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { Log.error("AppleScript 오류: \(error)") }
    }

    // MARK: 키 입력 (손쉬운 사용 권한 필요)

    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func sendKey(_ action: ActionConfig) {
        guard ensureAccessibility(prompt: true) else {
            Log.error("손쉬운 사용 권한이 없어 키 입력을 보낼 수 없습니다.")
            return
        }
        let code: UInt16
        if let keyCode = action.keyCode {
            code = keyCode
        } else if let name = action.key?.lowercased(), let mapped = KeyCodes.map[name] {
            code = mapped
        } else {
            Log.error("알 수 없는 키: \(action.key ?? "nil")")
            return
        }

        var flags = CGEventFlags()
        for modifier in action.modifiers ?? [] {
            switch modifier.lowercased() {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "option", "opt", "alt", "⌥": flags.insert(.maskAlternate)
            case "control", "ctrl", "⌃": flags.insert(.maskControl)
            case "fn", "function": flags.insert(.maskSecondaryFn)
            default: Log.error("알 수 없는 modifier: \(modifier)")
            }
        }

        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: isDown) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: 미디어 키 (볼륨/밝기/재생)

    /// IOKit hidsystem 의 NX_KEYTYPE_* 값
    private static let mediaKeys: [String: Int] = [
        "volumeup": 0, "volumedown": 1,
        "brightnessup": 2, "brightnessdown": 3,
        "mute": 7,
        "playpause": 16, "play": 16,
        "next": 17, "previous": 18, "prev": 18,
        "fastforward": 19, "rewind": 20,
        "illuminationup": 21, "illuminationdown": 22,
    ]

    static func sendMediaKey(_ name: String) {
        guard let keyType = mediaKeys[name.lowercased()] else {
            Log.error("알 수 없는 미디어 키: \(name)")
            return
        }
        for isDown in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: isDown ? 0xA00 : 0xB00)
            let data1 = (keyType << 16) | ((isDown ? 0xA : 0xB) << 8)
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

/// 셸 명령 실행 (zsh, 백그라운드)
enum Shell {
    static func run(_ command: String, completion: ((String) -> Void)?) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            var environment = ProcessInfo.processInfo.environment
            let extraPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = extraPath + (environment["PATH"].map { ":" + $0 } ?? "")
            environment["LANG"] = environment["LANG"] ?? "ko_KR.UTF-8"
            process.environment = environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            var output = ""
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } catch {
                output = "실행 실패"
            }
            let result = output
            if let completion {
                DispatchQueue.main.async { completion(result) }
            }
        }
    }
}

/// 키 이름 → macOS 가상 키코드 (ANSI 배열 기준)
enum KeyCodes {
    static let map: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "delete": 51, "backspace": 51, "esc": 53, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "pageup": 116, "forwarddelete": 117, "end": 119, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}
