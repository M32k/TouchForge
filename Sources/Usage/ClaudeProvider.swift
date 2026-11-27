import Foundation

/// Claude Pro/Max 구독 한도
/// - CLI 계정: Claude Code 가 저장한 로그인 정보(키체인 / ~/.claude/.credentials.json) → api.anthropic.com/api/oauth/usage
/// - 웹 로그인: claude.ai 세션 → claude.ai/api/organizations/{id}/usage
enum ClaudeProvider {
    struct Credentials {
        let accessToken: String
        let expiresAt: Date?
        let subscriptionType: String?
        let rateLimitTier: String?

        var isExpired: Bool {
            guard let expiresAt else { return false }
            return expiresAt < Date().addingTimeInterval(60)
        }

        var planLabel: String? {
            guard let type = subscriptionType, !type.isEmpty else { return nil }
            var label = type.prefix(1).uppercased() + type.dropFirst()
            if let tier = rateLimitTier, let range = tier.range(of: #"\d+x"#, options: .regularExpression) {
                label += " " + tier[range]
            }
            return label
        }
    }

    private static var cached: Credentials?
    private static let lock = NSLock()

    // MARK: CLI 계정

    static func fetchCLI() async throws -> ProviderSnapshot {
        let credentials = try await Task.detached(priority: .userInitiated) { try loadCredentials() }.value
        guard !credentials.isExpired else {
            invalidateCache()
            throw UsageError("Claude Code 로그인 토큰이 만료됐어요. 터미널에서 claude 를 한 번 실행하면 갱신돼요")
        }
        let request = HTTP.request(
            "https://api.anthropic.com/api/oauth/usage",
            bearer: credentials.accessToken,
            headers: ["anthropic-beta": "oauth-2025-04-20"]
        )
        let json: Any
        do {
            json = try await HTTP.json(request)
        } catch let error as HTTPStatusError where error.status == 401 {
            invalidateCache()
            throw UsageError("Claude Code 토큰이 거부됐어요 (401). claude 를 한 번 실행하거나 /login 해 주세요")
        }
        guard let object = json as? [String: Any] else { throw UsageError("Claude 응답 형식을 알 수 없어요") }
        let windows = parseUsage(object)
        guard !windows.isEmpty else { throw UsageError("Claude 응답에 한도 정보가 없어요") }
        return ProviderSnapshot(
            provider: .claude, windows: windows, plan: credentials.planLabel, account: nil,
            source: .cliAccount, fetchedAt: Date(), error: nil
        )
    }

    private static func invalidateCache() {
        lock.lock(); cached = nil; lock.unlock()
    }

    /// 키체인 → 파일 순서로 읽고, 유효하면 메모리에 보관 (키체인 질문을 줄이기 위해)
    static func loadCredentials() throws -> Credentials {
        lock.lock()
        defer { lock.unlock() }
        if let cached, !cached.isExpired { return cached }

        var raw = Keychain.genericPassword(service: "Claude Code-credentials")
        if raw == nil {
            let file = Paths.home.appendingPathComponent(".claude/.credentials.json")
            raw = try? Data(contentsOf: file)
        }
        guard let data = raw,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw UsageError("Claude Code 로그인 정보를 찾지 못했어요. 터미널에서 claude 실행 후 /login 하거나, 웹 로그인을 써 주세요")
        }
        let credentials = Credentials(
            accessToken: token,
            expiresAt: JSONValue.date(oauth["expiresAt"]),
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String
        )
        cached = credentials
        return credentials
    }

    // MARK: 웹 로그인

    @MainActor
    static func fetchWeb(_ web: WebSessionManager) async throws -> ProviderSnapshot {
        guard let organizations = try await web.fetchJSON(.claude, path: "/api/organizations") as? [[String: Any]],
              !organizations.isEmpty else {
            throw UsageError("claude.ai 조직 정보를 찾지 못했어요")
        }
        let chatOrg = organizations.first { ($0["capabilities"] as? [String])?.contains("chat") == true }
        let organization = chatOrg ?? organizations[0]
        guard let orgID = organization["uuid"] as? String else {
            throw UsageError("claude.ai 조직 ID 가 없어요")
        }
        guard let usage = try await web.fetchJSON(.claude, path: "/api/organizations/\(orgID)/usage") as? [String: Any] else {
            throw UsageError("claude.ai 사용량 응답 형식을 알 수 없어요")
        }
        let windows = parseUsage(usage)
        guard !windows.isEmpty else {
            throw UsageError("claude.ai 에 사용량 정보가 없어요 (무료 플랜은 한도 화면이 없어요)")
        }
        let capabilities = organization["capabilities"] as? [String] ?? []
        let plan: String?
        if capabilities.contains("claude_max") {
            plan = "Max"
        } else if capabilities.contains("claude_pro") {
            plan = "Pro"
        } else {
            plan = nil
        }
        return ProviderSnapshot(
            provider: .claude, windows: windows, plan: plan, account: organization["name"] as? String,
            source: .webLogin, fetchedAt: Date(), error: nil
        )
    }

    // MARK: 응답 해석 (OAuth / 웹 공통)

    static func parseUsage(_ json: [String: Any]) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        var handled: Set<String> = []

        func add(_ key: String, _ title: String, minutes: Int?) {
            handled.insert(key)
            guard let window = json[key] as? [String: Any],
                  let utilization = JSONValue.double(window["utilization"]) else { return }
            windows.append(UsageWindow(
                id: key,
                title: title,
                usedPercent: utilization,
                resetsAt: JSONValue.date(window["resets_at"]),
                windowMinutes: minutes
            ))
        }

        add("five_hour", "5시간", minutes: 300)
        add("seven_day", "주간", minutes: 10_080)
        if !windows.contains(where: { $0.id == "seven_day" }) {
            add("seven_day_oauth_apps", "주간", minutes: 10_080)
        }
        add("seven_day_opus", "주간 · Opus", minutes: 10_080)
        add("seven_day_sonnet", "주간 · Sonnet", minutes: 10_080)

        let extraNames: [String: String] = [
            "seven_day_omelette": "주간 · Claude Design",
            "seven_day_cowork": "주간 · Cowork",
            "seven_day_routines": "주간 · Routines",
        ]
        for key in json.keys.sorted() where key.hasPrefix("seven_day_") && !handled.contains(key) {
            let suffix = String(key.dropFirst("seven_day_".count))
            add(key, extraNames[key] ?? "주간 · \(suffix.capitalized)", minutes: 10_080)
        }
        return windows
    }
}
