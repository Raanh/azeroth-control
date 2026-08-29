import { useEffect, useMemo, useRef, useState } from 'react';

type Module = { id: string; name: string; description: string; required?: boolean; default?: boolean; conflicts?: string[]; license: string; estimatedBytes: number };
type Profile = { id: string; name: string; expansion: string; description: string; levelCap: number; recommendedBots: number; estimatedBytes: number };
type Catalog = { core: { name: string; estimatedDownloadBytes: number; estimatedInstalledBytes: number; freshInstallReady?: boolean }; profiles: Profile[]; modules: Module[] };
type SystemInfo = { platform: string; release: string; cpuModel: string; cpuThreads: number; memoryBytes: number; disk: { freeBytes: number; totalBytes: number }; defaultInstallRoot: string; dependencies: Record<string, boolean> };
type Selection = { mode: 'new' | 'import'; installRoot: string; clientPath: string; profile: string; bots: number; modules: string[]; stopWithGame: boolean; steamShortcuts: boolean; serverId?: string; serverName?: string; accountName?: string; accountPassword?: string; adminAccount?: boolean; autoLogin?: boolean };
type DetectedInstallation = { path: string; name: string; realms: number; resumable?: boolean; selection?: Selection };
type InstallPlan = { requiredBytes: number; downloadBytes: number; freeBytes: number; enoughSpace: boolean; steps: string[] };

const steps = ['Welcome', 'System Check', 'Server Profile', 'Modules', 'Game Client', 'Review', 'Install'];
const fallbackCatalog: Catalog = {
  core: { name: 'AzerothCore Playerbots', estimatedDownloadBytes: 4 * 1024 ** 3, estimatedInstalledBytes: 10 * 1024 ** 3, freshInstallReady: false },
  profiles: [{ id: 'progression', name: 'Progressive 1–80', expansion: 'Wrath of the Lich King', description: 'Start at level 1 and progress naturally.', levelCap: 80, recommendedBots: 500, estimatedBytes: 3 * 1024 ** 3 }],
  modules: [],
};
const fallbackSystem: SystemInfo = { platform: 'linux', release: 'SteamOS', cpuModel: 'AMD Custom APU', cpuThreads: 8, memoryBytes: 16 * 1024 ** 3, disk: { freeBytes: 80 * 1024 ** 3, totalBytes: 512 * 1024 ** 3 }, defaultInstallRoot: '~/.local/share/azeroth-control', dependencies: { podman: true, distrobox: true, git: true, python: true, steam: true } };
const formatBytes = (bytes: number) => bytes ? new Intl.NumberFormat('en-US', { style: 'unit', unit: 'gigabyte', maximumFractionDigits: 1 }).format(bytes / 1024 ** 3) : '0 GB';
const installStages = [
  ['Source', 'Download AzerothCore Playerbots'], ['Modules', 'Prepare selected server modules'],
  ['Configure', 'Create realm and client configuration'], ['Build', 'Compile four server container images'],
  ['Initialize', 'Create databases, maps and first account'], ['Finish', 'Create launchers and verify installation'],
];
const stageProgress = [0, 5, 10, 15, 80, 95, 100];

