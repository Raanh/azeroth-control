const { app, BrowserWindow, dialog, ipcMain, screen, shell } = require('electron');
const { spawn, spawnSync } = require('child_process');
const fs = require('fs');
const crypto = require('crypto');
const os = require('os');
const path = require('path');
const net = require('net');

const PORT = 8742;
let mainWindow;
let backend;
let installChild;
let shuttingDown = false;
let previousCpuSample;
let lastKeyboardOpen = 0;
let gameChild;

const addonCatalog = [
  {
    id: 'consoleportlk', name: 'ConsolePortLK', version: '1.5.0-rc2', category: 'Gamepad',
    description: 'Controller-first action bars, menus and navigation for WoW 3.3.5a.',
    note: 'Recommended for Gaming Mode. Pair it with the Gamepad leoaviana ConsolePortLK Steam Input layout.',
    sourceUrl: 'https://github.com/leoaviana/ConsolePortLK',
    downloadUrl: 'https://github.com/leoaviana/ConsolePortLK/releases/download/1.5.0-rc2/ConsolePortLK-1.5.0-rc2.zip',
    sha256: '9ee20bb1f3c5c5b8d45fcc5980a07bb90d49a707e120613453177c05fea6497f',
    folders: ['ConsolePort', 'ConsolePortAdvanced', 'ConsolePortBar', 'ConsolePortHelp', 'ConsolePortKeyboard', 'ConsolePortLoader', 'ConsolePortUI_Loot', 'ConsolePortUI_Menu'],
  },
  {
    id: 'questiex', name: 'Questie-X', version: '1.6.4', category: 'Questing',
    description: 'Quest objectives, map markers and tracker support for legacy WoW clients.',
    note: 'Universal private-server build with a 3.3.5a-compatible table of contents.',
    sourceUrl: 'https://github.com/Xurkon/Questie-X',
    downloadUrl: 'https://github.com/Xurkon/Questie-X/releases/download/v1.6.4/Questie-X-1.6.4.zip',
    sha256: '621bf504c43da8d7e34c06b48aeb7dd85cb45b568d0f6a8630a7cfea4143f65f',
    folders: ['Questie-X'],
  },
];

const resources = () => app.isPackaged ? process.resourcesPath : path.resolve(__dirname, '..');
const stateDir = () => path.join(app.getPath('userData'));
const stateFile = () => path.join(stateDir(), 'state.json');
const catalogFile = () => path.join(resources(), 'manifests', 'catalog.json');
const defaultInstallRoot = () => path.join(os.homedir(), '.local', 'share', 'azeroth-control');

