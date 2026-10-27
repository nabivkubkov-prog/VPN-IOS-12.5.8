#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then echo "Native iOS libraries must be built on macOS with Xcode." >&2; exit 1; fi
command -v go >/dev/null || { echo "Install Go 1.22.12 from go.dev/dl." >&2; exit 1; }
case "$(go env GOVERSION)" in go1.22.*) ;; *) echo "Use Go 1.22.x for this legacy build; do not upgrade the toolchain automatically." >&2; exit 1 ;; esac
xcrun --sdk iphoneos --find clang >/dev/null
HEV="$ROOT/Vendor/hev-socks5-tunnel"
EXPECTED_HEV=55cc2efc280f3a72ffc60ce856772b57f5122e9c
[[ -d "$HEV/src/core/include" && -d "$HEV/third-part/lwip/src" ]] || { echo "Vendor sources incomplete. See README.md." >&2; exit 1; }
if [[ -d "$HEV/.git" || -f "$HEV/.git" ]]; then
  [[ "$(git -C "$HEV" rev-parse HEAD)" == "$EXPECTED_HEV" ]] || { echo "Unexpected HEV revision." >&2; exit 1; }
fi
GOTOOLCHAIN=local go run "$ROOT/Scripts/restore-vendor-links.go" "$HEV"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC="$(xcrun --sdk iphoneos --find clang)"
AR="$(xcrun --sdk iphoneos --find ar)"
FLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=12.5 -O2"
mkdir -p "$ROOT/Native/lib" "$ROOT/Native/include"
export GOTOOLCHAIN=local
export GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC
export CGO_CFLAGS="$FLAGS" CGO_LDFLAGS="$FLAGS -framework Security -framework CoreFoundation -lresolv"
(cd "$ROOT/Core"; go build -trimpath -buildmode=c-archive -ldflags='-s -w' -o "$ROOT/Native/lib/libIncyXray.a" .)
cp "$ROOT/Native/lib/libIncyXray.h" "$ROOT/Native/include/libIncyXray.h"
# Upstream build-apple.sh targets iOS 15; build its static target explicitly for 12.5.
make -C "$HEV" clean
make -C "$HEV" -j2 PP="$CC -E" CC="$CC" AR="$AR" CFLAGS="$FLAGS" static
xcrun libtool -static -o "$ROOT/Native/lib/libHevTunnel.a" \
  "$HEV/bin/libhev-socks5-tunnel.a" \
  "$HEV/third-part/lwip/bin/liblwip.a" \
  "$HEV/third-part/yaml/bin/libyaml.a" \
  "$HEV/third-part/hev-task-system/bin/libhev-task-system.a"
xcrun lipo -info "$ROOT/Native/lib/libIncyXray.a"
xcrun lipo -info "$ROOT/Native/lib/libHevTunnel.a"
echo "Native arm64 libraries ready. Open INCY.xcodeproj."

