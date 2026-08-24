# Azeroth Control architecture

The desktop application is an x86-64 Electron AppImage. It bundles the control
UI, local orchestration service, signed install manifests, recovery tools and
documentation. It does not bundle a WoW client or extracted client data.

All mutable files live below a user-selected writable directory. The default is
'~/.local/share/azeroth-control'. No application data is written to the
immutable SteamOS system partition.

An installation provider describes a compatible core, branch, client build,
build strategy, realm templates and module catalog. Version 1 ships only the
WotLK 3.3.5a Playerbots provider. Additional providers can be added later.

The renderer has no Node.js access. A small preload bridge exposes only
allow-listed operations. Paths are canonicalized and destructive operations
are limited to registered installation directories. Install operations are
checkpointed so interrupted work can resume.
