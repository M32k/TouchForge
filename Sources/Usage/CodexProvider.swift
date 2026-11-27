import Foundation

/// ChatGPT 구독의 Codex 한도
/// - CLI 계정: ~/.codex/auth.json → chatgpt.com/backend-api/wham/usage
/// - 웹 로그인: chatgpt.com 세션 → /api/auth/session 토큰 → wham/usage
/// - 로컬 기록: ~/.codex/sessions/**/*.jsonl 의 마지막 token_count 이벤트 rate_limits
enum CodexProvider {
    static var codexHome: URL {
        if let custom = ProcessInfo.processInfo.environment["CODEX_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return Paths.home.appendingPathComponent(".codex")
    }

    static let usageURL = "https://chatgpt.com/backend-api/wham/usage"

    // MARK: CLI 계정

    static func fetchCLI() async throws -> ProviderSnapshot {
        let authURL = codexHome.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UsageError("Codex 로그인 정보(~/.codex/auth.json)가 없어요. 터미널에서 codex login 해 주세요")
        }
        guard let tokens = object["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty else {
            throw UsageError("Codex 가 ChatGPT 계정이 아닌 API 키로 로그인돼 있어요. 구독 한도는 ChatGPT 로그인에서만 보여요")
        }
        var headers: [String: String] = [:]
        if let accountID = tokens["account_id"] as? String, !accountID.isEmpty {
            headers["chatgpt-account-id"] = accountID
        }
        let email = (tokens["id_token"] as? String).flatMap { JSONValue.jwtPayload($0)?["email"] as? String }

        let json: Any
        do {
            json = try await HTTP.json(HTTP.request(usageURL, bearer: accessToken, headers: headers))
        } catch let error as HTTPStatusError where error.status == 401 {
            throw UsageError("Codex 토큰이 만료됐어요 (401). codex 를 한 번 실행하면 갱신돼요")
        }
        guard let usage = json as? [String: Any] else { throw UsageError("Codex 응답 형식을 알 수 없어요") }
        return try snapshot(from: usage, source: .cliAccount, account: email)
    }

    // MARK: 웹 로그인

    @MainActor
    static func fetchWeb(_ web: WebSessionManager) async throws -> ProviderSnapshot {
        guard let session = try await web.fetchJSON(.chatgpt, path: "/api/auth/session") as? [String: Any],
              let accessToken = session["accessToken"] as? String, !accessToken.isEmpty else {
            throw UsageError("chatgpt.com 세션 토큰을 받지 못했어요. 다시 로그인해 주세요")
        }
        var headers = ["Authorization": "Bearer \(accessToken)"]
        let account = session["account"] as? [String: Any]
        if let accountID = account?["id"] as? String {
            headers["chatgpt-account-id"] = accountID
        }
        let email = (session["user"] as? [String: Any])?["email"] as? String
        guard let usage = try await web.fetchJSON(.chatgpt, path: "/backend-api/wham/usage", headers: headers) as? [String: Any] else {
            throw UsageError("Codex 사용량 응답 형식을 알 수 없어요")
        }
        return try snapshot(from: usage, source: .webLogin, account: email)
    }

    // MARK: wham/usage 해석

