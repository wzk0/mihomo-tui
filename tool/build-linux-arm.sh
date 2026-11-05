#!/usr/bin/env bash
# Builds the linux-armv7 binary inside an armv7 Debian container (qemu-user).
# The Dart SDK ships a 32 bit ARM SDK, but no ARM host is available on GitHub
# hosted runners, so the AOT compiler itself is executed under emulation.
set -euo pipefail

DART_VERSION="${DART_VERSION:-3.13.7}"
ASSET_NAME="${ASSET_NAME:-mihomo-tui-dev-linux-armv7}"

echo "==> installing prerequisites"
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  curl unzip ca-certificates git >/dev/null

echo "==> downloading Dart SDK ${DART_VERSION} (linux-arm)"
curl -fsSL -o /tmp/dart-sdk.zip \
  "https://storage.googleapis.com/dart-archive/channels/stable/release/${DART_VERSION}/sdk/dartsdk-linux-arm-release.zip"
unzip -q /tmp/dart-sdk.zip -d /opt
rm -f /tmp/dart-sdk.zip
export PATH="/opt/dart-sdk/bin:${PATH}"
dart --version

echo "==> resolving dependencies"
dart pub get

echo "==> compiling"
mkdir -p dist
dart compile exe bin/mihomo_tui.dart -o dist/mihomo-tui
tar -czf "dist/${ASSET_NAME}.tar.gz" -C dist mihomo-tui
rm -f dist/mihomo-tui
ls -la dist