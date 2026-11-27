import AppKit

/// 주기적으로 갱신되는 아이템
protocol BarWidget: AnyObject {
    func start()
    func stop()
}

/// 일정 간격으로 update() 를 부르고 버튼 글자를 바꾸는 위젯의 공통 부모
class TimedWidget: NSObject, BarWidget {
    let button: ActionButton
    let interval: TimeInterval
    let prefix: String?
    private var timer: Timer?

    init(button: ActionButton, interval: TimeInterval, prefix: String?) {
        self.button = button
        self.interval = max(0.5, interval)
        self.prefix = prefix
        super.init()
    }

    func start() {
        stop()
        update()
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        timer.tolerance = min(1, interval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerFired() {
        update()
    }

    /// 하위 클래스가 구현
    func update() {}

    func show(_ value: String, color: NSColor? = nil) {
        if let prefix, !prefix.isEmpty {
            button.setText("\(prefix) \(value)", color: color)
        } else {
            button.setText(value, color: color)
        }
    }
}

// MARK: - 시계

final class ClockWidget: TimedWidget {
    private let formatter: DateFormatter

    init(button: ActionButton, format: String?, prefix: String?) {
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = format ?? "HH:mm"
        super.init(button: button, interval: 1, prefix: prefix)
    }

    override func update() {
        show(formatter.string(from: Date()))
    }
}

// MARK: - 배터리

final class BatteryWidget: TimedWidget {
    override func update() {
        guard let battery = SystemStats.battery() else {
            show("AC")
            return
        }
        let icon = battery.isCharging ? "⚡︎" : (battery.onAC ? "🔌" : "🔋")
        let color: NSColor? = (!battery.onAC && battery.percent <= 20) ? .systemRed : nil
        show("\(icon)\(battery.percent)%", color: color)
    }
}

// MARK: - CPU

final class CPUWidget: TimedWidget {
    private var lastTicks: SystemStats.CPUTicks?

    override func update() {
        guard let ticks = SystemStats.cpuTicks() else { return }
        defer { self.lastTicks = ticks }
        guard let lastTicks else {
            show("—")
            return
        }
        let percent = SystemStats.cpuPercent(from: lastTicks, to: ticks)
        let color: NSColor? = percent >= 80 ? .systemRed : nil
        show(String(format: "%.0f%%", percent), color: color)
    }
}

// MARK: - 메모리

final class MemoryWidget: TimedWidget {
    override func update() {
        guard let memory = SystemStats.memory() else { return }
        let gb = 1024.0 * 1024.0 * 1024.0
        show(String(format: "%.1f/%.0fG", Double(memory.used) / gb, Double(memory.total) / gb))
    }
}

// MARK: - 셸 명령 결과

final class ShellWidget: TimedWidget {
    private let command: String
    private var running = false

    init(button: ActionButton, command: String, interval: TimeInterval, prefix: String?) {
        self.command = command
        super.init(button: button, interval: interval, prefix: prefix)
    }

    override func update() {
        guard !running else { return }
        running = true
        Shell.run(command) { [weak self] output in
            guard let self else { return }
            self.running = false
            let firstLine = output.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
            self.show(firstLine)
        }
    }
}

// MARK: - 날씨 (open-meteo, API 키 불필요)

final class WeatherWidget: TimedWidget {
    private let latitude: Double
    private let longitude: Double

    init(button: ActionButton, latitude: Double, longitude: Double, interval: TimeInterval, prefix: String?) {
        self.latitude = latitude
        self.longitude = longitude
        super.init(button: button, interval: interval, prefix: prefix)
    }

    override func update() {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weather_code&timezone=auto"
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            var text = "날씨 —"
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let current = json["current"] as? [String: Any],
               let temperature = (current["temperature_2m"] as? NSNumber)?.doubleValue {
                let code = (current["weather_code"] as? NSNumber)?.intValue ?? -1
                text = "\(WeatherWidget.emoji(for: code)) \(Int(temperature.rounded()))°"
            }
            let finalText = text
            DispatchQueue.main.async { self?.show(finalText) }
        }.resume()
    }

    static func emoji(for code: Int) -> String {
        switch code {
        case 0: return "☀️"
        case 1, 2: return "🌤"
        case 3: return "☁️"
        case 45, 48: return "🌫"
        case 51...57: return "🌦"
        case 61...67, 80...82: return "🌧"
        case 71...77, 85, 86: return "❄️"
        case 95...99: return "⛈"
        default: return "🌡"
        }
    }
}

// MARK: - 주식 (Yahoo Finance 비공식 API)

final class StockWidget: TimedWidget {
    private let ticker: String
    private let displayName: String

    init(button: ActionButton, ticker: String, name: String?, interval: TimeInterval, prefix: String?) {
        self.ticker = ticker
        self.displayName = name ?? ticker
        super.init(button: button, interval: interval, prefix: prefix)
    }

