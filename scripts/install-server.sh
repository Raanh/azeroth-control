#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${1:?Missing installation configuration}"
CATALOG_FILE="${AZEROTH_CATALOG:?Missing catalog path}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARTY_BRIDGE_SOURCE="$SCRIPT_DIR/../resources/modules/mod-azeroth-control-bridge"

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
COA_REPACK_PATH="$(json_optional coaRepackPath)"
PROFILE="$(json_value profile)"
BOT_COUNT="$(json_value bots)"
SERVER_ID="$(json_optional serverId)"
SERVER_NAME="$(json_optional serverName)"
ACCOUNT_NAME="$(json_optional accountName)"
ACCOUNT_PASSWORD="$(json_optional accountPassword)"
ADMIN_ACCOUNT="$(json_optional adminAccount)"
AUTO_LOGIN="$(json_optional autoLogin)"
PROVIDER_ID="$(json_optional provider)"
PROVIDER_ID="${PROVIDER_ID:-azerothcore-playerbots}"
mapfile -t PROVIDER_FIELDS < <(python3 - "$CATALOG_FILE" "$PROVIDER_ID" <<'PY'
import json, sys
catalog = json.load(open(sys.argv[1]))
providers = catalog.get("providers") or [{
    "id": catalog.get("core", {}).get("id", "azerothcore-playerbots"),
    "core": catalog.get("core", {}), "profiles": catalog.get("profiles", []),
    "modules": catalog.get("modules", []), "capabilities": {"bots": True},
}]
provider = next((item for item in providers if item.get("id") == sys.argv[2]), None)
if provider is None:
    raise SystemExit("Unknown installation provider: " + sys.argv[2])
core = provider.get("core", {})
print(core.get("repository", ""))
print(core.get("branch", ""))
print(core.get("revision", ""))
print("1" if provider.get("capabilities", {}).get("bots") else "0")
PY
)
CORE_REPOSITORY="${PROVIDER_FIELDS[0]:-}"
CORE_BRANCH="${PROVIDER_FIELDS[1]:-}"
CORE_REVISION="${PROVIDER_FIELDS[2]:-}"
SUPPORTS_BOTS="${PROVIDER_FIELDS[3]:-0}"
if [[ -z "$CORE_REPOSITORY" || -z "$CORE_BRANCH" ]]; then
    printf 'Provider %s has an incomplete core definition.\n' "$PROVIDER_ID" >&2
    exit 2
fi
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
if [[ ! -d "$CLIENT_PATH" ]]; then
    printf 'The selected client folder does not exist.\n' >&2
    exit 2
fi
CLIENT_EXECUTABLE=""
if [[ "$PROVIDER_ID" == azerothcore-coa ]]; then
    CLIENT_EXECUTABLE_NAMES=(Ascension.exe ascension.exe Wow-HD.exe Wow.exe wow.exe)
else
    CLIENT_EXECUTABLE_NAMES=(Wow-HD.exe Wow.exe wow.exe)
fi
for executable_name in "${CLIENT_EXECUTABLE_NAMES[@]}"; do
    if [[ -f "$CLIENT_PATH/$executable_name" ]]; then
        CLIENT_EXECUTABLE="$CLIENT_PATH/$executable_name"
        break
    fi
done
if [[ -z "$CLIENT_EXECUTABLE" ]]; then
    if [[ "$PROVIDER_ID" == azerothcore-coa ]]; then
        printf 'The selected CoA client folder does not contain Ascension.exe.\n' >&2
    else
        printf 'The selected folder does not contain Wow.exe.\n' >&2
    fi
    exit 2
fi
if [[ "$PROVIDER_ID" == azerothcore-coa && ! -f "$CLIENT_PATH/Extensions.dll" ]]; then
    printf 'The selected folder is not a supported CoA native-v4 client: Extensions.dll is missing.\n' >&2
    exit 2
