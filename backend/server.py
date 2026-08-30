#!/usr/bin/env python3
"""Loopback-only control API and static server for Azeroth Control."""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import tarfile
import threading
import tempfile
import time
import urllib.request
import zipfile
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

HOST = "127.0.0.1"
PORT = int(os.environ.get("AZEROTH_CONTROL_PORT", "8742"))
HOME = Path.home()
ROOT = Path(os.environ.get("AZEROTH_SERVER_ROOT", HOME / "Applications/azerothcore-playerbots")).expanduser().resolve()
RUNTIME = ROOT / "runtime"
CONTROL = ROOT / "bin/server-control"
UPDATE_CONTROL = ROOT / "bin/update-server"
REPAIR_CONTROL = ROOT / "bin/repair-server"
APP_ROOT = Path(__file__).resolve().parent.parent
STATIC_ROOT = APP_ROOT / "dist"
BACKUP_ROOT = Path(os.environ.get("AZEROTH_CONTROL_BACKUP_ROOT", APP_ROOT / "backups")).expanduser()
try:
    CONTAINER_PREFIX = (ROOT / "state" / "container-prefix").read_text().strip() or "ac"
except OSError:
    CONTAINER_PREFIX = "ac"
WORLD_CONTAINER = f"{CONTAINER_PREFIX}-worldserver"
AUTH_CONTAINER = f"{CONTAINER_PREFIX}-authserver"
DATABASE_CONTAINER = f"{CONTAINER_PREFIX}-database"

ADDON_CATALOG = [
    {"id": "azeroth-dungeon-guide", "name": "Azeroth Dungeon Guide", "version": "0.1.0", "category": "Gamepad", "description": "Controller-friendly dungeon run selector for Dungeon Clear.", "note": "Choose Dynamic, Fast, Careful or Manual tank-leading behavior.", "sourceUrl": "https://github.com/Raanh/azeroth-control", "bundledFolder": "AzerothDungeonGuide", "folders": ["AzerothDungeonGuide"]},
    {"id": "consoleportlk", "name": "ConsolePortLK", "version": "1.5.0-rc2", "category": "Gamepad", "description": "Controller action bars, menus and navigation for WoW 3.3.5a.", "note": "Recommended for Steam Deck and living-room play.", "sourceUrl": "https://github.com/leoaviana/ConsolePortLK", "downloadUrl": "https://github.com/leoaviana/ConsolePortLK/releases/download/1.5.0-rc2/ConsolePortLK-1.5.0-rc2.zip", "sha256": "9ee20bb1f3c5c5b8d45fcc5980a07bb90d49a707e120613453177c05fea6497f", "folders": ["ConsolePort", "ConsolePortAdvanced", "ConsolePortBar", "ConsolePortHelp", "ConsolePortKeyboard", "ConsolePortLoader", "ConsolePortUI_Loot", "ConsolePortUI_Menu"]},
    {"id": "questiex", "name": "Questie-X", "version": "1.6.4", "category": "Questing", "description": "Quest objectives, map markers and tracker support.", "note": "Private-server build with a 3.3.5a-compatible TOC.", "sourceUrl": "https://github.com/Xurkon/Questie-X", "downloadUrl": "https://github.com/Xurkon/Questie-X/releases/download/v1.6.4/Questie-X-1.6.4.zip", "sha256": "621bf504c43da8d7e34c06b48aeb7dd85cb45b568d0f6a8630a7cfea4143f65f", "folders": ["Questie-X"]},
    {"id": "refined-blizz-plates", "name": "RefinedBlizzPlates", "version": "1.11.2", "category": "Interface", "description": "Modern readable Blizzard-style nameplates for WotLK.", "note": "Configure it in game after restarting WoW.", "sourceUrl": "https://github.com/KhalGH/RefinedBlizzPlates-WotLK", "downloadUrl": "https://github.com/KhalGH/RefinedBlizzPlates-WotLK/releases/download/v1.11.2/RefinedBlizzPlates-v1.11.2.zip", "sha256": "5f5eb1527a997a6e0439966910ec9ea506b577240c0c0e1a0b0e5c2f915ba39a", "folders": ["!!RefinedBlizzPlates"]},
    {"id": "ffxiv-controller", "name": "Azeroth FFXIV Crossbar", "version": "0.1.0", "category": "Gamepad", "description": "FFXIV-style L2/R2 crossbar preset for ConsolePortLK.", "note": "Install ConsolePortLK first; Steam Input layout confirmation remains manual.", "sourceUrl": "https://github.com/Raanh/azeroth-control", "bundledFolder": "AzerothFFXIVController", "folders": ["AzerothFFXIVController"]},
]


def addon_paths():
    selection = json.loads((ROOT / "install-selection.json").read_text())
    client = Path(selection["clientPath"]).expanduser().resolve()
    addons = client / "Interface" / "AddOns"
    records = client / "Interface" / ".azeroth-control-addons.json"
    return client, addons, records


def addon_payload() -> dict:
    client, addons, records_path = addon_paths()
    try: records = json.loads(records_path.read_text())
    except (OSError, json.JSONDecodeError): records = {}
    entries = []
    for addon in ADDON_CATALOG:
        item = dict(addon)
        item["installed"] = all((addons / folder).is_dir() for folder in addon["folders"])
        item["installedVersion"] = records.get(addon["id"], {}).get("version", "")
        entries.append(item)
    return {"clientPath": str(client), "addonsPath": str(addons), "addons": entries}