    override func update() {
        let encoded = ticker.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ticker
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=1d&interval=1d") else { return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        let name = displayName
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            var text = "\(name) —"
            var color: NSColor?
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let chart = json["chart"] as? [String: Any],
               let results = chart["result"] as? [[String: Any]],
               let meta = results.first?["meta"] as? [String: Any],
               let price = (meta["regularMarketPrice"] as? NSNumber)?.doubleValue {
                let previous = ((meta["chartPreviousClose"] ?? meta["previousClose"]) as? NSNumber)?.doubleValue ?? price
                let change = previous > 0 ? (price - previous) / previous * 100 : 0
                let arrow = change > 0 ? "▲" : (change < 0 ? "▼" : "")
                text = "\(name) \(StockWidget.format(price)) \(arrow)\(String(format: "%.2f", abs(change)))%"
                // 한국식: 상승 빨강, 하락 파랑
                if change > 0 { color = .systemRed } else if change < 0 { color = .systemBlue }
            }
            let finalText = text
            let finalColor = color
            DispatchQueue.main.async { self?.show(finalText, color: finalColor) }
        }.resume()
    }

    static func format(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = price >= 1000 ? 0 : 2
        formatter.minimumFractionDigits = price >= 1000 ? 0 : 2
        return formatter.string(from: NSNumber(value: price)) ?? String(price)
    }
}

// MARK: - 구독 한도 (같은 앱의 UsageStore 가 읽어 둔 값)

final class UsageBarWidget: TimedWidget {
    private static let letters = ["claude": "C", "codex": "X", "gemini": "G"]
    private let providers: Set<String>?

    init(button: ActionButton, providers: [String]?, interval: TimeInterval, prefix: String?) {
        self.providers = providers.map { Set($0.map { $0.lowercased() }) }
        super.init(button: button, interval: interval, prefix: prefix)
    }

    override func update() {
        let snapshots = UsageCache.shared.snapshots
        guard !snapshots.isEmpty else {
            show("한도 —")
            return
        }
        // 30분 넘게 갱신이 없으면 회색 (네트워크·로그인 문제일 수 있음)
        let isStale = UsageCache.shared.updatedAt.map { Date().timeIntervalSince($0) > 30 * 60 } ?? true

        var entries: [(text: String, color: NSColor?)] = []
        for snapshot in snapshots {
            let provider = snapshot.provider.rawValue
            if let providers, !providers.contains(provider) { continue }
            let letter = Self.letters[provider] ?? String(provider.prefix(1)).uppercased()
            guard let used = snapshot.primary?.usedPercent else {
                entries.append((text: letter + "—", color: NSColor.secondaryLabelColor))
                continue
            }
            var color: NSColor? = nil
            if used >= 90 { color = .systemRed } else if used >= 70 { color = .systemOrange }
            if isStale { color = .secondaryLabelColor }
            entries.append((text: "\(letter)\(Int(used.rounded()))", color: color))
        }

        guard !entries.isEmpty else {
            show("한도 —")
            return
        }

        var parts: [(text: String, color: NSColor?)] = []
        if let prefix, !prefix.isEmpty { parts.append((text: "\(prefix) ", color: nil)) }
        for (index, entry) in entries.enumerated() {
            if index > 0 { parts.append((text: " ", color: nil)) }
            parts.append(entry)
        }
        button.setParts(parts)
    }
}

/// "usage" 를 누르면 펼쳐지는 상세 터치바: 서비스별 5시간·주간 % 와 리셋까지 남은 시간
enum UsageTouchBar {
    static func items() -> [ItemConfig] {
        var items: [ItemConfig] = []
        let snapshots = UsageCache.shared.snapshots
        if snapshots.isEmpty {
            items.append(.label("구독 한도 정보가 아직 없어요. 메뉴바에서 확인해 주세요", color: "#FF9F0A"))
        }
        let names: [ProviderID: (String, String)] = [
            .claude: ("Claude", "#D97757"),
            .codex: ("Codex", "#10A37F"),
            .gemini: ("Gemini", "#4285F4"),
        ]
        for snapshot in snapshots {
            let (name, hex) = names[snapshot.provider] ?? (snapshot.provider.displayName, "#FFFFFF")
            items.append(.label(name, color: hex))
            if snapshot.windows.isEmpty {
                items.append(.label("연결 안 됨", color: "#8E8E93"))
            }
            for window in snapshot.windows.prefix(2) {
                var text = "\(window.title) \(Format.percent(window.usedPercent))"
                if let reset = window.resetsAt {
                    text += " · " + shortReset(reset)
                }
                let color = window.usedPercent >= 90 ? "#FF453A" : (window.usedPercent >= 70 ? "#FF9F0A" : "#FFFFFF")
                var item = ItemConfig.label(text, color: color)
                item.fontSize = 13
                items.append(item)
            }
            items.append(ItemConfig(type: "smallSpace"))
        }
        items.append(ItemConfig(type: "flexibleSpace"))
        var refresh = ItemConfig(type: "button")
        refresh.symbol = "arrow.clockwise"
        refresh.action = ActionConfig(type: "usageRefresh")
        items.append(refresh)
        items.append(ItemConfig(type: "close"))
        return items
    }

    /// "2시간 10분 후 리셋" → 터치바용으로 짧게 "2:10"
    private static func shortReset(_ date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)일 \(hours)시간" }
        return String(format: "%d:%02d", hours, minutes)
    }
}