fi
if [[ -n "$COA_REPACK_PATH" ]]; then
    [[ "$PROVIDER_ID" == azerothcore-coa ]] || { printf 'A CoA Repack folder can only be used with the CoA provider.\n' >&2; exit 2; }
    [[ -d "$COA_REPACK_PATH/Data" ]] || { printf 'The CoA Repack folder is missing Data: %s\n' "$COA_REPACK_PATH" >&2; exit 2; }
    [[ -f "$COA_REPACK_PATH/Database/Clean/databases.sql.gz" ]] || { printf 'The CoA Repack folder is missing Database/Clean/databases.sql.gz.\n' >&2; exit 2; }
    command -v gzip >/dev/null 2>&1 || { printf 'Required command is missing: gzip\n' >&2; exit 2; }
fi
for command in git podman python3; do
    command -v "$command" >/dev/null 2>&1 || { printf 'Required command is missing: %s\n' "$command" >&2; exit 2; }
done
for bundled_file in \
    "$SCRIPT_DIR/server-control-managed" \
    "$SCRIPT_DIR/coa-mysql-managed" \
    "$SCRIPT_DIR/autologin-managed" \
    "$SCRIPT_DIR/update-server-managed" \
    "$SCRIPT_DIR/repair-server-managed"; do
    [[ -f "$bundled_file" ]] || {
        printf 'Azeroth Control installation bundle is incomplete: missing %s\n' "$bundled_file" >&2
        exit 2
    }
done
if [[ "$SUPPORTS_BOTS" == 1 ]]; then
    for bundled_file in \
        "$PARTY_BRIDGE_SOURCE/VERSION" \
        "$PARTY_BRIDGE_SOURCE/src/mod_azeroth_control_bridge.cpp" \
        "$PARTY_BRIDGE_SOURCE/src/AzerothControlBridge.cpp"; do
        [[ -f "$bundled_file" ]] || {
            printf 'Azeroth Control installation bundle is incomplete: missing %s\n' "$bundled_file" >&2
            exit 2
        }
    done
fi

mkdir -p "$INSTALL_ROOT"/{servers,cache,backups,logs,state}
SERVER_ROOT="$INSTALL_ROOT/servers/$SERVER_ID"
CORE="$SERVER_ROOT/core"
CHECKPOINTS="$SERVER_ROOT/.install-checkpoints"
mkdir -p "$SERVER_ROOT" "$CHECKPOINTS"
if [[ "$(realpath "$CONFIG_FILE")" != "$(realpath -m "$SERVER_ROOT/install-selection.json")" ]]; then
    cp "$CONFIG_FILE" "$SERVER_ROOT/install-selection.json"
fi

if [[ ! -f "$CHECKPOINTS/core-source" ]]; then
    printf '[1/6] Downloading %s source…\n' "$PROVIDER_ID"
    git clone --filter=blob:none --single-branch --branch "$CORE_BRANCH" "$CORE_REPOSITORY" "$CORE"
    if [[ -n "$CORE_REVISION" ]]; then
        git -C "$CORE" checkout --detach "$CORE_REVISION"
    fi
    touch "$CHECKPOINTS/core-source"
else
    printf '[1/6] Core source already present; resuming.\n'
fi

if [[ ! -f "$CHECKPOINTS/modules" ]]; then
    printf '[2/6] Downloading selected open-source modules…\n'
    while IFS='|' read -r module_id repository branch revision directory; do
        [[ -n "$repository" ]] || continue
        target="$CORE/modules/$directory"
        if [[ ! -d "$target/.git" ]]; then
            clone_args=(--filter=blob:none)
            [[ -n "$branch" ]] && clone_args+=(--single-branch --branch "$branch")
            [[ -z "$revision" ]] && clone_args+=(--depth 1)
            git clone "${clone_args[@]}" "$repository" "$target"
            [[ -n "$revision" ]] && git -C "$target" checkout --detach "$revision"
        fi
    done < <(python3 - "$CONFIG_FILE" "$CATALOG_FILE" <<'PY'
import json, sys
selection = json.load(open(sys.argv[1]))
catalog = json.load(open(sys.argv[2]))
provider_id = selection.get("provider", catalog.get("defaultProvider", "azerothcore-playerbots"))
providers = catalog.get("providers") or [{"id": catalog.get("core", {}).get("id", "azerothcore-playerbots"), "modules": catalog.get("modules", [])}]
provider = next((item for item in providers if item.get("id") == provider_id), None)
if provider is None:
    raise SystemExit("Unknown installation provider: " + provider_id)
enabled = set(selection.get("modules", []))
enabled.update(module["id"] for module in provider.get("modules", []) if module.get("required"))
for module in provider.get("modules", []):
    if module["id"] in enabled and module.get("repository") and module["id"] != "playerbots":
        directory = module["repository"].rsplit("/", 1)[-1].removesuffix(".git")
        print("|".join((module["id"], module["repository"], module.get("branch", ""), module.get("revision", ""), directory)))
PY
)
    if [[ "$SUPPORTS_BOTS" == 1 ]]; then
        [[ -d "$CORE/modules/mod-playerbots/.git" ]] || git clone --filter=blob:none --depth 1 https://github.com/mod-playerbots/mod-playerbots.git "$CORE/modules/mod-playerbots"
    fi
    touch "$CHECKPOINTS/modules"
