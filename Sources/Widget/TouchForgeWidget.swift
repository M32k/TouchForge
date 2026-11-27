import WidgetKit
import SwiftUI

struct LimitEntry: TimelineEntry {
    let date: Date
    let bundle: SnapshotBundle?
}

struct LimitTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> LimitEntry {
        LimitEntry(date: Date(), bundle: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (LimitEntry) -> Void) {
        let bundle = context.isPreview ? (SharedStore.load() ?? .sample) : SharedStore.load()
        completion(LimitEntry(date: Date(), bundle: bundle))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LimitEntry>) -> Void) {
        // 메뉴바 앱이 새로고침할 때마다 위젯을 다시 그리라고 알려준다. 그 사이엔 15분마다 파일을 다시 읽음.
        let entry = LimitEntry(date: Date(), bundle: SharedStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

@main
struct TouchForgeWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageLimitWidget()
    }
}

struct UsageLimitWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TouchForgeUsageWidget", provider: LimitTimelineProvider()) { entry in
            LimitWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("구독 한도")
        .description("Claude · Codex · Gemini 의 5시간/주간 사용률")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct LimitWidgetView: View {
    let entry: LimitEntry
    @Environment(\.widgetFamily) private var family

    /// 연결된(값을 읽어 온) 서비스만 남긴 묶음
    private var connected: SnapshotBundle? {
        guard var bundle = entry.bundle else { return nil }
        bundle.snapshots = bundle.snapshots.filter { !$0.windows.isEmpty }
        return bundle.snapshots.isEmpty ? nil : bundle
    }

    var body: some View {
        if let bundle = connected {
            switch family {
            case .systemSmall:
                SmallLimitView(bundle: bundle)
            default:
                ListLimitView(bundle: bundle, detailed: family == .systemLarge)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.title2)
                Text(entry.bundle == nil ? "TouchForge 를 실행해 주세요" : "연결된 서비스가 없어요")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// 작은 위젯: 서비스별 5시간 % 크게
struct SmallLimitView: View {
    let bundle: SnapshotBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(bundle.snapshots.prefix(3)) { snapshot in
                HStack(spacing: 6) {
                    Circle()
                        .fill(snapshot.provider.color)
                        .frame(width: 7, height: 7)
                    Text(snapshot.provider.shortName == "X" ? "Codex" : snapshot.provider.displayName)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if let primary = snapshot.primary {
                        Text(Format.percent(primary.usedPercent))
                            .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                            .foregroundStyle(Format.color(for: primary.usedPercent))
                    } else {
                        Text("—")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Text(bundle.updatedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// 중간·큰 위젯: 서비스별로 창마다 막대
struct ListLimitView: View {
    let bundle: SnapshotBundle
    let detailed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: detailed ? 12 : 8) {
            ForEach(bundle.snapshots) { snapshot in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(snapshot.provider.color)
                            .frame(width: 7, height: 7)
                        Text(snapshot.provider.displayName)
                            .font(.caption.weight(.semibold))
                        if let plan = snapshot.plan {
                            Text(plan)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if snapshot.windows.isEmpty {
                        Text("연결 안 됨 — 메뉴바에서 확인")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else {
                        ForEach(snapshot.windows.prefix(detailed ? 4 : 2)) { window in
                            WidgetBarRow(window: window)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct WidgetBarRow: View {
    let window: UsageWindow

    var body: some View {
        HStack(spacing: 6) {
            Text(window.title)
                .font(.caption2)
                .frame(width: 64, alignment: .leading)
                .lineLimit(1)
            ProgressView(value: min(max(window.usedPercent, 0), 100), total: 100)
                .tint(Format.color(for: window.usedPercent))
            Text(Format.percent(window.usedPercent))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .frame(width: 34, alignment: .trailing)
            if let reset = window.resetsAt, reset > Date() {
                Text(reset, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
                    .lineLimit(1)
            }
        }
    }
}
