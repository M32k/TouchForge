import Foundation

/// Gemini CLI 한도 (모델별 일일 요청 한도)
/// - CLI 계정: ~/.gemini/oauth_creds.json → cloudcode-pa.googleapis.com
///   loadCodeAssist(요금제·프로젝트) → retrieveUserQuota(모델별 남은 비율)
enum GeminiProvider {
    private static let base = "https://cloudcode-pa.googleapis.com/v1internal"

    /// 갱신한 토큰은 메모리에만 둔다 (Gemini CLI 파일은 건드리지 않음)
    private static var refreshedToken: (token: String, expiresAt: Date)?
    private static var clientCredentials: (id: String, secret: String)?
    private static let lock = NSLock()

    static func fetchCLI() async throws -> ProviderSnapshot {
        let credsURL = Paths.home.appendingPathComponent(".gemini/oauth_creds.json")
        guard let data = try? Data(contentsOf: credsURL),
              let creds = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UsageError("Gemini CLI 로그인 정보(~/.gemini/oauth_creds.json)가 없어요. 터미널에서 gemini 실행 후 Google 로 로그인해 주세요")
        }
        let email = (creds["id_token"] as? String).flatMap { JSONValue.jwtPayload($0)?["email"] as? String }
        let token = try await validAccessToken(creds)

        // 1) 요금제 + 프로젝트
        let load = try await post("loadCodeAssist", token: token, body: [
            "metadata": ["ideType": "GEMINI_CLI", "pluginType": "GEMINI"],
        ])
        let plan = planLabel(load)
        var project: String?
        if let value = load["cloudaicompanionProject"] as? String {
            project = value
        } else if let value = (load["cloudaicompanionProject"] as? [String: Any])?["id"] as? String {
            project = value
        }
        let unsupportedClient = (load["ineligibleTiers"] as? [[String: Any]])?
            .contains { ($0["reasonCode"] as? String) == "UNSUPPORTED_CLIENT" } ?? false

        // 2) 모델별 한도
        let quotaBody: [String: Any] = project.map { ["project": $0] } ?? [:]
        let quota: [String: Any]
        do {
            quota = try await post("retrieveUserQuota", token: token, body: quotaBody)
        } catch let error as HTTPStatusError where error.status == 403 {
            if unsupportedClient || error.body.contains("SUBSCRIPTION_REQUIRED") {
                throw UsageError("Google 이 2026-06-18 부터 개인·AI Pro·Ultra 계정의 Gemini CLI 로그인을 끝내서 한도를 읽을 수 없어요 (Workspace·Standard 계정만 지원)")
            }
            throw error
        }

