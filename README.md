# Azeroth Control

**A gamepad-friendly Steam Deck and SteamOS installer and control center for a local AzerothCore WotLK 3.3.5a server with Playerbots.**

Azeroth Control is built for people searching for an easier way to run an
AzerothCore Playerbots server on a Steam Deck, Steam Machine, living-room Linux
PC, or other x86-64 SteamOS device. It replaces most configuration-file work
with a large-screen interface designed for a controller, keyboard, mouse, and
4K TV.

> [!IMPORTANT]
> Azeroth Control does **not** contain, download, sell, or provide World of
> Warcraft. You must supply your own separate WoW Wrath of the Lich King 3.3.5a
> client (build 12340). Blizzard executables, game data, accounts, credentials,
> models, textures, and MPQ files are not included in this repository or its
> releases.

Azeroth Control is an independent community project. It is not affiliated with
or endorsed by Blizzard Entertainment, Valve, AzerothCore, or the upstream
module authors.

## What version 0.1 can do

### Guided SteamOS installation

- Detects CPU threads, memory, free disk space, and required local tools.
- Estimates download size, installed size, and build time before installation.
- Installs from the open-source AzerothCore Playerbots provider.
- Offers Progressive 1–80, Instant Level 80, and Custom server profiles.
- Recommends a bot population from the device hardware and supports up to 2,000
  configured bots.
- Lets the user select server modules with descriptions, license information,
  dependencies, and conflicts.
- Validates a user-supplied WoW 3.3.5a client and safely configures its local
  realmlist.
- Creates the first game account, optionally with administrator permissions,
  and removes the account password from saved installation records afterward.
- Builds the server, authentication service, databases, maps, and client data
  as rootless Podman containers.
- Shows installation stages, elapsed/estimated time, CPU use, memory use, and a
  collapsible technical log.
- Checkpoints long build stages so an interrupted installation can resume.
- Creates a server-bound WoW launcher and can add it to Steam.
- Can stop the local server automatically when WoW exits.
- Detects, imports, and controls compatible existing installations without
  moving their files.
- Supports multiple separately managed local server installations.

### Dashboard and realm control

- Start, stop, and restart the active local server.
- Launch the configured WoW or WoW-HD client through Steam.
- Automatically start the server before launching the game.
- View realm state, uptime, ports, online bot count, CPU, memory, and recent
  worldserver logs.
- Remove a server from the dashboard or delete only installations created by
  Azeroth Control. A WoW client is never deleted.
- Create and restore full database plus server-configuration backups.

### Bot, queue, and world settings

- Change the Playerbots population from the UI.
- Control level-bracket distribution, dynamic player-level tracking, faction
  synchronization, and real-player weighting.
- Enable or disable built-in Playerbots LFG and battleground participation.
- Configure automatic battleground joining and dungeon/BG deserter penalties.
- Change XP, item drop, and creature respawn rates.
- Enable and tune AoE looting when the matching server module is installed.
- Back up configuration files automatically before supported values change.

### Client addon library and controller setup

- Install or remove verified upstream releases of ConsolePortLK and Questie-X.
- Verify addon downloads with SHA-256 before extraction.
- Move replaced or removed addon folders into a recoverable local backup.
- Detect the active WoW Steam shortcut.
- Open Steam Input for that exact shortcut and show the recommended
  ConsolePortLK community-layout instructions.

### TV and controller interface

- Directional gamepad navigation across the installer and dashboard.
- `A` selects, `B` goes back, shoulder buttons switch dashboard sections, and
  `Start` launches WoW from the dashboard.
- `X` opens the Steam on-screen keyboard only when a text field is focused.
- Automatic 4K/TV UI scaling plus manual 100–200% scale controls.
- Steam Gaming Mode exit handling and safe return to the control center.

## Available server modules

Version 0.1 exposes this curated installer catalog. Modules are downloaded from
their original repositories and retain their original licenses.

