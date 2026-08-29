# Azeroth Control Bridge

Small server-side command bridge used by Azeroth Control's Party Builder.

The bridge intentionally exposes no network listener. Requests arrive through the
existing local AzerothCore world console and are validated again inside the world
thread before any player or bot is changed.

The current command prepares a five-player party around one online player:

```text
azerothcontrol party build <request-id> <leader-name> <class:spec,...>
```

It selects unowned random PlayerBots from the leader's faction, matches their
level, initializes spells and skills, applies a selected PvE talent template,
regenerates suitable equipment, joins the party and summons them to the leader.

License: GPL-2.0-or-later, matching the linked AzerothCore/mod-playerbots code.
