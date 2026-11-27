import Foundation
import SwiftUI

/// 지원하는 서비스
enum ProviderID: String, Codable, CaseIterable, Identifiable, Hashable {
    case claude
    case codex
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "ChatGPT · Codex"
        case .gemini: return "Gemini CLI"
        }
    }

    /// 메뉴바에 붙는 한 글자
    var shortName: String {
        switch self {
        case .claude: return "C"
        case .codex: return "X"
        case .gemini: return "G"
        }
    }

    var color: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: return Color(red: 0.06, green: 0.64, blue: 0.50)
        case .gemini: return Color(red: 0.26, green: 0.52, blue: 0.96)
        }
    }
}

/// 한도를 어디서 읽어오는지
enum SourceKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case auto
    case cliAccount
    case webLogin
    case localFiles

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "자동"
        case .cliAccount: return "CLI 계정"
        case .webLogin: return "웹 로그인"
        case .localFiles: return "로컬 기록"
        }
    }
}

/// 한도 창 하나 (예: 5시간, 주간, 주간·Opus)
struct UsageWindow: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    /// 0 ~ 100
    var usedPercent: Double
    var resetsAt: Date?
    var windowMinutes: Int?

    var remainingPercent: Double { max(0, 100 - usedPercent) }
}

/// 서비스 하나의 최신 상태
struct ProviderSnapshot: Codable, Identifiable, Hashable {
    var provider: ProviderID
    var windows: [UsageWindow]
    var plan: String?
    var account: String?
    var source: SourceKind
    var fetchedAt: Date
    var error: String?

    var id: String { provider.rawValue }
    /// 가장 먼저 보여줄 창 (보통 5시간)
    var primary: UsageWindow? { windows.first }
    var highestUsed: Double? { windows.map(\.usedPercent).max() }
}

/// 위젯과 공유하는 묶음
struct SnapshotBundle: Codable {
    var snapshots: [ProviderSnapshot]
    var updatedAt: Date

    static var sample: SnapshotBundle {
        let now = Date()
        return SnapshotBundle(
            snapshots: [
                ProviderSnapshot(
                    provider: .claude,
                    windows: [
                        UsageWindow(id: "five_hour", title: "5시간", usedPercent: 42, resetsAt: now.addingTimeInterval(7_800)),
                        UsageWindow(id: "seven_day", title: "주간", usedPercent: 18, resetsAt: now.addingTimeInterval(300_000)),
                    ],
                    plan: "Max", account: nil, source: .cliAccount, fetchedAt: now, error: nil
                ),
                ProviderSnapshot(
                    provider: .codex,
                    windows: [
                        UsageWindow(id: "primary_window", title: "5시간", usedPercent: 73, resetsAt: now.addingTimeInterval(3_600)),
                        UsageWindow(id: "secondary_window", title: "주간", usedPercent: 31, resetsAt: now.addingTimeInterval(400_000)),
                    ],
                    plan: "Plus", account: nil, source: .cliAccount, fetchedAt: now, error: nil
                ),
                ProviderSnapshot(
                    provider: .gemini,
                    windows: [
                        UsageWindow(id: "gemini-2.5-pro", title: "Gemini 2.5 Pro", usedPercent: 12, resetsAt: now.addingTimeInterval(50_000)),
                    ],
                    plan: "Standard", account: nil, source: .cliAccount, fetchedAt: now, error: nil
                ),
            ],
            updatedAt: now
        )
    }
}
