import { useCallback, useEffect, useRef, useState } from 'react';

type View = 'dashboard' | 'realms' | 'bots' | 'queues' | 'party' | 'world' | 'addons' | 'maintenance' | 'logs';
type Realm = 'progression' | 'endgame' | 'qa';
type Status = { realm: Realm; realmName: string; availableRealms: Realm[]; port: number; state: 'online' | 'offline'; uptime: string; bots: number; cpu: string; memory: string; job: { running: boolean; label: string; ok: boolean; message: string } };
type Settings = { realm: Realm; botCount: number; xpRate: number; dropRate: number; spawnRate: number; xpKill: number; xpQuest: number; xpExplore: number; respawnRate: number; dungeonDeserter: boolean; bgDeserter: boolean; joinLfg: boolean; joinBg: boolean; autoJoinBg: boolean; levelBrackets: boolean; dynamicBrackets: boolean; syncFactions: boolean; playerWeight: number; aoeLoot: boolean; aoeLootRange: number };
type Installation = { id: string; name: string; path: string; provider: string; imported: boolean; createdAt: string };
type DesktopState = { activeInstallationId: string | null; installations: Installation[] };
type Backup = { id: string; createdAt: string; realm: string; sizeBytes: number };
type ClientAddon = { id: string; name: string; version: string; category: string; description: string; note: string; sourceUrl: string; installed: boolean; installedVersion: string | null };
type AddonState = { clientPath: string; addonsPath: string; steamInput: { found: boolean; shortcutName: string; gameId: string }; addons: ClientAddon[] };

const realmInfo: Record<Realm, { name: string; detail: string; bots: number }> = {
  progression: { name: 'Progression', detail: 'Levels 1–80', bots: 1000 },
  endgame: { name: 'Endgame 80', detail: 'Starter gear · instant level 80', bots: 300 },
  qa: { name: 'QA Custom', detail: 'Isolated test realm', bots: 100 },
};
const nav: { id: View; icon: string; label: string }[] = [
  { id: 'dashboard', icon: '⌂', label: 'Dashboard' }, { id: 'realms', icon: '◈', label: 'Realms' },
  { id: 'bots', icon: '♟', label: 'Bots' }, { id: 'queues', icon: '⇄', label: 'Queues' },
  { id: 'party', icon: '♜', label: 'Party Builder' }, { id: 'world', icon: '◎', label: 'World Settings' },
  { id: 'addons', icon: '＋', label: 'Addons' },
  { id: 'maintenance', icon: '▣', label: 'Backup & Restore' }, { id: 'logs', icon: '≡', label: 'Logs' },
];
const initialStatus: Status = { realm: 'progression', realmName: 'AzerothCore Progression', availableRealms: ['progression'], port: 8085, state: 'offline', uptime: '—', bots: 0, cpu: '—', memory: '—', job: { running: false, label: '', ok: true, message: '' } };

async function api<T>(url: string, options?: RequestInit): Promise<T> {
  const response = await fetch(url, { ...options, headers: { 'Content-Type': 'application/json', ...(options?.headers || {}) } });
  const data = await response.json() as T & { error?: string };
  if (!response.ok) throw new Error(data.error || 'Request failed');
  return data;
}
function Toggle({ checked, onChange, label }: { checked: boolean; onChange: (value: boolean) => void; label: string }) {
  return <button type="button" role="switch" aria-checked={checked} aria-label={label} className={`toggle ${checked ? 'on' : ''}`} onClick={() => onChange(!checked)} />;
}
function autoScale(width = window.innerWidth) { return width >= 3200 ? 1.75 : width >= 2500 ? 1.5 : width >= 1800 ? 1.25 : 1; }

