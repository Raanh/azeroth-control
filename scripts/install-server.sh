#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${1:?Missing installation configuration}"
CATALOG_FILE="${AZEROTH_CATALOG:?Missing catalog path}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

json_value() {
    python3 - "$CONFIG_FILE" "$1" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))
for part in sys.argv[2].split('.'):
    value = value[part]
if isinstance(value, bool):
    print("1" if value else "0")
elif isinstance(value, list):
    print("\n".join(str(item) for item in value))
else:
    print(value)
PY
}

json_optional() {
    python3 - "$CONFIG_FILE" "$1" <<'PY'
import json, sys
value = json.load(open(sys.argv[1])).get(sys.argv[2], "")
if isinstance(value, bool):
    print("1" if value else "0")
else:
    print(value if value is not None else "")
PY
}

INSTALL_ROOT="$(json_value installRoot)"
CLIENT_PATH="$(json_value clientPath)"
PROFILE="$(json_value profile)"
BOT_COUNT="$(json_value bots)"
SERVER_ID="$(json_optional serverId)"
SERVER_NAME="$(json_optional serverName)"
ACCOUNT_NAME="$(json_optional accountName)"
ACCOUNT_PASSWORD="$(json_optional accountPassword)"
ADMIN_ACCOUNT="$(json_optional adminAccount)"
AUTO_LOGIN="$(json_optional autoLogin)"
SERVER_ID="${SERVER_ID:-default}"
if [[ ! "$SERVER_ID" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,47}$ ]]; then
    printf 'Invalid server identifier: %s\n' "$SERVER_ID" >&2
    exit 2
fi
if [[ -n "$ACCOUNT_NAME" ]] && [[ ! "$ACCOUNT_NAME" =~ ^[a-zA-Z0-9_]{3,16}$ ]]; then
    printf 'Account name must be 3-16 letters, numbers or underscores.\n' >&2
    exit 2
