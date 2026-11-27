import SwiftUI
import AppKit

/// 메뉴바 아이콘을 누르면 뜨는 팝오버: 구독 한도 카드 + TouchForge 바로가기
struct UsageMenuView: View {
    @EnvironmentObject private var state: UsageStore

    /// AppDelegate 가 넘겨주는 동작들
    var onShowTouchBar: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onOpenMoreMenu: () -> Void = {}
    var onQuit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("구독 한도")
                    .font(.headline)
                Spacer()
                if state.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task { await state.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(state.isRefreshing)
                .help("지금 새로고침")
            }

            if state.orderedSnapshots.isEmpty {
                Text(state.isRefreshing ? "불러오는 중…" : "켜진 서비스가 없어요. 한도 설정에서 켜 주세요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(state.orderedSnapshots) { snapshot in
                ProviderCard(snapshot: snapshot)
            }

            if let last = state.lastRefresh {
                Text("업데이트 \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 6) {
                Button("터치바 열기", action: onShowTouchBar)
                Button("한도 설정…", action: onOpenSettings)
                Spacer()
                Button {
                    onOpenMoreMenu()
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
                .help("TouchForge 메뉴 (오른쪽 클릭과 같아요)")
                Button("종료", action: onQuit)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 340)
    }
}

struct ProviderCard: View {
    let snapshot: ProviderSnapshot
    @EnvironmentObject private var state: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(snapshot.provider.color)
                    .frame(width: 8, height: 8)
                Text(snapshot.provider.displayName)
                    .font(.subheadline.weight(.semibold))
                if let plan = snapshot.plan {
                    Text(plan)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                Spacer()
                Text(snapshot.provider.sourceLabel(snapshot.source))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ForEach(snapshot.windows) { window in
                WindowRow(window: window)
            }

            if let error = snapshot.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(snapshot.windows.isEmpty ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if snapshot.windows.isEmpty, snapshot.provider.webService != nil {
                    Button("웹으로 로그인…") {
                        state.startWebLogin(snapshot.provider)
                    }
                    .controlSize(.small)
                }
            }

            if snapshot.source == .localFiles, !snapshot.windows.isEmpty {
                Text("마지막 사용 기록 기준 (\(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct WindowRow: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.title)
                    .font(.caption)
                Spacer()
                Text(Format.percent(window.usedPercent))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Format.color(for: window.usedPercent))
            }
            ProgressView(value: min(max(window.usedPercent, 0), 100), total: 100)
                .tint(Format.color(for: window.usedPercent))
            if let reset = window.resetsAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Format.resetText(reset, now: context.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
