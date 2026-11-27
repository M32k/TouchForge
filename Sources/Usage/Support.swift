import Foundation
import Security

/// 사용자에게 보여줄 에러
struct UsageError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct HTTPStatusError: LocalizedError {
    let status: Int
    let body: String

    var errorDescription: String? {
        switch status {
        case 401: return "인증이 만료됐어요 (401)"
        case 403: return "접근이 거부됐어요 (403)"
        case 429: return "요청이 너무 많아요. 잠시 후 다시 시도해요 (429)"
        default: return "서버 응답 오류 (\(status))"
        }
    }
}

enum HTTP {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = ["User-Agent": "TouchForge/0.2 (macOS)"]
        return URLSession(configuration: configuration)
    }()

    /// 요청을 보내고 JSON 을 돌려준다. 2xx 가 아니면 HTTPStatusError
    static func json(_ request: URLRequest) async throws -> Any {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(decoding: data.prefix(400), as: UTF8.self)
            throw HTTPStatusError(status: status, body: body)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func request(_ urlString: String, method: String = "GET", bearer: String? = nil, headers: [String: String] = [:], jsonBody: Any? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let jsonBody, let data = try? JSONSerialization.data(withJSONObject: jsonBody) {
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}

/// JSON 값 꺼내기 도우미
enum JSONValue {
    static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// ISO8601 문자열, 유닉스 초, 유닉스 밀리초 모두 처리
    static func date(_ value: Any?) -> Date? {
        if let string = value as? String {
            if let date = isoFractional.date(from: string) ?? isoPlain.date(from: string) {
                return date
            }
            // 소수점 6자리 같은 경우: 소수 부분을 지우고 다시 시도
            let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
            if let date = isoPlain.date(from: trimmed) {
                return date
            }
            if let number = Double(string) {
                return epoch(number)
            }
            return nil
        }
        if let number = double(value) {
            return epoch(number)
        }
        return nil
    }

    private static func epoch(_ number: Double) -> Date {
        number > 1e12 ? Date(timeIntervalSince1970: number / 1000) : Date(timeIntervalSince1970: number)
    }

    /// JWT 의 payload 부분 디코딩 (서명 검증 없이 이메일 등 표시용)
    static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

enum Keychain {
    /// 다른 앱(예: Claude Code)이 저장한 일반 암호 항목 읽기.
    /// 처음엔 macOS 가 "TouchForge 가 키체인 항목을 사용하려고 합니다" 라고 물어본다.
    static func genericPassword(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }
}

enum Paths {
    static var home: URL { URL(fileURLWithPath: SharedStore.realHome) }
}
