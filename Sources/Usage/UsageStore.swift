import Foundation
import SwiftUI
import WidgetKit

/// UserDefaults 키 모음 (설정 화면의 @AppStorage 와 같은 키)
enum Prefs {
    static let defaults = UserDefaults.standard

    static func enabledKey(_ provider: ProviderID) -> String { "enabled.\(provider.rawValue)" }
    static func sourceKey(_ provider: ProviderID) -> String { "source.\(provider.rawValue)" }

    static func isEnabled(_ provider: ProviderID) -> Bool {
        defaults.object(forKey: enabledKey(provider)) as? Bool ?? true
    }

    static func source(for provider: ProviderID) -> SourceKind {
        SourceKind(rawValue: defaults.string(forKey: sourceKey(provider)) ?? "") ?? .auto
    }

    static var refreshMinutes: Int {
        let value = defaults.integer(forKey: "refreshMinutes")
        return value > 0 ? value : 5
    }

    static var notificationsEnabled: Bool {
        defaults.object(forKey: "notifications") as? Bool ?? true
    }
}

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    /// 웹 로그인/로그아웃 할 때마다 올라가는 값 (설정 화면 갱신용)
    @Published var webLoginVersion = 0

    let web = WebSessionManager()
    private var loopTask: Task<Void, Never>?

    private init() {
        if let saved = SharedStore.load() {
            for snapshot in saved.snapshots { snapshots[snapshot.provider] = snapshot }
            lastRefresh = saved.updatedAt
            UsageCache.shared.set(saved.snapshots, updatedAt: saved.updatedAt)
        }
        Notifier.requestAuthorization()
        startLoop()
    }

    var orderedSnapshots: [ProviderSnapshot] {
        ProviderID.allCases.filter { Prefs.isEnabled($0) }.compactMap { snapshots[$0] }
    }

    /// 주기적 새로고침 (간격을 바꾸면 다시 호출)
    func startLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let minutes = Prefs.refreshMinutes
                try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        for provider in ProviderID.allCases {
            guard Prefs.isEnabled(provider) else {
                snapshots[provider] = nil
                continue
            }
            let snapshot = await ProviderRegistry.fetch(provider, source: Prefs.source(for: provider), web: web)
            // 실패했지만 이전 값이 있으면 이전 값을 유지하고 에러만 붙인다
            if snapshot.windows.isEmpty, var previous = snapshots[provider], !previous.windows.isEmpty,
               Date().timeIntervalSince(previous.fetchedAt) < 6 * 3_600 {
                previous.error = snapshot.error
                snapshots[provider] = previous
            } else {
                snapshots[provider] = snapshot
            }
        }

        lastRefresh = Date()
        let current = orderedSnapshots
        UsageCache.shared.set(current, updatedAt: Date())
        SharedStore.save(SnapshotBundle(snapshots: current, updatedAt: Date()))
        WidgetCenter.shared.reloadAllTimelines()
        Notifier.check(current)
    }

    func startWebLogin(_ provider: ProviderID) {
        guard let service = provider.webService else { return }
        LoginWindowController.show(service) { [weak self] success in
            guard let self else { return }
            self.webLoginVersion += 1
            if success {
                Task { await self.refresh() }
            }
        }
    }

    func webLogout(_ provider: ProviderID) {
        guard let service = provider.webService else { return }
        Task {
            await WebSessionManager.logout(service)
            self.webLoginVersion += 1
            await self.refresh()
        }
    }
}

/// 80% / 95% 를 넘으면 한 번씩 알림
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenterBridge.requestAuthorization()
    }

    static func check(_ snapshots: [ProviderSnapshot]) {
        guard Prefs.notificationsEnabled else { return }
        let key = "notifiedLevels"
        var record = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        if record.count > 300 { record.removeAll() }

        for snapshot in snapshots {
            for window in snapshot.windows {
                let level = [95, 80].first { window.usedPercent >= Double($0) } ?? 0
                guard level > 0 else { continue }
                // 리셋 시각(시간 단위)마다 따로 기록 → 다음 창에서는 다시 알림
                let bucket = Int((window.resetsAt?.timeIntervalSince1970 ?? 0) / 3_600)
                let id = "\(snapshot.provider.rawValue).\(window.id).\(bucket)"
                guard level > (record[id] ?? 0) else { continue }
                record[id] = level
                var body = "\(window.title) 한도를 \(Format.percent(window.usedPercent)) 썼어요."
                if let reset = window.resetsAt { body += " \(Format.resetText(reset))" }
                UNUserNotificationCenterBridge.post(title: "\(snapshot.provider.displayName) 한도 \(level)% 도달", body: body)
            }
        }
        UserDefaults.standard.set(record, forKey: key)
    }
}

/// 터치바 위젯이 메인 스레드 상태를 건드리지 않고 읽을 수 있게 둔 복사본
final class UsageCache {
    static let shared = UsageCache()

    private let lock = NSLock()
    private var storedSnapshots: [ProviderSnapshot] = []
    private var storedUpdatedAt: Date?

    var snapshots: [ProviderSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return storedSnapshots
    }

    var updatedAt: Date? {
        lock.lock()
        defer { lock.unlock() }
        return storedUpdatedAt
    }

    func set(_ snapshots: [ProviderSnapshot], updatedAt: Date) {
        lock.lock()
        defer { lock.unlock() }
        storedSnapshots = snapshots
        storedUpdatedAt = updatedAt
    }
}