else
    printf '[2/6] Modules already present; resuming.\n'
fi

# Party Builder only applies to the Playerbots provider.
PARTY_BRIDGE_VERSION=none
if [[ "$SUPPORTS_BOTS" == 1 ]]; then
    PARTY_BRIDGE_TARGET="$CORE/modules/mod-azeroth-control-bridge"
    PARTY_BRIDGE_VERSION="$(tr -d '[:space:]' < "$PARTY_BRIDGE_SOURCE/VERSION")"
    INSTALLED_PARTY_BRIDGE_VERSION=""
    if [[ -f "$SERVER_ROOT/state/party-bridge-version" ]]; then
        INSTALLED_PARTY_BRIDGE_VERSION="$(tr -d '[:space:]' < "$SERVER_ROOT/state/party-bridge-version")"
    fi
    if [[ "$INSTALLED_PARTY_BRIDGE_VERSION" != "$PARTY_BRIDGE_VERSION" ]]; then
        mkdir -p "$PARTY_BRIDGE_TARGET"
        cp -a "$PARTY_BRIDGE_SOURCE/." "$PARTY_BRIDGE_TARGET/"
        if [[ -f "$CHECKPOINTS/images" ]]; then
            rm "$CHECKPOINTS/images"
        fi
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

AUTOBALANCE_ENABLED="$(python3 - "$CONFIG_FILE" <<'PY'
import json, sys
selection = json.load(open(sys.argv[1]))
print("1" if "autobalance" in selection.get("modules", []) else "0")
PY
)"
if [[ "$SUPPORTS_BOTS" != 1 ]]; then
    BOT_COUNT=0
fi
printf '[3/6] Preparing %s realm configuration…\n' "$PROFILE"
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
    coa) REALM_KEY=coa; REALM_NAME="Conquest of Azeroth"; START_LEVEL=1; WORLD_PORT=8085 ;;
    *) printf 'Unsupported profile: %s\n' "$PROFILE" >&2; exit 2 ;;
esac
if [[ "$PROVIDER_ID" == azerothcore-coa && "$PROFILE" != coa ]] || [[ "$PROVIDER_ID" != azerothcore-coa && "$PROFILE" == coa ]]; then
    printf 'Profile %s does not belong to provider %s.\n' "$PROFILE" "$PROVIDER_ID" >&2
    exit 2
