# Azeroth Control Native

Qt 6 Quick/QML frontend for Azeroth Control 0.4. It intentionally contains no
Chromium or embedded web runtime. The existing loopback-only Python service and
managed AzerothCore scripts remain the source of truth during migration.

The native preview mirrors the classic dashboard: realm start/restart/stop,
CPU/memory/bot telemetry, bot population, XP/drop/spawn rates, queue options,
Party Builder (build, summon and recovery), addon folder access, maintenance
and backups, server logs, and the create-server installer with progress.
On SteamOS the native executable reads Steam's virtual XInput device directly:
D-pad/left stick navigates, A confirms, and B returns to the dashboard. It does
not depend on a per-shortcut Steam keyboard layout.

The SteamOS preview uses X11 through Gamescope and disables Steam's overlay
injection for the control process only. This avoids the Electron/Chromium
startup freeze while leaving the WoW shortcut and Proton Experimental setup
unchanged.

The native application intentionally does not launch WoW. Users add their own
`Wow.exe` or `Wow-HD.exe` non-Steam shortcut, select Proton Experimental, start
the desired realm in Azeroth Control, and launch the game separately through
Steam. This keeps Gamescope focus and lifecycle ownership unambiguous.

This directory is an active preview. Expect unfinished screens and SteamOS,
gamepad, focus, and installer bugs while the migration is being completed.

Build with Qt 6:

```sh
qmake6 AzerothControl.pro
make -j"$(nproc)"
```
