import React from 'react';
import ReactDOM from 'react-dom/client';
import { useEffect, useState } from 'react';
import Home from '../app/page';
import Installer from '../app/Installer';
import { useGamepadNavigation } from './useGamepadNavigation';
import '../app/globals.css';

function App() {
  const [loading, setLoading] = useState(Boolean(window.azerothDesktop));
  const [setup, setSetup] = useState(new URLSearchParams(location.search).has('setup'));
  useGamepadNavigation(!loading && !setup);
  useEffect(() => {
    const saved = Number(localStorage.getItem('azeroth-control-ui-scale') || 0);
    void window.azerothDesktop?.setUiScale(saved);
  }, []);
  useEffect(() => {
    if (!window.azerothDesktop) return;
    window.azerothDesktop.getState().then((state) => { setSetup(!state.onboardingComplete); setLoading(false); });
  }, []);
  if (loading) return <main className="boot-screen"><span className="brand-mark">A</span><strong>Azeroth Control</strong><small>Starting local services…</small></main>;
  async function leaveSetup() {
    await window.azerothDesktop?.finishOnboarding();
    setSetup(false);
  }
  return setup ? <Installer onComplete={() => setSetup(false)} onCancel={leaveSetup} /> : <Home />;
}

ReactDOM.createRoot(document.getElementById('root')!).render(<React.StrictMode><App /></React.StrictMode>);
