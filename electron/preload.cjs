const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('azerothDesktop', {
  getSystemInfo: () => ipcRenderer.invoke('system-info'),
  getInstallTelemetry: () => ipcRenderer.invoke('install-telemetry'),
  getUiMetrics: () => ipcRenderer.invoke('ui-metrics'),
  setUiScale: (scale) => ipcRenderer.invoke('ui-scale-set', scale),
  getCatalog: () => ipcRenderer.invoke('catalog'),
  getState: () => ipcRenderer.invoke('state-get'),
  chooseDirectory: (kind) => ipcRenderer.invoke('choose-directory', kind),
  validateClient: (path) => ipcRenderer.invoke('client-validate', path),
  openKeyboard: () => ipcRenderer.invoke('keyboard-open'),
  launchGame: () => ipcRenderer.invoke('game-launch'),
  getAddons: () => ipcRenderer.invoke('addons-get'),
  openSteamInput: () => ipcRenderer.invoke('steam-input-open'),
  installAddon: (id) => ipcRenderer.invoke('addon-install', id),
  removeAddon: (id) => ipcRenderer.invoke('addon-remove', id),
  installControllerPreset: () => ipcRenderer.invoke('controller-preset-install'),
  detectInstallations: () => ipcRenderer.invoke('installations-detect'),
  importInstallation: (path) => ipcRenderer.invoke('installation-import', path),
  selectInstallation: (id) => ipcRenderer.invoke('installation-select', id),
  removeInstallation: (id, deleteFiles) => ipcRenderer.invoke('installation-remove', id, deleteFiles),
  createPlan: (selection) => ipcRenderer.invoke('install-plan', selection),
  startInstallation: (selection) => ipcRenderer.invoke('install-start', selection),
  onInstallProgress: (listener) => {
    const handler = (_event, payload) => listener(payload);
    ipcRenderer.on('install-progress', handler);
    return () => ipcRenderer.removeListener('install-progress', handler);
  },
  finishOnboarding: () => ipcRenderer.invoke('onboarding-finish'),
  resetOnboarding: () => ipcRenderer.invoke('onboarding-reset'),
  restartApp: () => ipcRenderer.invoke('app-restart'),
  quitApp: () => ipcRenderer.invoke('app-quit'),
});
