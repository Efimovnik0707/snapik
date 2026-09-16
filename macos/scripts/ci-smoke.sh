#!/bin/bash
# CI smoke: runs the built app on the runner's GUI session.
#  1. --smoke-test  : export pipeline, sessions, settings round-trip (exit code matters)
#  2. TCC grants    : on GitHub runners SIP is disabled, so Screen Recording / Accessibility /
#                     Input Monitoring can be pre-granted in the TCC databases (best effort)
#  3. --demo        : synthetic captures, real windows; the app saves its own window images,
#                     the script captures the whole runner desktop while windows are up
#  4. --capture-test: one real ScreenCaptureKit capture (only meaningful if TCC grant worked)
set -uo pipefail
APP="$1"
BIN="$APP/Contents/MacOS/Snapik"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Contents/Info.plist")
OUT="smoke-out"; rm -rf "$OUT"; mkdir -p "$OUT"
DATA="$(mktemp -d)/snapik-data"
RC=0

echo "== SIP =="; csrutil status || true

echo "== 1. --smoke-test =="
"$BIN" --smoke-test --data-dir "$DATA" > "$OUT/smoke-test.log" 2>&1; RC=$?
cat "$OUT/smoke-test.log"; echo "smoke-test exit code: $RC"

echo "== 1b. bundled sounds (G-11) =="
# The three mp3 are checked from inside the app by `UiSoundService.verifyAssets`; what only the
# bundle can answer is that the two camera WAVs they replaced are really gone from it.
for sound in shutter-1-039s.mp3 click-tiny-005s.mp3 notify-soft-040.mp3; do
  if [ -f "$APP/Contents/Resources/$sound" ]; then echo "shipped $sound"; else echo "missing $sound"; RC=1; fi
done
for gone in camera-shutter.wav camera-dial-click.wav; do
  if [ -f "$APP/Contents/Resources/$gone" ]; then echo "still shipped $gone"; RC=1; else echo "gone $gone"; fi
done

echo "== 2. TCC grants (best effort) =="
grant() { # db service client
  local db="$1" svc="$2" cli="$3"
  sudo sqlite3 "$db" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier_type, indirect_object_identifier, flags, last_modified) VALUES ('$svc','$cli',0,2,4,1,0,'UNUSED',0,strftime('%s','now'));" 2>&1 && echo "granted $svc" || echo "grant failed $svc"
}
USER_TCC="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
SYS_TCC="/Library/Application Support/com.apple.TCC/TCC.db"
grant "$USER_TCC" kTCCServiceScreenCapture "$BUNDLE_ID"
grant "$SYS_TCC"  kTCCServiceScreenCapture "$BUNDLE_ID"
grant "$SYS_TCC"  kTCCServiceAccessibility "$BUNDLE_ID"
grant "$SYS_TCC"  kTCCServiceListenEvent   "$BUNDLE_ID"
sudo killall tccd 2>/dev/null || true
sleep 1

echo "== 3. --demo (synthetic captures, real windows) =="
"$BIN" --demo --data-dir "$DATA" --demo-screenshot "$OUT" > "$OUT/demo.log" 2>&1 &
PID=$!
sleep 3;  screencapture -x "$OUT/runner-desktop-1.png" || true
sleep 3;  screencapture -x "$OUT/runner-desktop-2.png" || true
for i in $(seq 1 12); do kill -0 $PID 2>/dev/null || break; sleep 1; done
if kill -0 $PID 2>/dev/null; then echo "demo did not exit in 18s, killing"; kill -9 $PID; fi
wait $PID 2>/dev/null; echo "demo exit code: $?"
ps aux | grep -i "[S]napik" || true
tail -40 "$OUT/demo.log"

echo "== 4. --capture-test (real ScreenCaptureKit capture, needs TCC) =="
perl -e 'alarm shift; exec @ARGV' 40 "$BIN" --capture-test "$OUT/capture-test.png" --data-dir "$DATA" > "$OUT/capture-test.log" 2>&1
echo "capture-test exit code: $? (informational)"
tail -20 "$OUT/capture-test.log" 2>/dev/null || true

ls -la "$OUT"
echo "== sessions on disk =="; find "$DATA" -maxdepth 2 | head -20
cp "$DATA/startup.log" "$OUT/startup.log" 2>/dev/null || true
exit $RC
