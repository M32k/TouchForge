# TouchForge

인텔 맥북 프로의 **터치바를 시스템 전체에서 내 마음대로** 바꾸는 macOS 메뉴바 앱.
어떤 앱을 쓰든 내가 만든 터치바가 뜨고, 앞에 있는 앱에 따라 구성이 자동으로 바뀝니다.

- **커스텀 버튼**: 앱 실행, 단축키 입력, 셸 명령, URL 열기, AppleScript, 볼륨/밝기/재생 키
- **정보 위젯**: 시계, 배터리, CPU, 메모리, 날씨(open-meteo), 주식(야후 파이낸스), 셸 명령 결과
- **이미지·애니메이션**: PNG/JPG, 움직이는 GIF, 흐르는 글자(전광판)
- **앱별 프리셋**: 번들 ID 마다 다른 터치바, 앱을 바꾸면 자동 전환
- **AI 구독 한도**: Claude · ChatGPT(Codex) · Gemini CLI 의 5시간/주간 한도 % 를 터치바, 메뉴바, 바탕화면 위젯에서 확인
- `config.json` 을 저장하는 순간 바로 반영 (재시작 필요 없음)

## 두 가지 모드

| 모드 | 동작 |
|---|---|
| `"strip"` (기본) | **애플 기본 터치바를 그대로 유지**. 각 앱의 기본 버튼과 오른쪽 컨트롤 스트립은 그대로 있고, 컨트롤 스트립에 내 위젯(`strip`)과 TouchForge 아이콘만 추가돼요. 아이콘을 누르면 전체 커스텀 터치바(앱별 프리셋)가 열리고, « 를 누르거나 다른 앱으로 넘어가면 애플 터치바로 돌아가요. |
| `"full"` | 항상 TouchForge 터치바로 덮어요. `passthrough` 에 적은 앱(번들 ID)에서만 애플 터치바가 나와요. |

컨트롤 스트립은 자리가 좁아서 `strip` 아이템은 2~3개, 각각 `width` 50~70 정도가 알맞아요.

> ⚠️ 시스템 전체 터치바는 Apple **비공개 API**(DFRFoundation)를 씁니다. MTMR, Pock 과 같은 방식이라
> 앱스토어 배포는 안 되고, macOS 업데이트로 막힐 수 있어요.

## 요구 사항

- 터치바가 있는 MacBook Pro (인텔 2016~2020) — 터치바가 없는 Mac 에서도 구독 한도(메뉴바·위젯)는 동작
- macOS 14 Sonoma 이상 (Tahoe 26 대상으로 작성)
- 빌드하려면 Xcode 와 XcodeGen (`brew install xcodegen`)

## 설치

### 방법 1: 맥북에서 직접 빌드 (추천)

```bash
brew install xcodegen
git clone https://github.com/M32k/TouchForge.git
cd TouchForge
bash scripts/build-app.sh
mv build/TouchForge.app /Applications/
open /Applications/TouchForge.app
```

바탕화면 위젯 목록에 TouchForge 가 안 보이면 `xcodegen generate` 후 `TouchForge.xcodeproj` 를 Xcode 로 열고,
두 타깃(TouchForge, TouchForgeWidget)의 Signing & Capabilities 에서 Team 을 내 Apple ID(Personal Team)로 고른 뒤 ▶︎ 실행하세요.

### 방법 2: GitHub Actions 빌드 받기

저장소의 **Actions → Build → 최신 실행 → Artifacts → TouchForge** 에서 zip 을 받아 풉니다.
서명되지 않은 앱이라 처음 한 번은 격리 속성을 지워야 열려요.

```bash
xattr -cr ~/Downloads/TouchForge.app
mv ~/Downloads/TouchForge.app /Applications/
open /Applications/TouchForge.app
```

### 처음 실행 후 할 일

1. **손쉬운 사용 권한**: 단축키 버튼(예: ⌘T)을 누르면 권한을 물어봅니다.
   시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 에서 TouchForge 를 켜 주세요.
   (다시 빌드하면 서명이 바뀌어서 권한을 껐다 켜야 할 수 있어요.)
2. **터치바 설정**: 시스템 설정 → 키보드 → 터치바 설정 → "터치바에 표시"를 **앱 제어**로 두세요.
3. 메뉴바 아이콘 **오른쪽 클릭** → **로그인 시 자동 실행** 을 켜면 부팅할 때마다 자동으로 뜹니다.
4. **구독 한도**: Claude Code 를 쓰면 처음에 "TouchForge 가 키체인의 Claude Code-credentials 를 사용하려고 합니다" 가 떠요. **항상 허용** 을 눌러 주세요.

## 구독 한도 (Claude · Codex · Gemini)

서비스마다 맞는 방법으로 연결해서 구독 한도 % 를 5분마다 읽어요. "자동" 으로 두면 아래 순서대로 시도해요.