    static func snapshot(from usage: [String: Any], source: SourceKind, account: String?) throws -> ProviderSnapshot {
        var windows: [UsageWindow] = []
        if let rateLimit = usage["rate_limit"] as? [String: Any] {
            windows += parseWindows(rateLimit, idPrefix: "", titlePrefix: "")
        }
        if let extras = usage["additional_rate_limits"] as? [[String: Any]] {
            for (index, extra) in extras.enumerated() {
                let name = (extra["limit_name"] as? String) ?? (extra["metered_feature"] as? String) ?? "추가 \(index + 1)"
                let limits = (extra["rate_limit"] as? [String: Any]) ?? extra
                windows += parseWindows(limits, idPrefix: "extra\(index)_", titlePrefix: "\(name) · ")
            }
        }
        guard !windows.isEmpty else { throw UsageError("Codex 응답에 한도 정보가 없어요") }
        let plan = (usage["plan_type"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return ProviderSnapshot(
            provider: .codex, windows: windows, plan: plan, account: account,
            source: source, fetchedAt: Date(), error: nil
        )
    }

    private static func parseWindows(_ rateLimit: [String: Any], idPrefix: String, titlePrefix: String) -> [UsageWindow] {
        var result: [UsageWindow] = []
        for (key, fallback) in [("primary_window", "5시간"), ("secondary_window", "주간")] {
            guard let window = rateLimit[key] as? [String: Any],
                  let used = JSONValue.double(window["used_percent"]) else { continue }
            let seconds = JSONValue.double(window["limit_window_seconds"])
            var resetsAt = JSONValue.date(window["reset_at"])
            if resetsAt == nil, let after = JSONValue.double(window["reset_after_seconds"]) {
                resetsAt = Date().addingTimeInterval(after)
            }
            result.append(UsageWindow(
                id: idPrefix + key,
                title: titlePrefix + (seconds.map { Format.windowTitle(seconds: $0) } ?? fallback),
                usedPercent: used,
                resetsAt: resetsAt,
                windowMinutes: seconds.map { Int($0 / 60) }
            ))
        }
        return result
    }

    // MARK: 로컬 기록

    static func fetchLocal() throws -> ProviderSnapshot {
        let roots = [
            codexHome.appendingPathComponent("sessions"),
            codexHome.appendingPathComponent("archived_sessions"),
        ]
        var files: [(url: URL, modified: Date)] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                files.append((url, modified))
            }
        }
        guard !files.isEmpty else {
            throw UsageError("Codex 사용 기록(~/.codex/sessions)이 없어요")
        }
        files.sort { $0.modified > $1.modified }

        for file in files.prefix(15) {
            guard let found = lastRateLimits(in: file.url) else { continue }
            let windows = localWindows(found.rateLimits, eventTime: found.timestamp)
            if windows.isEmpty { continue }
            let plan = (found.rateLimits["plan_type"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return ProviderSnapshot(
                provider: .codex, windows: windows, plan: plan, account: nil,
                source: .localFiles, fetchedAt: found.timestamp ?? file.modified, error: nil
            )
        }
        throw UsageError("Codex 사용 기록에서 한도 정보를 찾지 못했어요")
    }

    /// 파일 끝 1MB 만 읽어서 마지막 rate_limits 를 찾는다
    private static func lastRateLimits(in url: URL) -> (rateLimits: [String: Any], timestamp: Date?)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let chunk: UInt64 = 1_000_000
        try? handle.seek(toOffset: size > chunk ? size - chunk : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(decoding: data, as: UTF8.self)

        for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            let payload = object["payload"] as? [String: Any]
            guard let rateLimits = (payload?["rate_limits"] ?? object["rate_limits"]) as? [String: Any] else { continue }
            return (rateLimits, JSONValue.date(object["timestamp"]))
        }
        return nil
    }

    private static func localWindows(_ rateLimits: [String: Any], eventTime: Date?) -> [UsageWindow] {
        var result: [UsageWindow] = []
        let now = Date()
        for (key, fallback) in [("primary", "5시간"), ("secondary", "주간")] {
            guard let window = rateLimits[key] as? [String: Any],
                  var used = JSONValue.double(window["used_percent"]) else { continue }
            let minutes = JSONValue.double(window["window_minutes"]).map { Int($0) }
            var resetsAt = JSONValue.date(window["resets_at"])
            if resetsAt == nil, let seconds = JSONValue.double(window["resets_in_seconds"]) {
                resetsAt = (eventTime ?? now).addingTimeInterval(seconds)
            }
            var title = minutes.map { Format.windowTitle(minutes: $0) } ?? fallback
            // 기록 이후 이미 리셋 시간이 지났다면 지금은 0%
            if let reset = resetsAt, reset < now {
                used = 0
                resetsAt = nil
                title += " (리셋됨)"
            }
            result.append(UsageWindow(id: key, title: title, usedPercent: used, resetsAt: resetsAt, windowMinutes: minutes))
        }
        return result
    }
}
