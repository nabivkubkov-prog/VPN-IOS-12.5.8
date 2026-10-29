#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HEV="$ROOT/Vendor/hev-socks5-tunnel"
go run "$ROOT/Scripts/restore-vendor-links.go" "$HEV"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
CC="$(xcrun --sdk macosx --find clang)"
AR="$(xcrun --sdk macosx --find ar)"
FLAGS="-isysroot $SDK -O2"
mkdir -p "$ROOT/build/native-tests"
make -C "$HEV" clean
make -C "$HEV" -j2 PP="$CC -E" CC="$CC" AR="$AR" CFLAGS="$FLAGS" static
xcrun libtool -static -o "$ROOT/build/native-tests/libHevHost.a" \
  "$HEV/bin/libhev-socks5-tunnel.a" \
  "$HEV/third-part/lwip/bin/liblwip.a" \
  "$HEV/third-part/yaml/bin/libyaml.a" \
  "$HEV/third-part/hev-task-system/bin/libhev-task-system.a"
"$CC" -dynamiclib -isysroot "$SDK" -O2 \
  -I"$HEV/src" -I"$HEV/src/misc" -I"$HEV/src/core/include" \
  -I"$HEV/third-part/lwip/src/include" -I"$HEV/third-part/lwip/src/ports/include" \
  -I"$HEV/third-part/hev-task-system/include" \
  "$ROOT/Native/PacketBridge.c" "$ROOT/Native/HevBridge.c" "$ROOT/Native/HevDiagnostics.c" \
  "$ROOT/build/native-tests/libHevHost.a" -lpthread \
  -o "$ROOT/build/native-tests/libIncyBridgeTests.dylib"
python3 "$ROOT/Tests/Native/PacketBridgeIntegration.py" "$ROOT/build/native-tests/libIncyBridgeTests.dylib"
