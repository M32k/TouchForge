#!/bin/bash
# TouchForge.app 빌드 (메뉴바 앱 + 바탕화면 위젯)
#
#   bash scripts/build-app.sh                        # 지금 Mac 의 아키텍처로 빌드
#   ARCHS="x86_64" bash scripts/build-app.sh         # 인텔용만
#   ARCHS="x86_64 arm64" bash scripts/build-app.sh   # 유니버설
#
# 필요: Xcode, XcodeGen (brew install xcodegen)
# 결과: build/TouchForge.app
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null; then
    echo "XcodeGen 이 필요해요: brew install xcodegen" >&2
    exit 1
fi

xcodegen generate
mkdir -p build

EXTRA=()
if [ -n "${ARCHS:-}" ]; then
    EXTRA+=(ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO)
fi

set -o pipefail
xcodebuild -project TouchForge.xcodeproj -scheme TouchForge -configuration Release \
    -derivedDataPath build/DerivedData ${EXTRA[@]+"${EXTRA[@]}"} -quiet build 2>&1 | tee build/build.log

rm -rf build/TouchForge.app
cp -R build/DerivedData/Build/Products/Release/TouchForge.app build/

echo "✅ 빌드 완료: build/TouchForge.app"
lipo -archs build/TouchForge.app/Contents/MacOS/TouchForge || true