export default function Installer({ onComplete, onCancel }: { onComplete: () => void; onCancel: () => void }) {
  const bridge = window.azerothDesktop;
  const [step, setStep] = useState(0);
  const [catalog, setCatalog] = useState<Catalog>(fallbackCatalog);
  const [system, setSystem] = useState<SystemInfo>(fallbackSystem);
  const [detected, setDetected] = useState<DetectedInstallation[]>([]);
  const [plan, setPlan] = useState<InstallPlan | null>(null);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState('');
  const [output, setOutput] = useState<string[]>([]);
  const [complete, setComplete] = useState(false);
  const [installing, setInstalling] = useState(false);
  const [clientCheck, setClientCheck] = useState<{ ok: boolean; message: string } | null>(null);
  const [installPhase, setInstallPhase] = useState(0);
  const [installStartedAt, setInstallStartedAt] = useState(0);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [telemetry, setTelemetry] = useState({ cpuPercent: 0, memoryUsedBytes: 0, memoryTotalBytes: system.memoryBytes });
  const [selection, setSelection] = useState<Selection>({ mode: 'new', installRoot: '', clientPath: '', profile: 'progression', bots: 500, modules: [], stopWithGame: true, steamShortcuts: true, serverId: `server-${crypto.randomUUID().slice(0, 8)}`, serverName: 'Azeroth Progression', accountName: 'player', accountPassword: 'player', adminAccount: false, autoLogin: true });
  const gamepadState = useRef<boolean[]>([]);
  const logRef = useRef<HTMLPreElement>(null);

  useEffect(() => {
    Promise.all([bridge?.getCatalog() ?? fallbackCatalog, bridge?.getSystemInfo() ?? fallbackSystem, bridge?.detectInstallations() ?? []]).then(([nextCatalog, nextSystem, installations]) => {
      setCatalog(nextCatalog); setSystem(nextSystem); setDetected(installations);
      setSelection((current) => ({ ...current, installRoot: nextSystem.defaultInstallRoot, modules: nextCatalog.modules.filter((item: Module) => item.default || item.required).map((item: Module) => item.id) }));
      setBusy(false);
    }).catch((caught) => { setError(String(caught)); setBusy(false); });
  }, [bridge]);
  useEffect(() => bridge?.onInstallProgress((event) => {
    const message = event.message || '';
    if (message) {
      setOutput((current) => [...current.slice(-120), message]);
      const matches = [...message.matchAll(/\[(\d)\/6\]/g)];
      if (matches.length) setInstallPhase(Number(matches.at(-1)?.[1] || 0));
      else if (/Creating the first game account/i.test(message)) setInstallPhase(5);
      else if (/Creating launchers/i.test(message)) setInstallPhase(6);
    }
    if (event.type === 'complete') { const ok = Boolean(event.ok); setInstalling(false); setComplete(ok); if (!ok) setError(message || 'Installation failed.'); }
  }), [bridge]);
  useEffect(() => { if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight; }, [output]);
  useEffect(() => {
    if (!installing) return;
    const update = async () => {
      setElapsedSeconds(Math.floor((Date.now() - installStartedAt) / 1000));
      const next = await bridge?.getInstallTelemetry();
      if (next) setTelemetry(next);
    };
    update();
    const timer = window.setInterval(update, 1500);
    return () => window.clearInterval(timer);
  }, [installing, installStartedAt, bridge]);
  useEffect(() => {
    const timer = window.setInterval(() => {
      const pad = navigator.getGamepads?.()[0]; if (!pad) return;
      const pressed = pad.buttons.map((button) => button.pressed);
      const edge = (index: number) => pressed[index] && !gamepadState.current[index];
      const focusables = [...document.querySelectorAll<HTMLElement>('button:not(:disabled), input:not(:disabled), select:not(:disabled)')].filter((element) => element.offsetParent !== null);
      const active = Math.max(0, focusables.indexOf(document.activeElement as HTMLElement));
      const focusAt = (index: number) => { const target = focusables[index]; target?.focus({ preventScroll: true }); target?.scrollIntoView({ behavior: 'smooth', block: 'nearest' }); };
      if (edge(12) || edge(14)) focusAt((active - 1 + focusables.length) % focusables.length);
      if (edge(13) || edge(15)) focusAt((active + 1) % focusables.length);
      if (edge(0)) (document.activeElement as HTMLElement)?.click();
      if ((edge(5) || edge(9)) && !installing) (document.querySelector<HTMLButtonElement>('[data-gamepad-primary="true"]') ?? document.querySelector<HTMLButtonElement>('.install-stage > .primary-button'))?.click();
      if (edge(4) && !installing) document.querySelector<HTMLButtonElement>('[data-gamepad-back="true"]')?.click();
      if (edge(2)) {
        const activeElement = document.activeElement;
        const acceptsText = activeElement instanceof HTMLTextAreaElement || (
          activeElement instanceof HTMLInputElement && !['button', 'checkbox', 'radio', 'range', 'submit'].includes(activeElement.type)
        );
        if (acceptsText) { activeElement.focus({ preventScroll: true }); void bridge?.openKeyboard(); }
      }
      if (edge(1) && !installing) {
        if (step > 0 && !complete) setStep((current) => current - 1);
        else if (step === 0) onCancel();
      }
      gamepadState.current = pressed;
    }, 80);
    return () => window.clearInterval(timer);
  }, [step, complete, installing, onCancel, bridge]);

  const profile = catalog.profiles.find((item) => item.id === selection.profile) || catalog.profiles[0];
  const recommendedBots = useMemo(() => {
    const memoryGiB = system.memoryBytes / 1024 ** 3;
    const ceiling = Math.min(system.cpuThreads >= 12 ? 1000 : system.cpuThreads >= 8 ? 600 : 300, memoryGiB >= 28 ? 1000 : memoryGiB >= 14 ? 600 : 250);
    return Math.min(profile?.recommendedBots || 200, ceiling);
  }, [system, profile]);
  const set = <K extends keyof Selection>(key: K, value: Selection[K]) => setSelection((current) => ({ ...current, [key]: value }));
  const toggleModule = (item: Module) => {
    if (item.required) return;
    setSelection((current) => {
      const enabled = current.modules.includes(item.id);
      let modules = enabled ? current.modules.filter((id) => id !== item.id) : [...current.modules, item.id];
      if (!enabled && item.conflicts) modules = modules.filter((id) => !item.conflicts?.includes(id));
      return { ...current, modules };
    });
  };
  async function importExisting(path: string) {
    setBusy(true); setError('');
    try { await bridge?.importInstallation(path); await bridge?.restartApp(); onComplete(); }
    catch (caught) { setError(caught instanceof Error ? caught.message : String(caught)); setBusy(false); }
  }
  async function resumeExisting(item: DetectedInstallation) {
    if (!item.selection) return;
    setSelection(item.selection);
    setError('');
    try {
      setPlan(await (bridge?.createPlan(item.selection) ?? Promise.resolve(null)));
      setOutput(['Previous build work found. Select Resume Installation to continue from the saved checkpoints.']);
      setStep(6);
    } catch (caught) { setError(caught instanceof Error ? caught.message : String(caught)); }
  }
  async function next() {
    setError('');
    if (step === 1 && !Object.values(system.dependencies).every(Boolean)) { setError('A required dependency is missing. Health Check can install supported SteamOS prerequisites in the next build.'); return; }
    if (step === 2 && !(selection.serverName || '').trim()) { setError('Enter a name for this server. Focus the field and press X to open the Steam keyboard.'); return; }
    if (step === 4) {
      if (!selection.clientPath) { setError('Select your own WoW 3.3.5a client folder. The app never downloads or distributes the game.'); return; }
      const checked = await (bridge?.validateClient(selection.clientPath) ?? Promise.resolve({ ok: true, message: 'Client ready.' }));
      setClientCheck(checked);
      if (!checked.ok) { setError(checked.message); return; }
      if (!/^[A-Za-z0-9_]{3,16}$/.test(selection.accountName || '')) { setError('Account name must be 3–16 letters, numbers or underscores.'); return; }
      if (!/^[!-~]{4,16}$/.test(selection.accountPassword || '')) { setError('Password must be 4–16 characters without spaces.'); return; }
    }
    if (step === 5) {
      const nextPlan = await (bridge?.createPlan(selection) ?? Promise.resolve({ requiredBytes: catalog.core.estimatedInstalledBytes + (profile?.estimatedBytes || 0), downloadBytes: catalog.core.estimatedDownloadBytes, freeBytes: system.disk.freeBytes, enoughSpace: true, steps: [] }));
      setPlan(nextPlan); setStep(6); return;
    }
    setStep((current) => Math.min(6, current + 1));
  }
  async function beginInstall() {
    setBusy(true); setInstalling(true); setComplete(false); setError(''); setOutput(['Preparing installation…']); setInstallPhase(0); setInstallStartedAt(Date.now()); setElapsedSeconds(0);
    try { await bridge?.startInstallation(selection); if (!bridge) { setOutput((current) => [...current, 'Preview mode: no files were changed.']); setComplete(true); } }
    catch (caught) { setInstalling(false); setError(caught instanceof Error ? caught.message : String(caught)); }
    finally { setBusy(false); }
  }

  const expectedBuildMinutes = system.cpuThreads >= 12 ? [35, 45] : system.cpuThreads >= 8 ? [55, 70] : [80, 100];
  const installPercent = complete ? 100 : stageProgress[Math.max(0, installPhase - 1)] ?? 0;
  const remainingBuildMinutes = expectedBuildMinutes.map((minutes) => Math.max(1, Math.round(minutes * (1 - installPercent / 100))));
  const installationTiming = installing
    ? `Elapsed ${Math.floor(elapsedSeconds / 60)}m ${elapsedSeconds % 60}s · estimated ${remainingBuildMinutes[0]}–${remainingBuildMinutes[1]} min remaining`
    : complete ? 'All health checks passed.' : 'Your completed work is saved for Resume.';

  return <main className="installer-shell">
    <aside className="installer-rail"><div className="brand"><span className="brand-mark">A</span><div><strong>Azeroth</strong><span>Control</span></div></div><ol>{steps.map((label, index) => <li key={label} className={index === step ? 'active' : index < step ? 'done' : ''}><span>{index < step ? '✓' : index + 1}</span><b>{label}</b></li>)}</ol><div className="input-hints"><span>↕ Navigate</span><span>A Select</span><span>B Back</span></div></aside>
    <section className="installer-content">
      <header><p className="eyebrow">STEAM DECK SETUP</p><h1>{steps[step]}</h1><p>Simple, local and open-source. Your game client stays yours.</p></header>
      {error && <div className="toast error">{error}<button onClick={() => setError('')}>×</button></div>}
      {busy && step === 0 ? <div className="setup-loading">Checking this system…</div> : <>
        {step === 0 && <div className="welcome-grid"><button className="choice-card featured" onClick={() => { set('mode', 'new'); setStep(1); }}><span className="choice-icon">＋</span><strong>Install a new server</strong><small>Guided WotLK Playerbots setup with recommended settings.</small></button><div className="choice-card import-card"><span className="choice-icon">↳</span><strong>Import or resume</strong><small>Continue an interrupted managed build, or connect an existing server without moving it.</small>{detected.length ? detected.map((item) => <button key={item.path} className="detected-install" onClick={() => item.resumable ? resumeExisting(item) : importExisting(item.path)}><span>{item.name}</span><small>{item.resumable ? 'Resume saved build' : `${item.realms} realms`} · {item.path}</small></button>) : <button className="ghost-button" onClick={async () => { const path = await bridge?.chooseDirectory('install'); if (path) importExisting(path); }}>Choose Folder</button>}</div></div>}
        {step === 1 && <div className="setup-stack"><section className="hardware-card"><div><p className="eyebrow">THIS DEVICE</p><h2>{system.cpuModel}</h2><p>{system.cpuThreads} CPU threads · {formatBytes(system.memoryBytes)} memory</p></div><div className="disk-ring"><strong>{formatBytes(system.disk.freeBytes)}</strong><span>free</span></div></section><div className="check-grid">{Object.entries(system.dependencies).map(([name, ok]) => <article key={name} className={ok ? 'check-ok' : 'check-bad'}><span>{ok ? '✓' : '!'}</span><strong>{name}</strong><small>{ok ? 'Ready' : 'Missing'}</small></article>)}</div><label className="path-card"><span><strong>Installation location</strong><small>{selection.installRoot}</small></span><button className="ghost-button" onClick={async () => { const path = await bridge?.chooseDirectory('install'); if (path) set('installRoot', path); }}>Change</button></label></div>}
        {step === 2 && <div className="setup-stack"><div className="expansion-banner"><span>Ⅲ</span><div><p className="eyebrow">SUPPORTED PROVIDER</p><h2>Wrath of the Lich King · 3.3.5a</h2><p>Classic and Burning Crusade progression run inside the WotLK core. Other expansion providers will be added separately.</p></div></div><label className="server-name-card"><span><strong>Server name</strong><small>Shown in Azeroth Control and on the WoW realm list. Focus and press X for the Steam keyboard.</small></span><input type="text" maxLength={48} value={selection.serverName || ''} onChange={(event) => set('serverName', event.target.value)} /></label><div className="profile-grid">{catalog.profiles.map((item) => <button key={item.id} className={`profile-card ${selection.profile === item.id ? 'selected' : ''}`} onClick={() => { set('profile', item.id); set('bots', item.recommendedBots); }}><span>{selection.profile === item.id ? '●' : '○'}</span><strong>{item.name}</strong><small>{item.description}</small><b>Level cap {item.levelCap}</b></button>)}</div><section className="bot-picker"><div><strong>Bot population</strong><small>Recommended for this device: {recommendedBots}</small></div><output>{selection.bots.toLocaleString('en-US')}</output><input type="range" min="0" max="2000" step="50" value={selection.bots} onChange={(e) => set('bots', Number(e.target.value))} /><div className="preset-row">{[200, recommendedBots, 1000].map((count) => <button key={count} onClick={() => set('bots', count)}>{count === recommendedBots ? 'Recommended ' : ''}{count}</button>)}</div></section></div>}
        {step === 3 && <div className="module-grid">{catalog.modules.map((item) => { const enabled = selection.modules.includes(item.id); return <button key={item.id} className={`module-card ${enabled ? 'selected' : ''}`} onClick={() => toggleModule(item)}><span className="module-check">{enabled ? '✓' : ''}</span><div><strong>{item.name}</strong><small>{item.description}</small><em>{item.required ? 'Required' : item.license}</em></div></button>; })}</div>}
        {step === 4 && <div className="client-account-stage"><div className="client-stage"><div className="client-visual">3.3.5a</div><h2>Select your WoW client</h2><p>Azeroth Control validates and configures a client you already own. No Blizzard files are included or downloaded.</p><button className="primary-button large" onClick={async () => { const chosen = await bridge?.chooseDirectory('client'); if (!chosen) return; const checked = await (bridge?.validateClient(chosen) ?? Promise.resolve({ ok: true, path: chosen, message: 'Client ready.' })); setClientCheck(checked); if (checked.ok) set('clientPath', checked.path || chosen); }}>{selection.clientPath ? 'Change Client Folder' : 'Choose Client Folder'}</button>{selection.clientPath && <code>{selection.clientPath}</code>}{clientCheck && <div className={`client-check ${clientCheck.ok ? 'ok' : 'bad'}`}><strong>{clientCheck.ok ? '✓ Client ready' : '! Client problem'}</strong><span>{clientCheck.message}</span></div>}<div className="legal-note">Your original client remains in place. Config.wtf is backed up before its realmlist is set to this local server.</div></div><section className="account-card"><p className="eyebrow">GAME LOGIN</p><h2>Create your first account</h2><p>Created through the AzerothCore world console after the health check. Press X while focused on a field to open the Steam keyboard.</p><label><span>Username</span><input type="text" maxLength={16} autoCapitalize="none" value={selection.accountName || ''} onChange={(event) => set('accountName', event.target.value)} /></label><label><span>Password</span><input type="password" maxLength={16} value={selection.accountPassword || ''} onChange={(event) => set('accountPassword', event.target.value)} /></label><ToggleRow label="Automatic local login" checked={Boolean(selection.autoLogin)} onChange={(value) => set('autoLogin', value)} /><ToggleRow label="Administrator account" checked={Boolean(selection.adminAccount)} onChange={(value) => set('adminAccount', value)} /><small>{selection.autoLogin ? 'Autologin stores this local-only password in a user-readable credential file (mode 600) and types it into WoW at launch.' : 'The password is removed from installation records after the account is created.'}</small></section></div>}
        {step === 5 && <div className="review-grid"><section><p className="eyebrow">SERVER</p><h2>{selection.serverName || profile?.name}</h2><dl><div><dt>Profile</dt><dd>{profile?.name}</dd></div><div><dt>Expansion</dt><dd>WotLK 3.3.5a</dd></div><div><dt>Bots</dt><dd>{selection.bots}</dd></div><div><dt>Modules</dt><dd>{selection.modules.length}</dd></div><div><dt>Login account</dt><dd>{selection.accountName}{selection.adminAccount ? ' · Admin' : ''}{selection.autoLogin ? ' · Autologin' : ''}</dd></div><div><dt>Estimated build</dt><dd>{system.cpuThreads >= 12 ? '25–45 minutes' : system.cpuThreads >= 8 ? '40–70 minutes' : '60–100 minutes'}</dd></div><div><dt>Location</dt><dd>{selection.installRoot}/servers/{selection.serverId || 'default'}</dd></div></dl></section><section><p className="eyebrow">BEHAVIOR</p><ToggleRow label="Add a separate WoW Steam entry" checked={selection.steamShortcuts} onChange={(value) => set('steamShortcuts', value)} /><ToggleRow label="Stop server when WoW exits" checked={selection.stopWithGame} onChange={(value) => set('stopWithGame', value)} /><p className="estimate">Uses Wow-HD.exe when available and launches it separately through Proton Experimental.</p><p className="estimate">Estimated installed size <strong>{formatBytes(catalog.core.estimatedInstalledBytes + (profile?.estimatedBytes || 0))}</strong></p><p className="estimate">Currently free <strong>{formatBytes(system.disk.freeBytes)}</strong></p></section></div>}
        {step === 6 && <div className="install-stage">{!output.length && <><div className="install-summary"><span>{catalog.core.freshInstallReady ? 'Ready' : 'Test milestone'}</span><h2>{formatBytes(plan?.requiredBytes || 0)} installation</h2><p>{formatBytes(plan?.downloadBytes || 0)} download · {formatBytes(plan?.freeBytes || 0)} available · about {system.cpuThreads >= 12 ? '25–45' : system.cpuThreads >= 8 ? '40–70' : '60–100'} minutes</p></div>{plan && !plan.enoughSpace && <div className="toast error">Not enough free space with the required safety margin.</div>}<button className="primary-button large" disabled={!catalog.core.freshInstallReady || Boolean(plan && !plan.enoughSpace)} onClick={beginInstall}>Start Installation</button></>} {!!output.length && <><section className="install-hero"><div><p className="eyebrow">{installing ? 'INSTALLATION RUNNING' : complete ? 'INSTALLATION COMPLETE' : 'INSTALLATION PAUSED'}</p><h2>{complete ? 'Your server is ready' : installStages[Math.max(0, installPhase - 1)]?.[1] || 'Preparing installation'}</h2><p>{installationTiming}</p></div><div className="install-meters"><article><span>CPU</span><strong>{telemetry.cpuPercent}%</strong></article><article><span>RAM</span><strong>{formatBytes(telemetry.memoryUsedBytes)}</strong><small>of {formatBytes(telemetry.memoryTotalBytes)}</small></article></div></section><div className="install-progress"><span style={{ width: `${installPercent}%` }} /></div><div className="install-steps">{installStages.map(([title, detail], index) => <article key={title} className={complete || index + 1 < installPhase ? 'done' : index + 1 === installPhase ? 'active' : ''}><span>{complete || index + 1 < installPhase ? '✓' : index + 1}</span><div><strong>{title}</strong><small>{detail}</small></div></article>)}</div>{installing && <p className="install-state">Keep Azeroth Control open. Build work is cached automatically for safe resume.</p>}{!installing && !complete && <div className="install-recovery"><button className="ghost-button large" onClick={() => setStep(5)}>Back to Review</button><button className="primary-button large" onClick={beginInstall}>Resume Installation</button></div>}{complete && <button className="primary-button large" onClick={async () => { await bridge?.finishOnboarding(); await bridge?.restartApp(); onComplete(); }}>Open Control Center</button>}<details className="technical-log"><summary>Show technical installation log</summary><pre ref={logRef} className="install-output">{output.join('\n')}</pre></details></>}</div>}
      </>}
      {step > 0 && step < 6 && <footer className="wizard-actions"><button data-gamepad-back="true" className="ghost-button" onClick={() => setStep((current) => current - 1)}>Back</button><span>Step {step + 1} of {steps.length} · LB/RB or B/Start</span><button data-gamepad-primary="true" className="primary-button" onClick={next}>{step === 5 ? 'Create Install Plan' : 'Continue'}</button></footer>}
    </section>
  </main>;
}

function ToggleRow({ label, checked, onChange }: { label: string; checked: boolean; onChange: (value: boolean) => void }) {
  return <button className="review-toggle" onClick={() => onChange(!checked)}><span>{label}</span><b>{checked ? 'ON' : 'OFF'}</b></button>;
}
