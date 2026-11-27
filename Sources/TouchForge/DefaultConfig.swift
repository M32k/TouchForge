import Foundation

/// 처음 실행할 때 만들어지는 기본 설정 (~/Library/Application Support/TouchForge/config.json)
enum DefaultConfig {
    static let json = #"""
{
  "mode": "strip",
  "strip": [
    {"type": "usage"},
    {"type": "battery", "width": 58},
    {"type": "clock", "format": "HH:mm", "width": 50}
  ],
  "passthrough": ["com.apple.FinalCut"],
  "hideControlStrip": true,
  "default": [
    {"type": "button", "symbol": "terminal", "action": {"type": "launch", "app": "com.apple.Terminal"}},
    {"type": "button", "symbol": "safari", "action": {"type": "launch", "app": "com.apple.Safari"}},
    {"type": "image", "image": "sample.gif", "width": 60},
    {"type": "marquee", "text": "TouchForge — config.json 을 저장하면 바로 반영돼요 ✨", "width": 180, "color": "#64D2FF"},
    {"type": "flexibleSpace"},
    {"type": "stock", "ticker": "005930.KS", "name": "삼성전자"},
    {"type": "weather", "latitude": 35.18, "longitude": 129.08},
    {"type": "battery"},
    {"type": "clock", "format": "M/d(E) HH:mm"},
    {"type": "button", "symbol": "speaker.wave.1", "action": {"type": "media", "key": "volumeDown"}, "longAction": {"type": "media", "key": "mute"}},
    {"type": "button", "symbol": "speaker.wave.3", "action": {"type": "media", "key": "volumeUp"}},
    {"type": "close"}
  ],
  "apps": {
    "com.apple.Safari": [
      {"type": "button", "symbol": "chevron.left", "action": {"type": "key", "key": "[", "modifiers": ["cmd"]}},
      {"type": "button", "symbol": "chevron.right", "action": {"type": "key", "key": "]", "modifiers": ["cmd"]}},
      {"type": "button", "symbol": "arrow.clockwise", "action": {"type": "key", "key": "r", "modifiers": ["cmd"]}},
      {"type": "button", "title": "새 탭", "symbol": "plus", "action": {"type": "key", "key": "t", "modifiers": ["cmd"]}},
      {"type": "button", "title": "velog", "bg": "#20C997", "action": {"type": "url", "url": "https://velog.io"}},
      {"type": "flexibleSpace"},
      {"type": "battery"},
      {"type": "clock", "format": "HH:mm"},
      {"type": "button", "symbol": "speaker.wave.1", "action": {"type": "media", "key": "volumeDown"}, "longAction": {"type": "media", "key": "mute"}},
      {"type": "button", "symbol": "speaker.wave.3", "action": {"type": "media", "key": "volumeUp"}},
      {"type": "close"}
    ],
    "com.apple.Music": [
      {"type": "button", "symbol": "backward.fill", "action": {"type": "media", "key": "previous"}},
      {"type": "button", "symbol": "playpause.fill", "action": {"type": "media", "key": "playPause"}},
      {"type": "button", "symbol": "forward.fill", "action": {"type": "media", "key": "next"}},
      {"type": "image", "image": "sample.gif", "width": 60},
      {"type": "shell", "title": "♪", "interval": 3, "width": 360, "command": "osascript -e 'if application \"Music\" is running then' -e 'tell application \"Music\"' -e 'if player state is playing then return (artist of current track) & \" - \" & (name of current track)' -e 'end tell' -e 'end if' -e 'return \"재생 중 아님\"'"},
      {"type": "flexibleSpace"},
      {"type": "button", "symbol": "speaker.wave.1", "action": {"type": "media", "key": "volumeDown"}, "longAction": {"type": "media", "key": "mute"}},
      {"type": "button", "symbol": "speaker.wave.3", "action": {"type": "media", "key": "volumeUp"}},
      {"type": "close"}
    ],
    "com.microsoft.VSCode": [
      {"type": "button", "title": "명령", "symbol": "command", "action": {"type": "key", "key": "p", "modifiers": ["cmd", "shift"]}},
      {"type": "button", "title": "사이드바", "action": {"type": "key", "key": "b", "modifiers": ["cmd"]}},
      {"type": "button", "title": "터미널", "symbol": "terminal", "action": {"type": "key", "key": "`", "modifiers": ["control"]}},
      {"type": "button", "title": "알림 테스트", "bg": "#5E5CE6", "action": {"type": "shell", "command": "osascript -e 'display notification \"터치바 버튼으로 셸 명령을 실행했어요\" with title \"TouchForge\"'"}},
      {"type": "flexibleSpace"},
      {"type": "cpu"},
      {"type": "memory"},
      {"type": "clock", "format": "HH:mm:ss"},
      {"type": "close"}
    ]
  }
}
"""#

    /// 기본 설정에서 쓰는 이퀄라이저 GIF (직접 만든 샘플 애니메이션)
    static var sampleGIF: Data? {
        Data(base64Encoded: sampleGIFBase64, options: .ignoreUnknownCharacters)
    }

    private static let sampleGIFBase64 = """
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
"""
}
