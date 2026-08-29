export {};

type DesktopModule = { id: string; name: string; description: string; required?: boolean; default?: boolean; conflicts?: string[]; license: string; estimatedBytes: number };
type DesktopProfile = { id: string; name: string; expansion: string; description: string; levelCap: number; recommendedBots: number; estimatedBytes: number };
type DesktopCatalog = { core: { name: string; estimatedDownloadBytes: number; estimatedInstalledBytes: number; freshInstallReady?: boolean }; profiles: DesktopProfile[]; modules: DesktopModule[] };
type DesktopSystemInfo = { platform: string; release: string; cpuModel: string; cpuThreads: number; memoryBytes: number; disk: { freeBytes: number; totalBytes: number }; defaultInstallRoot: string; dependencies: Record<string, boolean> };
type DesktopSelection = { mode: 'new' | 'import'; installRoot: string; clientPath: string; profile: string; bots: number; modules: string[]; stopWithGame: boolean; steamShortcuts: boolean; serverId?: string; serverName?: string; accountName?: string; accountPassword?: string; adminAccount?: boolean; autoLogin?: boolean };
type DesktopInstallation = { id: string; name: string; path: string; provider: string; imported: boolean; createdAt: string };
type DesktopState = { schemaVersion: number; onboardingComplete: boolean; activeInstallationId: string | null; installations: DesktopInstallation[] };
type DesktopPlan = { requiredBytes: number; downloadBytes: number; freeBytes: number; enoughSpace: boolean; steps: string[] };
type DesktopControllerPreset = { version: string; installed: boolean; addonInstalled: boolean; steamTemplatesInstalled: number; steamTemplatesExpected: number; steamTemplateName: string; backupPath: string; installedAt: string };
type DesktopAddonState = { clientPath: string; addonsPath: string; steamInput: { found: boolean; shortcutName: string; gameId: string }; addons: Array<{ id: string; name: string; version: string; category: string; description: string; note: string; sourceUrl: string; installed: boolean; installedVersion: string | null }>; controllerPreset: DesktopControllerPreset };
type DesktopInstallProgress = { type?: string; ok?: boolean; message?: string };

declare global {
  interface Window {
    azerothDesktop?: {
      getSystemInfo(): Promise<DesktopSystemInfo>;
      getInstallTelemetry(): Promise<{ cpuPercent: number; memoryUsedBytes: number; memoryTotalBytes: number }>;
      getUiMetrics(): Promise<{ width: number; height: number; recommendedScale: number }>;
      setUiScale(scale: number): Promise<number>;
      getCatalog(): Promise<DesktopCatalog>;
      getState(): Promise<DesktopState>;
      chooseDirectory(kind: 'install' | 'client'): Promise<string | null>;
      validateClient(path: string): Promise<{ ok: boolean; path?: string; message: string }>;
      openKeyboard(): Promise<boolean>;
      launchGame(): Promise<{ ok: boolean; message: string }>;
      getAddons(): Promise<DesktopAddonState>;
      openSteamInput(): Promise<{ ok: boolean; shortcutName: string }>;
      installAddon(id: string): Promise<DesktopAddonState>;
      removeAddon(id: string): Promise<DesktopAddonState>;
      installControllerPreset(): Promise<DesktopAddonState>;
      detectInstallations(): Promise<Array<{ path: string; name: string; realms: number; resumable?: boolean; selection?: DesktopSelection }>>;
      importInstallation(path: string): Promise<DesktopInstallation>;
      selectInstallation(id: string): Promise<DesktopState>;
      removeInstallation(id: string, deleteFiles: boolean): Promise<DesktopState>;
      createPlan(selection: DesktopSelection): Promise<DesktopPlan>;
      startInstallation(selection: DesktopSelection): Promise<{ ok: boolean }>;
      onInstallProgress(listener: (event: DesktopInstallProgress) => void): () => void;
      finishOnboarding(): Promise<DesktopState>;
      resetOnboarding(): Promise<DesktopState>;
      restartApp(): Promise<void>;
      quitApp(): Promise<void>;
    };
  }
}
