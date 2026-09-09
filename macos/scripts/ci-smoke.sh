#!/bin/bash
# CI smoke: launches the built app in headless-ish mode on the runner's GUI session,
# runs the built-in --smoke-test, captures runner screenshots of the real windows.
set -uo pipefail
APP="$1"
BIN="$APP/Contents/MacOS/SnapBrief"
OUT="smoke-out"; rm -rf "$OUT"; mkdir -p "$OUT"
DATA="$(mktemp -d)/snapbrief-data"
echo "== TCC status =="
csrutil status || true
echo "== 1. --smoke-test (export pipeline, sessions, settings round-trip) =="
"$BIN" --smoke-test --data-dir "$DATA" > "$OUT/smoke-test.log" 2>&1
RC=$?
cat "$OUT/smoke-test.log"
echo "smoke-test exit code: $RC"
echo "== 2. --demo (synthetic captures, real windows) =="
"$BIN" --demo --data-dir "$DATA" --demo-screenshot "$OUT" > "$OUT/demo.log" 2>&1 &
PID=$!
sleep 6
screencapture -x "$OUT/runner-desktop-1.png" || true
sleep 2
screencapture -x "$OUT/runner-desktop-2.png" || true
kill $PID 2>/dev/null; wait $PID 2>/dev/null
cat "$OUT/demo.log" | tail -40
ls -la "$OUT"
echo "== sessions on disk =="
find "$DATA" -maxdepth 3 | head -30
exit $RC
