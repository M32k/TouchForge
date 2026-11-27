import Foundation
import UserNotifications

/// 알림 보내기 (서명이 없으면 조용히 실패할 수 있음)
enum UNUserNotificationCenterBridge {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("[TouchForge] 알림 권한 요청 실패: %@", error.localizedDescription) }
        }
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("[TouchForge] 알림 실패: %@", error.localizedDescription) }
        }
    }
}
