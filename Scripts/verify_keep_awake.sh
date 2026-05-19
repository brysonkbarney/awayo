#!/usr/bin/env bash
set -euo pipefail

reason="Awayo Keep Awake Verification"
tmpdir="$(mktemp -d)"
swift_file="$tmpdir/verify_keep_awake.swift"
log_file="$tmpdir/assertions.log"

cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

cat > "$swift_file" <<'SWIFT'
import Foundation
import IOKit.pwr_mgt

var systemAssertion: IOPMAssertionID = 0
var displayAssertion: IOPMAssertionID = 0
let reason = "Awayo Keep Awake Verification" as CFString

let systemResult = IOPMAssertionCreateWithName(
    kIOPMAssertionTypeNoIdleSleep as CFString,
    IOPMAssertionLevel(kIOPMAssertionLevelOn),
    reason,
    &systemAssertion
)

let displayResult = IOPMAssertionCreateWithName(
    kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
    IOPMAssertionLevel(kIOPMAssertionLevelOn),
    reason,
    &displayAssertion
)

guard systemResult == kIOReturnSuccess, displayResult == kIOReturnSuccess else {
    FileHandle.standardError.write(Data("Could not create IOPM assertions: system=\(systemResult) display=\(displayResult)\n".utf8))
    exit(1)
}

print("Awayo verification assertions are active")
fflush(stdout)

Thread.sleep(forTimeInterval: 8)

IOPMAssertionRelease(displayAssertion)
IOPMAssertionRelease(systemAssertion)
SWIFT

swift "$swift_file" >/dev/null &
swift_pid="$!"

sleep 2
pmset -g assertions > "$log_file"

if grep -q "$reason" "$log_file"; then
  echo "Keep-awake verification passed: macOS reports active Awayo sleep/display assertions."
else
  echo "Keep-awake verification failed: macOS did not report the expected assertion." >&2
  sed -n '1,220p' "$log_file" >&2
  kill "$swift_pid" >/dev/null 2>&1 || true
  wait "$swift_pid" 2>/dev/null || true
  exit 1
fi

wait "$swift_pid"