fi
REALM_NAME="${SERVER_NAME:-$REALM_NAME}"
WORLD_IMAGE="localhost/azeroth-control/wotlk-worldserver:$IMAGE_TAG"
AUTH_IMAGE="localhost/azeroth-control/wotlk-authserver:$IMAGE_TAG"
IMPORT_IMAGE="localhost/azeroth-control/wotlk-db-import:$IMAGE_TAG"
DATA_IMAGE="localhost/azeroth-control/wotlk-client-data:$IMAGE_TAG"
TOOLS_IMAGE="localhost/azeroth-control/wotlk-tools:$IMAGE_TAG"
ENGINE_FINGERPRINT="$({
    git -C "$CORE" rev-parse HEAD
    find "$CORE/modules" -mindepth 1 -maxdepth 1 -type d -name 'mod-*' -print0 | sort -z | while IFS= read -r -d '' module; do
        printf '%s=' "$(basename "$module")"
        if [[ -d "$module/.git" ]]; then git -C "$module" rev-parse HEAD; else find "$module" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum; fi
    done
    printf 'provider=%s\nbridge=%s\nuid=%s\ngid=%s\n' "$PROVIDER_ID" "$PARTY_BRIDGE_VERSION" "$HOST_UID" "$HOST_GID"
} | sha256sum | cut -c1-20)"
SHARED_WORLD_IMAGE="localhost/azeroth-control/wotlk-worldserver:engine-$ENGINE_FINGERPRINT"
SHARED_AUTH_IMAGE="localhost/azeroth-control/wotlk-authserver:engine-$ENGINE_FINGERPRINT"
SHARED_IMPORT_IMAGE="localhost/azeroth-control/wotlk-db-import:engine-$ENGINE_FINGERPRINT"
SHARED_DATA_IMAGE="localhost/azeroth-control/wotlk-client-data:engine-$ENGINE_FINGERPRINT"
SHARED_TOOLS_IMAGE="localhost/azeroth-control/wotlk-tools:engine-$ENGINE_FINGERPRINT"
{
    printf 'PROVIDER_ID=%q\n' "$PROVIDER_ID"
    printf 'SUPPORTS_BOTS=%q\n' "$SUPPORTS_BOTS"
    printf 'AUTOBALANCE_ENABLED=%q\n' "$AUTOBALANCE_ENABLED"
    printf 'PROFILE=%q\n' "$PROFILE"
    printf 'REALM_KEY=%q\n' "$REALM_KEY"
    printf 'REALM_NAME=%q\n' "$REALM_NAME"
    printf 'START_LEVEL=%q\n' "$START_LEVEL"
    printf 'WORLD_PORT=%q\n' "$WORLD_PORT"
    printf 'BOT_COUNT=%q\n' "$BOT_COUNT"
    printf 'CLIENT_PATH=%q\n' "$CLIENT_PATH"
    printf 'COA_REPACK_PATH=%q\n' "$COA_REPACK_PATH"
    printf 'CLIENT_EXECUTABLE=%q\n' "$CLIENT_EXECUTABLE"
    printf 'AUTO_LOGIN=%q\n' "${AUTO_LOGIN:-0}"
    printf 'CONTAINER_PREFIX=%q\n' "$CONTAINER_PREFIX"
    printf 'DB_PASSWORD=%q\n' "$DB_PASSWORD"
    printf 'CHARACTER_DB=%q\n' acore_characters
    printf 'PLAYERBOTS_DB=%q\n' acore_playerbots
    printf 'WORLD_IMAGE=%q\n' "$WORLD_IMAGE"
    printf 'AUTH_IMAGE=%q\n' "$AUTH_IMAGE"
    printf 'IMPORT_IMAGE=%q\n' "$IMPORT_IMAGE"
    printf 'DATA_IMAGE=%q\n' "$DATA_IMAGE"
    printf 'TOOLS_IMAGE=%q\n' "$TOOLS_IMAGE"
} > "$SERVER_ROOT/install.env"
printf '%s\n' "$CONTAINER_PREFIX" > "$SERVER_ROOT/state/container-prefix"
cp "$SCRIPT_DIR/server-control-managed" "$SERVER_ROOT/bin/server-control"
cp "$SCRIPT_DIR/coa-mysql-managed" "$SERVER_ROOT/bin/coa-mysql"
cp "$SCRIPT_DIR/autologin-managed" "$SERVER_ROOT/bin/autologin"
cp "$SCRIPT_DIR/update-server-managed" "$SERVER_ROOT/bin/update-server"
cp "$SCRIPT_DIR/repair-server-managed" "$SERVER_ROOT/bin/repair-server"
if [[ "$SUPPORTS_BOTS" == 1 ]]; then
    mkdir -p "$SERVER_ROOT/state/bundled/mod-azeroth-control-bridge"
    cp -a "$PARTY_BRIDGE_SOURCE/." "$SERVER_ROOT/state/bundled/mod-azeroth-control-bridge/"
