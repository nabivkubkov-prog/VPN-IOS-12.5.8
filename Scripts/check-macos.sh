#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
INCY_CONFIG_OUTPUT="$ROOT/build/swift-fixtures" swift test
(cd Core; INCY_CONFIG_INPUT="$ROOT/build/swift-fixtures" go test ./engine -count=1)
bash Scripts/check-packet-bridge.sh
bash Scripts/build-core.sh
for plist in Config/*.plist Config/*.entitlements; do plutil -lint "$plist"; done
xcodebuild -project INCY.xcodeproj -scheme INCY -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
echo "Unsigned device build verified. Sign both targets to install on iPhone."