fi
if [[ -n "$ACCOUNT_NAME" ]] && { [[ ${#ACCOUNT_PASSWORD} -lt 4 ]] || [[ ${#ACCOUNT_PASSWORD} -gt 16 ]] || [[ "$ACCOUNT_PASSWORD" =~ [[:space:]] ]]; }; then
    printf 'Account password must be 4-16 characters without spaces.\n' >&2
    exit 2
fi

if [[ -z "$INSTALL_ROOT" || "$INSTALL_ROOT" == "/" || "$INSTALL_ROOT" == "$HOME" ]]; then
    printf 'Refusing unsafe installation location: %s\n' "$INSTALL_ROOT" >&2
    exit 2
fi
if [[ ! -d "$CLIENT_PATH" || ! -f "$CLIENT_PATH/Wow.exe" ]]; then
    printf 'The selected folder does not contain Wow.exe.\n' >&2
    exit 2
fi
for command in git podman python3; do
    command -v "$command" >/dev/null 2>&1 || { printf 'Required command is missing: %s\n' "$command" >&2; exit 2; }
done

mkdir -p "$INSTALL_ROOT"/{servers,cache,backups,logs,state}
SERVER_ROOT="$INSTALL_ROOT/servers/$SERVER_ID"
CORE="$SERVER_ROOT/core"
CHECKPOINTS="$SERVER_ROOT/.install-checkpoints"
mkdir -p "$SERVER_ROOT" "$CHECKPOINTS"
if [[ "$(realpath "$CONFIG_FILE")" != "$(realpath -m "$SERVER_ROOT/install-selection.json")" ]]; then
    cp "$CONFIG_FILE" "$SERVER_ROOT/install-selection.json"
fi

if [[ ! -f "$CHECKPOINTS/core-source" ]]; then
    printf '[1/6] Downloading AzerothCore Playerbots source…\n'
    git clone --filter=blob:none --single-branch --branch Playerbot https://github.com/mod-playerbots/azerothcore-wotlk.git "$CORE"
    touch "$CHECKPOINTS/core-source"
else
    printf '[1/6] Core source already present; resuming.\n'
fi

if [[ ! -f "$CHECKPOINTS/modules" ]]; then
    printf '[2/6] Downloading selected open-source modules…\n'
    while IFS=$'\t' read -r module_id repository directory; do
        [[ -n "$repository" ]] || continue
        target="$CORE/modules/$directory"
        [[ -d "$target/.git" ]] || git clone --filter=blob:none --depth 1 "$repository" "$target"
    done < <(python3 - "$CONFIG_FILE" "$CATALOG_FILE" <<'PY'
import json, sys
selection = json.load(open(sys.argv[1]))
catalog = json.load(open(sys.argv[2]))
enabled = set(selection["modules"])
for module in catalog["modules"]:
    if module["id"] in enabled and module.get("repository") and module["id"] != "playerbots":
        directory = module["repository"].rsplit("/", 1)[-1].removesuffix(".git")
        print(module["id"] + "\t" + module["repository"] + "\t" + directory)
PY
)
    [[ -d "$CORE/modules/mod-playerbots/.git" ]] || git clone --filter=blob:none --depth 1 https://github.com/mod-playerbots/mod-playerbots.git "$CORE/modules/mod-playerbots"
    touch "$CHECKPOINTS/modules"
else
    printf '[2/6] Modules already present; resuming.\n'
fi

# Party Builder is backed by a small, local-only world-console command module.
# It is part of Azeroth Control itself (not a downloadable third-party module),
# so every managed server gets the same safe bridge implementation.
PARTY_BRIDGE_SOURCE="$SCRIPT_DIR/../resources/modules/mod-azeroth-control-bridge"
PARTY_BRIDGE_TARGET="$CORE/modules/mod-azeroth-control-bridge"
PARTY_BRIDGE_VERSION="$(tr -d '[:space:]' < "$PARTY_BRIDGE_SOURCE/VERSION")"
INSTALLED_PARTY_BRIDGE_VERSION=""
if [[ -f "$SERVER_ROOT/state/party-bridge-version" ]]; then
    INSTALLED_PARTY_BRIDGE_VERSION="$(tr -d '[:space:]' < "$SERVER_ROOT/state/party-bridge-version")"
fi
if [[ "$INSTALLED_PARTY_BRIDGE_VERSION" != "$PARTY_BRIDGE_VERSION" ]]; then
    mkdir -p "$PARTY_BRIDGE_TARGET"
    cp -a "$PARTY_BRIDGE_SOURCE/." "$PARTY_BRIDGE_TARGET/"
    # A resumed installation with an older compiled image must rebuild the
    # worldserver once so the updated bridge is actually linked.
    if [[ -f "$CHECKPOINTS/images" ]]; then
        rm "$CHECKPOINTS/images"
    fi
fi

# Buildah/Podman does not retain named ARG values in every child stage used by
# AzerothCore's multi-stage Dockerfile. Numeric ownership keeps the image
# non-root while avoiding late COPY failures after the expensive compilation.
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"
DOCKERFILE="$CORE/apps/docker/Dockerfile"
sed -i \
    -e 's/--chown=\$DOCKER_USER:\$DOCKER_USER/--chown='"$HOST_UID:$HOST_GID"'/g' \
    -e 's/^USER \$DOCKER_USER$/USER '"$HOST_UID:$HOST_GID"'/g' \
    "$DOCKERFILE"

printf '[3/6] Preparing %s realm configuration for %s bots…\n' "$PROFILE" "$BOT_COUNT"
mkdir -p "$SERVER_ROOT/runtime/etc" "$SERVER_ROOT/runtime/logs" "$SERVER_ROOT/state" "$SERVER_ROOT/bin"
INSTALL_ID="$(printf '%s' "$SERVER_ROOT" | sha256sum | cut -c1-10)"
CONTAINER_PREFIX="azc-$INSTALL_ID"
IMAGE_TAG="local-$INSTALL_ID"
if [[ -f "$SERVER_ROOT/install.env" ]]; then
    DB_PASSWORD="$(sed -n 's/^DB_PASSWORD=//p' "$SERVER_ROOT/install.env" | head -n 1)"
fi
DB_PASSWORD="${DB_PASSWORD:-$(python3 -c 'import secrets; print(secrets.token_hex(24))')}"
case "$PROFILE" in
    progression) REALM_KEY=progression; REALM_NAME="Azeroth Progression"; START_LEVEL=1; WORLD_PORT=8085 ;;
    endgame) REALM_KEY=endgame; REALM_NAME="Azeroth Endgame 80"; START_LEVEL=80; WORLD_PORT=8086 ;;
    custom) REALM_KEY=qa; REALM_NAME="Azeroth Custom"; START_LEVEL=1; WORLD_PORT=8087 ;;
    *) printf 'Unsupported profile: %s\n' "$PROFILE" >&2; exit 2 ;;