def change_addon(addon_id: str, action: str) -> dict:
    addon = next((item for item in ADDON_CATALOG if item["id"] == addon_id), None)
    if not addon: raise ValueError("Unknown addon")
    client, addons, records_path = addon_paths()
    addons.mkdir(parents=True, exist_ok=True)
    try: records = json.loads(records_path.read_text())
    except (OSError, json.JSONDecodeError): records = {}
    backup = client / "Interface" / ".azeroth-control-backups" / f"{addon_id}-{int(time.time())}"
    if action == "remove":
        for folder in addon["folders"]:
            target = addons / folder
            if target.exists(): backup.mkdir(parents=True, exist_ok=True); shutil.move(str(target), str(backup / folder))
        records.pop(addon_id, None)
    elif action == "install":
        with tempfile.TemporaryDirectory(prefix="azeroth-addon-") as temporary:
            extracted = Path(temporary) / "extracted"
            if addon.get("bundledFolder"):
                source_root = APP_ROOT / "resources" / "addons"
            else:
                archive = Path(temporary) / "addon.zip"
                with urllib.request.urlopen(addon["downloadUrl"], timeout=90) as response:
                    data = response.read(200 * 1024 * 1024 + 1)
                if len(data) > 200 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != addon["sha256"]: raise ValueError("Addon download checksum failed")
                archive.write_bytes(data); extracted.mkdir()
                with zipfile.ZipFile(archive) as bundle:
                    for member in bundle.namelist():
                        path = Path(member.replace("\\", "/"))
                        if path.is_absolute() or ".." in path.parts: raise ValueError("Unsafe addon archive")
                    bundle.extractall(extracted)
                source_root = extracted
            for folder in addon["folders"]:
                source, target = source_root / folder, addons / folder
                if not source.is_dir(): raise ValueError(f"Addon release is missing {folder}")
                if target.exists(): backup.mkdir(parents=True, exist_ok=True); shutil.move(str(target), str(backup / folder))
                shutil.copytree(source, target)
        records[addon_id] = {"version": addon["version"], "installedAt": dt.datetime.now(dt.timezone.utc).isoformat(), "folders": addon["folders"]}
    else: raise ValueError("Unknown addon action")
    records_path.write_text(json.dumps(records, indent=2))
    return addon_payload()

REALMS = {
    "progression": {"config": RUNTIME / "etc", "port": 8085, "name": "AzerothCore Progression", "characters": "acore_characters"},
    "endgame": {"config": RUNTIME / "endgame/etc", "port": 8086, "name": "AzerothCore Endgame 80", "characters": "acore_characters_endgame"},
    "qa": {"config": RUNTIME / "qa/etc", "port": 8087, "name": "AzerothCore QA Custom", "characters": "acore_characters_qa"},
}

SETTING_MAP = {
    "xpKill": ("worldserver.conf", "Rate.XP.Kill", float, 0.0, 20.0),
    "xpQuest": ("worldserver.conf", "Rate.XP.Quest", float, 0.0, 20.0),
    "xpExplore": ("worldserver.conf", "Rate.XP.Explore", float, 0.0, 20.0),
    "respawnRate": ("worldserver.conf", "Respawn.DynamicRateCreature", float, 0.01, 10.0),
    "dungeonDeserter": ("worldserver.conf", "DungeonFinder.CastDeserter", bool, 0, 1),
    "bgDeserter": ("worldserver.conf", "Battleground.CastDeserter", bool, 0, 1),
    "joinLfg": ("modules/playerbots.conf", "AiPlayerbot.RandomBotJoinLfg", bool, 0, 1),
    "joinBg": ("modules/playerbots.conf", "AiPlayerbot.RandomBotJoinBG", bool, 0, 1),
    "autoJoinBg": ("modules/playerbots.conf", "AiPlayerbot.RandomBotAutoJoinBG", bool, 0, 1),
    "levelBrackets": ("modules/playerbots.conf", "AiPlayerbot.LevelBrackets.Enabled", bool, 0, 1),
    "dynamicBrackets": ("modules/playerbots.conf", "AiPlayerbot.LevelBrackets.Dynamic.UseDynamicDistribution", bool, 0, 1),
    "syncFactions": ("modules/playerbots.conf", "AiPlayerbot.LevelBrackets.Dynamic.SyncFactions", bool, 0, 1),
    "playerWeight": ("modules/playerbots.conf", "AiPlayerbot.LevelBrackets.Dynamic.RealPlayerWeight", float, 0.0, 30.0),
    "aoeLoot": ("modules/mod_aoe_loot.conf", "AOELoot.Enable", bool, 0, 1),
    "aoeLootRange": ("modules/mod_aoe_loot.conf", "AOELoot.Range", float, 1.0, 100.0),
}
DROP_RATE_KEYS = (
    "Rate.Drop.Item.Poor", "Rate.Drop.Item.Normal", "Rate.Drop.Item.Uncommon",
    "Rate.Drop.Item.Rare", "Rate.Drop.Item.Epic", "Rate.Drop.Item.Legendary",
    "Rate.Drop.Item.Artifact", "Rate.Drop.Item.Referenced",
)

job_lock = threading.Lock()
job = {"running": False, "label": "", "ok": True, "message": ""}


def run(args: list[str], timeout: int = 15, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, text=True, input=input_text, capture_output=True, timeout=timeout, check=False)


