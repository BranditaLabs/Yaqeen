#!/usr/bin/env bash
# Release smoke test (CI `mobile-smoke`): installs the release APK on a booted emulator, launches it and
# waits for the app's first Flutter frame (`YQ-BOOT first-frame`, logged by lib/app/bootstrap.dart).
# Always prints the relevant logcat so a hang or crash shows its cause in the job log.
#   bash apps/mobile/tool/smoke_android.sh path/to/app-release.apk [screenshot.png]
set -u
APK=$1
SHOT=${2:-smoke.png}
PKG=com.yaqinbrand.yaqeen

adb wait-for-device
adb shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 1; done'
adb install -r -g "$APK" || exit 1
adb logcat -c
adb shell am start -W -n "$PKG/.MainActivity"

ok=0
for _ in $(seq 1 90); do
  if adb logcat -d -s flutter:I | grep -q 'YQ-BOOT first-frame'; then ok=1; break; fi
  sleep 1
done
# Let the Flutter splash play into its next screen before the screenshot.
sleep 8
adb exec-out screencap -p > "$SHOT"

echo '----- logcat: flutter, AndroidRuntime, errors -----'
adb logcat -d -v brief flutter:V AndroidRuntime:V 'YQ-BOOT:V' '*:E' | grep -v 'chatty' | tail -n 400
echo '----- end logcat -----'

if adb logcat -d | grep -q 'FATAL EXCEPTION'; then echo '::error::native crash (see logcat above)'; ok=0; fi
if ! adb shell pidof "$PKG" >/dev/null; then echo '::error::app process is not running'; ok=0; fi
if [ "$ok" != 1 ]; then echo '::error::no first Flutter frame within 90 s — the app is stuck on the native splash'; exit 1; fi
echo 'smoke: first frame drawn, app alive'