esac
REALM_NAME="${SERVER_NAME:-$REALM_NAME}"
CLIENT_EXECUTABLE="$CLIENT_PATH/Wow.exe"
[[ -f "$CLIENT_PATH/Wow-HD.exe" ]] && CLIENT_EXECUTABLE="$CLIENT_PATH/Wow-HD.exe"
WORLD_IMAGE="localhost/azeroth-control/wotlk-worldserver:$IMAGE_TAG"
AUTH_IMAGE="localhost/azeroth-control/wotlk-authserver:$IMAGE_TAG"
IMPORT_IMAGE="localhost/azeroth-control/wotlk-db-import:$IMAGE_TAG"
DATA_IMAGE="localhost/azeroth-control/wotlk-client-data:$IMAGE_TAG"
{
    printf 'PROFILE=%q\n' "$PROFILE"
    printf 'REALM_KEY=%q\n' "$REALM_KEY"
    printf 'REALM_NAME=%q\n' "$REALM_NAME"
    printf 'START_LEVEL=%q\n' "$START_LEVEL"
    printf 'WORLD_PORT=%q\n' "$WORLD_PORT"
    printf 'BOT_COUNT=%q\n' "$BOT_COUNT"
    printf 'CLIENT_PATH=%q\n' "$CLIENT_PATH"
    printf 'CLIENT_EXECUTABLE=%q\n' "$CLIENT_EXECUTABLE"
    printf 'STOP_WITH_GAME=%q\n' "$(json_value stopWithGame)"
    printf 'AUTO_LOGIN=%q\n' "${AUTO_LOGIN:-0}"
    printf 'CONTAINER_PREFIX=%q\n' "$CONTAINER_PREFIX"
    printf 'DB_PASSWORD=%q\n' "$DB_PASSWORD"
    printf 'CHARACTER_DB=%q\n' acore_characters
    printf 'PLAYERBOTS_DB=%q\n' acore_playerbots
    printf 'WORLD_IMAGE=%q\n' "$WORLD_IMAGE"
    printf 'AUTH_IMAGE=%q\n' "$AUTH_IMAGE"
    printf 'IMPORT_IMAGE=%q\n' "$IMPORT_IMAGE"
    printf 'DATA_IMAGE=%q\n' "$DATA_IMAGE"
} > "$SERVER_ROOT/install.env"
printf '%s\n' "$CONTAINER_PREFIX" > "$SERVER_ROOT/state/container-prefix"
cp "$SCRIPT_DIR/server-control-managed" "$SERVER_ROOT/bin/server-control"
cp "$SCRIPT_DIR/launch-wow-managed" "$SERVER_ROOT/bin/launch-wow"
cp "$SCRIPT_DIR/autologin-managed" "$SERVER_ROOT/bin/autologin"
chmod +x "$SERVER_ROOT/bin/server-control" "$SERVER_ROOT/bin/launch-wow" "$SERVER_ROOT/bin/autologin"
mkdir -p "$CLIENT_PATH/WTF"
CLIENT_CONFIG="$CLIENT_PATH/WTF/Config.wtf"
if [[ -f "$CLIENT_CONFIG" && ! -f "$CLIENT_CONFIG.azeroth-control-backup" ]]; then
    cp -a "$CLIENT_CONFIG" "$CLIENT_CONFIG.azeroth-control-backup"
fi
touch "$CLIENT_CONFIG"
if grep -qi '^SET realmlist ' "$CLIENT_CONFIG"; then
    sed -i 's/^SET realmlist .*/SET realmlist "127.0.0.1"/I' "$CLIENT_CONFIG"
else
    printf 'SET realmlist "127.0.0.1"\n' >> "$CLIENT_CONFIG"
fi
if [[ -n "$ACCOUNT_NAME" ]]; then
    if grep -qi '^SET accountName ' "$CLIENT_CONFIG"; then
        sed -i 's/^SET accountName .*/SET accountName "'"${ACCOUNT_NAME^^}"'"/I' "$CLIENT_CONFIG"
    else
        printf 'SET accountName "%s"\n' "${ACCOUNT_NAME^^}" >> "$CLIENT_CONFIG"
    fi
fi
AUTOLOGIN_FILE="$SERVER_ROOT/state/autologin.json"
if [[ "$AUTO_LOGIN" == 1 || "$AUTO_LOGIN" == true ]]; then
    python3 - "$AUTOLOGIN_FILE" "$ACCOUNT_NAME" "$ACCOUNT_PASSWORD" <<'PY'
import json, os, sys
target, account, password = sys.argv[1:4]
temporary = target + ".tmp"
with open(temporary, "w", encoding="utf-8") as output:
    json.dump({"account": account.upper(), "password": password}, output)
