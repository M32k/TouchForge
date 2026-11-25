import AppKit

/// config.json 최상위 구조
struct TouchForgeConfig: Codable {
    /// true 면 오른쪽 시스템 컨트롤 스트립까지 덮고 터치바 전체를 사용한다
    var hideControlStrip: Bool?
    /// 기본 터치바 구성 (JSON 키: "default")
    var defaultItems: [ItemConfig]
    /// 앱별 프리셋. 키는 번들 ID (예: "com.apple.Safari")
    var apps: [String: [ItemConfig]]?

    enum CodingKeys: String, CodingKey {
        case hideControlStrip
        case defaultItems = "default"
        case apps
    }
}

/// 터치바 아이템 하나. type 에 따라 쓰는 필드가 다르다 (README 참고)
struct ItemConfig: Codable {
    var type: String

    // 공통 모양
    var title: String?
    var symbol: String?      // SF Symbol 이름
    var image: String?       // 이미지/GIF 파일 경로 (~, 절대경로, 또는 설정 폴더 기준 상대경로)
    var width: Double?
    var bg: String?          // 배경색 "#RRGGBB" 또는 "#RRGGBBAA"
    var color: String?       // 글자/아이콘 색
    var fontSize: Double?
    var bordered: Bool?

    // 동작
    var action: ActionConfig?
    var longAction: ActionConfig?

    // 위젯 옵션
    var format: String?      // clock 날짜 형식
    var command: String?     // shell 위젯 명령
    var interval: Double?    // 갱신 주기(초)
    var latitude: Double?    // weather
    var longitude: Double?
    var ticker: String?      // stock (예: "005930.KS")
    var name: String?        // stock 표시 이름

    // 전광판
    var text: String?
    var speed: Double?       // 초당 이동 포인트

    static func label(_ text: String, color: String? = nil) -> ItemConfig {
        var item = ItemConfig(type: "label")
        item.title = text
        item.color = color
        return item
    }
}

/// 버튼을 눌렀을 때 할 일
struct ActionConfig: Codable {
    var type: String         // launch | key | media | shell | url | applescript | minimize
    var app: String?         // launch: 번들 ID 또는 .app 경로
    var key: String?         // key: "esc", "a", "f5" ... / media: "volumeUp" ...
    var keyCode: UInt16?     // key: 가상 키코드 직접 지정
    var modifiers: [String]? // key: ["cmd", "shift", "option", "control", "fn"]
    var command: String?     // shell
    var url: String?         // url
    var source: String?      // applescript
}

enum ConfigPaths {
    static let directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/TouchForge", isDirectory: true)
    static var file: URL { directory.appendingPathComponent("config.json") }

    /// "~/x", "/abs/x", "상대/x" 를 실제 파일 URL 로 바꾼다
    static func resolve(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        return directory.appendingPathComponent(expanded)
    }
}

extension NSColor {
    /// "#RRGGBB" / "#RRGGBBAA" / "RRGGBB"
    static func fromHex(_ string: String?) -> NSColor? {
        guard var hex = string?.trimmingCharacters(in: .whitespaces), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if hex.count == 6 {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        } else {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

/// 디코딩 에러를 사람이 읽을 수 있게
func describeConfigError(_ error: Error) -> String {
    if let decoding = error as? DecodingError {
        func path(_ ctx: DecodingError.Context) -> String {
            let p = ctx.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
            return p.isEmpty ? "" : " (위치: \(p))"
        }
        switch decoding {
        case .dataCorrupted(let ctx):
            let underlying = ctx.underlyingError.map { $0 as NSError }?.userInfo["NSDebugDescription"] as? String
            return "JSON 문법 오류: \(underlying ?? ctx.debugDescription)"
        case .keyNotFound(let key, let ctx):
            return "필수 키 '\(key.stringValue)' 없음\(path(ctx))"
        case .typeMismatch(_, let ctx):
            return "값 타입이 맞지 않음\(path(ctx)): \(ctx.debugDescription)"
        case .valueNotFound(_, let ctx):
            return "값이 비어 있음\(path(ctx))"
        @unknown default:
            return "\(decoding)"
        }
    }
    return error.localizedDescription
}
