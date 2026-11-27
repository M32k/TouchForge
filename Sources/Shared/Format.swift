import Foundation
import SwiftUI

enum Format {
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// 사용률에 따른 색 (초록 → 주황 → 빨강)
    static func color(for used: Double) -> Color {
        if used >= 90 { return .red }
        if used >= 70 { return .orange }
        return .green
    }

    static func resetText(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "곧 리셋" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)일 \(hours)시간 후 리셋" }
        if hours > 0 { return "\(hours)시간 \(minutes)분 후 리셋" }
        return "\(max(minutes, 1))분 후 리셋"
    }

    /// 창 길이(초) → "5시간", "주간" ...
    static func windowTitle(seconds: Double) -> String {
        windowTitle(minutes: Int((seconds / 60).rounded()))
    }

    static func windowTitle(minutes: Int) -> String {
        switch minutes {
        case 300: return "5시간"
        case 10_080: return "주간"
        case 1_440: return "일일"
        default:
            if minutes > 0, minutes % 1_440 == 0 { return "\(minutes / 1_440)일" }
            if minutes > 0, minutes % 60 == 0 { return "\(minutes / 60)시간" }
            return "\(minutes)분"
        }
    }
}
