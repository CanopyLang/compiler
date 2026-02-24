/**
 * Main Debugger Panel component
 */

import React, { useState, useCallback, useRef } from 'react';
import { useDebuggerStore, getFilteredHistory } from '../store';
import { Timeline } from './Timeline';
import { StateInspector } from './StateInspector';
import { MessageDetails } from './MessageDetails';
import { FilterPanel } from './FilterPanel';
import type { DebugSession } from '../types';

export const DebuggerPanel: React.FC = () => {
  const store = useDebuggerStore();
  const [showFilters, setShowFilters] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const filteredHistory = getFilteredHistory(store);

  const selectedEntry =
    store.selectedIndex !== null
      ? store.history.find((e) => e.index === store.selectedIndex)
      : null;

  const previousEntry =
    selectedEntry && store.selectedIndex !== null && store.selectedIndex > 0
      ? store.history.find((e) => e.index === store.selectedIndex - 1)
      : null;

  const handleExport = useCallback(async () => {
    const json = await store.exportSession();
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `canopy-debug-${Date.now()}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }, [store]);

  const handleImport = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      const file = event.target.files?.[0];
      if (!file) return;

      const reader = new FileReader();
      reader.onload = (e) => {
        try {
          const session = JSON.parse(e.target?.result as string) as DebugSession;
          store.importSession(session);
        } catch (err) {
          console.error('Failed to import session:', err);
          alert('Failed to import session: Invalid file format');
        }
      };
      reader.readAsText(file);

      // Reset input
      event.target.value = '';
    },
    [store]
  );

  return (
    <div className="debugger-panel">
      <header className="debugger-header">
        <div className="header-left">
          <h1 className="debugger-title">
            <CanopyLogo />
            Canopy Debugger
          </h1>
          <ConnectionStatus
            state={store.connectionState}
            url={store.websocketUrl}
            onConnect={() => store.connect(store.websocketUrl)}
            onDisconnect={store.disconnect}
          />
        </div>

        <div className="header-controls">
          <TimeControls
            canStepBack={store.currentIndex > 0}
            canStepForward={store.currentIndex < store.history.length - 1}
            isPaused={store.isPaused}
            onStepBack={store.stepBackward}
            onStepForward={store.stepForward}
            onTogglePause={store.togglePause}
          />

          <div className="header-actions">
            <button
              className="action-button"
              onClick={() => setShowFilters(!showFilters)}
              title="Toggle filters"
            >
              <FilterIcon />
              {store.filters.filter((f) => f.enabled).length > 0 && (
                <span className="filter-badge">
                  {store.filters.filter((f) => f.enabled).length}
                </span>
              )}
            </button>

            <button
              className="action-button"
              onClick={handleExport}
              title="Export session"
            >
              <ExportIcon />
            </button>

            <button
              className="action-button"
              onClick={() => fileInputRef.current?.click()}
              title="Import session"
            >
              <ImportIcon />
            </button>

            <input
              ref={fileInputRef}
              type="file"
              accept=".json"
              style={{ display: 'none' }}
              onChange={handleImport}
            />

            <button
              className="action-button danger"
              onClick={store.clearHistory}
              title="Clear history"
            >
              <TrashIcon />
            </button>
          </div>
        </div>
      </header>

      {showFilters && (
        <FilterPanel
          filters={store.filters}
          searchQuery={store.searchQuery}
          onSearchChange={store.setSearchQuery}
          onAddFilter={store.addFilter}
          onRemoveFilter={store.removeFilter}
          onToggleFilter={store.toggleFilter}
          onClose={() => setShowFilters(false)}
        />
      )}

      <div className="debugger-content">
        <aside className="timeline-panel">
          <div className="panel-header">
            <span>Timeline</span>
            <button
              className={`toggle-button ${store.compactMode ? 'active' : ''}`}
              onClick={store.toggleCompactMode}
              title="Toggle compact mode"
            >
              <CompactIcon />
            </button>
          </div>
          <Timeline
            entries={filteredHistory}
            currentIndex={store.currentIndex}
            selectedIndex={store.selectedIndex}
            onSelect={store.selectEntry}
            onJump={store.jumpTo}
            compactMode={store.compactMode}
          />
        </aside>

        <main className="inspector-panel">
          {selectedEntry ? (
            <>
              <section className="message-section">
                <div className="panel-header">
                  <span>Message</span>
                </div>
                <MessageDetails entry={selectedEntry} previousEntry={previousEntry || undefined} />
              </section>

              <section className="state-section">
                <div className="panel-header">
                  <span>State</span>
                  <button
                    className={`toggle-button ${store.showDiff ? 'active' : ''}`}
                    onClick={store.toggleDiff}
                    title="Toggle diff view"
                  >
                    <DiffIcon />
                  </button>
                </div>
                <StateInspector
                  state={selectedEntry.state}
                  previousState={previousEntry?.state}
                  showDiff={store.showDiff}
                />
              </section>
            </>
          ) : (
            <div className="no-selection">
              <p>Select a message from the timeline to inspect its details.</p>
            </div>
          )}
        </main>
      </div>

      <footer className="debugger-footer">
        <span className="footer-stats">
          {store.history.length} messages
          {filteredHistory.length !== store.history.length &&
            ` (${filteredHistory.length} shown)`}
        </span>
        <span className="footer-position">
          Position: {store.currentIndex + 1} / {store.history.length}
        </span>
      </footer>
    </div>
  );
};

// Sub-components

interface ConnectionStatusProps {
  state: string;
  url: string;
  onConnect: () => void;
  onDisconnect: () => void;
}

const ConnectionStatus: React.FC<ConnectionStatusProps> = ({
  state,
  url,
  onConnect,
  onDisconnect
}) => {
  const [editUrl, setEditUrl] = useState(false);
  const [urlValue, setUrlValue] = useState(url);

  const statusClass = {
    connected: 'status-connected',
    connecting: 'status-connecting',
    disconnected: 'status-disconnected',
    error: 'status-error'
  }[state] || 'status-disconnected';

  return (
    <div className="connection-status">
      <span className={`status-indicator ${statusClass}`} />
      {editUrl ? (
        <input
          type="text"
          value={urlValue}
          onChange={(e) => setUrlValue(e.target.value)}
          onBlur={() => setEditUrl(false)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              onConnect();
              setEditUrl(false);
            }
            if (e.key === 'Escape') {
              setEditUrl(false);
            }
          }}
          autoFocus
          className="url-input"
        />
      ) : (
        <span className="status-url" onClick={() => setEditUrl(true)}>
          {url}
        </span>
      )}
      {state === 'connected' ? (
        <button className="connect-button" onClick={onDisconnect}>
          Disconnect
        </button>
      ) : (
        <button className="connect-button" onClick={onConnect}>
          Connect
        </button>
      )}
    </div>
  );
};

interface TimeControlsProps {
  canStepBack: boolean;
  canStepForward: boolean;
  isPaused: boolean;
  onStepBack: () => void;
  onStepForward: () => void;
  onTogglePause: () => void;
}

const TimeControls: React.FC<TimeControlsProps> = ({
  canStepBack,
  canStepForward,
  isPaused,
  onStepBack,
  onStepForward,
  onTogglePause
}) => (
  <div className="time-controls">
    <button
      className="time-button"
      onClick={onStepBack}
      disabled={!canStepBack}
      title="Step backward"
    >
      <StepBackIcon />
    </button>

    <button
      className={`time-button ${isPaused ? 'paused' : ''}`}
      onClick={onTogglePause}
      title={isPaused ? 'Resume' : 'Pause'}
    >
      {isPaused ? <PlayIcon /> : <PauseIcon />}
    </button>

    <button
      className="time-button"
      onClick={onStepForward}
      disabled={!canStepForward}
      title="Step forward"
    >
      <StepForwardIcon />
    </button>
  </div>
);

// Icons

const CanopyLogo: React.FC = () => (
  <svg viewBox="0 0 24 24" width="24" height="24" className="canopy-logo">
    <path
      fill="currentColor"
      d="M12 2L4 7v10l8 5 8-5V7l-8-5zm0 2.18l6 3.75v7.14l-6 3.75-6-3.75V7.93l6-3.75z"
    />
  </svg>
);

const FilterIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path fill="currentColor" d="M10 18h4v-2h-4v2zM3 6v2h18V6H3zm3 7h12v-2H6v2z" />
  </svg>
);

const ExportIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path fill="currentColor" d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z" />
  </svg>
);

const ImportIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path fill="currentColor" d="M9 16h6v-6h4l-7-7-7 7h4v6zm-4 2h14v2H5v-2z" />
  </svg>
);

const TrashIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path fill="currentColor" d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z" />
  </svg>
);

const CompactIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path fill="currentColor" d="M3 15h18v-2H3v2zm0 4h18v-2H3v2zm0-8h18V9H3v2zm0-6v2h18V5H3z" />
  </svg>
);

const DiffIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path fill="currentColor" d="M9 7H7v2h2V7zm0 4H7v2h2v-2zm0-8a2 2 0 00-2 2v14a2 2 0 002 2h6v-2H9V5h6V3H9zm8 6h2v2h-2v-2zm-4 0h2v2h-2v-2zm8 0v6a2 2 0 01-2 2h-4v-2h4v-6h-4v-2h4a2 2 0 012 2z" />
  </svg>
);

const StepBackIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path fill="currentColor" d="M6 6h2v12H6V6zm3.5 6l8.5 6V6l-8.5 6z" />
  </svg>
);

const StepForwardIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path fill="currentColor" d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z" />
  </svg>
);

const PlayIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path fill="currentColor" d="M8 5v14l11-7z" />
  </svg>
);

const PauseIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path fill="currentColor" d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
  </svg>
);

export default DebuggerPanel;
