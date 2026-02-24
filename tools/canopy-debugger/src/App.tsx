/**
 * Main App component for the Canopy Debugger
 */

import React, { useEffect } from 'react';
import { DebuggerPanel } from './components/DebuggerPanel';
import { useDebuggerStore } from './store';
import './styles/main.css';

export const App: React.FC = () => {
  const connect = useDebuggerStore((state) => state.connect);
  const websocketUrl = useDebuggerStore((state) => state.websocketUrl);

  // Auto-connect on mount
  useEffect(() => {
    connect(websocketUrl);
  }, [connect, websocketUrl]);

  return (
    <div className="app">
      <DebuggerPanel />
    </div>
  );
};

export default App;