def active_realm() -> str:
    try:
        value = (RUNTIME / "active-realm").read_text().strip()
        return value if value in REALMS else "progression"
    except OSError:
        return "progression"


def available_realms() -> list[str]:
    available = [name for name, value in REALMS.items() if (Path(value["config"]) / "worldserver.conf").exists()]
    current = active_realm()
    return available or [current]


def container_state() -> tuple[str, str]:
    world = run(["podman", "inspect", "-f", "{{.State.Status}}|{{.State.StartedAt}}", WORLD_CONTAINER])
    auth = run(["podman", "inspect", "-f", "{{.State.Status}}", AUTH_CONTAINER])
    if world.returncode or auth.returncode:
        return "offline", ""
    status, _, started = world.stdout.strip().partition("|")
    if status != "running" or auth.stdout.strip() != "running":
        return "offline", started
    for port in (3724, int(REALMS[active_realm()]["port"])):
        try:
            with socket.create_connection((HOST, port), timeout=0.4):
                pass
        except OSError:
            return "offline", started
    return "running", started


def human_duration(started: str) -> str:
    if not started:
        return "—"
    try:
        value = started.replace("Z", "+00:00")
        # Rootless Podman on SteamOS may append a timezone abbreviation and
        # print nanoseconds; datetime.fromisoformat accepts neither together.
        value = re.sub(r" ([A-Z]{2,6})$", "", value)
        value = re.sub(r"(\.\d{6})\d+", r"\1", value)
        began = dt.datetime.fromisoformat(value)
        seconds = max(0, int((dt.datetime.now(dt.timezone.utc) - began).total_seconds()))
        hours, rem = divmod(seconds, 3600)
        minutes = rem // 60
        return f"{hours} h {minutes} min" if hours else f"{minutes} min"
    except ValueError:
        return "—"


def podman_stats() -> tuple[str, str]:
    result = run(["podman", "stats", "--no-stream", "--format", "json", WORLD_CONTAINER], timeout=8)
    if result.returncode:
        return "—", "—"
    try:
        data = json.loads(result.stdout)
        if isinstance(data, list):
            data = data[0] if data else {}
        return str(data.get("cpu_percent", data.get("CPU", "—"))), str(data.get("mem_usage", data.get("MemUsage", "—")))
    except (json.JSONDecodeError, IndexError):
        return "—", "—"


def recent_logs(lines: int = 160) -> str:
    result = run(["podman", "logs", "--tail", str(max(20, min(lines, 800))), WORLD_CONTAINER], timeout=10)
    return (result.stdout + result.stderr)[-100_000:]


def bot_count_from_logs(text: str) -> int:
    matches = re.findall(r"(\d+)/(\d+) Bot .+ logged in", text)
    return int(matches[-1][0]) if matches else 0


def online_bot_count(realm: str, fallback_logs: str) -> int:
    database = str(REALMS[realm]["characters"])
    query = (
        f"SELECT COUNT(*) FROM {database}.characters c "
        "JOIN acore_auth.account a ON a.id=c.account WHERE c.online=1 AND "
        "(a.username LIKE 0x524E44424F5425 OR a.username LIKE 0x414444434C41535325)"
    )
    script = f'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "{query}"'
    result = run(["podman", "exec", DATABASE_CONTAINER, "sh", "-lc", script], timeout=8)
    try:
        return int(result.stdout.strip()) if result.returncode == 0 else bot_count_from_logs(fallback_logs)
    except ValueError:
        return bot_count_from_logs(fallback_logs)


PARTY_SPECS = {
    1: {0: "Arms", 1: "Fury", 2: "Protection"},
    2: {0: "Holy", 1: "Protection", 2: "Retribution"},
    3: {0: "Beast Mastery", 1: "Marksmanship", 2: "Survival"},
    4: {0: "Assassination", 1: "Combat", 2: "Subtlety"},
    5: {0: "Discipline", 1: "Holy", 2: "Shadow"},
    6: {0: "Blood", 1: "Frost", 2: "Unholy"},
    7: {0: "Elemental", 1: "Enhancement", 2: "Restoration"},
    8: {0: "Arcane", 1: "Fire", 2: "Frost"},
    9: {0: "Affliction", 1: "Demonology", 2: "Destruction"},
    11: {0: "Balance", 1: "Feral Tank", 2: "Restoration", 3: "Feral DPS"},
}
PARTY_CLASS_NAMES = {
    1: "Warrior", 2: "Paladin", 3: "Hunter", 4: "Rogue", 5: "Priest",
    6: "Death Knight", 7: "Shaman", 8: "Mage", 9: "Warlock", 11: "Druid",
}
PARTY_ROLE_SPECS = {
    "Tank": {(1, 2), (2, 1), (6, 0), (11, 1)},
    "Healer": {(2, 0), (5, 0), (5, 1), (7, 2), (11, 2)},
    "DPS": {
        (1, 0), (1, 1), (2, 2), (3, 0), (3, 1), (3, 2), (4, 0), (4, 1), (4, 2),
        (5, 2), (6, 1), (6, 2), (7, 0), (7, 1), (8, 0), (8, 1), (8, 2),
        (9, 0), (9, 1), (9, 2), (11, 0), (11, 3),
    },
}


def party_bridge_version() -> str:
    try:
        return (ROOT / "state" / "party-bridge-version").read_text().strip()
    except OSError:
        return ""


