# Azeroth Control architecture

The primary desktop application is an x86-64 Qt 6 Quick AppImage. It bundles
the native control UI, local orchestration service, install manifests and
recovery tools. It does not bundle a WoW client or extracted client data.

All mutable files live below a user-selected writable directory. The default is
'~/.local/share/azeroth-control'. No application data is written to the
immutable SteamOS system partition.

An installation provider describes a compatible core, pinned revision, client
requirements, capabilities, realm templates and module catalog. Schema v2
ships the WotLK Playerbots provider and an experimental Conquest of Azeroth
provider. The UI derives bot, queue, party, AutoBalance and update controls
from the active provider capabilities.

The renderer has no Node.js access. A small preload bridge exposes only
allow-listed operations. Paths are canonicalized and destructive operations
are limited to registered installation directories. Install operations are
checkpointed so interrupted work can resume.