function managedServerPaths() {
  const root = path.join(defaultInstallRoot(), 'servers');
  try {
    return fs.readdirSync(root, { withFileTypes: true }).filter((entry) => entry.isDirectory()).map((entry) => path.join(root, entry.name));
  } catch { return []; }
}
function syncManagedScripts() {
  for (const managedPath of managedServerPaths()) {
    const bin = path.join(managedPath, 'bin');
    if (!fs.existsSync(bin)) continue;
    for (const [sourceName, targetName] of [['server-control-managed', 'server-control'], ['launch-wow-managed', 'launch-wow']]) {
      const source = path.join(resources(), 'scripts', sourceName);
      const target = path.join(bin, targetName);
      if (!fs.existsSync(source)) continue;
      fs.copyFileSync(source, target);
      fs.chmodSync(target, 0o755);
    }
  }
}

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}
function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = file + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2));
  fs.renameSync(temporary, file);
}
function readState() {
  const state = readJson(stateFile(), { schemaVersion: 1, onboardingComplete: false, activeInstallationId: null, installations: [] });
  let changed = false;
  for (const managedPath of managedServerPaths()) {
    if (!fs.existsSync(path.join(managedPath, '.install-checkpoints', 'complete')) || state.installations.some((item) => item.path === managedPath)) continue;
    const selection = readJson(path.join(managedPath, 'install-selection.json'), {});
    const id = 'managed-' + Buffer.from(managedPath).toString('hex').slice(-12);
    state.installations.push({ id, name: selection.serverName || 'Azeroth ' + (selection.profile || 'server'), path: managedPath, provider: 'azerothcore-playerbots', imported: false, createdAt: new Date().toISOString() });
    state.activeInstallationId = id;
    state.onboardingComplete = true;
    changed = true;
  }
  if (changed) writeJson(stateFile(), state);
  return state;
}
function commandAvailable(command) {
  return spawnSync('sh', ['-lc', 'command -v "$1" >/dev/null 2>&1', 'sh', command]).status === 0;
}
function diskInfo(target) {
  try {
    const stats = fs.statfsSync(target);
    return { path: target, freeBytes: Number(stats.bavail) * Number(stats.bsize), totalBytes: Number(stats.blocks) * Number(stats.bsize) };
  } catch { return { path: target, freeBytes: 0, totalBytes: 0 }; }
}
function detectInstallations() {
  const candidates = [...new Set([
    path.join(os.homedir(), 'Applications', 'azerothcore-playerbots'),
    ...managedServerPaths(),
  ])];
  return candidates.filter((candidate) => fs.existsSync(path.join(candidate, 'bin', 'server-control'))).map((candidate) => {
    const selectionFile = path.join(candidate, 'install-selection.json');
    const managed = fs.existsSync(selectionFile);
    const resumable = managed && !fs.existsSync(path.join(candidate, '.install-checkpoints', 'complete'));
    return {
      path: candidate,
      name: resumable ? 'Incomplete AzerothCore installation' : path.basename(candidate) === 'azerothcore-playerbots' ? 'Existing AzerothCore Playerbots' : path.basename(candidate),
      realms: resumable ? 0 : fs.existsSync(path.join(candidate, 'runtime', 'endgame')) ? 3 : 1,
      resumable,
      selection: resumable ? readJson(selectionFile, null) : null,
    };
  });
}
function activeRoot() {
  const state = readState();
  const installation = state.installations.find((item) => item.id === state.activeInstallationId);
  return installation?.path || detectInstallations()[0]?.path || path.join(os.homedir(), 'Applications', 'azerothcore-playerbots');
}
function activeClientPath() {
  const selection = readJson(path.join(activeRoot(), 'install-selection.json'), {});
  const candidate = selection.clientPath || (() => {
    try {
      const environment = fs.readFileSync(path.join(activeRoot(), 'install.env'), 'utf8');
      return environment.match(/^CLIENT_PATH=(.*)$/m)?.[1]?.replace(/^['"]|['"]$/g, '');
    } catch { return ''; }
  })();
  if (!candidate || !fs.existsSync(path.join(candidate, 'Wow.exe'))) throw new Error('The active server does not have a valid WoW client path.');
  return fs.realpathSync(candidate);
}
function readCString(buffer, offset) {
  const end = buffer.indexOf(0, offset);
  if (end < 0) throw new Error('Invalid Steam shortcuts file.');
  return [buffer.toString('utf8', offset, end), end + 1];
}
function readVdfObject(buffer, initialOffset) {
  const value = {};
  let offset = initialOffset;
  while (offset < buffer.length) {
    const type = buffer[offset++];
    if (type === 8) return [value, offset];
    let key;
    [key, offset] = readCString(buffer, offset);
    if (type === 0) [value[key], offset] = readVdfObject(buffer, offset);
    else if (type === 1) [value[key], offset] = readCString(buffer, offset);
    else if (type === 2) { value[key] = buffer.readUInt32LE(offset); offset += 4; }
    else if (type === 7) { value[key] = buffer.readBigUInt64LE(offset); offset += 8; }
    else throw new Error(`Unsupported Steam shortcut value type ${type}.`);
  }
  return [value, offset];
}
function steamShortcuts() {
  const userdata = path.join(os.homedir(), '.local', 'share', 'Steam', 'userdata');
  const entries = [];
  try {
    for (const user of fs.readdirSync(userdata)) {
      const file = path.join(userdata, user, 'config', 'shortcuts.vdf');
      if (!fs.existsSync(file)) continue;
      const buffer = fs.readFileSync(file);
      if (!buffer.length || buffer[0] !== 0) continue;
      let offset = 1;
      [, offset] = readCString(buffer, offset);
      const [root] = readVdfObject(buffer, offset);
      entries.push(...Object.values(root).filter((item) => item && typeof item === 'object'));
    }
  } catch {}
  return entries;
}
function activeClientSteamShortcut() {
  const clientPath = activeClientPath();
  const selection = readJson(path.join(activeRoot(), 'install-selection.json'), {});
  const managedExecutable = selection.steamExecutable ? path.resolve(selection.steamExecutable) : '';
  const normalize = (value) => String(value || '').replaceAll('"', '').replaceAll('\\\\', '/');
  const matches = steamShortcuts().filter((entry) => {
    const executable = normalize(entry.Exe);
    return executable.startsWith(clientPath + '/') || (managedExecutable && executable === managedExecutable);
  });
  return matches.sort((left, right) => {
    const score = (entry) => /wow-hd\.exe$/i.test(normalize(entry.Exe)) ? 4 : /wow\.exe$/i.test(normalize(entry.Exe)) ? 3 : normalize(entry.Exe) === managedExecutable ? 2 : 1;
    return score(right) - score(left);
  })[0] || null;
}
function recommendedUiScale() {
  const width = screen.getPrimaryDisplay().size.width;
  return width >= 3200 ? 1.75 : width >= 2500 ? 1.5 : width >= 1800 ? 1.25 : 1;
}
function addonState() {
  const clientPath = activeClientPath();
  const steamShortcut = activeClientSteamShortcut();
  const addonsPath = path.join(clientPath, 'Interface', 'AddOns');
  const recordsPath = path.join(clientPath, 'Interface', '.azeroth-control-addons.json');
  const records = readJson(recordsPath, {});
  return {
    clientPath,
    addonsPath,
    steamInput: steamShortcut ? {
      found: true,
      shortcutName: String(steamShortcut.AppName || 'WoW'),
      gameId: String(steamShortcut.appid),
    } : { found: false, shortcutName: '', gameId: '' },
    addons: addonCatalog.map((addon) => ({
      ...addon,
      installed: addon.folders.every((folder) => fs.existsSync(path.join(addonsPath, folder))),
      installedVersion: records[addon.id]?.version || null,
    })),
  };
}
function validateZipEntries(archive) {
  const listing = spawnSync('python3', ['-c', 'import sys,zipfile; print("\\n".join(zipfile.ZipFile(sys.argv[1]).namelist()))', archive], { encoding: 'utf8', timeout: 30000 });
  if (listing.status !== 0) throw new Error('The downloaded addon archive is invalid.');
  for (const entry of listing.stdout.split('\n').filter(Boolean)) {
    const normalized = entry.replaceAll('\\\\', '/');
    if (normalized.startsWith('/') || normalized.split('/').includes('..')) throw new Error('The addon archive contains an unsafe path.');
  }
}
async function installAddon(addonId) {
  const addon = addonCatalog.find((item) => item.id === addonId);
  if (!addon) throw new Error('Unknown addon.');
  const { clientPath, addonsPath } = addonState();
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'azeroth-addon-'));
  try {
    const response = await fetch(addon.downloadUrl, { redirect: 'follow' });
    if (!response.ok) throw new Error(`Addon download failed (${response.status}).`);
    const data = Buffer.from(await response.arrayBuffer());
    if (data.length > 200 * 1024 * 1024) throw new Error('The addon archive is unexpectedly large.');
    const digest = crypto.createHash('sha256').update(data).digest('hex');
    if (digest !== addon.sha256) throw new Error('Addon checksum verification failed.');
    const archive = path.join(temporary, 'addon.zip');
    const extracted = path.join(temporary, 'extracted');
    fs.writeFileSync(archive, data);
    fs.mkdirSync(extracted);
    validateZipEntries(archive);
    const unpack = spawnSync('python3', ['-m', 'zipfile', '-e', archive, extracted], { encoding: 'utf8', timeout: 120000 });
    if (unpack.status !== 0) throw new Error(unpack.stderr || 'Unable to extract the addon.');
    fs.mkdirSync(addonsPath, { recursive: true });
    const backupRoot = path.join(clientPath, 'Interface', '.azeroth-control-backups', `${addon.id}-${Date.now()}`);
    for (const folder of addon.folders) {
      const source = path.join(extracted, folder);
      if (!fs.existsSync(source)) throw new Error(`The release is missing ${folder}.`);
      const target = path.join(addonsPath, folder);
      if (fs.existsSync(target)) {
        fs.mkdirSync(backupRoot, { recursive: true });
        fs.renameSync(target, path.join(backupRoot, folder));
      }
      fs.cpSync(source, target, { recursive: true, force: false });
    }
    const recordsPath = path.join(clientPath, 'Interface', '.azeroth-control-addons.json');
    const records = readJson(recordsPath, {});
    records[addon.id] = { version: addon.version, installedAt: new Date().toISOString(), folders: addon.folders };
    writeJson(recordsPath, records);
    return addonState();
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}
function removeAddon(addonId) {
  const addon = addonCatalog.find((item) => item.id === addonId);
  if (!addon) throw new Error('Unknown addon.');
  const { clientPath, addonsPath } = addonState();
  const backupRoot = path.join(clientPath, 'Interface', '.azeroth-control-backups', `${addon.id}-removed-${Date.now()}`);
  for (const folder of addon.folders) {
    const target = path.join(addonsPath, folder);
    if (!fs.existsSync(target)) continue;
    fs.mkdirSync(backupRoot, { recursive: true });
    fs.renameSync(target, path.join(backupRoot, folder));
  }
  const recordsPath = path.join(clientPath, 'Interface', '.azeroth-control-addons.json');
  const records = readJson(recordsPath, {});
  delete records[addon.id];
  writeJson(recordsPath, records);
  return addonState();
}
function waitForPort(port, timeout = 8000) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const attempt = () => {
      const socket = net.createConnection({ host: '127.0.0.1', port });
      socket.once('connect', () => { socket.destroy(); resolve(); });
      socket.once('error', () => {
        socket.destroy();
        if (Date.now() - started > timeout) reject(new Error('Local service did not start'));
        else setTimeout(attempt, 120);
      });
    };
    attempt();
  });
}
function startBackend() {
  const script = path.join(resources(), 'backend', 'server.py');
  backend = spawn('python3', [script], {
    env: { ...process.env, AZEROTH_CONTROL_PORT: String(PORT), AZEROTH_SERVER_ROOT: activeRoot(), AZEROTH_CONTROL_BACKUP_ROOT: path.join(stateDir(), 'backups') },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const log = path.join(stateDir(), 'logs', 'desktop.log');
  fs.mkdirSync(path.dirname(log), { recursive: true });
  const stream = fs.createWriteStream(log, { flags: 'a' });
  backend.stdout.pipe(stream);
  backend.stderr.pipe(stream);
}
function stopBackend() {
  if (backend && !backend.killed) {
    backend.kill('SIGTERM');
    backend = null;
  }
}
function stopBackendAndWait() {
  const child = backend;
  backend = null;
  if (!child || child.killed || child.exitCode !== null) return Promise.resolve();
  return new Promise((resolve) => {
    let finished = false;
    const done = () => { if (!finished) { finished = true; resolve(); } };
    child.once('exit', done);
    child.kill('SIGTERM');
    setTimeout(() => { if (child.exitCode === null) child.kill('SIGKILL'); done(); }, 2500).unref();
  });
}
function cpuTelemetry() {
  const totals = os.cpus().reduce((sum, cpu) => {
    const total = Object.values(cpu.times).reduce((value, time) => value + time, 0);
    return { idle: sum.idle + cpu.times.idle, total: sum.total + total };
  }, { idle: 0, total: 0 });
  let percent = 0;
  if (previousCpuSample) {
    const totalDelta = totals.total - previousCpuSample.total;
    const idleDelta = totals.idle - previousCpuSample.idle;
    percent = totalDelta > 0 ? Math.max(0, Math.min(100, Math.round((1 - idleDelta / totalDelta) * 100))) : 0;
  }
  previousCpuSample = totals;
  return percent;
}
function stopInstaller() {
  if (installChild && installChild.exitCode === null) {
    try { process.kill(-installChild.pid, 'SIGTERM'); } catch {}
    installChild = null;
  }
}
function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  stopInstaller();
  stopBackend();
  app.quit();
  setTimeout(() => app.exit(0), 1500).unref();
}
async function createWindow() {
  syncManagedScripts();
  startBackend();
  await waitForPort(PORT);
  const display = screen.getPrimaryDisplay();
  const steamSession = process.platform === 'linux' && Boolean(
    process.env.AZEROTH_FULLSCREEN === '1' || process.env.SteamAppId || process.env.SteamGameId || process.env.GAMESCOPE_WAYLAND_DISPLAY,
  );
  mainWindow = new BrowserWindow({
    width: Math.max(1280, display.workAreaSize.width),
    height: Math.max(720, display.workAreaSize.height),
    minWidth: 960,
    minHeight: 600,
    backgroundColor: '#090e13',
    autoHideMenuBar: true,
    fullscreen: steamSession,
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  mainWindow.loadURL('http://127.0.0.1:' + PORT);
  mainWindow.webContents.once('did-finish-load', () => mainWindow?.webContents.setZoomFactor(recommendedUiScale()));
  mainWindow.webContents.setWindowOpenHandler(({ url }) => { if (url.startsWith('https://')) shell.openExternal(url); return { action: 'deny' }; });
}

ipcMain.handle('catalog', () => readJson(catalogFile(), { profiles: [], modules: [] }));
ipcMain.handle('state-get', () => readState());
ipcMain.handle('system-info', () => {
  const root = defaultInstallRoot();
  const parent = fs.existsSync(root) ? root : os.homedir();
  return {
    platform: process.platform,
    release: os.release(),
    hostname: os.hostname(),
    cpuModel: os.cpus()[0]?.model || 'Unknown CPU',
    cpuThreads: os.cpus().length,
    memoryBytes: os.totalmem(),
    disk: diskInfo(parent),
    defaultInstallRoot: root,
    dependencies: {
      podman: commandAvailable('podman'),
      distrobox: commandAvailable('distrobox'),
      git: commandAvailable('git'),
      python: commandAvailable('python3'),
      steam: commandAvailable('steam'),
    },
  };
});
ipcMain.handle('install-telemetry', () => ({
  cpuPercent: cpuTelemetry(),
  memoryUsedBytes: os.totalmem() - os.freemem(),
  memoryTotalBytes: os.totalmem(),
}));
ipcMain.handle('ui-metrics', () => {
  const display = screen.getPrimaryDisplay();
  return { width: display.size.width, height: display.size.height, recommendedScale: recommendedUiScale() };
});
ipcMain.handle('ui-scale-set', (_event, requested) => {
  const factor = Number(requested) > 0 ? Math.max(1, Math.min(2, Number(requested))) : recommendedUiScale();
  mainWindow?.webContents.setZoomFactor(factor);
  return factor;
});
ipcMain.handle('choose-directory', async (_event, kind) => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: kind === 'client' ? 'Select your WoW 3.3.5a folder' : 'Select installation location',
    properties: ['openDirectory', 'createDirectory'],
  });
  return result.canceled ? null : result.filePaths[0];
});
ipcMain.handle('client-validate', (_event, clientPath) => {
  if (!clientPath || typeof clientPath !== 'string') return { ok: false, message: 'Choose a WoW client folder.' };
  let canonical;
  try { canonical = fs.realpathSync(clientPath); } catch { return { ok: false, message: 'The selected folder does not exist.' }; }
  const executable = ['Wow.exe', 'wow.exe'].map((name) => path.join(canonical, name)).find(fs.existsSync);
  if (!executable) return { ok: false, message: 'Wow.exe was not found in this folder.' };
  if (!fs.statSync(executable).isFile()) return { ok: false, message: 'The selected Wow.exe is not a file.' };
  const dataDirectory = ['Data', 'data'].map((name) => path.join(canonical, name)).find(fs.existsSync);
  if (!dataDirectory) return { ok: false, message: 'The WoW Data folder was not found.' };
  const configPath = path.join(canonical, 'WTF', 'Config.wtf');
  return {
    ok: true,
    path: canonical,
    message: fs.existsSync(configPath) ? 'Client ready. Existing Config.wtf will be backed up before configuration.' : 'Client ready. A local Config.wtf will be created.',
  };
});
ipcMain.handle('keyboard-open', () => {
  if (process.platform !== 'linux') return false;
  if (Date.now() - lastKeyboardOpen < 1500) return false;
  lastKeyboardOpen = Date.now();
  const child = spawn('steam', ['-ifrunning', 'steam://open/keyboard'], { detached: true, stdio: 'ignore' });
  child.unref();
  return true;
});
ipcMain.handle('game-launch', async () => {
  const steamShortcut = activeClientSteamShortcut();
  if (steamShortcut?.appid) {
    const control = path.join(activeRoot(), 'bin', 'server-control');
    const status = spawnSync(control, ['status'], { encoding: 'utf8', timeout: 15000 });
    if (status.status !== 0) {
      await new Promise((resolve, reject) => {
        const start = spawn(control, ['start'], { env: { ...process.env }, stdio: 'ignore' });
        start.once('error', reject);
        start.once('exit', (code) => code === 0 ? resolve() : reject(new Error('The server could not be started.')));
      });
    }
    const steamGameId = (BigInt(steamShortcut.appid) << 32n) | 0x02000000n;
    const child = spawn('steam', ['-ifrunning', `steam://rungameid/${steamGameId}`], { detached: true, stdio: 'ignore' });
    child.unref();
    return { ok: true, message: `Launching ${steamShortcut.AppName || 'WoW-HD'} through Steam.` };
  }
  if (gameChild && gameChild.exitCode === null) return { ok: true, message: 'WoW is already running.' };
  const launcher = path.join(activeRoot(), 'bin', 'launch-wow');
  if (!fs.existsSync(launcher)) throw new Error('The WoW launcher is missing from the active server.');
  const restoreFullscreen = Boolean(mainWindow?.isFullScreen());
  mainWindow?.blur();
  mainWindow?.hide();
  await new Promise((resolve) => setTimeout(resolve, 450));
  const logPath = path.join(stateDir(), 'logs', 'game-launch.log');
  fs.mkdirSync(path.dirname(logPath), { recursive: true });
  const log = fs.openSync(logPath, 'a');
  gameChild = spawn(launcher, [], { detached: true, env: { ...process.env, STEAM_COMPAT_APP_ID: process.env.SteamAppId || '' }, stdio: ['ignore', log, log] });
  let finished = false;
  const restoreControl = () => {
    if (finished) return;
    finished = true;
    try { fs.closeSync(log); } catch {}
    gameChild = null;
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show();
      if (restoreFullscreen) mainWindow.setFullScreen(true);
      mainWindow.focus();
    }
  };
  gameChild.once('exit', restoreControl);
  gameChild.once('error', restoreControl);
  return { ok: true, message: 'Launching WoW in borderless windowed mode.' };
});
ipcMain.handle('addons-get', () => addonState());
ipcMain.handle('steam-input-open', () => {
  const shortcut = activeClientSteamShortcut();
  if (!shortcut?.appid) throw new Error('No Steam entry was found for the active WoW client.');
  const child = spawn('steam', ['-ifrunning', `steam://controllerconfig/${shortcut.appid}`], { detached: true, stdio: 'ignore' });
  child.unref();
  return { ok: true, shortcutName: String(shortcut.AppName || 'WoW') };
});
ipcMain.handle('addon-install', (_event, addonId) => installAddon(addonId));
ipcMain.handle('addon-remove', (_event, addonId) => removeAddon(addonId));
ipcMain.handle('installations-detect', () => detectInstallations());
ipcMain.handle('installation-import', (_event, installPath) => {
  const canonical = fs.realpathSync(installPath);
  if (!fs.existsSync(path.join(canonical, 'bin', 'server-control'))) throw new Error('This folder does not contain a supported server-control installation.');
  const state = readState();
  const id = 'imported-' + Buffer.from(canonical).toString('hex').slice(-12);
  const entry = { id, name: path.basename(canonical), path: canonical, provider: 'azerothcore-playerbots', imported: true, createdAt: new Date().toISOString() };
  state.installations = [...state.installations.filter((item) => item.path !== canonical), entry];
  state.activeInstallationId = id;
  state.onboardingComplete = true;
  writeJson(stateFile(), state);
  return entry;
});
ipcMain.handle('installation-select', (_event, id) => {
  const state = readState();
  if (!state.installations.some((item) => item.id === id)) throw new Error('Server installation was not found.');
  const current = state.installations.find((item) => item.id === state.activeInstallationId);
  if (current && current.id !== id) {
    const control = path.join(current.path, 'bin', 'server-control');
    if (fs.existsSync(control)) spawnSync(control, ['stop'], { timeout: 90000, stdio: 'ignore' });
  }
  state.activeInstallationId = id;
  state.onboardingComplete = true;
  writeJson(stateFile(), state);
  return state;
});
ipcMain.handle('installation-remove', async (_event, id, deleteFiles) => {
  const state = readState();
  const entry = state.installations.find((item) => item.id === id);
  if (!entry) throw new Error('Server installation was not found.');
  if (deleteFiles && entry.imported) throw new Error('Imported server files must be removed manually. The app can only forget this server.');

  let canonical;
  if (deleteFiles) {
    canonical = fs.realpathSync(entry.path);
    const managedRoot = path.resolve(defaultInstallRoot(), 'servers') + path.sep;
    if (!canonical.startsWith(managedRoot) || canonical === path.resolve(defaultInstallRoot(), 'servers')) {
      throw new Error('Refusing to delete a folder outside the managed server directory.');
    }
  }

  if (state.activeInstallationId === id) {
    const control = path.join(entry.path, 'bin', 'server-control');
    if (fs.existsSync(control)) spawnSync(control, ['stop'], { timeout: 90000, stdio: 'ignore' });
    stopBackend();
  }
  if (deleteFiles) {
    const environment = fs.readFileSync(path.join(canonical, 'install.env'), 'utf8');
    const value = (key) => environment.match(new RegExp(`^${key}=([^\\n]+)$`, 'm'))?.[1];
    const prefix = value('CONTAINER_PREFIX');
    if (prefix) {
      spawnSync('podman', ['volume', 'rm', '-f', `${prefix}-database-data`, `${prefix}-client-data`], { timeout: 90000, stdio: 'ignore' });
      const images = ['WORLD_IMAGE', 'AUTH_IMAGE', 'IMPORT_IMAGE', 'DATA_IMAGE'].map(value).filter(Boolean);
      if (images.length) spawnSync('podman', ['rmi', '-f', ...images], { timeout: 90000, stdio: 'ignore' });
    }
    await shell.trashItem(canonical);
  }

  state.installations = state.installations.filter((item) => item.id !== id);
  if (state.activeInstallationId === id) state.activeInstallationId = state.installations[0]?.id || null;
  state.onboardingComplete = state.installations.length > 0;
  writeJson(stateFile(), state);
  return state;
});
ipcMain.handle('install-plan', (_event, selection) => {
  const catalog = readJson(catalogFile(), { core: {}, profiles: [], modules: [] });
  const profile = catalog.profiles.find((item) => item.id === selection.profile);
  const modules = catalog.modules.filter((item) => selection.modules.includes(item.id));
  const requiredBytes = Number(catalog.core.estimatedInstalledBytes || 0) + Number(profile?.estimatedBytes || 0) + modules.reduce((sum, item) => sum + Number(item.estimatedBytes || 0), 0);
  const disk = diskInfo(fs.existsSync(selection.installRoot) ? selection.installRoot : path.dirname(selection.installRoot));
  return { requiredBytes, downloadBytes: Number(catalog.core.estimatedDownloadBytes || 0), freeBytes: disk.freeBytes, enoughSpace: disk.freeBytes > requiredBytes * 1.15, steps: ['Prepare writable folders', 'Download open-source core and modules', 'Build server containers', 'Extract data from your local client', 'Create realm databases', 'Add Steam shortcuts', 'Run health check'] };
});
ipcMain.handle('install-start', async (_event, selection) => {
  if (installChild && installChild.exitCode === null) throw new Error('An installation is already running.');
  const currentState = readState();
  const current = currentState.installations.find((item) => item.id === currentState.activeInstallationId);
  const currentControl = current && path.join(current.path, 'bin', 'server-control');
  if (currentControl && fs.existsSync(currentControl)) spawnSync(currentControl, ['stop'], { timeout: 90000, stdio: 'ignore' });
  const installer = path.join(resources(), 'scripts', 'install-server.sh');
  const configDir = path.join(stateDir(), 'jobs');
  fs.mkdirSync(configDir, { recursive: true });
  const configPath = path.join(configDir, 'install-' + Date.now() + '.json');
  writeJson(configPath, selection);
  const installLogDir = path.join(stateDir(), 'logs');
  const installLogPath = path.join(installLogDir, 'installation.log');
  fs.mkdirSync(installLogDir, { recursive: true });
  const installLog = fs.createWriteStream(installLogPath, { flags: 'a' });
  installLog.write(`\n[${new Date().toISOString()}] Starting or resuming installation\n`);
  const child = spawn('bash', [installer, configPath], { env: { ...process.env, AZEROTH_CATALOG: catalogFile() }, detached: true });
  installChild = child;
  child.stdout.on('data', (data) => { installLog.write(data); mainWindow?.webContents.send('install-progress', { type: 'output', message: String(data).trim() }); });
  child.stderr.on('data', (data) => { installLog.write(data); mainWindow?.webContents.send('install-progress', { type: 'output', level: 'error', message: String(data).trim() }); });
  child.on('exit', (code) => {
    if (code === 0) {
      const serverRoot = path.join(selection.installRoot, 'servers', selection.serverId || 'default');
      const state = readState();
      const id = 'managed-' + Buffer.from(serverRoot).toString('hex').slice(-12);
      const entry = { id, name: selection.serverName || 'Azeroth ' + selection.profile, path: serverRoot, provider: 'azerothcore-playerbots', imported: false, createdAt: new Date().toISOString() };
      state.installations = [...state.installations.filter((item) => item.path !== serverRoot), entry];
      state.activeInstallationId = id;
      state.onboardingComplete = true;
      writeJson(stateFile(), state);
    }
    installLog.write(`[${new Date().toISOString()}] Installer exited with code ${code}\n`);
    installLog.end();
    installChild = null;
    mainWindow?.webContents.send('install-progress', { type: 'complete', ok: code === 0, message: code === 0 ? 'Installation completed.' : 'Installation stopped. Fix the reported issue and run the same plan again to resume.' });
  });
  return { started: true, configPath };
});
ipcMain.handle('onboarding-finish', () => { const state = readState(); state.onboardingComplete = true; writeJson(stateFile(), state); return state; });
ipcMain.handle('onboarding-reset', () => { const state = readState(); state.onboardingComplete = false; writeJson(stateFile(), state); return state; });
ipcMain.handle('app-restart', async () => { await stopBackendAndWait(); app.relaunch(); app.exit(0); });
ipcMain.handle('app-quit', () => shutdown());

app.whenReady().then(createWindow).catch((error) => { dialog.showErrorBox('Azeroth Control', error.message); app.quit(); });
app.on('window-all-closed', () => app.quit());
app.on('before-quit', stopBackend);
for (const signal of ['SIGTERM', 'SIGINT', 'SIGHUP']) process.on(signal, shutdown);
