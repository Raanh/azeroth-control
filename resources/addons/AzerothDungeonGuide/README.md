# Azeroth Dungeon Guide

A small WoW 3.3.5a companion addon for `mod-dungeon-clear`. Entering a five-player
dungeon opens a controller-friendly run selector:

- **Dynamic** — choose fast or careful pulls per pack;
- **Fast** — fight packs where they stand;
- **Careful** — pull every pack back to camp;
- **Manual** — keep Dungeon Clear off and follow the player.

The addon sends the existing `DC` addon-message protocol implemented by
`mod-dungeon-clear`; it does not open a new network connection. `/adg` or
`/dungeonrun` reopens the selector, and `/adg off` stops the run.

License: MIT.
