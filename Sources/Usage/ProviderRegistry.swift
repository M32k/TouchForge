import Foundation

extension ProviderID {
    /// 자동 모드에서 시도하는 순서
    var autoOrder: [SourceKind] {
        switch self {
        case .claude: return [.cliAccount, .webLogin]
        case .codex: return [.cliAccount, .webLogin, .localFiles]
        case .gemini: return [.cliAccount]
        }
    }

    var supportedSources: [SourceKind] { [.auto] + autoOrder }

    var webService: WebService? {
        switch self {
        case .claude: return .claude
        case .codex: return .chatgpt
        case .gemini: return nil
        }
    }

    func sourceLabel(_ source: SourceKind) -> String {
        switch (self, source) {
        case (.claude, .cliAccount): return "CLI 계정 (Claude Code)"
        case (.codex, .cliAccount): return "CLI 계정 (Codex)"
        case (.gemini, .cliAccount): return "CLI 계정 (Gemini CLI)"
        case (.claude, .webLogin): return "웹 로그인 (claude.ai)"
        case (.codex, .webLogin): return "웹 로그인 (chatgpt.com)"
        case (.codex, .localFiles): return "로컬 기록 (~/.codex/sessions)"
        default: return source.label
        }
    }

    var sourceHelp: String {
        switch self {
        case .claude:
            return "CLI 계정은 Claude Code 로그인 정보를 읽어요 (처음 한 번 키체인 허용 필요). 웹 로그인은 claude.ai 공식 로그인 페이지를 앱 안에서 띄워요."
        case .codex:
            return "CLI 계정은 codex login 정보를, 웹 로그인은 chatgpt.com 로그인을 써요. 로컬 기록은 마지막으로 Codex 를 쓴 시점의 값이에요."
        case .gemini:
            return "Gemini CLI 의 Google 로그인 정보를 읽어요. 개인·AI Pro·Ultra 계정은 Google 정책상 지원되지 않을 수 있어요."
        }
    }
}

enum ProviderRegistry {
    @MainActor
    static func fetch(_ provider: ProviderID, source: SourceKind, web: WebSessionManager) async -> ProviderSnapshot {
        let order = source == .auto ? provider.autoOrder : [source]
        var errors: [String] = []
        for attempt in order {
            do {
                return try await fetchOne(provider, attempt, web: web)
            } catch {
                errors.append("• \(provider.sourceLabel(attempt)): \(error.localizedDescription)")
            }
        }
        return ProviderSnapshot(
            provider: provider, windows: [], plan: nil, account: nil,
            source: order.first ?? .auto, fetchedAt: Date(),
            error: errors.joined(separator: "\n")
        )
    }

    @MainActor
    private static func fetchOne(_ provider: ProviderID, _ source: SourceKind, web: WebSessionManager) async throws -> ProviderSnapshot {
        switch (provider, source) {
        case (.claude, .cliAccount): return try await ClaudeProvider.fetchCLI()
        case (.claude, .webLogin): return try await ClaudeProvider.fetchWeb(web)
        case (.codex, .cliAccount): return try await CodexProvider.fetchCLI()
        case (.codex, .webLogin): return try await CodexProvider.fetchWeb(web)
        case (.codex, .localFiles): return try await Task.detached { try CodexProvider.fetchLocal() }.value
        case (.gemini, .cliAccount): return try await GeminiProvider.fetchCLI()
        default: throw UsageError("이 서비스는 '\(source.label)' 방식을 지원하지 않아요")
        }
    }
}