fi
chmod +x "$SERVER_ROOT/bin/server-control" "$SERVER_ROOT/bin/coa-mysql" "$SERVER_ROOT/bin/autologin" "$SERVER_ROOT/bin/update-server" "$SERVER_ROOT/bin/repair-server"
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
if [[ "$PROVIDER_ID" == azerothcore-coa && -d "$CLIENT_PATH/Data" ]]; then
    while IFS= read -r -d '' realm_config; do
        if [[ ! -f "$realm_config.azeroth-control-backup" ]]; then
            cp -a "$realm_config" "$realm_config.azeroth-control-backup"
        fi
        if grep -qi '^set realmlist ' "$realm_config"; then
            sed -i 's/^set realmlist .*/set realmlist 127.0.0.1/I' "$realm_config"
        else
            printf 'set realmlist 127.0.0.1\n' >> "$realm_config"
        fi
    done < <(find "$CLIENT_PATH/Data" -mindepth 2 -maxdepth 2 -type f -iname realmlist.wtf -print0)
fi
if [[ "$PROVIDER_ID" == azerothcore-coa ]]; then
    # Native-v4 Extensions.dll rejects a local world endpoint and corrupts an
    # active hook after a successful auth login. Use CoA's checksum-pinned
    # generator, never modify the source DLL in place, and retain the original
    # client file before atomically installing its verified output.
    ENDPOINT_PATCHER="$CORE/apps/client-compat/patch_world_endpoint.py"
    EXTENSIONS_DLL="$CLIENT_PATH/Extensions.dll"
    EXTENSIONS_SHA256="$(sha256sum "$EXTENSIONS_DLL" | awk '{print $1}')"
    case "$EXTENSIONS_SHA256" in
        f7b713095aab17a1e376f487290d4b7c4c18931635e4d91136d76db2592be8fa)
            [[ -f "$ENDPOINT_PATCHER" ]] || { printf 'The CoA client endpoint compatibility tool is missing from the server source.\n' >&2; exit 2; }
            EXTENSIONS_BACKUP="$CLIENT_PATH/Extensions.dll.azeroth-control-backup"
            [[ -f "$EXTENSIONS_BACKUP" ]] || cp -a "$EXTENSIONS_DLL" "$EXTENSIONS_BACKUP"
            EXTENSIONS_CANDIDATE="$CLIENT_PATH/.Extensions.dll.azeroth-control-$RANDOM-$RANDOM"
            printf 'Applying the verified CoA local world-endpoint compatibility fix…\n'
            python3 "$ENDPOINT_PATCHER" --input "$EXTENSIONS_DLL" --output "$EXTENSIONS_CANDIDATE"
            mv -f "$EXTENSIONS_CANDIDATE" "$EXTENSIONS_DLL"
            ;;
        9791801053f828d1ccdab1a4c17e64852d3ebe0fa708b91fa3674d0805d15bc8)
            printf 'CoA local world-endpoint compatibility fix is already installed.\n'
            ;;
        *)
            printf 'Unsupported CoA Extensions.dll checksum (%s). The client was not changed; use the matching pinned native-v4 client.\n' "$EXTENSIONS_SHA256" >&2
            exit 2
            ;;
    esac
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

# Checkpoint resumes must still receive fixes to the managed control scripts.
# The configuration checkpoint is intentionally retained so no client config,
# account input or already-built image work is discarded.
cp "$SCRIPT_DIR/server-control-managed" "$SERVER_ROOT/bin/server-control"
cp "$SCRIPT_DIR/coa-mysql-managed" "$SERVER_ROOT/bin/coa-mysql"
cp "$SCRIPT_DIR/autologin-managed" "$SERVER_ROOT/bin/autologin"
cp "$SCRIPT_DIR/update-server-managed" "$SERVER_ROOT/bin/update-server"
cp "$SCRIPT_DIR/repair-server-managed" "$SERVER_ROOT/bin/repair-server"
chmod +x "$SERVER_ROOT/bin/server-control" "$SERVER_ROOT/bin/coa-mysql" "$SERVER_ROOT/bin/autologin" "$SERVER_ROOT/bin/update-server" "$SERVER_ROOT/bin/repair-server"