def online_human_players() -> list[dict]:
    if container_state()[0] != "running":
        return []
    database = str(REALMS[active_realm()]["characters"])
    query = (
        f"SELECT c.name,c.level,c.class FROM {database}.characters c "
        "JOIN acore_auth.account a ON a.id=c.account WHERE c.online=1 "
        "AND UPPER(a.username) NOT LIKE 'RNDBOT%' AND UPPER(a.username) NOT LIKE 'ADDCLASS%' "
        "ORDER BY c.name"
    )
    script = f'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B -e "{query}"'
    result = run(["podman", "exec", DATABASE_CONTAINER, "sh", "-lc", script], timeout=10)
    if result.returncode:
        return []
    players = []
    for line in result.stdout.splitlines():
        fields = line.split("\t")
        if len(fields) != 3 or not re.fullmatch(r"[A-Za-z]{2,12}", fields[0]):
            continue
        try:
            players.append({"name": fields[0], "level": int(fields[1]), "classId": int(fields[2])})
        except ValueError:
            continue
    return players


def party_payload() -> dict:
    return {
        "bridgeReady": bool(party_bridge_version()),
        "bridgeVersion": party_bridge_version(),
        "serverOnline": container_state()[0] == "running",
        "players": online_human_players(),
    }


def validate_party_slots(raw_slots) -> list[dict]:
    if not isinstance(raw_slots, list) or len(raw_slots) != 4:
        raise ValueError("Party Builder requires exactly four bot slots")
    slots = []
    for raw in raw_slots:
        if not isinstance(raw, dict):
            raise ValueError("Invalid party slot")
        role = str(raw.get("role", ""))
        try:
            class_id = int(raw.get("classId"))
            spec_id = int(raw.get("specId"))
        except (TypeError, ValueError) as exc:
            raise ValueError("Invalid class or specialization") from exc
        if role not in PARTY_ROLE_SPECS or (class_id, spec_id) not in PARTY_ROLE_SPECS[role]:
            raise ValueError(f"{PARTY_CLASS_NAMES.get(class_id, 'Selected class')} / {PARTY_SPECS.get(class_id, {}).get(spec_id, 'spec')} cannot fill the {role or 'selected'} role")
        slots.append({"role": role, "classId": class_id, "specId": spec_id})
    return slots


def build_party(payload: dict) -> dict:
    if not party_bridge_version():
        raise RuntimeError("This managed server needs the Azeroth Control Party Bridge update")
    if container_state()[0] != "running":
        raise RuntimeError("Start the server before building a party")

    leader = str(payload.get("leader", ""))
    if not re.fullmatch(r"[A-Za-z]{2,12}", leader):
        raise ValueError("Select an online player character")
    online_names = {player["name"] for player in online_human_players()}
    if leader not in online_names:
        raise RuntimeError("The selected character must be logged into the world")

    slots = validate_party_slots(payload.get("slots"))
    request_id = secrets.token_hex(8)
    encoded = ",".join(f'{slot["classId"]}:{slot["specId"]}' for slot in slots)
    command = f"azerothcontrol party build {request_id} {leader} {encoded}"
    submitted = run([str(CONTROL), "console"], timeout=30, input_text=command + "\n")
    if submitted.returncode:
        raise RuntimeError((submitted.stdout + submitted.stderr).strip()[-800:] or "World console rejected the Party Builder request")

    marker = f"AZC_PARTY_RESULT|{request_id}|"
    deadline = time.monotonic() + 180
    result_line = ""
    while time.monotonic() < deadline:
        logs = run(["podman", "logs", "--tail", "10000", WORLD_CONTAINER], timeout=15)
        combined = logs.stdout + logs.stderr
        position = combined.rfind(marker)
        if position >= 0:
            result_line = combined[position:].splitlines()[0].strip()
            break
        time.sleep(0.5)
    if not result_line:
        raise RuntimeError("Party preparation did not finish within three minutes; check World Log before trying again")

    fields = result_line.split("|")
    if len(fields) < 5 or fields[2] == "ERR":
        message = fields[4] if len(fields) > 4 else "The server could not prepare this party"
        raise RuntimeError(message)
    if len(fields) < 7 or fields[2] != "OK":
        raise RuntimeError("Party Bridge returned an invalid response")

    prepared = []
    for entry in fields[6].split(";"):
        values = entry.split(",")
        if len(values) != 3:
            continue
        class_id, spec_id = int(values[1]), int(values[2])
        prepared.append({
            "name": values[0],
            "classId": class_id,
            "className": PARTY_CLASS_NAMES.get(class_id, "Unknown"),
            "specId": spec_id,
            "spec": PARTY_SPECS.get(class_id, {}).get(spec_id, "Unknown"),
        })
    return {
        "ok": True,
        "leader": fields[3],
        "level": int(fields[4]),
        "bots": prepared,
        "message": f"Party ready: {len(prepared)} bots joined, prepared and summoned to {fields[3]}.",
    }