| 서비스 | 연결 방법 | 보이는 한도 |
|---|---|---|
| **Claude** (Pro/Max) | ① CLI 계정 — Claude Code 로그인 정보 (키체인)<br>② 웹 로그인 — 앱 안에서 claude.ai 공식 로그인 | 5시간, 주간, 모델별 주간 |
| **ChatGPT · Codex** (Plus/Pro) | ① CLI 계정 — `~/.codex/auth.json`<br>② 웹 로그인 — chatgpt.com 공식 로그인<br>③ 로컬 기록 — `~/.codex/sessions` | 5시간, 주간 |
| **Gemini CLI** | ① CLI 계정 — `~/.gemini/oauth_creds.json` | 모델별 일일 한도 |

보는 곳:

- **터치바**: 컨트롤 스트립의 `usage` 위젯에 `C42 X73 G12` (70%↑ 주황, 90%↑ 빨강). 누르면 서비스별 5시간·주간 % 와 리셋까지 남은 시간이 터치바에 펼쳐져요.
- **메뉴바**: 아이콘 옆에 `C 42%  X 73%`, 왼쪽 클릭하면 서비스별 카드가 있는 팝오버.
- **바탕화면 위젯**: 바탕화면 우클릭 → 위젯 편집 → TouchForge (작게·중간·크게).
- **알림**: 80% · 95% 를 넘으면 알려줘요.

비밀번호는 TouchForge 가 받지 않아요. 웹 로그인은 공식 로그인 페이지를 그대로 띄우고, 로그인 쿠키는 macOS WebKit 저장소에만 남아요.
한도 값은 `~/Library/Application Support/TouchForge/usage.json` 에 저장돼요 (바탕화면 위젯이 읽는 파일).

> ⚠️ 세 서비스 모두 사용량 API 가 **비공개** 라 사이트가 바뀌면 깨질 수 있어요.
> Claude 는 2026년 2월 약관에서 구독 OAuth 토큰을 Claude.ai·Claude Code 전용으로 정했어요. TouchForge 는 사용량을 읽기만 하지만 공식 허용 방식은 아니에요.
> Gemini CLI 는 Google 이 2026-06-18 부터 개인·AI Pro·Ultra 계정 로그인을 끝내서 Workspace·Standard 계정만 한도가 나와요.

## 사용법

메뉴바 아이콘을 **왼쪽 클릭** 하면 구독 한도 팝오버, **오른쪽 클릭** 하면 TouchForge 메뉴가 열려요.

| 메뉴 | 설명 |
|---|---|
| 터치바에 구독 한도 펼치기 | 터치바에 서비스별 한도 상세 표시 |
| 구독 한도 새로고침 / 설정… | 서비스 켜고 끄기, 연결 방법, 웹 로그인, 새로고침 간격, 메뉴바 표시, 알림 |

| 메뉴 | 설명 |
|---|---|
| 터치바 보이기 / 접기 | 접으면 원래 시스템 터치바, 컨트롤 스트립의 TouchForge 아이콘으로 다시 열기 |
| 설정 다시 불러오기 (⌘R) | 강제로 다시 읽기 (보통은 저장만 해도 자동 반영) |
| 설정 파일 열기 (⌘,) | `~/Library/Application Support/TouchForge/config.json` |
| 번들 ID 복사 | 방금 쓰던 앱의 번들 ID 를 복사 → 앱별 프리셋 만들 때 사용 |
| 기본 설정으로 초기화 | 지금 설정은 `config.backup.json` 으로 보관 |

설정에 오류가 있으면 터치바에 **빨간 글씨로 어디가 틀렸는지** 표시됩니다.

## 설정 파일

```json
{
  "mode": "strip",
  "strip": [ { "type": "usage", "fontSize": 13 }, { "type": "battery", "width": 58 }, { "type": "clock", "format": "HH:mm", "width": 50 } ],
  "passthrough": [ "com.apple.FinalCut" ],
  "hideControlStrip": true,
  "default": [ 아이템, 아이템, ... ],
  "apps": {
    "com.apple.Safari": [ 아이템, ... ],
    "com.apple.Music":  [ { "type": "defaults" }, 아이템 ]
  }
}
```

- `mode`: `"strip"`(애플 터치바 유지) 또는 `"full"`(항상 덮기)
- `strip`: strip 모드에서 컨트롤 스트립에 붙일 작은 아이템
- `passthrough`: full 모드에서 애플 터치바를 그대로 보여줄 앱의 번들 ID 목록
- `hideControlStrip`: `true` 면 오른쪽 시스템 영역까지 덮고 터치바 전체를 씀 (볼륨 버튼 등을 직접 넣어야 함)
- `default`: 프리셋이 없는 앱에서 쓰는 기본 구성
- `apps`: 번들 ID 별 구성. 안에 `{ "type": "defaults" }` 를 넣으면 그 자리에 기본 아이템들이 들어감
- 이미지 경로는 `~/...`, 절대경로, 또는 설정 폴더 기준 상대경로 (`sample.gif`)

전체 예시는 [`examples/config.json`](examples/config.json) 을 보세요. (처음 실행 때 만들어지는 기본 설정과 같아요.)

### 공통 옵션

