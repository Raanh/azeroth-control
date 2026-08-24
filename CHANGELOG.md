# Changelog

All notable public changes to Azeroth Control are documented here.

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