def party_action(payload: dict, action: str) -> dict:
    if action not in {"summon", "prepare", "recover", "disband"}:
        raise ValueError("Unknown party recovery action")
    version = party_bridge_version()
    try:
        supported = tuple(int(part) for part in version.split(".")[:2]) >= (0, 3)
    except ValueError:
        supported = False
    if not supported:
        raise RuntimeError("Party Recovery requires Party Bridge v0.3 or newer. Install the managed update first.")
    if container_state()[0] != "running":
        raise RuntimeError("Start the server before managing a party")
    leader = str(payload.get("leader", ""))
    if not re.fullmatch(r"[A-Za-z]{2,12}", leader) or leader not in {player["name"] for player in online_human_players()}:
        raise ValueError("Select an online player character")

    request_id = secrets.token_hex(8)
    command = f"azerothcontrol party {action} {request_id} {leader}"
    submitted = run([str(CONTROL), "console"], timeout=30, input_text=command + "\n")
    if submitted.returncode:
        raise RuntimeError((submitted.stdout + submitted.stderr).strip()[-800:] or "World console rejected the Party Recovery request")

    marker = f"AZC_PARTY_RESULT|{request_id}|"
    deadline = time.monotonic() + 180
    result_line = ""
    while time.monotonic() < deadline:
        logs = run(["podman", "logs", "--tail", "10000", WORLD_CONTAINER], timeout=15)
        combined = logs.stdout + logs.stderr
        position = combined.rfind(marker)
        if position >= 0:
            result_line = combined[position:].splitlines()[0].strip()
            break
        time.sleep(0.5)
    if not result_line:
        raise RuntimeError("Party Recovery did not finish within three minutes")
    fields = result_line.split("|")
    if len(fields) < 5 or fields[2] == "ERR":
        raise RuntimeError(fields[4] if len(fields) > 4 else "The server could not manage this party")
    if len(fields) < 6 or fields[2] != "OK":
        raise RuntimeError("Party Bridge returned an invalid response")
    labels = {
        "summon": "Party summoned to your character.",
        "prepare": "Party matched to your level, geared and trained.",
        "recover": "Party fully recovered, prepared and summoned.",
        "disband": "Bot party disbanded.",
    }
    return {"ok": True, "action": fields[3], "leader": fields[4], "bots": int(fields[5]), "message": labels[action]}


def status_payload() -> dict:
    realm = active_realm()
    state, started = container_state()
    cpu, memory = podman_stats() if state == "running" else ("—", "—")
    logs = recent_logs(400) if state == "running" else ""
    port = REALMS[realm]["port"]
    ready = state == "running"
    return {
        "realm": realm,
        "realmName": REALMS[realm]["name"],
        "availableRealms": available_realms(),
        "port": port,
        "state": "online" if ready else "offline",
        "uptime": human_duration(started),
        "bots": online_bot_count(realm, logs) if ready else 0,
        "cpu": cpu,
        "memory": memory,
        "job": dict(job),
    }


def read_conf_value(path: Path, key: str) -> str | None:
    try:
        pattern = re.compile(rf"^\s*{re.escape(key)}\s*=\s*(.*?)\s*$", re.MULTILINE)
        match = pattern.search(path.read_text())
        return match.group(1).strip().strip('"') if match else None
    except OSError:
        return None


def parse_value(raw: str | None, kind: type):
    if kind is bool:
        return str(raw or "0").lower() in {"1", "true", "yes", "on"}
    try:
        return float(raw or 0)
    except ValueError:
        return 0


def read_bot_count(realm: str) -> int:
    try:
        managed_env = ROOT / "install.env"
        if managed_env.exists():
            match = re.search(r'^BOT_COUNT=["\']?(\d+)', managed_env.read_text(), re.MULTILINE)
            return int(match.group(1)) if match else 0
        text = CONTROL.read_text()
        labels = {"progression": r"progression\|normal\|1", "endgame": r"endgame\|80\|2", "qa": r"qa\|custom\|3"}
        block = re.search(rf"{labels[realm]}\)\s*(.*?)(?=\n\s*;;)", text, re.DOTALL)
        count = re.search(r"BOT_COUNT=(\d+)", block.group(1) if block else "")
        return int(count.group(1)) if count else 0
    except OSError:
        return 0


def settings_payload(realm: str) -> dict:
    base = REALMS[realm]["config"]
    values = {"realm": realm, "botCount": read_bot_count(realm)}
    for name, (relative, key, kind, _low, _high) in SETTING_MAP.items():
        values[name] = parse_value(read_conf_value(base / relative, key), kind)
    values["xpRate"] = values["xpKill"]
    values["dropRate"] = parse_value(read_conf_value(base / "worldserver.conf", "Rate.Drop.Item.Normal"), float)
    values["spawnRate"] = round(1.0 / max(float(values["respawnRate"]), 0.0001), 3)
    return values


def backup_file(path: Path) -> None:
    if not path.exists():
        return
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    destination = BACKUP_ROOT / stamp / path.relative_to(ROOT)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, destination)


def replace_conf_value(path: Path, key: str, value: str) -> None:
    text = path.read_text()
    pattern = re.compile(rf"^(\s*{re.escape(key)}\s*=\s*).*$", re.MULTILINE)
    if not pattern.search(text):
        raise ValueError(f"Setting {key} was not found")
    backup_file(path)
    updated = pattern.sub(rf"\g<1>{value}", text, count=1)
    temporary = path.with_suffix(path.suffix + ".azeroth-control.tmp")
    temporary.write_text(updated)
    os.replace(temporary, path)


