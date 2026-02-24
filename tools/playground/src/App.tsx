import { useState, useCallback } from 'react';
import { Panel, PanelGroup, PanelResizeHandle } from 'react-resizable-panels';
import { Editor } from './components/Editor';
import { Preview } from './components/Preview';
import { ErrorPanel } from './components/ErrorPanel';
import { ExamplePicker } from './components/ExamplePicker';
import { FileTabs } from './components/FileTabs';
import { OutputTabs } from './components/OutputTabs';
import { StatusBar } from './components/StatusBar';
import { KeyboardShortcutsModal } from './components/KeyboardShortcutsModal';
import { ShareModal } from './components/ShareModal';
import { usePlayground } from './hooks/usePlayground';
import { useKeyboardShortcuts } from './hooks/useKeyboardShortcuts';
import { downloadAsZip } from './utils/sharing';
import type { PlaygroundFile } from './types';

function App(): JSX.Element {
  const {
    files,
    activeFileIndex,
    compiledOutput,
    errors,
    isCompiling,
    theme,
    activeOutputTab,
    setActiveFileIndex,
    updateFileContent,
    addFile,
    removeFile,
    loadExample,
    compile,
    toggleTheme,
    setActiveOutputTab,
    getShareUrl,
  } = usePlayground();

  const [showShortcuts, setShowShortcuts] = useState(false);
  const [showShare, setShowShare] = useState(false);

  const handleSave = useCallback(() => {
    downloadAsZip(files);
  }, [files]);

  const handleShare = useCallback(() => {
    setShowShare(true);
  }, []);

  useKeyboardShortcuts({
    onCompile: compile,
    onSave: handleSave,
    onShare: handleShare,
    onToggleTheme: toggleTheme,
    onShowHelp: () => setShowShortcuts(true),
  });

  const handleAddFile = useCallback(() => {
    const newFile: PlaygroundFile = {
      name: `Module${files.length + 1}.can`,
      content: `module Module${files.length + 1} exposing (..)\n\n-- Add your code here\n`,
      language: 'canopy',
    };
    addFile(newFile);
  }, [files.length, addFile]);

  const activeFile = files[activeFileIndex];

  return (
    <div className="app-container">
      <header className="header">
        <div className="header-left">
          <div className="logo">
            <CanopyLogo />
            <span>Canopy Playground</span>
          </div>
          <ExamplePicker onSelectExample={loadExample} />
        </div>
        <div className="header-actions">
          <button
            className="btn btn-primary"
            onClick={compile}
            disabled={isCompiling}
          >
            {isCompiling ? (
              <>
                <span className="loading-spinner" />
                <span>Compiling</span>
              </>
            ) : (
              <>
                <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
                  <path d="M11.596 8.697l-6.363 3.692c-.54.313-1.233-.066-1.233-.697V4.308c0-.63.692-1.01 1.233-.696l6.363 3.692a.802.802 0 0 1 0 1.393z"/>
                </svg>
                <span>Run</span>
              </>
            )}
          </button>
          <button
            className="btn btn-secondary tooltip"
            onClick={handleShare}
            data-tooltip="Share code"
          >
            <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
              <path d="M11 2.5a2.5 2.5 0 1 1 .603 1.628l-6.718 3.12a2.499 2.499 0 0 1 0 1.504l6.718 3.12a2.5 2.5 0 1 1-.488.876l-6.718-3.12a2.5 2.5 0 1 1 0-3.256l6.718-3.12A2.5 2.5 0 0 1 11 2.5zm-8.5 4a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3zm8.5-2a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3zm0 9a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z"/>
            </svg>
            <span>Share</span>
          </button>
          <button
            className="btn btn-secondary tooltip"
            onClick={handleSave}
            data-tooltip="Download project"
          >
            <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
              <path d="M7.47 10.78a.75.75 0 0 0 1.06 0l3.75-3.75a.75.75 0 0 0-1.06-1.06L8.75 8.44V1.75a.75.75 0 0 0-1.5 0v6.69L4.78 5.97a.75.75 0 0 0-1.06 1.06l3.75 3.75zM3.75 13a.75.75 0 0 0 0 1.5h8.5a.75.75 0 0 0 0-1.5h-8.5z"/>
            </svg>
            <span>Download</span>
          </button>
          <button
            className="btn btn-icon tooltip"
            onClick={toggleTheme}
            data-tooltip={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
          >
            {theme === 'dark' ? (
              <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
                <path d="M8 11a3 3 0 1 1 0-6 3 3 0 0 1 0 6zm0 1a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM8 0a.5.5 0 0 1 .5.5v2a.5.5 0 0 1-1 0v-2A.5.5 0 0 1 8 0zm0 13a.5.5 0 0 1 .5.5v2a.5.5 0 0 1-1 0v-2A.5.5 0 0 1 8 13zm8-5a.5.5 0 0 1-.5.5h-2a.5.5 0 0 1 0-1h2a.5.5 0 0 1 .5.5zM3 8a.5.5 0 0 1-.5.5h-2a.5.5 0 0 1 0-1h2A.5.5 0 0 1 3 8zm10.657-5.657a.5.5 0 0 1 0 .707l-1.414 1.415a.5.5 0 1 1-.707-.708l1.414-1.414a.5.5 0 0 1 .707 0zm-9.193 9.193a.5.5 0 0 1 0 .707L3.05 13.657a.5.5 0 0 1-.707-.707l1.414-1.414a.5.5 0 0 1 .707 0zm9.193 2.121a.5.5 0 0 1-.707 0l-1.414-1.414a.5.5 0 0 1 .707-.707l1.414 1.414a.5.5 0 0 1 0 .707zM4.464 4.465a.5.5 0 0 1-.707 0L2.343 3.05a.5.5 0 1 1 .707-.707l1.414 1.414a.5.5 0 0 1 0 .708z"/>
              </svg>
            ) : (
              <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
                <path d="M6 .278a.768.768 0 0 1 .08.858 7.208 7.208 0 0 0-.878 3.46c0 4.021 3.278 7.277 7.318 7.277.527 0 1.04-.055 1.533-.16a.787.787 0 0 1 .81.316.733.733 0 0 1-.031.893A8.349 8.349 0 0 1 8.344 16C3.734 16 0 12.286 0 7.71 0 4.266 2.114 1.312 5.124.06A.752.752 0 0 1 6 .278z"/>
              </svg>
            )}
          </button>
          <button
            className="btn btn-icon tooltip"
            onClick={() => setShowShortcuts(true)}
            data-tooltip="Keyboard shortcuts"
          >
            <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
              <path d="M14 5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H2a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h12zM2 4a2 2 0 0 0-2 2v5a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2H2z"/>
              <path d="M13 10.25a.25.25 0 0 1 .25-.25h.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-.5a.25.25 0 0 1-.25-.25v-.5zm0-2a.25.25 0 0 1 .25-.25h.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-.5a.25.25 0 0 1-.25-.25v-.5zm-5 0A.25.25 0 0 1 8.25 8h.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-.5A.25.25 0 0 1 8 8.75v-.5zm2 0a.25.25 0 0 1 .25-.25h1.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-1.5a.25.25 0 0 1-.25-.25v-.5zm1 2a.25.25 0 0 1 .25-.25h.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-.5a.25.25 0 0 1-.25-.25v-.5zm-5-2A.25.25 0 0 1 6.25 8h.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-.5A.25.25 0 0 1 6 8.75v-.5zm-2 0A.25.25 0 0 1 4.25 8h.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-.5A.25.25 0 0 1 4 8.75v-.5zm-2 0A.25.25 0 0 1 2.25 8h.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-.5A.25.25 0 0 1 2 8.75v-.5zm11-2a.25.25 0 0 1 .25-.25h.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-.5a.25.25 0 0 1-.25-.25v-.5zm-2 0a.25.25 0 0 1 .25-.25h.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-.5a.25.25 0 0 1-.25-.25v-.5zm-2 0A.25.25 0 0 1 9.25 6h.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-.5A.25.25 0 0 1 9 6.75v-.5zm-2 0A.25.25 0 0 1 7.25 6h.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-.5A.25.25 0 0 1 7 6.75v-.5zm-2 0A.25.25 0 0 1 5.25 6h.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-.5A.25.25 0 0 1 5 6.75v-.5zm-3 0A.25.25 0 0 1 2.25 6h1.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-1.5A.25.25 0 0 1 2 6.75v-.5zm0 4a.25.25 0 0 1 .25-.25h.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-.5a.25.25 0 0 1-.25-.25v-.5zm2 0a.25.25 0 0 1 .25-.25h5.5a.25.25 0 0 1 .25.25v.5a.25.25 0 0 1-.25.25h-5.5a.25.25 0 0 1-.25-.25v-.5z"/>
            </svg>
          </button>
        </div>
      </header>

      <main className="main-content">
        <PanelGroup direction="horizontal">
          <Panel defaultSize={50} minSize={30}>
            <div className="panel editor-panel">
              <FileTabs
                files={files}
                activeIndex={activeFileIndex}
                onSelectFile={setActiveFileIndex}
                onCloseFile={removeFile}
                onAddFile={handleAddFile}
              />
              <div className="panel-content">
                <Editor
                  value={activeFile?.content ?? ''}
                  onChange={(content) => updateFileContent(activeFileIndex, content)}
                  language={activeFile?.language ?? 'canopy'}
                  theme={theme}
                  errors={errors}
                />
              </div>
            </div>
          </Panel>

          <PanelResizeHandle className="resize-handle" />

          <Panel defaultSize={50} minSize={30}>
            <div className="panel output-panel">
              <OutputTabs
                activeTab={activeOutputTab}
                onTabChange={setActiveOutputTab}
                errorCount={errors.length}
              />
              <div className="panel-content">
                {activeOutputTab === 'preview' && (
                  <Preview
                    compiledOutput={compiledOutput}
                    isCompiling={isCompiling}
                  />
                )}
                {activeOutputTab === 'javascript' && (
                  <div className="code-output">
                    {compiledOutput || '// No compiled output yet. Press Run to compile.'}
                  </div>
                )}
                {activeOutputTab === 'errors' && (
                  <ErrorPanel errors={errors} />
                )}
              </div>
            </div>
          </Panel>
        </PanelGroup>
      </main>

      <StatusBar
        isCompiling={isCompiling}
        errorCount={errors.length}
        fileName={activeFile?.name}
      />

      <KeyboardShortcutsModal
        isOpen={showShortcuts}
        onClose={() => setShowShortcuts(false)}
      />

      <ShareModal
        isOpen={showShare}
        onClose={() => setShowShare(false)}
        shareUrl={getShareUrl()}
      />
    </div>
  );
}

function CanopyLogo(): JSX.Element {
  return (
    <svg width="28" height="28" viewBox="0 0 28 28" fill="none" xmlns="http://www.w3.org/2000/svg">
      <rect width="28" height="28" rx="6" fill="url(#canopy-gradient)"/>
      <path
        d="M14 6C9.58 6 6 9.58 6 14C6 18.42 9.58 22 14 22C18.42 22 22 18.42 22 14"
        stroke="white"
        strokeWidth="2.5"
        strokeLinecap="round"
      />
      <path
        d="M14 10C11.79 10 10 11.79 10 14C10 16.21 11.79 18 14 18"
        stroke="white"
        strokeWidth="2.5"
        strokeLinecap="round"
      />
      <circle cx="20" cy="8" r="2" fill="white"/>
      <defs>
        <linearGradient id="canopy-gradient" x1="0" y1="0" x2="28" y2="28" gradientUnits="userSpaceOnUse">
          <stop stopColor="#38bdf8"/>
          <stop offset="1" stopColor="#818cf8"/>
        </linearGradient>
      </defs>
    </svg>
  );
}

export default App;