export default function Home() {
  const [view, setView] = useState<View>('dashboard');
  const viewHistory = useRef<View[]>([]);
  const [status, setStatus] = useState<Status>(initialStatus);
  const [selectedRealm, setSelectedRealm] = useState<Realm>('progression');
  const [settings, setSettings] = useState<Settings | null>(null);
  const [logs, setLogs] = useState('Loading logs…');
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  const [desktopState, setDesktopState] = useState<DesktopState>({ activeInstallationId: null, installations: [] });
  const [deleteTarget, setDeleteTarget] = useState<Installation | null>(null);
  const [restoreTarget, setRestoreTarget] = useState<Backup | null>(null);
  const [backups, setBackups] = useState<Backup[]>([]);
  const [addons, setAddons] = useState<AddonState | null>(null);
  const [addonBusy, setAddonBusy] = useState<string | null>(null);
  const [scaleMode, setScaleMode] = useState(() => Number(localStorage.getItem('azeroth-control-ui-scale') || 0));
  const [autoScaleValue, setAutoScaleValue] = useState(() => autoScale(window.screen.width));
  const [party, setParty] = useState([
    { role: 'Tank', className: 'Warrior', spec: 'Protection' }, { role: 'Healer', className: 'Priest', spec: 'Holy' },
    { role: 'DPS', className: 'Mage', spec: 'Frost' }, { role: 'DPS', className: 'Rogue', spec: 'Combat' },
  ]);
  const availableRealms = status.availableRealms?.length ? status.availableRealms : [status.realm];

  const navigate = useCallback((next: View) => {
    setView((current) => {
      if (current !== next) viewHistory.current.push(current);
      return next;
    });
  }, []);
  const goBack = useCallback(() => {
    if (deleteTarget) { setDeleteTarget(null); return; }
    if (restoreTarget) { setRestoreTarget(null); return; }
    setView(viewHistory.current.pop() ?? 'dashboard');
  }, [deleteTarget, restoreTarget]);

  const refresh = useCallback(async () => {
    try { const next = await api<Status>('/api/status'); setStatus(next); if (next.job.message && !next.job.running) setNotice(next.job.ok ? 'Server action completed.' : next.job.message); }
    catch { setStatus((current) => ({ ...current, state: 'offline' })); }
  }, []);
  const loadSettings = useCallback(async (realm: Realm) => {
    try { setSettings(await api<Settings>(`/api/settings?realm=${realm}`)); setError(''); }
    catch (caught) { setError(caught instanceof Error ? caught.message : 'Unable to load settings'); }
  }, []);
  const loadLogs = useCallback(async () => {
    try { const data = await api<{ logs: string }>('/api/logs?lines=220'); setLogs(data.logs || 'No log entries.'); }
    catch (caught) { setLogs(caught instanceof Error ? caught.message : 'Logs are unavailable.'); }
  }, []);
  const loadBackups = useCallback(async () => {
    try { const data = await api<{ backups: Backup[] }>('/api/backups'); setBackups(data.backups); }
    catch (caught) { setError(caught instanceof Error ? caught.message : 'Unable to load backups'); }
  }, []);
  const loadAddons = useCallback(async () => {
    try { const next = await window.azerothDesktop?.getAddons(); if (next) setAddons(next); setError(''); }
    catch (caught) { setError(caught instanceof Error ? caught.message : 'Unable to inspect the WoW AddOns folder'); }
  }, []);

  useEffect(() => { window.azerothDesktop?.getUiMetrics().then((metrics) => setAutoScaleValue(metrics.recommendedScale)); }, []);
  useEffect(() => { refresh(); const timer = window.setInterval(refresh, 5000); return () => window.clearInterval(timer); }, [refresh]);
  useEffect(() => { if (['bots', 'queues', 'world'].includes(view)) loadSettings(selectedRealm); if (view === 'logs') loadLogs(); if (view === 'maintenance') loadBackups(); if (view === 'addons') loadAddons(); }, [view, selectedRealm, loadSettings, loadLogs, loadBackups, loadAddons]);
  useEffect(() => { if (status.realm) setSelectedRealm(status.realm); }, [status.realm]);
  useEffect(() => { window.azerothDesktop?.getState().then(setDesktopState); }, []);
  useEffect(() => {
    window.addEventListener('azeroth-gamepad-back', goBack);
    return () => window.removeEventListener('azeroth-gamepad-back', goBack);
  }, [goBack]);
  useEffect(() => {
    if (deleteTarget || restoreTarget) window.setTimeout(() => document.querySelector<HTMLButtonElement>('.confirm-modal button')?.focus(), 30);
  }, [deleteTarget, restoreTarget]);

  function changeScale(value: number) { setScaleMode(value); if (value) localStorage.setItem('azeroth-control-ui-scale', String(value)); else localStorage.removeItem('azeroth-control-ui-scale'); void window.azerothDesktop?.setUiScale(value); }
  async function action(name: 'start' | 'restart' | 'stop' | 'launch-wow', realm: Realm = selectedRealm) {
    setError(''); setNotice('');
    try { const result = await api<{ message: string }>('/api/action', { method: 'POST', body: JSON.stringify({ action: name, realm }) }); setNotice(result.message); refresh(); }
    catch (caught) { setError(caught instanceof Error ? caught.message : 'Action failed'); }
  }
  async function launchWoW() {
    setError(''); setNotice('');
    try {
      const result = window.azerothDesktop ? await window.azerothDesktop.launchGame() : await api<{ message: string }>('/api/action', { method: 'POST', body: JSON.stringify({ action: 'launch-wow', realm: selectedRealm }) });
      setNotice(result.message);
    } catch (caught) { setError(caught instanceof Error ? caught.message : 'Unable to launch WoW'); }
  }
  async function changeAddon(addon: ClientAddon) {
    setAddonBusy(addon.id); setError(''); setNotice('');
    try {
      const next = addon.installed ? await window.azerothDesktop?.removeAddon(addon.id) : await window.azerothDesktop?.installAddon(addon.id);
      if (next) setAddons(next);
      setNotice(addon.installed ? `${addon.name} was removed. A recovery copy was kept.` : `${addon.name} ${addon.version} installed and verified.`);
    } catch (caught) { setError(caught instanceof Error ? caught.message : 'Addon operation failed'); }
    finally { setAddonBusy(null); }
  }
  async function openSteamInput() {
    setError(''); setNotice('');
    try { const result = await window.azerothDesktop?.openSteamInput(); if (result) setNotice(`Opening Steam Input for ${result.shortcutName}.`); }
    catch (caught) { setError(caught instanceof Error ? caught.message : 'Unable to open Steam Input'); }
  }
  async function saveSettings() {
    if (!settings) return;
    setSaving(true); setError(''); setNotice('');
    try {
      const result = await api<{ restartRequired: boolean; settings: Settings }>('/api/settings', { method: 'POST', body: JSON.stringify({ realm: selectedRealm, settings }) });
      setSettings(result.settings); setNotice(result.restartRequired ? 'Saved. Restart the active realm to apply changes.' : 'Settings saved.');
    } catch (caught) { setError(caught instanceof Error ? caught.message : 'Unable to save settings'); } finally { setSaving(false); }
  }
  const update = <K extends keyof Settings>(key: K, value: Settings[K]) => setSettings((current) => current ? { ...current, [key]: value } : current);
  async function selectServer(id: string) {
    setError('');
    try { await window.azerothDesktop?.selectInstallation(id); await window.azerothDesktop?.restartApp(); }
    catch (caught) { setError(caught instanceof Error ? caught.message : 'Unable to switch server'); }
  }
  async function removeServer(deleteFiles: boolean) {
    if (!deleteTarget) return;
    setError('');
    try { await window.azerothDesktop?.removeInstallation(deleteTarget.id, deleteFiles); await window.azerothDesktop?.restartApp(); }
    catch (caught) { setError(caught instanceof Error ? caught.message : 'Unable to remove server'); setDeleteTarget(null); }
  }
  async function createBackup() {
    setError(''); setNotice('');
    try { const result = await api<{ message: string }>('/api/backup', { method: 'POST', body: '{}' }); setNotice(result.message); refresh(); }
    catch (caught) { setError(caught instanceof Error ? caught.message : 'Unable to create backup'); }
  }
  async function restoreBackup() {
    if (!restoreTarget) return;
    setError(''); setNotice('');
    try { const result = await api<{ message: string }>('/api/restore', { method: 'POST', body: JSON.stringify({ backupId: restoreTarget.id }) }); setNotice(result.message); setRestoreTarget(null); refresh(); }
    catch (caught) { setError(caught instanceof Error ? caught.message : 'Unable to restore backup'); setRestoreTarget(null); }
  }
  function RealmPicker() { return <div className="realm-tabs">{availableRealms.map((realm) => <button key={realm} className={selectedRealm === realm ? 'active' : ''} onClick={() => setSelectedRealm(realm)}>{realmInfo[realm].name}</button>)}</div>; }

  function Dashboard() { const online = status.state === 'online'; return <>
    <section className={`server-card ${online ? '' : 'offline'}`}><div className="server-glow" /><div className="server-copy"><div className="status-line"><span className="pulse" /> SERVER {online ? 'ONLINE' : 'OFFLINE'}</div><h2>{status.realmName}</h2><p>{online ? 'Authentication, world server and database are running.' : 'The server is not running.'}</p><div className="server-meta"><span>Uptime <strong>{status.uptime}</strong></span><span>Port <strong>{status.port}</strong></span><span>Build <strong>3.3.5a</strong></span></div></div><div className="server-controls">{online ? <><button className="danger-button" disabled={status.job.running} onClick={() => action('stop', status.realm)}>Stop Server</button><button className="ghost-button" disabled={status.job.running} onClick={() => action('restart', status.realm)}>Restart</button></> : <button className="primary-button" disabled={status.job.running} onClick={() => action('start', selectedRealm)}>Start Server</button>}</div></section>
    <section className="stats-grid"><article className="stat-card"><span>Online bots</span><strong>{status.bots.toLocaleString('en-US')}</strong><small>Active playerbots</small></article><article className="stat-card"><span>Active realm</span><strong>{realmInfo[status.realm].name}</strong><small>Port {status.port}</small></article><article className="stat-card"><span>Server CPU</span><strong>{status.cpu}</strong><small>Worldserver container</small></article><article className="stat-card"><span>Memory</span><strong>{status.memory}</strong><small>Worldserver container</small></article></section>
    <div className="dashboard-grid"><section className="panel"><div className="panel-head"><div><p className="eyebrow">QUICK SELECT</p><h3>Installed realms</h3></div><button className="text-button" onClick={() => navigate('realms')}>Manage</button></div><div className="realm-list">{availableRealms.map((realm) => <button className={`realm-row ${status.realm === realm && online ? 'selected' : ''}`} key={realm} onClick={() => action(status.realm === realm && online ? 'restart' : 'start', realm)}><span className="realm-symbol">{status.realm === realm && online ? '◆' : '◇'}</span><span><strong>{realmInfo[realm].name}</strong><small>{realmInfo[realm].detail} · configured on this server</small></span><span className="realm-action">{status.realm === realm && online ? 'Restart' : 'Start'}</span></button>)}</div></section>
    <section className="panel"><div className="panel-head"><div><p className="eyebrow">QUICK CONTROLS</p><h3>Game & queues</h3></div><span className="gamepad-hint">START</span></div><p className="panel-description">Launch the HD client or open the controls for dungeon and battleground bot queues.</p><div className="quick-actions"><button data-gamepad-launch-wow="true" className="primary-button" onClick={launchWoW}>▶ Launch WoW-HD</button><button className="ghost-button" onClick={() => navigate('queues')}>Queue Settings</button><button className="ghost-button" onClick={() => navigate('logs')}>World Log</button></div></section></div>
    <footer className="activity"><span className="activity-icon">{status.job.running ? '…' : '✓'}</span><p><strong>{status.job.running ? status.job.label : 'System ready'}</strong><small>{status.job.running ? 'This may take several minutes.' : `${realmInfo[status.realm].name} · ${status.uptime}`}</small></p><button className="text-button" onClick={() => navigate('logs')}>Open Log</button></footer>
  </>; }
  function Realms() { return <section className="page-panel"><div className="section-title"><div><p className="eyebrow">SERVER PROFILES</p><h2>Realms</h2><p>Switch the entire local server to another profile with one click.</p></div></div><div className="realm-cards">{availableRealms.map((realm) => <article key={realm} className={status.realm === realm && status.state === 'online' ? 'active' : ''}><span className="realm-card-icon">{realm === 'progression' ? 'Ⅰ' : realm === 'endgame' ? 'Ⅷ' : 'Q'}</span><p className="eyebrow">{status.realm === realm && status.state === 'online' ? 'CURRENTLY ACTIVE' : 'REALM PROFILE'}</p><h3>{realmInfo[realm].name}</h3><p>{realmInfo[realm].detail}<br />{realmInfo[realm].bots} configured bots</p><button className={status.realm === realm && status.state === 'online' ? 'ghost-button' : 'primary-button'} onClick={() => action(status.realm === realm && status.state === 'online' ? 'restart' : 'start', realm)}>{status.realm === realm && status.state === 'online' ? 'Restart' : 'Start'}</button></article>)}</div><div className="installed-heading"><div><p className="eyebrow">LOCAL INSTALLATIONS</p><h2>Servers</h2></div><button className="ghost-button" onClick={async () => { await window.azerothDesktop?.resetOnboarding(); await window.azerothDesktop?.restartApp(); }}>Add Server</button></div><div className="installation-list">{desktopState.installations.map((server) => <article key={server.id} className={server.id === desktopState.activeInstallationId ? 'active' : ''}><div><strong>{server.name}</strong><small>{server.imported ? 'Imported — files stay untouched' : 'Managed by Azeroth Control'}</small><code>{server.path}</code></div><div className="installation-actions">{server.id !== desktopState.activeInstallationId && <button className="ghost-button" onClick={() => selectServer(server.id)}>Use Server</button>}<button className="danger-button" onClick={() => setDeleteTarget(server)}>{server.imported ? 'Forget' : 'Delete'}</button></div></article>)}</div></section>; }
  function Bots() { return <section className="page-panel"><div className="section-title"><div><p className="eyebrow">PLAYERBOTS</p><h2>Bot Population</h2><p>Changes are safely written to the selected realm configuration.</p></div><RealmPicker /></div>{settings && <div className="settings-grid"><NumberSetting title="Online bot count" note="Up to 1,000 recommended for this machine" value={settings.botCount} min={0} max={2000} step={50} onChange={(v) => update('botCount', v)} /><SwitchSetting title="Level bracket distribution" note="Keeps bots across all level ranges" checked={settings.levelBrackets} onChange={(v) => update('levelBrackets', v)} /><SwitchSetting title="Follow player level" note="Moves more bots into your current bracket" checked={settings.dynamicBrackets} onChange={(v) => update('dynamicBrackets', v)} /><SwitchSetting title="Synchronize factions" note="Alliance and Horde use the same level range" checked={settings.syncFactions} onChange={(v) => update('syncFactions', v)} /><NumberSetting title="Player tracking weight" note="10–15 creates a denser world around you" value={settings.playerWeight} min={0} max={30} step={1} onChange={(v) => update('playerWeight', v)} /></div>}<SaveBar saving={saving} onSave={saveSettings} onRestart={() => action('restart', selectedRealm)} /></section>; }
  function Queues() { return <section className="page-panel"><div className="section-title"><div><p className="eyebrow">DUNGEON FINDER & PVP</p><h2>Queue Controls</h2><p>Built-in playerbot queue manager settings.</p></div><RealmPicker /></div>{settings && <div className="settings-grid"><SwitchSetting title="Dungeon bots" note="Bots react to a human LFG queue" checked={settings.joinLfg} onChange={(v) => update('joinLfg', v)} /><SwitchSetting title="Battleground bots" note="Bots can fill an active BG queue" checked={settings.joinBg} onChange={(v) => update('joinBg', v)} /><SwitchSetting title="Automatic BG queue" note="Required by the current playerbots BG behavior" checked={settings.autoJoinBg} onChange={(v) => update('autoJoinBg', v)} /><SwitchSetting title="Dungeon deserter" note="Apply a penalty for leaving early" checked={settings.dungeonDeserter} onChange={(v) => update('dungeonDeserter', v)} /><SwitchSetting title="BG deserter" note="Apply a penalty for leaving early" checked={settings.bgDeserter} onChange={(v) => update('bgDeserter', v)} /></div>}<div className="info-banner"><strong>Instant reserve queue</strong><span>The server component that prepares exact roles, levels and gear is not enabled yet. These controls use the reliable built-in playerbots system.</span></div><SaveBar saving={saving} onSave={saveSettings} onRestart={() => action('restart', selectedRealm)} /></section>; }
  function Party() { const classes = ['Warrior', 'Paladin', 'Druid', 'Priest', 'Shaman', 'Mage', 'Rogue', 'Hunter', 'Warlock', 'Death Knight']; return <section className="page-panel"><div className="section-title"><div><p className="eyebrow">MY PARTY</p><h2>Party Builder</h2><p>Prepare and save a preferred five-player group for quick summoning later.</p></div></div><div className="party-list"><div className="party-player"><span className="avatar">YOU</span><span><strong>Your character</strong><small>Party leader · uses your current level</small></span></div>{party.map((slot, index) => <div className="party-slot" key={index}><span className={`role-gem role-${slot.role.toLowerCase()}`}>{index + 2}</span><select value={slot.role} onChange={(e) => setParty((p) => p.map((s, i) => i === index ? { ...s, role: e.target.value } : s))}><option>Tank</option><option>Healer</option><option>DPS</option></select><select value={slot.className} onChange={(e) => setParty((p) => p.map((s, i) => i === index ? { ...s, className: e.target.value } : s))}>{classes.map((name) => <option key={name}>{name}</option>)}</select><input value={slot.spec} onChange={(e) => setParty((p) => p.map((s, i) => i === index ? { ...s, spec: e.target.value } : s))} aria-label={`Spec for slot ${index + 2}`} /></div>)}</div><div className="info-banner"><strong>Preset saved for this local session</strong><span>Summoning and automatic gearing will require a reserve-bot bridge; the current server does not expose a safe API for it.</span></div></section>; }
  function World() { return <section className="page-panel"><div className="section-title"><div><p className="eyebrow">REALM CONFIG</p><h2>World Settings</h2><p>Common quality-of-life and rate controls without editing files.</p></div><RealmPicker /></div>{settings && <><div className="rate-grid"><NumberSetting title="XP Rate" note="Kill, quest and exploration XP" value={settings.xpRate} min={0} max={20} step={0.5} suffix="×" onChange={(v) => update('xpRate', v)} /><NumberSetting title="Item Drop Rate" note="All item quality tiers" value={settings.dropRate} min={0} max={20} step={0.5} suffix="×" onChange={(v) => update('dropRate', v)} /><NumberSetting title="Creature Spawn Speed" note="Higher means creatures return faster" value={settings.spawnRate} min={0.25} max={20} step={0.25} suffix="×" onChange={(v) => update('spawnRate', v)} /></div><div className="settings-grid"><SwitchSetting title="AoE looting" note="Loot nearby creatures at once" checked={settings.aoeLoot} onChange={(v) => update('aoeLoot', v)} /><NumberSetting title="AoE loot range" note="Range in yards" value={settings.aoeLootRange} min={1} max={100} step={1} onChange={(v) => update('aoeLootRange', v)} /></div></>}<SaveBar saving={saving} onSave={saveSettings} onRestart={() => action('restart', selectedRealm)} /></section>; }
  function Addons() {
    const consolePortInstalled = Boolean(addons?.addons.find((addon) => addon.id === 'consoleportlk')?.installed);
    return <section className="page-panel addons-page">
      <div className="section-title"><div><p className="eyebrow">WOW 3.3.5A CLIENT</p><h2>Addon Library</h2><p>Verified releases are downloaded from their original GitHub projects and installed into your active client.</p></div><button className="ghost-button" onClick={loadAddons}>Refresh</button></div>
      {addons && <>
        <div className="client-path-banner"><span>Active client</span><strong>{addons.clientPath}</strong><small>{addons.addonsPath}</small></div>
        <div className="addon-grid">{addons.addons.map((addon) => <article key={addon.id} className={addon.installed ? 'installed' : ''}><div className="addon-card-head"><span className="addon-glyph">{addon.category === 'Gamepad' ? '⌘' : '!'}</span><div><p className="eyebrow">{addon.category}</p><h3>{addon.name}</h3></div><span className={`addon-state ${addon.installed ? 'ready' : ''}`}>{addon.installed ? `Installed ${addon.installedVersion || ''}` : `v${addon.version}`}</span></div><p>{addon.description}</p><small>{addon.note}</small><div className="addon-actions"><button className="text-button" onClick={() => window.open(addon.sourceUrl, '_blank')}>Source</button><button className={addon.installed ? 'danger-button' : 'primary-button'} disabled={addonBusy !== null} onClick={() => changeAddon(addon)}>{addonBusy === addon.id ? 'Working…' : addon.installed ? 'Remove' : 'Install'}</button></div></article>)}</div>
        {consolePortInstalled && <section className="steam-input-setup">
          <div className="steam-input-head">
            <div><p className="eyebrow">RECOMMENDED CONTROLLER SETUP</p><h3>Steam Input for ConsolePortLK</h3><p>Native SteamOS mapping with no helper program, Windows runtime or shared Proton prefix.</p></div>
            <span className={`steam-shortcut-badge ${addons.steamInput.found ? 'found' : ''}`}>{addons.steamInput.found ? addons.steamInput.shortcutName : 'Steam entry not found'}</span>
          </div>
          <div className="steam-input-steps">
            <article><span className="steam-step-number">1</span><div><strong>Name the WoW Steam entry</strong><small>Use <code>World of Warcraft: WotLK</code> so the community layout is easy to find.</small></div></article>
            <article><span className="steam-step-number">2</span><div><strong>Browse Community Layouts</strong><small>Open Controller Settings, choose Community Layouts and select Show All Layouts.</small></div></article>
            <article><span className="steam-step-number">3</span><div><strong>Apply the ConsolePort layout</strong><small>Choose <code>Gamepad leoaviana ConsolePortLK</code> by Prrg, then apply it.</small></div></article>
          </div>
          <div className="steam-input-actions">
            <p>Azeroth Control opens the correct non-Steam game settings. Steam keeps ownership of your controller layout.</p>
            <button className="primary-button large" disabled={!addons.steamInput.found} onClick={openSteamInput}>Open Steam Input</button>
          </div>
        </section>}
        <div className="info-banner"><strong>Safe addon changes</strong><span>Existing folders are moved to Interface/.azeroth-control-backups before replacement or removal. Azeroth Control never bundles third-party addons inside its AppImage.</span></div>
      </>}
    </section>;
  }
  function Maintenance() { return <section className="page-panel"><div className="section-title"><div><p className="eyebrow">SERVER SAFETY</p><h2>Backup & Restore</h2><p>Full database and configuration snapshots for the active server.</p></div><button className="primary-button large" disabled={status.state !== 'online' || status.job.running} onClick={createBackup}>Create Backup</button></div><div className="info-banner"><strong>Safe local snapshots</strong><span>Backups contain AzerothCore databases and server configuration only. Your WoW client is never copied.</span></div><div className="backup-list">{backups.length ? backups.map((backup) => <article key={backup.id}><div><strong>{new Date(backup.createdAt).toLocaleString('en-GB')}</strong><small>{backup.realm} · {(backup.sizeBytes / 1024 ** 2).toFixed(1)} MB</small></div><button className="ghost-button" disabled={status.state !== 'online' || status.job.running} onClick={() => setRestoreTarget(backup)}>Restore</button></article>) : <div className="empty-backups"><strong>No backups yet</strong><span>Start the server and create your first snapshot.</span></div>}</div></section>; }
  function Logs() { return <section className="page-panel logs-page"><div className="section-title"><div><p className="eyebrow">WORLDSERVER</p><h2>Live Log</h2><p>The last 220 lines from the active worldserver.</p></div><button className="ghost-button" onClick={loadLogs}>Refresh</button></div><pre>{logs}</pre></section>; }

  return <main className="shell"><aside className="sidebar"><div className="brand"><span className="brand-mark">A</span><div><strong>Azeroth</strong><span>Control</span></div></div><nav aria-label="Main navigation">{nav.map((item) => <button key={item.id} className={`nav-item ${view === item.id ? 'active' : ''}`} onClick={() => navigate(item.id)}><span>{item.icon}</span>{item.label}</button>)}</nav><div className="sidebar-foot"><span className={`health-dot ${status.state}`} /> {status.state === 'online' ? 'Local connection' : 'Server offline'}<small>Steam machine · deck</small><button className="exit-app-button" onClick={() => window.azerothDesktop?.quitApp()}>Exit App</button></div></aside>
    <section className="content"><header className="topbar"><div><p className="eyebrow">STEAMOS · LOCAL SERVER</p><h1>{nav.find((item) => item.id === view)?.label}</h1></div><div className="top-actions"><label className="scale-control"><span>UI size</span><select value={scaleMode} onChange={(e) => changeScale(Number(e.target.value))}><option value={0}>Auto ({Math.round(autoScaleValue * 100)}%)</option><option value={1}>100%</option><option value={1.25}>125%</option><option value={1.5}>150%</option><option value={1.75}>175%</option><option value={2}>200%</option></select></label>{window.azerothDesktop && <button className="ghost-button" onClick={async () => { await window.azerothDesktop?.resetOnboarding(); await window.azerothDesktop?.restartApp(); }}>Add Server</button>}<button className="icon-button" onClick={refresh} aria-label="Refresh status">↻</button><button className="primary-button" onClick={launchWoW}><span>▶</span> Launch WoW-HD</button></div></header>{error && <div className="toast error">{error}<button onClick={() => setError('')}>×</button></div>}{notice && <div className="toast success">{notice}<button onClick={() => setNotice('')}>×</button></div>}{view === 'dashboard' && <Dashboard />}{view === 'realms' && <Realms />}{view === 'bots' && <Bots />}{view === 'queues' && <Queues />}{view === 'party' && <Party />}{view === 'world' && <World />}{view === 'addons' && <Addons />}{view === 'maintenance' && <Maintenance />}{view === 'logs' && <Logs />}</section>{deleteTarget && <div className="modal-backdrop" role="presentation"><section className="confirm-modal" role="dialog" aria-modal="true" aria-labelledby="delete-server-title"><p className="eyebrow">CONFIRM SERVER REMOVAL</p><h2 id="delete-server-title">{deleteTarget.imported ? 'Forget this server?' : 'Delete this server?'}</h2><p>{deleteTarget.imported ? 'The server will disappear from Azeroth Control. No server or WoW files will be deleted.' : 'Remove Only keeps everything on disk. Delete Server Data moves managed files to Trash and permanently removes its container database and images. Your WoW client is never deleted.'}</p><code>{deleteTarget.path}</code><div className="modal-actions"><button className="ghost-button" onClick={() => setDeleteTarget(null)}>Cancel</button><button className="danger-button" onClick={() => removeServer(false)}>{deleteTarget.imported ? 'Forget Server' : 'Remove Only'}</button>{!deleteTarget.imported && <button className="danger-button solid" onClick={() => removeServer(true)}>Delete Server Data</button>}</div></section></div>}{restoreTarget && <div className="modal-backdrop" role="presentation"><section className="confirm-modal" role="dialog" aria-modal="true" aria-labelledby="restore-title"><p className="eyebrow">CONFIRM RESTORE</p><h2 id="restore-title">Restore this backup?</h2><p>The current AzerothCore databases and server configuration will be replaced. The server restarts automatically when restoration finishes.</p><code>{restoreTarget.id}</code><div className="modal-actions"><button className="ghost-button" onClick={() => setRestoreTarget(null)}>Cancel</button><button className="danger-button solid" onClick={restoreBackup}>Restore Backup</button></div></section></div>}</main>;
}

function NumberSetting({ title, note, value, min, max, step, suffix, onChange }: { title: string; note: string; value: number; min: number; max: number; step: number; suffix?: string; onChange: (value: number) => void }) {
  return <label className="setting-card"><span><strong>{title}</strong><small>{note}</small></span><span className="number-input"><input type="number" inputMode="decimal" min={min} max={max} step={step} value={value} onChange={(e) => onChange(Number(e.target.value))} />{suffix && <b>{suffix}</b>}</span></label>;
}
function SwitchSetting({ title, note, checked, onChange }: { title: string; note: string; checked: boolean; onChange: (value: boolean) => void }) { return <label className="setting-card"><span><strong>{title}</strong><small>{note}</small></span><Toggle label={title} checked={checked} onChange={onChange} /></label>; }
function SaveBar({ saving, onSave, onRestart }: { saving: boolean; onSave: () => void; onRestart: () => void }) { return <div className="save-bar"><span>Changes are applied after restarting the realm.</span><button className="ghost-button" onClick={onRestart}>Restart</button><button className="primary-button" disabled={saving} onClick={onSave}>{saving ? 'Saving…' : 'Save Changes'}</button></div>; }