def replace_bot_count(realm: str, count: int) -> None:
    managed_env = ROOT / "install.env"
    if managed_env.exists():
        text = managed_env.read_text()
        pattern = re.compile(r"^(BOT_COUNT=).*$", re.MULTILINE)
        if not pattern.search(text):
            raise ValueError("BOT_COUNT was not found in install.env")
        backup_file(managed_env)
        temporary = managed_env.with_suffix(".azeroth-control.tmp")
        temporary.write_text(pattern.sub(rf"\g<1>{count}", text, count=1))
        os.replace(temporary, managed_env)
        return
    text = CONTROL.read_text()
    labels = {"progression": r"progression\|normal\|1", "endgame": r"endgame\|80\|2", "qa": r"qa\|custom\|3"}
    pattern = re.compile(rf"({labels[realm]}\)\s*.*?\n\s*BOT_COUNT=)\d+", re.DOTALL)
    if not pattern.search(text):
        raise ValueError("BOT_COUNT was not found in server-control")
    backup_file(CONTROL)
    updated = pattern.sub(rf"\g<1>{count}", text, count=1)
    temporary = CONTROL.with_suffix(".azeroth-control.tmp")
    temporary.write_text(updated)
    temporary.chmod(CONTROL.stat().st_mode)
    os.replace(temporary, CONTROL)


def save_settings(realm: str, payload: dict) -> dict:
    base = REALMS[realm]["config"]
    if "botCount" in payload:
        count = int(payload["botCount"])
        if not 0 <= count <= 2000:
            raise ValueError("Bot count must be between 0 and 2,000")
        replace_bot_count(realm, count)
    for name, raw in payload.items():
        if name not in SETTING_MAP:
            continue
        relative, key, kind, low, high = SETTING_MAP[name]
        if kind is bool:
            value = "1" if bool(raw) else "0"
        else:
            number = float(raw)
            if not low <= number <= high:
                raise ValueError(f"{name} must be between {low} and {high}")
            value = f"{number:g}"
        replace_conf_value(base / relative, key, value)
    if "xpRate" in payload:
        rate = float(payload["xpRate"])
        if not 0 <= rate <= 20:
            raise ValueError("XP rate must be between 0 and 20")
        for key in ("Rate.XP.Kill", "Rate.XP.Quest", "Rate.XP.Explore"):
            replace_conf_value(base / "worldserver.conf", key, f"{rate:g}")
    if "dropRate" in payload:
        rate = float(payload["dropRate"])
        if not 0 <= rate <= 20:
            raise ValueError("Item drop rate must be between 0 and 20")
        for key in DROP_RATE_KEYS:
            replace_conf_value(base / "worldserver.conf", key, f"{rate:g}")
    if "spawnRate" in payload:
        speed = float(payload["spawnRate"])
        if not 0.25 <= speed <= 20:
            raise ValueError("Creature spawn speed must be between 0.25 and 20")
        replace_conf_value(base / "worldserver.conf", "Respawn.DynamicRateCreature", f"{1.0 / speed:g}")
    return settings_payload(realm)


def start_job(label: str, command: list[str]) -> bool:
    return start_task(label, lambda: run(command, timeout=1200))


def start_task(label: str, operation) -> bool:
    with job_lock:
        if job["running"]:
            return False
        job.update(running=True, label=label, ok=True, message="")

    def worker() -> None:
        try:
            result = operation()
            if isinstance(result, subprocess.CompletedProcess):
                ok = result.returncode == 0
                output = (result.stdout + result.stderr).strip()
                message = f"{label} completed successfully." if ok else (output[-1200:] or f"{label} failed.")
            else:
                message = str(result)
                ok = True
            with job_lock:
                job.update(running=False, ok=ok, message=message)
        except Exception as exc:  # noqa: BLE001
            with job_lock:
                job.update(running=False, ok=False, message=str(exc))

    threading.Thread(target=worker, daemon=True).start()
    return True


def update_job_message(message: str) -> None:
    with job_lock:
        job["message"] = message[-4000:]