os.chmod(temporary, 0o600)
os.replace(temporary, target)
PY
else
    rm -f "$AUTOLOGIN_FILE"
fi
touch "$CHECKPOINTS/configuration"

if [[ ! -f "$CHECKPOINTS/images" ]]; then
    printf '[4/6] Building server containers. This is the longest step…\n'
    BUILD_ARGS=(--layers --build-arg "USER_ID=$HOST_UID" --build-arg "GROUP_ID=$HOST_GID" --build-arg DOCKER_USER=acore -f "$DOCKERFILE")
    podman build "${BUILD_ARGS[@]}" --target worldserver -t "$WORLD_IMAGE" "$CORE"
    podman build "${BUILD_ARGS[@]}" --target authserver -t "$AUTH_IMAGE" "$CORE"
    podman build "${BUILD_ARGS[@]}" --target db-import -t "$IMPORT_IMAGE" "$CORE"
    podman build "${BUILD_ARGS[@]}" --target client-data -t "$DATA_IMAGE" "$CORE"
    touch "$CHECKPOINTS/images"
    printf '%s\n' "$PARTY_BRIDGE_VERSION" > "$SERVER_ROOT/state/party-bridge-version"
else
    printf '[4/6] Container images already exist; resuming.\n'
fi

if [[ ! -f "$CHECKPOINTS/health-check" ]]; then
    printf '[5/6] Creating databases, client data and running the health check…\n'
    for port in 3307 3724 "$WORLD_PORT"; do
        if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
            printf 'Port %s is already in use. Stop the other local server and press Resume.\n' "$port" >&2
            exit 3
        fi
    done
    "$SERVER_ROOT/bin/server-control" start
    touch "$CHECKPOINTS/health-check"
else
    printf '[5/6] Health check already passed.\n'
fi

if [[ -n "$ACCOUNT_NAME" && ! -f "$CHECKPOINTS/account" ]]; then
    printf 'Creating the first game account…\n'
    {
        printf 'account create %s %s\n' "$ACCOUNT_NAME" "$ACCOUNT_PASSWORD"
        if [[ "$ADMIN_ACCOUNT" == 1 || "$ADMIN_ACCOUNT" == true ]]; then
            printf 'account set gmlevel %s 3 -1\n' "$ACCOUNT_NAME"
        fi
    } | "$SERVER_ROOT/bin/server-control" console >/dev/null 2>&1 || true
    account_count=0
    for _ in $(seq 1 15); do
        account_count="$(podman exec "$CONTAINER_PREFIX-database" mysql -N -uroot -p"$DB_PASSWORD" acore_auth -e "SELECT COUNT(*) FROM account WHERE username=UPPER('$ACCOUNT_NAME')" 2>/dev/null || printf 0)"
        [[ "$account_count" == 1 ]] && break
        sleep 2
    done
    [[ "$account_count" == 1 ]] || { printf 'The server started, but account creation failed. Press Resume to retry.\n' >&2; exit 4; }
    touch "$CHECKPOINTS/account"
fi

printf '[6/6] Creating launchers and Steam shortcuts…\n'
STEAM_LAUNCHER="$SERVER_ROOT/bin/Azeroth-WoW-$SERVER_ID"
if [[ "$(json_value steamShortcuts)" == 1 && ! -f "$CHECKPOINTS/steam-shortcut" ]] && command -v steamos-add-to-steam >/dev/null 2>&1; then
    cp "$SERVER_ROOT/bin/launch-wow" "$STEAM_LAUNCHER"
    chmod +x "$STEAM_LAUNCHER"
    steamos-add-to-steam "$STEAM_LAUNCHER" || true
    touch "$CHECKPOINTS/steam-shortcut"
fi
touch "$CHECKPOINTS/complete"
python3 - "$CONFIG_FILE" "$SERVER_ROOT/install-selection.json" "$CLIENT_EXECUTABLE" "$STEAM_LAUNCHER" <<'PY'
import json, sys
client_executable, steam_executable = sys.argv[3:5]
for name in sys.argv[1:3]:
    try:
        with open(name, encoding="utf-8") as source:
            value = json.load(source)
        value["accountPassword"] = ""
        value["clientExecutable"] = client_executable
        value["steamExecutable"] = steam_executable if value.get("steamShortcuts") else ""
        temporary = name + ".tmp"
        with open(temporary, "w", encoding="utf-8") as target:
            json.dump(value, target, indent=2)
        import os
        os.replace(temporary, name)
    except FileNotFoundError:
        pass
PY
printf 'Installation completed. %s is online and ready.\n' "$REALM_NAME"
