#!/usr/bin/env python3
"""Loopback-only control API and static server for Azeroth Control."""

from __future__ import annotations

import datetime as dt
import json
import os
import re
import shutil
import socket
import subprocess
import tarfile
import threading
import time
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
WOW_LAUNCHER = ROOT / "bin/launch-wow-hd-local"
if not WOW_LAUNCHER.exists():
    WOW_LAUNCHER = ROOT / "bin/launch-wow"
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


def run(args: list[str], timeout: int = 15) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, text=True, capture_output=True, timeout=timeout, check=False)


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
        began = dt.datetime.fromisoformat(started.replace("Z", "+00:00"))
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
                message = (result.stdout + result.stderr).strip()[-2000:]
                ok = result.returncode == 0
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
    server_version = "AzerothControl/0.1"

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
                if action == "launch-wow":
                    subprocess.Popen([str(WOW_LAUNCHER)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
                    return self.json_response({"ok": True, "message": "Launching WoW-HD"})
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
            return self.json_response({"error": "Unknown API route"}, 404)
        except (ValueError, OSError, json.JSONDecodeError) as exc:
            return self.json_response({"error": str(exc)}, 400)


def main() -> None:
    if not STATIC_ROOT.exists():
        raise SystemExit(f"Frontend build is missing: {STATIC_ROOT}")
    BACKUP_ROOT.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Azeroth Control: http://{HOST}:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