def run_streaming(command: list[str]) -> str:
    process = subprocess.Popen(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    lines: list[str] = []
    assert process.stdout is not None
    for line in process.stdout:
        line = line.rstrip()
        if line:
            lines.append(line)
            update_job_message("\n".join(lines[-12:]))
    return_code = process.wait()
    output = "\n".join(lines)
    if return_code:
        raise RuntimeError(output[-3000:] or f"Command failed with exit code {return_code}")
    return output[-3000:]


def read_version(path: Path) -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def maintenance_payload() -> dict:
    installed = party_bridge_version()
    bundled = read_version(ROOT / "state" / "bundled" / "mod-azeroth-control-bridge" / "VERSION")
    free = shutil.disk_usage(ROOT).free if ROOT.exists() else 0
    checks = [
        {"name": "Managed controls", "ok": CONTROL.is_file() and UPDATE_CONTROL.is_file() and REPAIR_CONTROL.is_file()},
        {"name": "AzerothCore source", "ok": (ROOT / "core" / ".git").exists()},
        {"name": "WoW client", "ok": WOW_LAUNCHER.exists()},
        {"name": "Podman images", "ok": False},
    ]
    # install.env is a shell file; querying the active container is a safer image
    # readiness signal than parsing arbitrary shell quoting in the web process.
    checks[-1]["ok"] = run(["podman", "image", "exists", container_image_name()]).returncode == 0
    return {
        "managed": (ROOT / "install-selection.json").exists(),
        "installedVersion": installed,
        "bundledVersion": bundled,
        "updateAvailable": bool(bundled and bundled != installed),
        "freeBytes": free,
        "checks": checks,
        "rollbackImage": read_version(ROOT / "state" / "last-worldserver-rollback-image"),
    }


def container_image_name() -> str:
    result = run(["podman", "inspect", "-f", "{{.ImageName}}", WORLD_CONTAINER])
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    try:
        match = re.search(r"^WORLD_IMAGE=(.*)$", (ROOT / "install.env").read_text(), re.MULTILINE)
        return (match.group(1).strip().strip("'\"") if match else "missing")
    except OSError:
        return "missing"


def update_managed_server() -> str:
    if not UPDATE_CONTROL.exists():
        raise RuntimeError("Managed update script is missing. Restart Azeroth Control and try again.")
    if container_state()[0] != "running":
        update_job_message("Starting the realm before creating a safety backup…")
        started = run([str(CONTROL), "start"], timeout=1200)
        if started.returncode:
            raise RuntimeError((started.stdout + started.stderr)[-2000:])
    update_job_message("Creating a full database and configuration backup…")
    backup_message = create_full_backup()
    update_job_message(f"{backup_message}\nCompiling the managed server update…")
    result = run_streaming([str(UPDATE_CONTROL)])
    return f"{backup_message}\n{result}"


def repair_managed_server() -> str:
    if not REPAIR_CONTROL.exists():
        raise RuntimeError("Managed repair script is missing. Restart Azeroth Control and try again.")
    return run_streaming([str(REPAIR_CONTROL)])


def backup_entries() -> list[dict]:
    entries = []
    try:
        candidates = [item for item in BACKUP_ROOT.iterdir() if item.is_dir() and (item / "manifest.json").exists()]
    except OSError:
        return entries
    for item in sorted(candidates, reverse=True):
        try:
            manifest = json.loads((item / "manifest.json").read_text())
            size = sum(path.stat().st_size for path in item.rglob("*") if path.is_file())
            entries.append({"id": item.name, "createdAt": manifest.get("createdAt", item.name), "realm": manifest.get("realm", "unknown"), "sizeBytes": size})
        except (OSError, json.JSONDecodeError):
            continue
    return entries


def create_full_backup() -> str:
    if container_state()[0] != "running":
        raise ValueError("Start the server before creating a backup.")
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    temporary = BACKUP_ROOT / f".{stamp}.tmp"
    destination = BACKUP_ROOT / stamp
    if temporary.exists():
        shutil.rmtree(temporary)
    temporary.mkdir(parents=True)
    databases_result = run(["podman", "exec", DATABASE_CONTAINER, "sh", "-lc", "mysql -N -uroot -p\"$MYSQL_ROOT_PASSWORD\" -e \"SHOW DATABASES LIKE 'acore_%'\""], timeout=20)
    databases = [name for name in databases_result.stdout.splitlines() if re.fullmatch(r"acore_[A-Za-z0-9_]+", name)]
    if databases_result.returncode or not databases:
        raise RuntimeError("Could not read the AzerothCore database list.")
    dump_path = temporary / "databases.sql"
    dump_command = ["podman", "exec", DATABASE_CONTAINER, "sh", "-lc", "exec mysqldump -uroot -p\"$MYSQL_ROOT_PASSWORD\" --single-transaction --routines --events --triggers --databases " + " ".join(databases)]
    with dump_path.open("wb") as dump_file:
        result = subprocess.run(dump_command, stdout=dump_file, stderr=subprocess.PIPE, timeout=1200, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace")[-1200:])
    with tarfile.open(temporary / "server-config.tar.gz", "w:gz") as archive:
        for source in (ROOT / "install.env", ROOT / "install-selection.json", RUNTIME / "etc", RUNTIME / "endgame/etc", RUNTIME / "qa/etc"):
            if source.exists():
                archive.add(source, arcname=source.relative_to(ROOT))
    (temporary / "manifest.json").write_text(json.dumps({"createdAt": dt.datetime.now(dt.timezone.utc).isoformat(), "realm": active_realm(), "databases": databases}, indent=2))
    os.replace(temporary, destination)
    return f"Backup {stamp} completed."


def restore_full_backup(backup_id: str) -> str:
    if not re.fullmatch(r"\d{8}-\d{6}", backup_id or ""):
        raise ValueError("Invalid backup identifier.")
    source = (BACKUP_ROOT / backup_id).resolve()
    if source.parent != BACKUP_ROOT.resolve() or not (source / "databases.sql").exists():
        raise ValueError("Backup was not found.")
    if run(["podman", "inspect", DATABASE_CONTAINER], timeout=10).returncode:
        raise ValueError("Start the server before restoring a backup.")
    run(["podman", "stop", "-t", "60", WORLD_CONTAINER, AUTH_CONTAINER], timeout=90)
    restore_command = ["podman", "exec", "-i", DATABASE_CONTAINER, "sh", "-lc", "exec mysql -uroot -p\"$MYSQL_ROOT_PASSWORD\""]
    with (source / "databases.sql").open("rb") as dump_file:
        result = subprocess.run(restore_command, stdin=dump_file, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=1200, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace")[-1200:])
    config_archive = source / "server-config.tar.gz"
    if config_archive.exists():
        with tarfile.open(config_archive, "r:gz") as archive:
            for member in archive.getmembers():
                target = (ROOT / member.name).resolve()
                if target != ROOT and ROOT not in target.parents:
                    raise ValueError("Backup contains an unsafe path.")
            archive.extractall(ROOT)
    result = run([str(CONTROL), "start"], timeout=1200)
    if result.returncode:
        raise RuntimeError((result.stdout + result.stderr)[-1200:])
    return f"Backup {backup_id} restored and server restarted."


class Handler(SimpleHTTPRequestHandler):
    server_version = "AzerothControl/0.3"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(STATIC_ROOT), **kwargs)

    def log_message(self, fmt: str, *args) -> None:
        print(f"[{self.log_date_time_string()}] {fmt % args}")

    def json_response(self, payload: dict, status: int = 200) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/api/status":
            return self.json_response(status_payload())
        if parsed.path == "/api/logs":
            lines = int(parse_qs(parsed.query).get("lines", [160])[0])
            return self.json_response({"logs": recent_logs(lines)})
        if parsed.path == "/api/settings":
            realm = parse_qs(parsed.query).get("realm", [active_realm()])[0]
            if realm not in REALMS:
                return self.json_response({"error": "Unknown realm"}, 400)
            return self.json_response(settings_payload(realm))
        if parsed.path == "/api/backups":
            return self.json_response({"backups": backup_entries()})
        if parsed.path == "/api/party":
            return self.json_response(party_payload())
        if parsed.path == "/api/maintenance":
            return self.json_response(maintenance_payload())
        if parsed.path == "/api/addons":
            return self.json_response(addon_payload())
        if parsed.path.startswith("/api/"):
            return self.json_response({"error": "Unknown API route"}, 404)
        if parsed.path != "/" and not (STATIC_ROOT / parsed.path.lstrip("/")).exists():
            self.path = "/"
        return super().do_GET()

    def do_POST(self) -> None:  # noqa: N802
        origin = self.headers.get("Origin", "")
        if origin and origin not in {f"http://{HOST}:{PORT}", f"http://localhost:{PORT}", "http://localhost:3000"}:
            return self.json_response({"error": "Origin is not allowed"}, HTTPStatus.FORBIDDEN)
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length > 65536:
                raise ValueError("Request is too large")
            payload = json.loads(self.rfile.read(length) or b"{}")
            if self.path == "/api/addons/action":
                action = payload.get("action", "")
                if action == "open-folder":
                    _client, addons, _records = addon_paths(); addons.mkdir(parents=True, exist_ok=True)
                    subprocess.Popen(["xdg-open", str(addons)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    return self.json_response({"ok": True, "message": "Addon folder opened."})
                result = change_addon(str(payload.get("id", "")), str(action))
                result["ok"] = True; result["message"] = "Addon library updated. Restart WoW to apply changes."
                return self.json_response(result)
            if self.path == "/api/action":
                action = payload.get("action")
                realm = payload.get("realm", active_realm())
                if realm not in REALMS or realm not in available_realms():
                    raise ValueError("This realm is not installed on the active server")
                commands = {
                    "start": (f"Starting {realm} realm", [str(CONTROL), "start", realm]),
                    "restart": (f"Restarting {realm} realm", [str(CONTROL), "restart", realm]),
                    "stop": ("Stopping server", [str(CONTROL), "stop"]),
                }
                if action not in commands:
                    raise ValueError("Unknown action")
                label, command = commands[action]
                if not start_job(label, command):
                    return self.json_response({"error": "Another server action is still running"}, 409)
                return self.json_response({"ok": True, "message": label}, 202)
            if self.path == "/api/settings":
                realm = payload.get("realm", active_realm())
                if realm not in REALMS:
                    raise ValueError("Unknown realm")
                return self.json_response({"ok": True, "settings": save_settings(realm, payload.get("settings", {})), "restartRequired": realm == active_realm()})
            if self.path == "/api/backup":
                if not start_task("Creating full backup", create_full_backup):
                    return self.json_response({"error": "Another server action is still running"}, 409)
                return self.json_response({"ok": True, "message": "Creating full backup"}, 202)
            if self.path == "/api/restore":
                backup_id = str(payload.get("backupId", ""))
                if not start_task(f"Restoring backup {backup_id}", lambda: restore_full_backup(backup_id)):
                    return self.json_response({"error": "Another server action is still running"}, 409)
                return self.json_response({"ok": True, "message": f"Restoring backup {backup_id}"}, 202)
            if self.path == "/api/party/build":
                return self.json_response(build_party(payload))
            if self.path == "/api/party/action":
                return self.json_response(party_action(payload, str(payload.get("action", ""))))
            if self.path == "/api/maintenance/update":
                if not start_task("Updating managed server", update_managed_server):
                    return self.json_response({"error": "Another server action is still running"}, 409)
                return self.json_response({"ok": True, "message": "Creating backup and compiling update"}, 202)
            if self.path == "/api/maintenance/repair":
                if not start_task("Repairing managed server", repair_managed_server):
                    return self.json_response({"error": "Another server action is still running"}, 409)
                return self.json_response({"ok": True, "message": "Running managed repair"}, 202)
            return self.json_response({"error": "Unknown API route"}, 404)
        except (ValueError, OSError, json.JSONDecodeError) as exc:
            return self.json_response({"error": str(exc)}, 400)
        except RuntimeError as exc:
            return self.json_response({"error": str(exc)}, 409)


def main() -> None:
    if not STATIC_ROOT.exists():
        raise SystemExit(f"Frontend build is missing: {STATIC_ROOT}")
    BACKUP_ROOT.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Azeroth Control: http://{HOST}:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