| 키 | 설명 | 예 |
|---|---|---|
| `title` | 글자 (위젯에서는 앞에 붙는 접두어) | `"새 탭"` |
| `symbol` | SF Symbol 이름 | `"safari"` |
| `image` | 버튼 아이콘 이미지 경로 | `"~/icons/a.png"` |
| `width` | 폭(pt). 터치바 전체 폭은 약 1000pt | `120` |
| `bg` | 배경색 | `"#20C997"` |
| `color` | 글자/아이콘 색 | `"#FFD60A"` |
| `fontSize` | 글자 크기 (기본 15) | `13` |
| `bordered` | 버튼 테두리(키 모양) 표시 | `false` |
| `action` | 탭했을 때 동작 | 아래 참고 |
| `longAction` | 길게 눌렀을 때 동작 (버튼만) | |
| `interval` | 위젯 갱신 주기(초) | `60` |

### 아이템 종류 (`type`)

| type | 설명 | 전용 옵션 |
|---|---|---|
| `button` | 버튼 | |
| `label` | 테두리 없는 글자 | |
| `escape` | esc 키 버튼 | |
| `close` | 우리 터치바를 접고 시스템 터치바 보이기 | |
| `clock` | 시계 | `format` (기본 `"HH:mm"`, 예 `"M/d(E) HH:mm"`) |
| `battery` | 배터리 % (20% 이하 빨강) | |
| `cpu` | CPU 사용률 | |
| `memory` | 메모리 사용량 | |
| `weather` | 현재 날씨·기온 | `latitude`, `longitude` |
| `stock` | 주가·등락률 (상승 빨강/하락 파랑) | `ticker` (`"005930.KS"`, `"AAPL"`), `name` |
| `shell` | 셸 명령 결과 첫 줄 | `command` |
| `usage` | 구독 한도 % (`C42 X73 G12`, 70%↑ 주황·90%↑ 빨강, 누르면 터치바에 상세) | `providers` (예: `["claude", "codex"]`) |
| `image` / `gif` | 이미지·움직이는 GIF | `image` |
| `marquee` | 흐르는 글자 | `text`, `speed` (초당 pt, 기본 40) |
| `space` | 빈칸 | `width` |
| `flexibleSpace` | 남는 공간 채우기 | |
| `smallSpace` / `largeSpace` | 시스템 기본 간격 | |
| `defaults` | (앱 프리셋 안에서) 기본 아이템 펼치기 | |

### 동작 종류 (`action.type`)

| type | 예 |
|---|---|
| `launch` | `{ "type": "launch", "app": "com.apple.Terminal" }` (번들 ID 또는 `.app` 경로) |
| `key` | `{ "type": "key", "key": "t", "modifiers": ["cmd", "shift"] }` |
| `media` | `{ "type": "media", "key": "volumeUp" }` |
| `shell` | `{ "type": "shell", "command": "open ~/Downloads" }` |
| `url` | `{ "type": "url", "url": "https://velog.io" }` |
| `applescript` | `{ "type": "applescript", "source": "tell application \"Music\" to playpause" }` |
| `minimize` | 우리 터치바 접기 |
| `usage` | 터치바에 구독 한도 상세 펼치기 |
| `usageRefresh` | 구독 한도 지금 새로고침 |

- `key` 이름: `a`~`z`, `0`~`9`, `esc`, `return`, `tab`, `space`, `delete`, `left`/`right`/`up`/`down`, `f1`~`f12`, `[`, `]`, `` ` `` 등. 목록에 없으면 `"keyCode": 53` 처럼 가상 키코드 직접 지정
- `modifiers`: `cmd`, `shift`, `option`, `control`, `fn`
- `media` 키: `volumeUp`, `volumeDown`, `mute`, `brightnessUp`, `brightnessDown`, `playPause`, `next`, `previous`, `illuminationUp`, `illuminationDown`

## 문제 해결

- **터치바가 안 바뀜**: 메뉴바 아이콘 → 터치바 보이기. 그래도 안 되면 앱 종료 후 다시 실행
- **터치바가 까맣게 됨 (Tahoe)**: macOS 26 자체 버그로 보고된 증상이 있어요. 재시동하면 대부분 돌아옵니다
- **단축키 버튼이 안 먹힘**: 손쉬운 사용 권한 확인 (다시 빌드했다면 목록에서 지웠다가 다시 추가)
- **음악 위젯이 비어 있음**: 처음 한 번 "TouchForge 가 음악을 제어하려고 합니다" 허용 필요
- 로그 보기: `log stream --predicate 'eventMessage CONTAINS "[TouchForge]"'`

## 구조

```
project.yml                  XcodeGen 설정 (앱 + 위젯 확장)
Sources/TouchForge/          터치바 앱 — 메뉴바, 프리셋, 비공개 API, 버튼·위젯
Sources/Usage/               구독 한도 — Claude·Codex·Gemini 연결, 웹 로그인, 팝오버·설정 화면
Sources/Shared/              앱·위젯 공용 모델과 저장소
Sources/Widget/              바탕화면 위젯 (WidgetKit)
Support/Info.plist           앱 Info.plist
scripts/build-app.sh         빌드 스크립트
```
