#!/bin/zsh
# Builds, installs and runs the repro (example/ModalRaceRepro.csproj) on a connected Android device or emulator, prints the result of each run
# and optionally saves a screenshot and the log line per run. Run it from the repository root.
#
#   ./run.sh                          builds, installs, runs with 0 ms and 1000 ms between Push and Pop
#   ./run.sh 0 50 150 400 1000        runs with the given delays (ms) between PushModalAsync and PopModalAsync
#   ./run.sh --skip-build 0           does not build/install again
#   ./run.sh --save results/<dir> 0 1000   saves delay-<ms>ms.png and delay-<ms>ms-log.txt per run into <dir>
#   ./run.sh --maui-version 10.0.20 0      builds with another Microsoft.Maui.Controls version than the one in the csproj
#
# Environment (optional):
#   ADB       path to adb (default: adb from PATH, otherwise ~/Library/Android/sdk/platform-tools/adb)
#   DEVICE    adb serial (default: the only connected device)
#   WAIT_S    how long to wait for the result of one run, default 30
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

SKIP_BUILD=0; SAVE=""; MAUI_VERSION=""; DELAYS=()
while (( $# )); do
  case "$1" in
    --skip-build) SKIP_BUILD=1 ;;
    --save) shift; SAVE="$1" ;;
    --maui-version) shift; MAUI_VERSION="$1" ;;
    *) DELAYS+=("$1") ;;
  esac
  shift
done
(( ${#DELAYS[@]} )) || DELAYS=(0 1000)
[[ -z "$SAVE" || "$SAVE" = /* ]] || SAVE="$ROOT/$SAVE"   # --save is relative to the repository root

ADB="${ADB:-$(command -v adb || echo "$HOME/Library/Android/sdk/platform-tools/adb")}"
DEVICE="${DEVICE:-$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')}"
[[ -n "$DEVICE" ]] || { echo "no Android device connected"; exit 1; }
PKG=com.companyname.modalracerepro
adb() { "$ADB" -s "$DEVICE" "$@"; }

if (( ! SKIP_BUILD )); then
  BUILD_ARGS=(-f net10.0-android -t:Install -p:AndroidAttachDebugger=false "-p:AdbTarget=-s $DEVICE" --nologo -v:q)
  [[ -n "$MAUI_VERSION" ]] && BUILD_ARGS+=("-p:MauiVersion=$MAUI_VERSION")
  dotnet build example/ModalRaceRepro.csproj "${BUILD_ARGS[@]}"
fi

ACTIVITY="$(adb shell cmd package resolve-activity --brief "$PKG" | tail -1 | tr -d '\r')"
[[ -n "$SAVE" ]] && mkdir -p "$SAVE"

for d in "${DELAYS[@]}"; do
  adb shell input keyevent KEYCODE_WAKEUP
  adb shell am force-stop "$PKG"
  adb logcat -c
  adb shell am start -n "$ACTIVITY" --ei delay_ms "$d" > /dev/null
  LINE=""
  for i in $(seq 1 "${WAIT_S:-30}"); do
    LINE="$(adb logcat -d | grep -F '[REPRO]' | tail -1 | sed 's/^.*\[REPRO\]/[REPRO]/' || true)"
    [[ -n "$LINE" ]] && break
    sleep 1
  done
  sleep 1
  WINDOWS="$(adb shell dumpsys window windows | grep -cE "Window #[0-9]+ Window.*$PKG" || true)"
  echo "${LINE:-[REPRO] no result within ${WAIT_S:-30} s}  (app windows: $WINDOWS)"
  if [[ -n "$SAVE" ]]; then
    adb exec-out screencap -p > "$SAVE/delay-${d}ms.png"
    { echo "$LINE"; echo "app windows (dumpsys window): $WINDOWS"; } > "$SAVE/delay-${d}ms-log.txt"
  fi
done
