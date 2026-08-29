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

> [!WARNING]
> The `main` branch is currently the **0.4 native preview**. The interface is
> being migrated from Electron/Chromium to Qt 6 Quick for much faster startup,
> lower overhead, and more predictable SteamOS Gaming Mode behavior. It is
> usable for testing, but unfinished flows and bugs are expected. The latest
> packaged stable snapshot remains [v0.2.0](https://github.com/Raanh/azeroth-control/releases/tag/v0.2.0).

## What the 0.4 native preview can do

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
- Creates the first game account and removes its password from saved
  installation records afterward.
- Builds the server, authentication service, databases, maps, and client data
  as rootless Podman containers.
- Shows installation stages, elapsed/estimated time, CPU use, memory use, and a
  collapsible technical log.
- Checkpoints long build stages so an interrupted installation can resume.
- Detects, imports, and controls compatible existing installations without
  moving their files.
- Supports multiple separately managed local server installations.

### Dashboard and realm control

- Start, stop, and restart the active local server.
- View realm state, uptime, ports, online bot count, CPU, memory, and recent
  worldserver logs.
- Remove a server from the dashboard or delete only installations created by
  Azeroth Control. A WoW client is never deleted.
- Create and restore full database plus server-configuration backups.
- Detect bundled server-component updates and install them with an automatic
  full backup, isolated worldserver rebuild, health check, and image/source
  rollback if activation fails.
- Repair managed scripts, permissions, runtime folders, container images, and
  server health without changing databases or WoW files.

### Bot, queue, and world settings

- Change the Playerbots population from the UI.
- Control level-bracket distribution, dynamic player-level tracking, faction
  synchronization, and real-player weighting.
- Enable or disable built-in Playerbots LFG and battleground participation.
- Instantly prepares a level-matched tank/healer/DPS bot party when a solo
  player joins Dungeon Finder, then lets the normal LFG role check and proposal
  flow continue.
- Configure automatic battleground joining and dungeon/BG deserter penalties.
- Change XP, item drop, and creature respawn rates.
- Enable and tune AoE looting when the matching server module is installed.
- Back up configuration files automatically before supported values change.

### Client addon library and controller setup

- Install or remove verified upstream releases of ConsolePortLK, Questie-X and
  RefinedBlizzPlates.
- Verify addon downloads with SHA-256 before extraction.
- Move replaced or removed addon folders into a recoverable local backup.
- Install the bundled **Azeroth Dungeon Guide**, a large controller-friendly
  Dynamic/Fast/Careful/Manual run selector shown when entering a dungeon.
- Detect a user-created WoW Steam shortcut when opening its Steam Input setup.
- Install the optional **Azeroth FFXIV Crossbar** preset, including:
  - a controller-friendly triple crossbar for ConsolePortLK;
  - L2, R2, and L2+R2 skill banks;
  - L1 targeting and L1+D-pad camera zoom;
  - map, interact, jump, back, and utility-ring face-button bindings;
  - local Steam Input templates for Steam Deck, Xbox, PlayStation, Switch Pro,
    and generic controllers.
- Back up the full client `WTF` folder before applying the crossbar preset.
- Open Steam Input for the exact WoW shortcut so the user can confirm the
  local layout without Azeroth Control changing Steam Cloud controller data.

### TV and controller interface

- Directional gamepad navigation across the installer and dashboard.
- `A` selects, `B` goes back, and shoulder buttons switch dashboard sections.
- `X` opens the Steam on-screen keyboard only when a text field is focused.
- Automatic 4K/TV UI scaling plus manual 100–200% scale controls.
- Steam Gaming Mode exit handling and safe return to the control center.

## Available server modules

The native preview exposes this curated installer catalog. Modules are downloaded from
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

The native preview is primarily developed and tested for **x86-64 SteamOS 3.x** on a
Steam Deck or Steam Machine. Other x86-64 Linux distributions are experimental.

You should have:

- A separate, complete WoW WotLK 3.3.5a client (build 12340) containing
  `Wow.exe` and a `Data` directory. `Wow-HD.exe` is used when present.
- A user-created non-Steam shortcut for that WoW executable. Azeroth Control
  deliberately does not add or launch the game.
- Proton Experimental installed from the Steam library.
- Steam and an internet connection for the first build and upstream downloads.
- Git, Python 3, Podman, and Distrobox available on the host. The v0.2 system
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
   - `Azeroth-Control-0.2.0-x86_64.AppImage`
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
6. Still in Desktop Mode, add your own `Wow.exe` or `Wow-HD.exe` as a separate
   non-Steam game. Open its **Properties → Compatibility**, enable **Force the
   use of a specific Steam Play compatibility tool**, and choose **Proton
   Experimental**.
7. Return to Gaming Mode, launch Azeroth Control, and choose **Install a new
   server**.

The small SteamOS launcher only prepares a clean environment for the native
AppImage. This prevents Steam overlay variables from disrupting Qt's X11
startup in Gaming Mode and lets Steam close the application cleanly. It does
not install a background service or require administrator access.

## First installation guide

1. **System Check** — confirm all required tools are green and review free disk
   space and the default writable installation location.
2. **Server Profile** — name the server, select Progressive 1–80, Instant 80, or
   Custom, and choose a bot population. Start with the recommended value.
3. **Modules** — keep the defaults for the simplest first test. AutoBalance and
   SoloCraft should not be enabled together.
4. **Game Client** — select your own WoW 3.3.5a folder and create the first local
   account. The account name is remembered by the client, but the password is
   entered manually when WoW is launched separately. The client remains in its
   original location. Existing `Config.wtf` is backed up before the realmlist
   is changed to `127.0.0.1`.
5. **Review** — confirm disk, estimated time, and server behavior. Azeroth
   Control does not create or modify a WoW Steam library entry.
6. **Install** — leave the device powered and connected. The CPU may remain near
   100% during the container build. If installation stops, fix the displayed
   problem and select the same resumable installation from the welcome screen.
7. When complete, open the dashboard and start the desired realm. Then switch
   to Steam and launch the WoW shortcut you created yourself.

## Party Builder

Party Builder creates a complete five-player group around an online character.
Choose one tank, one healer and two DPS class/spec combinations, then select
**Build & Summon Party**. Azeroth Control will:

1. reserve four free, same-faction random PlayerBots;
2. replace an existing bot-only party and add the selected bots;
3. match every bot to the leader's current level;
4. initialize class skills, spellbooks, a selected PvE talent template,
   consumables and level-appropriate equipment; and
5. summon the prepared party to the leader.

For an existing bot-only party, **Quick Recovery** can summon all bots, match
their level and refresh gear/spells, perform both operations together, or
disband the bot group. Existing talent choices are preserved during recovery.

The leader must be online and outside combat, flight, battlegrounds and active
queues. Party Builder never replaces a group containing another human player
or an LFG/BG group. Death Knight slots require a level 55 or higher leader.

Managed servers include a small GPL-licensed Azeroth Control Bridge module. It
accepts the narrow Party Builder command through the local worldserver console
and observes solo Dungeon Finder join packets so it can prepare missing roles
before AzerothCore performs its normal role check. It executes on the world
thread and opens no network listener. No account password or GM web API is
exposed to the server module.

## FFXIV-style ConsolePortLK setup

Open **Addons** and select **Install & Open Steam Input** on the FFXIV-style
Crossbar card. Azeroth Control will install ConsolePortLK if it is missing,
install its own small in-game preset addon, save a full WTF backup, and add
local controller templates to Steam.

Steam deliberately requires one final confirmation:

1. Open **Templates** in the WoW Controller Settings screen.
2. Choose **Azeroth FFXIV Crossbar**.
3. Select **Apply Layout**.
4. Start WoW. The in-game crossbar applies once after character login.

Default controls are L2/R2 for two eight-skill banks, L2+R2 for a third bank,
L1 for enemy targeting, L1+D-pad for zoom, X for the world map, A for interact,
Y for jump, B for back/close, and R1 for the utility ring. Base D-pad inputs
navigate targets. Trigger-modified D-pad and ABXY inputs remain skill buttons.

Use `/affxiv` in game for a short reminder, `/affxiv apply` to repair the
character preset, or `/affxiv restore` to restore the ConsolePort settings that
were recorded before the first application. The file-level WTF backup is kept
under `Interface/.azeroth-control-backups`.

This native Steam Input route avoids WoWpadX, a Windows runtime, and shared
Proton-prefix configuration. True retail-style nearest-object interaction is
not available in an unmodified 3.3.5a client, so A uses target interaction with
ConsolePort's cursor fallback.

## Important 0.4 native-preview limitations

- The Qt Quick migration is active development. Navigation, focus, layout,
  installation, Party Builder, and SteamOS integration may still contain bugs.
- Not every legacy Electron screen has received final visual and controller QA.
- This is a development preview, not a zero-maintenance appliance.
- Missing host prerequisites are detected but not installed automatically.
- The first server build is long and may be affected by upstream repository
  changes.
- Solo Dungeon Finder joins can be filled immediately with a prepared bot
  party. Battleground queues still use the built-in Playerbots population and
  timing.
- Steam requires the user to confirm **Apply Layout** for a locally installed
  controller template. Azeroth Control does not change Steam account or
  controller-cloud data.
- The managed updater currently ships tested Azeroth Control server components;
  it does not blindly pull arbitrary upstream AzerothCore or module revisions.
- SteamOS and Proton updates can change non-Steam-game behavior.

## Roadmap

Planned work includes:

- An in-game, controller-friendly **Azeroth Quick Control** addon.
- Group-wide strategies for combat, buffs, grinding, following, questing, and
  regeneration.
- Expanded Dungeon Guide controls for live pull pacing, recovery and
  autoplay-style assistance using capabilities already exposed by AzerothCore
  and mod-playerbots.
- On-demand battleground reserve bots and more configurable LFG compositions.
- Better raid and PvP orchestration.
- One-click SteamOS prerequisite setup.
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

The primary interface is now the C++/Qt 6 Quick application in [`native/`](native/).
It starts without an embedded browser and communicates with the same
loopback-only Python control service used by the earlier frontend.

```bash
cd native
qmake6 AzerothControl.pro
make -j"$(nproc)"
```

The React/Vite and Electron sources remain temporarily in the repository as a
migration reference and compatibility frontend:

```bash
npm install
npm run build
npm run desktop
npm run appimage
```

The primary interface is Qt Quick/C++, the local allow-listed control service
is Python, and server builds/runtime services use rootless Podman. See the
[native notes](native/README.md) and [architecture notes](docs/ARCHITECTURE.md).

Issues and focused pull requests are welcome. When reporting an installation
problem, include the failed stage and relevant technical-log lines, but remove
local paths, account names, and other personal information first.

## Credits and license

Vibecoded with Codex 5.6 Sol with love. ❤️

Azeroth Control is available under the [MIT License](LICENSE). Downloaded
third-party projects retain their original copyrights and licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
