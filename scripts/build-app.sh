#!/bin/bash
# TouchForge.app 빌드 스크립트
#
#   ./scripts/build-app.sh                       # 지금 Mac 의 아키텍처로 빌드
#   ARCHS="x86_64" ./scripts/build-app.sh        # 인텔용만
#   ARCHS="x86_64 arm64" ./scripts/build-app.sh  # 유니버설 (Xcode 필요)
#
# 결과: build/TouchForge.app
set -euo pipefail

cd "$(dirname "$0")/.."

ARCH_FLAGS=()
for arch in ${ARCHS:-}; do
    ARCH_FLAGS+=(--arch "$arch")
done

echo "▶︎ swift build -c release ${ARCH_FLAGS[*]:-}"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="build/TouchForge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TouchForge" "$APP/Contents/MacOS/TouchForge"
cp Support/Info.plist "$APP/Contents/Info.plist"

# 임시(ad-hoc) 서명. 개발자 인증서가 있으면 SIGN_IDENTITY 로 지정 가능
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"

echo "✅ 빌드 완료: $APP"
lipo -info "$APP/Contents/MacOS/TouchForge" || true
