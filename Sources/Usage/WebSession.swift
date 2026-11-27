import AppKit
import WebKit

/// 웹 로그인을 지원하는 사이트
enum WebService: String, CaseIterable {
    case claude
    case chatgpt

    var host: String {
        switch self {
        case .claude: return "claude.ai"
        case .chatgpt: return "chatgpt.com"
        }
    }

    var loginURL: URL {
        switch self {
        case .claude: return URL(string: "https://claude.ai/login")!
        case .chatgpt: return URL(string: "https://chatgpt.com/auth/login")!
        }
    }

    /// API 를 부를 때 머무르는 가벼운 같은 출처 페이지
    var originPage: URL {
        URL(string: "https://\(host)/robots.txt")!
    }

    /// 로그인됐는지 판단하는 쿠키 이름 (앞부분)
    var sessionCookiePrefixes: [String] {
        switch self {
        case .claude: return ["sessionKey"]
        case .chatgpt: return ["__Secure-next-auth.session-token"]
        }
    }

    /// 로그아웃 때 지울 사이트 데이터 이름
    var dataRecordKeywords: [String] {
        switch self {
        case .claude: return ["claude.ai", "anthropic.com"]
        case .chatgpt: return ["chatgpt.com", "openai.com"]
        }
    }

    var title: String {
        switch self {
        case .claude: return "Claude 로그인"
        case .chatgpt: return "ChatGPT 로그인"
        }
    }
}

/// 숨겨진 WKWebView 로 공식 웹사이트의 API 를 "브라우저처럼" 부른다.
/// 로그인 쿠키는 WebKit 기본 저장소에만 있고 TouchForge 가 따로 저장하지 않는다.
@MainActor
final class WebSessionManager: NSObject, WKNavigationDelegate {
    static let dataStore = WKWebsiteDataStore.default()
    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    private var webViews: [WebService: WKWebView] = [:]
    private var pendingLoads: [ObjectIdentifier: CheckedContinuation<Void, Error>] = [:]

    static func makeWebView(frame: NSRect = NSRect(x: 0, y: 0, width: 1000, height: 760)) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let webView = WKWebView(frame: frame, configuration: configuration)
        webView.customUserAgent = safariUserAgent
        return webView
    }

    // MARK: 로그인 상태

    static func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    static func isLoggedIn(_ service: WebService) async -> Bool {
        let cookies = await allCookies()
        return cookies.contains { cookie in
            cookie.domain.hasSuffix(service.host)
                && service.sessionCookiePrefixes.contains { cookie.name.hasPrefix($0) }
        }
    }

    static func logout(_ service: WebService) async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records: [WKWebsiteDataRecord] = await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(ofTypes: types) { records in
                continuation.resume(returning: records)
            }
        }
        let matching = records.filter { record in
            service.dataRecordKeywords.contains { record.displayName.contains($0) }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dataStore.removeData(ofTypes: types, for: matching) {
                continuation.resume()
            }
        }
    }

    // MARK: API 호출

    /// 로그인된 웹 세션으로 path 를 fetch 해서 JSON 을 돌려준다
    func fetchJSON(_ service: WebService, path: String, headers: [String: String] = [:]) async throws -> Any {
        guard await Self.isLoggedIn(service) else {
            throw UsageError("\(service.host) 웹 로그인이 안 돼 있어요")
        }
        let webView = try await readyWebView(for: service)
        let script = """
        const response = await fetch(path, { credentials: 'include', headers: headers });
        const text = await response.text();
        return JSON.stringify({ status: response.status, body: text });
        """
        let result = try await webView.callAsyncJavaScript(
            script,
            arguments: ["path": path, "headers": headers],
            in: nil,
            contentWorld: .defaultClient
        )
        guard let wrapped = result as? String,
              let envelope = try JSONSerialization.jsonObject(with: Data(wrapped.utf8)) as? [String: Any] else {
            throw UsageError("웹 응답을 읽지 못했어요")
        }
        let status = (envelope["status"] as? NSNumber)?.intValue ?? 0
        let body = envelope["body"] as? String ?? ""
        guard (200..<300).contains(status) else {
            if status == 401 || status == 403 {
                throw UsageError("\(service.host) 로그인이 만료됐거나 막혔어요 (\(status)). 다시 로그인해 주세요")
            }
            throw HTTPStatusError(status: status, body: String(body.prefix(400)))
        }
        guard let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) else {
            throw UsageError("\(service.host) 응답이 JSON 이 아니에요 (보안 확인 페이지일 수 있어요)")
        }
        return json
    }

    private func readyWebView(for service: WebService) async throws -> WKWebView {
        if let existing = webViews[service], !existing.isLoading, existing.url?.host == service.host {
            return existing
        }
        let webView = webViews[service] ?? Self.makeWebView()
        webView.navigationDelegate = self
        webViews[service] = webView
        try await load(webView, url: service.originPage)
        return webView
    }

    private func load(_ webView: WKWebView, url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingLoads[ObjectIdentifier(webView)] = continuation
            webView.load(URLRequest(url: url))
            Task { [weak self, weak webView] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard let self, let webView else { return }
                self.finishLoad(webView, error: UsageError("페이지를 불러오는 데 시간이 너무 오래 걸려요"))
            }
        }
    }

    private func finishLoad(_ webView: WKWebView, error: Error?) {
        guard let continuation = pendingLoads.removeValue(forKey: ObjectIdentifier(webView)) else { return }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoad(webView, error: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoad(webView, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoad(webView, error: error)
    }
}

/// 공식 로그인 페이지를 띄우는 창. 로그인 쿠키가 생기면 자동으로 닫힌다.
@MainActor
final class LoginWindowController: NSObject, NSWindowDelegate, WKUIDelegate {
    private static var open: [WebService: LoginWindowController] = [:]

    private let service: WebService
    private let window: NSWindow
    private let webView: WKWebView
    private var pollTimer: Timer?
    private let onFinish: (Bool) -> Void
    private var finished = false

    static func show(_ service: WebService, onFinish: @escaping (Bool) -> Void) {
        if let existing = open[service] {
            existing.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = LoginWindowController(service: service, onFinish: onFinish)
        open[service] = controller
        controller.start()
    }

    private init(service: WebService, onFinish: @escaping (Bool) -> Void) {
        self.service = service
        self.onFinish = onFinish
        let frame = NSRect(x: 0, y: 0, width: 520, height: 720)
        webView = WebSessionManager.makeWebView(frame: frame)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "\(service.title) — 공식 페이지에서 로그인하세요"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.delegate = self
        webView.uiDelegate = self
    }

    private func start() {
        webView.load(URLRequest(url: service.loginURL))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let timer = Timer(timeInterval: 1.5, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    @objc private func poll() {
        Task { @MainActor [weak self] in
            guard let self, !self.finished else { return }
            if await WebSessionManager.isLoggedIn(self.service) {
                self.complete(success: true)
            }
        }
    }

    private func complete(success: Bool) {
        guard !finished else { return }
        finished = true
        pollTimer?.invalidate()
        pollTimer = nil
        window.delegate = nil
        window.close()
        Self.open[service] = nil
        onFinish(success)
    }

    func windowWillClose(_ notification: Notification) {
        complete(success: false)
    }

    /// "Google 로 계속하기" 같은 팝업을 같은 창에서 열기
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
