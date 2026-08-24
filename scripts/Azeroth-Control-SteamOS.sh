#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$HOME/.local/state/azeroth-control"
mkdir -p "$LOG_DIR"

APPIMAGE="${AZEROTH_CONTROL_APPIMAGE:-}"
if [[ -z "$APPIMAGE" ]]; then
    shopt -s nullglob
    candidates=(
        "$SCRIPT_DIR"/Azeroth-Control-*-x86_64.AppImage
        "$HOME/Applications"/Azeroth-Control-*-x86_64.AppImage
    )
    shopt -u nullglob
    if (( ${#candidates[@]} )); then
        APPIMAGE="${candidates[${#candidates[@]} - 1]}"
    fi
fi

if [[ -z "$APPIMAGE" || ! -f "$APPIMAGE" ]]; then
    printf 'Azeroth Control AppImage was not found. Keep this launcher beside Azeroth-Control-*-x86_64.AppImage in ~/Applications.\n' >&2
    exit 2
fi

# Steam's overlay environment can crash Electron zygote processes on SteamOS.
unset LD_PRELOAD
unset LD_LIBRARY_PATH
unset QT_IM_MODULE
unset XMODIFIERS
export GTK_IM_MODULE=simple
export ELECTRON_DISABLE_SANDBOX=1
export AZEROTH_FULLSCREEN=1

chmod u+x "$APPIMAGE"
setsid "$APPIMAGE" --no-sandbox --disable-gpu-sandbox --disable-features=UseChromeOSDirectVideoDecoder >>"$LOG_DIR/appimage.log" 2>&1 &
APP_PID="$!"

shutdown() {
    trap - TERM INT HUP
    kill -TERM -- "-$APP_PID" >/dev/null 2>&1 || true
    for _ in $(seq 1 15); do
        kill -0 "$APP_PID" >/dev/null 2>&1 || { wait "$APP_PID" 2>/dev/null || true; exit 0; }
        sleep 0.1
    done
    kill -KILL -- "-$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" 2>/dev/null || true
    exit 0
}
trap shutdown TERM INT HUP

set +e
wait "$APP_PID"
STATUS="$?"
set -e
exit "$STATUS"
