import SwiftUI

struct UsageSettingsView: View {
    @EnvironmentObject private var state: UsageStore
    @AppStorage("refreshMinutes") private var refreshMinutes = 5
    @AppStorage("menuBarStyle") private var menuBarStyle = "all"
    @AppStorage("notifications") private var notifications = true

    var body: some View {
        Form {
            ForEach(ProviderID.allCases) { provider in
                ProviderSettingsSection(provider: provider)
            }

            Section("일반") {
                Picker("새로고침 간격", selection: $refreshMinutes) {
                    ForEach([1, 2, 5, 10, 15, 30], id: \.self) { minutes in
                        Text("\(minutes)분").tag(minutes)
                    }
                }
                Picker("메뉴바 표시", selection: $menuBarStyle) {
                    Text("서비스별 % (C·X·G)").tag("all")
                    Text("가장 높은 %만").tag("max")
                    Text("아이콘만").tag("icon")
                }
                Toggle("80% · 95% 넘으면 알림", isOn: $notifications)
            }

            Section {
                Text("C = Claude, X = ChatGPT·Codex, G = Gemini CLI. 표시되는 %는 5시간(또는 첫 번째) 한도의 사용률이에요. 터치바에는 config.json 의 usage 위젯으로 나와요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 560)
        .onChange(of: refreshMinutes) { _, _ in
            state.startLoop()
        }
    }
}

struct ProviderSettingsSection: View {
    let provider: ProviderID
    @EnvironmentObject private var state: UsageStore
    @AppStorage private var enabled: Bool
    @AppStorage private var source: String
    @State private var webLoggedIn = false

    init(provider: ProviderID) {
        self.provider = provider
        _enabled = AppStorage(wrappedValue: true, Prefs.enabledKey(provider))
        _source = AppStorage(wrappedValue: SourceKind.auto.rawValue, Prefs.sourceKey(provider))
    }

    var body: some View {
        Section(provider.displayName) {
            Toggle("사용", isOn: $enabled)

            if enabled {
                Picker("연결 방법", selection: $source) {
                    ForEach(provider.supportedSources) { kind in
                        Text(provider.sourceLabel(kind)).tag(kind.rawValue)
                    }
                }
                Text(provider.sourceHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if provider.webService != nil {
                    HStack {
                        Label(
                            webLoggedIn ? "웹 로그인 연결됨" : "웹 로그인 안 됨",
                            systemImage: webLoggedIn ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(webLoggedIn ? Color.green : Color.secondary)
                        Spacer()
                        if webLoggedIn {
                            Button("로그아웃") { state.webLogout(provider) }
                        } else {
                            Button("웹 로그인…") { state.startWebLogin(provider) }
                        }
                    }
                }

                if let snapshot = state.snapshots[provider] {
                    if snapshot.windows.isEmpty, let error = snapshot.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if !snapshot.windows.isEmpty {
                        Text("지금 쓰는 방법: \(provider.sourceLabel(snapshot.source))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: state.webLoginVersion) {
            await refreshLoginState()
        }
        .onChange(of: enabled) { _, _ in
            Task { await state.refresh() }
        }
        .onChange(of: source) { _, _ in
            Task { await state.refresh() }
        }
    }

    private func refreshLoginState() async {
        guard let service = provider.webService else { return }
        webLoggedIn = await WebSessionManager.isLoggedIn(service)
    }
}
