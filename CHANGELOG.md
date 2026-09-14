# Changelog

All notable public changes to Azeroth Control are documented here.

## [0.4.0-preview.15] - 2026-09-14

### Fixed

- Keep each managed MySQL database private to its Podman network, eliminating
  the unnecessary host-port-3307 conflict during CoA installation and resume.
- Refresh managed control scripts before an interrupted installation resumes.

## [0.4.0-preview.14] - 2026-09-14

### Fixed

- Accept and prefer `Ascension.exe` for CoA native-v4 clients throughout
  installation, maintenance checks, Steam shortcut discovery, and fallback
  launching.

## [0.4.0-preview.13] - 2026-09-14

### Fixed

- Bundle the QtQml WorkerScript runtime required by Qt Quick on SteamOS.
- Reject AppImage builds that report missing QML modules or fail a packaged
  X11 startup smoke test.

## [0.4.0-preview.12] - 2026-09-14

### Added

- Experimental Conquest of Azeroth provider pinned to a reviewed upstream
  revision and requiring a user-supplied native-v4 Ascension client.
- Verified CoA world-database bootstrap before first worldserver startup.
- Optional pinned AutoBalance module for solo dungeons and raids.
- Provider capability handling that removes Playerbots, queues and Party
  Builder controls from CoA installations.
- Native Qt AppImage release workflow for x86-64 SteamOS.

### Changed

- XP, item-drop and spawn-rate controls now apply to CoA; XP updates kill,
  quest and exploration rates together and supports a 5× value.
- CoA's built-in creature level scaling is disabled while AutoBalance is active
  to avoid stacking two independent scaling systems.

## [0.1.0] - 2026-08-24

First public SteamOS preview.

### Added

- Gamepad-friendly Steam Deck and Steam Machine first-run installer.
- Hardware, dependency, disk-space, download-size, and build-time checks.
- Resumable AzerothCore Playerbots source, module, container, database, client
  data, account, and launcher installation.
- Progressive 1–80, Instant Level 80, and Custom profiles.
- Curated Playerbots, Dungeon Clear, AoE Loot, Transmog, Learn Spells, Auction
  House Bot, Multibot Bridge, AutoBalance, Individual XP, and SoloCraft catalog.
- Dashboard start, stop, restart, WoW launch, status, resource, and log controls.
- Bot population, level-distribution, queue, deserter, XP, drop, respawn, and
  AoE loot settings.
- Full database and server-configuration backup and restore.
- Multi-installation discovery, import, selection, removal, and safe managed
  deletion.
- ConsolePortLK and Questie-X client-addon installer with checksums and backups.
- Steam Input setup assistant for the ConsolePortLK community layout.
- 4K-aware UI scaling, Steam keyboard support, and controller navigation.
- SteamOS Gaming Mode launcher.

### Known limitations

- Host prerequisites are detected but are not installed automatically.
- The initial source/container build is CPU-intensive and can take 35–100
  minutes.
- Party Builder and exact on-demand queue reserve bots are UI/roadmap features,
  not complete server integrations in this release.
- Automatic core/module/application updates and rollback are not available.