        let windows = parseBuckets(quota)
        guard !windows.isEmpty else { throw UsageError("Gemini 응답에 한도 정보가 없어요") }
        return ProviderSnapshot(
            provider: .gemini, windows: windows, plan: plan, account: email,
            source: .cliAccount, fetchedAt: Date(), error: nil
        )
    }

    private static func post(_ method: String, token: String, body: [String: Any]) async throws -> [String: Any] {
        let request = HTTP.request("\(base):\(method)", method: "POST", bearer: token, jsonBody: body)
        guard let json = try await HTTP.json(request) as? [String: Any] else {
            throw UsageError("Gemini \(method) 응답 형식을 알 수 없어요")
        }
        return json
    }

    private static func planLabel(_ load: [String: Any]) -> String? {
        if let name = (load["paidTier"] as? [String: Any])?["name"] as? String, !name.isEmpty { return name }
        let tier = load["currentTier"] as? [String: Any]
        switch tier?["id"] as? String {
        case "standard-tier": return "Standard"
        case "free-tier": return "Free"
        case "legacy-tier": return "Legacy"
        default: return tier?["name"] as? String
        }
    }

    /// 모델별로 가장 적게 남은 버킷을 골라 사용률로 바꾼다 (Pro → Flash → Flash Lite 순)
    static func parseBuckets(_ quota: [String: Any]) -> [UsageWindow] {
        guard let buckets = quota["buckets"] as? [[String: Any]] else { return [] }
        var lowest: [String: (fraction: Double, reset: Date?)] = [:]
        for bucket in buckets {
            guard let model = bucket["modelId"] as? String,
                  let fraction = JSONValue.double(bucket["remainingFraction"]) else { continue }
            let reset = JSONValue.date(bucket["resetTime"])
            if let current = lowest[model], current.fraction <= fraction { continue }
            lowest[model] = (fraction, reset)
        }
        func rank(_ model: String) -> Int {
            let name = model.lowercased()
            if name.contains("flash-lite") { return 2 }
            if name.contains("flash") { return 1 }
            if name.contains("pro") { return 0 }
            return 3
        }
        return lowest
            .sorted { lhs, rhs in
                rank(lhs.key) != rank(rhs.key) ? rank(lhs.key) < rank(rhs.key) : lhs.key > rhs.key
            }
            .prefix(5)
            .map { model, value in
                UsageWindow(
                    id: model,
                    title: prettyModel(model),
                    usedPercent: max(0, min(100, (1 - value.fraction) * 100)),
                    resetsAt: value.reset,
                    windowMinutes: nil
                )
            }
    }

    static func prettyModel(_ id: String) -> String {
        id.split(separator: "-").map { part -> String in
            let text = String(part)
            return text.first?.isLetter == true ? text.prefix(1).uppercased() + text.dropFirst() : text
        }.joined(separator: " ")
    }

    // MARK: 토큰

    private static func validAccessToken(_ creds: [String: Any]) async throws -> String {
        guard let token = creds["access_token"] as? String, !token.isEmpty else {
            throw UsageError("Gemini CLI 로그인 정보에 토큰이 없어요")
        }
        let expiry = JSONValue.date(creds["expiry_date"])
        if let expiry, expiry > Date().addingTimeInterval(60) {
            return token
        }
        if let memo = cachedToken(), memo.expiresAt > Date().addingTimeInterval(60) {
            return memo.token
        }
        guard let refresh = creds["refresh_token"] as? String else {
            throw UsageError("Gemini 토큰이 만료됐어요. 터미널에서 gemini 를 한 번 실행해 주세요")
        }
        guard let client = findClientCredentials() else {
            throw UsageError("Gemini 토큰이 만료됐어요. gemini 를 한 번 실행하면 갱신돼요 (설치된 Gemini CLI 를 찾지 못해 직접 갱신할 수 없어요)")
        }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form: [(String, String)] = [
            ("client_id", client.id),
            ("client_secret", client.secret),
            ("refresh_token", refresh),
            ("grant_type", "refresh_token"),
        ]
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = form
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }
            .joined(separator: "&")
            .data(using: .utf8)
        guard let json = try await HTTP.json(request) as? [String: Any],
              let newToken = json["access_token"] as? String else {
            throw UsageError("Gemini 토큰 갱신에 실패했어요")
        }
        let expiresIn = JSONValue.double(json["expires_in"]) ?? 3_000
        storeToken(newToken, expiresAt: Date().addingTimeInterval(expiresIn))
        return newToken
    }

    // 잠금은 동기 함수 안에서만 (async 안에서 NSLock 직접 쓰지 않기)
    private static func cachedToken() -> (token: String, expiresAt: Date)? {
        lock.lock()
        defer { lock.unlock() }
        return refreshedToken
    }

    private static func storeToken(_ token: String, expiresAt: Date) {
        lock.lock()
        defer { lock.unlock() }
        refreshedToken = (token, expiresAt)
    }

    /// 설치된 Gemini CLI 패키지 안에서 OAuth 클라이언트 ID/secret 을 찾는다
    static func findClientCredentials() -> (id: String, secret: String)? {
        lock.lock()
        let memo = clientCredentials
        lock.unlock()
        if let memo { return memo }

        let env = ProcessInfo.processInfo.environment
        if let id = env["GEMINI_OAUTH_CLIENT_ID"], let secret = env["GEMINI_OAUTH_CLIENT_SECRET"] {
            return (id, secret)
        }

        let fileManager = FileManager.default
        let home = SharedStore.realHome
        var roots = [
            "/opt/homebrew/lib/node_modules/@google/gemini-cli",
            "/usr/local/lib/node_modules/@google/gemini-cli",
            "\(home)/.npm-global/lib/node_modules/@google/gemini-cli",
            "\(home)/.bun/install/global/node_modules/@google/gemini-cli",
        ]
        let nvm = "\(home)/.nvm/versions/node"
        for version in (try? fileManager.contentsOfDirectory(atPath: nvm)) ?? [] {
            roots.append("\(nvm)/\(version)/lib/node_modules/@google/gemini-cli")
        }
        for cellar in ["/opt/homebrew/Cellar/gemini-cli", "/usr/local/Cellar/gemini-cli"] {
            for version in (try? fileManager.contentsOfDirectory(atPath: cellar)) ?? [] {
                roots.append("\(cellar)/\(version)/libexec/lib/node_modules/@google/gemini-cli")
            }
        }

        for root in roots where fileManager.fileExists(atPath: root) {
            if let found = scanForClient(root: root) {
                lock.lock()
                clientCredentials = found
                lock.unlock()
                return found
            }
        }
        return nil
    }

    private static func scanForClient(root: String) -> (id: String, secret: String)? {
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return nil }
        var candidates: [String] = []
        var others: [String] = []
        while let relative = enumerator.nextObject() as? String {
            guard relative.hasSuffix(".js") else { continue }
            if relative.contains("oauth2") { candidates.append(relative) } else if relative.contains("bundle") || relative.contains("chunk") { others.append(relative) }
            if candidates.count + others.count > 400 { break }
        }
        let idPattern = #"OAUTH_CLIENT_ID\s*=\s*['"]([^'"]+)['"]"#
        let secretPattern = #"OAUTH_CLIENT_SECRET\s*=\s*['"]([^'"]+)['"]"#
        for relative in candidates + others {
            let path = (root as NSString).appendingPathComponent(relative)
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue ?? 0
            guard size < 40_000_000, let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            guard text.contains("OAUTH_CLIENT_SECRET") else { continue }
            if let id = firstMatch(idPattern, in: text), let secret = firstMatch(secretPattern, in: text) {
                return (id, secret)
            }
        }
        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
