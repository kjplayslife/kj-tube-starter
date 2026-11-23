#!/bin/zsh
# Build, test and run KJ Tube in the iOS Simulator on this Mac.
#   scripts/sim.sh test   -> build + run all unit tests
#   scripts/sim.sh run    -> build, boot the simulator, install, launch, screenshot
#   scripts/sim.sh all    -> test, then run
set -euo pipefail

cd "$(dirname "$0")/.."
DEVICE="${DEVICE:-iPhone 17}"
DERIVED="build/DerivedData"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/KJTube.app"
BUNDLE_ID="com.example.kjtube"
# With two Xcode versions' simulators installed there can be two "iPhone 17"s: take the newest iOS.
DEST="platform=iOS Simulator,name=$DEVICE,OS=${OS:-latest}"
PROJ=(-project KJTube/KJTube.xcodeproj -scheme KJTube -destination "$DEST" -derivedDataPath "$DERIVED")

if [[ ! -f KJTube/Secrets.xcconfig ]]; then
  echo "Missing KJTube/Secrets.xcconfig. Copy KJTube/Secrets.example.xcconfig and add the API key." >&2
  exit 1
fi

do_test() {
  mkdir -p build
  echo "Testing on $DEVICE (log: build/test.log)..."
  # The tip jar purchase tests run apart from the rest, with a time limit. Run together under
  # Xcode 27 they sometimes stall forever and take every other test down with them: Xcode's test
  # store doesn't start from the command line (FB22237318), so the first of them asks Apple's
  # real servers instead and now and then never gets an answer.
  # Built once up front, so the time limit below covers only the tests themselves.
  if ! xcodebuild build-for-testing "${PROJ[@]}" > build/test.log 2>&1; then
    echo "TESTS FAILED (the build):"
    grep -E "error:" build/test.log | head -40
    exit 1
  fi
  if ! xcodebuild test-without-building "${PROJ[@]}" -skip-testing:KJTubeTests/TipJarStoreKitTests >> build/test.log 2>&1; then
    echo "TESTS FAILED:"
    grep -E "' failed on|error:" build/test.log | head -40
    exit 1
  fi
  local passed="$(grep -c "' passed on" build/test.log)"

  xcodebuild test-without-building "${PROJ[@]}" -only-testing:KJTubeTests/TipJarStoreKitTests > build/test-store.log 2>&1 &
  local store=$!
  local waited=0
  while kill -0 $store 2>/dev/null && (( waited < ${STORE_TEST_LIMIT:-180} )); do
    sleep 5
    (( waited += 5 ))
  done
  if kill -0 $store 2>/dev/null; then
    kill $store 2>/dev/null
    echo "TESTS PASSED: $passed passed, 0 failed"
    echo "NOTE: the tip jar purchase tests stalled and were stopped after ${waited}s (log: build/test-store.log)."
    echo "They only run for real from Xcode (FB22237318), so this says nothing about the app."
  elif wait $store; then
    echo "TESTS PASSED: $passed passed, 0 failed (plus the tip jar purchase tests, run apart)"
  else
    echo "TESTS FAILED (tip jar purchase tests, log: build/test-store.log):"
    grep -E "' failed on|error:" build/test-store.log | head -40
    exit 1
  fi
}

do_run() {
  mkdir -p build
  echo "Building..."
  xcodebuild build "${PROJ[@]}" > build/build.log 2>&1 || { grep -E "error:" build/build.log | head -40; exit 1; }
  xcrun simctl boot "$DEVICE" 2>/dev/null || true
  # No "open -a Simulator": the phone runs without its window, so nothing pops up on the Mac (D172).
  xcrun simctl bootstatus "$DEVICE" -b > /dev/null
  xcrun simctl install "$DEVICE" "$APP"
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID"
  sleep 3
  xcrun simctl io "$DEVICE" screenshot build/sim.png > /dev/null 2>&1
  echo "Running. Screenshot: build/sim.png"
}

case "${1:-all}" in
  test) do_test ;;
  run) do_run ;;
  all) do_test; do_run ;;
  *) echo "usage: scripts/sim.sh [test|run|all]" >&2; exit 2 ;;
esac