| Module | Default | Purpose |
| --- | --- | --- |
| [Playerbots](https://github.com/mod-playerbots/mod-playerbots) | Required | Autonomous characters for questing, grouping, raids, and PvP |
| [Dungeon Clear](https://github.com/jrad7/mod-dungeon-clear) | Yes | Improved dungeon movement, pulls, and recovery |
| [AoE Loot](https://github.com/azerothcore/mod-aoe-loot) | Yes | Loot nearby defeated creatures together |
| [Transmogrification](https://github.com/azerothcore/mod-transmog) | Yes | Change item appearance without changing stats |
| [Learn Spells](https://github.com/azerothcore/mod-learn-spells) | Yes | Teach appropriate class spells while leveling |
| [Auction House Bot](https://github.com/azerothcore/mod-ah-bot) | Yes | Populate the auction house with supply and demand |
| [Multibot Bridge](https://github.com/Wishmaster117/mod-multibot-bridge) | Yes | Server bridge for compatible multibot addons |
| [AutoBalance](https://github.com/azerothcore/mod-autobalance) | Optional | Scale instances to group size and strength |
| [Individual XP](https://github.com/azerothcore/mod-individual-xp) | Optional | Per-player experience multipliers |
| [SoloCraft](https://github.com/azerothcore/mod-solocraft) | Optional | Solo or undersized-group stat scaling; conflicts with AutoBalance |

Upstream projects can change independently. A catalog entry is not a promise
that every future upstream commit will remain compatible with this preview.

## Requirements

Version 0.1 is primarily developed and tested for **x86-64 SteamOS 3.x** on a
Steam Deck or Steam Machine. Other x86-64 Linux distributions are experimental.

You should have:

- A separate, complete WoW WotLK 3.3.5a client (build 12340) containing
  `Wow.exe` and a `Data` directory. `Wow-HD.exe` is used when present.
- Proton Experimental installed from the Steam library.
- Steam and an internet connection for the first build and upstream downloads.
- Git, Python 3, Podman, and Distrobox available on the host. The v0.1 system
  check reports missing tools but does not install them automatically.
- At least 16 GB RAM. More memory allows a larger bot population.
- At least 60 GB free before starting. The final installation is usually
  smaller, but container compilation needs temporary working space.
- Patience for the first build: approximately 35–100 minutes depending on CPU,
  storage, internet speed, selected modules, and upstream build state. High CPU
  utilization during compilation is expected.

## Steam Deck / SteamOS quick start

1. Open the [Releases](https://github.com/raanh/azeroth-control/releases) page
   and download both:
   - `Azeroth-Control-0.1.0-x86_64.AppImage`
   - `Azeroth-Control-SteamOS.sh`
2. In Desktop Mode, create `~/Applications` and move both downloaded files into
   it.
3. In Dolphin, open each file's **Properties → Permissions** and enable
   **Is executable**.
4. Open Steam in Desktop Mode and select **Games → Add a Non-Steam Game →
   Browse**. Add `Azeroth-Control-SteamOS.sh`, then rename the library entry to
   `Azeroth Control`.
5. Do not force a Proton compatibility tool for Azeroth Control itself; it is a
   native Linux application. Proton Experimental is used later for WoW.
6. Return to Gaming Mode, launch Azeroth Control, and choose **Install a new
   server**.

The small SteamOS launcher only prepares a clean environment for the native
AppImage. This avoids Steam overlay variables crashing Electron in Gaming Mode
and lets Steam close the application cleanly. It does not install a background
service or require administrator access.

## First installation guide

1. **System Check** — confirm all required tools are green and review free disk
   space and the default writable installation location.
2. **Server Profile** — name the server, select Progressive 1–80, Instant 80, or
   Custom, and choose a bot population. Start with the recommended value.
3. **Modules** — keep the defaults for the simplest first test. AutoBalance and
   SoloCraft should not be enabled together.
4. **Game Client** — select your own WoW 3.3.5a folder and create the first local
   account. The client remains in its original location. Existing `Config.wtf`
   is backed up before the realmlist is changed to `127.0.0.1`.
5. **Review** — confirm disk, estimated time, server behavior, and whether a WoW
   Steam entry should be created.
6. **Install** — leave the device powered and connected. The CPU may remain near
   100% during the container build. If installation stops, fix the displayed
   problem and select the same resumable installation from the welcome screen.
7. When complete, open the dashboard and choose **Launch WoW-HD**. The server is
   started first if needed.

## ConsolePortLK with Steam Input

After installing ConsolePortLK from **Addons**:

1. Name the WoW Steam entry `World of Warcraft: WotLK`.
2. Select **Open Steam Input** in Azeroth Control.
3. Open Community Layouts and enable **Show All Layouts**.
4. Apply `Gamepad leoaviana ConsolePortLK` by Prrg.

This native Steam Input route avoids WoWpadX, a Windows runtime, and shared
Proton-prefix configuration. These steps follow the upstream
[ConsolePortLK SteamOS instructions](https://github.com/leoaviana/ConsolePortLK#3-steam-game-controller-layout).

## Important v0.1 limitations

- This is the first public preview, not a zero-maintenance appliance.
- Missing host prerequisites are detected but not installed automatically.
- The first server build is long and may be affected by upstream repository
  changes.
- The Party Builder currently saves a local UI preset only. It does not yet
  create, summon, gear, or specialize reserve bots.
- LFG and battleground controls currently use the built-in Playerbots queue
  behavior. Exact instant role filling is not implemented yet.
- Controller community layouts are selected by the user in Steam; Azeroth
  Control does not change Steam account or controller-cloud data.
- There is no automatic application/core/module updater or rollback manager in
  v0.1.
- SteamOS and Proton updates can change non-Steam-game behavior.

## Roadmap

Planned work includes:

- An in-game, controller-friendly **Azeroth Quick Control** addon.
- Fast class/role selection, bot summoning, removal, and stuck-party recovery.
- Group-wide strategies for combat, buffs, grinding, following, questing, and
  regeneration.
- Dungeon Clear controls for pull pacing, tank-led navigation, recovery, and
  autoplay-style assistance using capabilities already exposed by AzerothCore
  and mod-playerbots.
- Automatic bot level, gear, spell, talent, and role preparation.
- On-demand LFG and battleground reserve bots with exact tank/healer/DPS roles.
- Better raid and PvP orchestration.
- One-click SteamOS prerequisite setup.
- Core/module compatibility checks, updates, backups, and rollback.
- More client addons and more server/expansion providers where legally and
  technically practical.

Roadmap items are intentions, not guarantees. WoW clients and proprietary game
data will never be distributed by this project.

## Privacy and safety

- The control service listens only on `127.0.0.1`.
- Azeroth Control has no telemetry, analytics, cloud account, or remote admin
  panel.
- Server actions and editable configuration keys use allow-lists.
- Installer work is checkpointed and resumable.
- Existing client and configuration files are backed up before supported
  changes.
- Destructive server deletion is restricted to registered, app-managed server
  roots. Imported servers can only be forgotten, not deleted by the app.
- Game-account passwords are cleared from installer selection records after
  account creation.

By default, mutable server data is stored below
`~/.local/share/azeroth-control`. The immutable SteamOS system partition is not
used for server data.

## Development

```bash
npm install
npm run build
npm run desktop
npm run appimage
```

The interface is React/Vite, the desktop shell is Electron, and the local
allow-listed control service is Python. Server builds and runtime services use
rootless Podman. See [the architecture notes](docs/ARCHITECTURE.md).

Issues and focused pull requests are welcome. When reporting an installation
problem, include the failed stage and relevant technical-log lines, but remove
local paths, account names, and other personal information first.

## Credits and license

Vibecoded with Codex 5.6 Sol with love. ❤️

Azeroth Control is available under the [MIT License](LICENSE). Downloaded
third-party projects retain their original copyrights and licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
