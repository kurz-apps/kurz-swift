#!/bin/sh
set -e
cd "$(dirname "$0")/.."
docker exec kurz-cache-1 valkey-cli flushall >/dev/null
docker cp e2e/seed.rb kurz-api:/tmp/seed.rb
docker exec kurz-api bin/rails runner /tmp/seed.rb >/dev/null
DEVICE="${KURZ_E2E_DEVICE:-iPhone 18 Pro}"
xcodebuild test -project Kurz.xcodeproj -scheme Kurz \
  -destination "platform=iOS Simulator,name=$DEVICE,OS=27.0" \
  -derivedDataPath "${TMPDIR:-/tmp}/kurz-dd" "$@"