if [[ ! -f "$CHECKPOINTS/images" ]]; then
    if podman image exists "$SHARED_WORLD_IMAGE" && podman image exists "$SHARED_AUTH_IMAGE" \
        && podman image exists "$SHARED_IMPORT_IMAGE" && podman image exists "$SHARED_DATA_IMAGE"; then
        printf '[4/6] Reusing compatible shared server engine %s…\n' "$ENGINE_FINGERPRINT"
    else
        printf '[4/6] Building shared server engine %s. This is the longest first-install step…\n' "$ENGINE_FINGERPRINT"
        BUILD_ARGS=(--layers --build-arg "USER_ID=$HOST_UID" --build-arg "GROUP_ID=$HOST_GID" --build-arg DOCKER_USER=acore -f "$DOCKERFILE")
        podman build "${BUILD_ARGS[@]}" --target worldserver -t "$SHARED_WORLD_IMAGE" "$CORE"
        podman build "${BUILD_ARGS[@]}" --target authserver -t "$SHARED_AUTH_IMAGE" "$CORE"
        podman build "${BUILD_ARGS[@]}" --target db-import -t "$SHARED_IMPORT_IMAGE" "$CORE"
        podman build "${BUILD_ARGS[@]}" --target client-data -t "$SHARED_DATA_IMAGE" "$CORE"
    fi
    podman tag "$SHARED_WORLD_IMAGE" "$WORLD_IMAGE"
    podman tag "$SHARED_AUTH_IMAGE" "$AUTH_IMAGE"
    podman tag "$SHARED_IMPORT_IMAGE" "$IMPORT_IMAGE"
    podman tag "$SHARED_DATA_IMAGE" "$DATA_IMAGE"
    touch "$CHECKPOINTS/images"
    if [[ "$SUPPORTS_BOTS" == 1 ]]; then
        printf '%s\n' "$PARTY_BRIDGE_VERSION" > "$SERVER_ROOT/state/party-bridge-version"
    fi
else
    printf '[4/6] Container images already exist; resuming.\n'
fi

if [[ "$PROVIDER_ID" == azerothcore-coa ]]; then
    if ! podman image exists "$SHARED_TOOLS_IMAGE"; then
        printf '[4/6] Preparing the CoA client-data extractor…\n'
        BUILD_ARGS=(--layers --build-arg "USER_ID=$HOST_UID" --build-arg "GROUP_ID=$HOST_GID" --build-arg DOCKER_USER=acore -f "$DOCKERFILE")
        podman build "${BUILD_ARGS[@]}" --target tools -t "$SHARED_TOOLS_IMAGE" "$CORE"
    fi
    podman tag "$SHARED_TOOLS_IMAGE" "$TOOLS_IMAGE"
    # Existing CoA installations need the complete matching client DBC tree,
    # including Ascension's collection records. Force one managed restart when
    # that revised migration has not completed.
    if [[ ! -f "$SERVER_ROOT/state/coa-client-dbc-v3-installed" ]]; then
        rm -f "$CHECKPOINTS/health-check"
        "$SERVER_ROOT/bin/server-control" stop
    fi
fi

if [[ ! -f "$CHECKPOINTS/health-check" ]]; then
    printf '[5/6] Creating databases, client data and running the health check…\n'
    for port in 3724 "$WORLD_PORT"; do
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

printf '[6/6] Finalizing the local server…\n'
touch "$CHECKPOINTS/complete"
python3 - "$CONFIG_FILE" "$SERVER_ROOT/install-selection.json" "$CLIENT_EXECUTABLE" <<'PY'
import json, sys
client_executable = sys.argv[3]
for name in sys.argv[1:3]:
    try:
        with open(name, encoding="utf-8") as source:
            value = json.load(source)
        value["accountPassword"] = ""
        value["clientExecutable"] = client_executable
        value["steamShortcuts"] = False
        value["steamExecutable"] = ""
        temporary = name + ".tmp"
        with open(temporary, "w", encoding="utf-8") as target:
            json.dump(value, target, indent=2)
        import os
        os.replace(temporary, name)
    except FileNotFoundError:
        pass
PY
printf 'Installation completed. %s is online and ready.\n' "$REALM_NAME"
