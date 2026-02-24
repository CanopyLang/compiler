/**
 * Canopy Debugger Webview Panel for VS Code
 *
 * Provides time-travel debugging capabilities within VS Code.
 */

import * as vscode from 'vscode';
import * as path from 'path';

interface HistoryEntry {
  index: number;
  timestamp: number;
  message: string;
  state: string;
}

interface DebuggerState {
  isConnected: boolean;
  history: HistoryEntry[];
  currentIndex: number;
  selectedIndex: number | null;
}

export class CanopyDebuggerPanel {
  public static currentPanel: CanopyDebuggerPanel | undefined;
  public static readonly viewType = 'canopyDebugger';

  private readonly _panel: vscode.WebviewPanel;
  private readonly _extensionUri: vscode.Uri;
  private _disposables: vscode.Disposable[] = [];
  private _websocket: WebSocket | null = null;
  private _state: DebuggerState = {
    isConnected: false,
    history: [],
    currentIndex: -1,
    selectedIndex: null
  };

  public static createOrShow(extensionUri: vscode.Uri): void {
    const column = vscode.window.activeTextEditor
      ? vscode.window.activeTextEditor.viewColumn
      : undefined;

    if (CanopyDebuggerPanel.currentPanel) {
      CanopyDebuggerPanel.currentPanel._panel.reveal(column);
      return;
    }

    const panel = vscode.window.createWebviewPanel(
      CanopyDebuggerPanel.viewType,
      'Canopy Debugger',
      column || vscode.ViewColumn.Two,
      {
        enableScripts: true,
        retainContextWhenHidden: true,
        localResourceRoots: [vscode.Uri.joinPath(extensionUri, 'media')]
      }
    );

    CanopyDebuggerPanel.currentPanel = new CanopyDebuggerPanel(panel, extensionUri);
  }

  public static revive(panel: vscode.WebviewPanel, extensionUri: vscode.Uri): void {
    CanopyDebuggerPanel.currentPanel = new CanopyDebuggerPanel(panel, extensionUri);
  }

  private constructor(panel: vscode.WebviewPanel, extensionUri: vscode.Uri) {
    this._panel = panel;
    this._extensionUri = extensionUri;

    this._update();

    this._panel.onDidDispose(() => this.dispose(), null, this._disposables);

    this._panel.onDidChangeViewState(
      () => {
        if (this._panel.visible) {
          this._update();
        }
      },
      null,
      this._disposables
    );

    this._panel.webview.onDidReceiveMessage(
      (message) => this._handleMessage(message),
      null,
      this._disposables
    );
  }

  public dispose(): void {
    CanopyDebuggerPanel.currentPanel = undefined;

    if (this._websocket) {
      this._websocket.close();
      this._websocket = null;
    }

    this._panel.dispose();

    while (this._disposables.length) {
      const disposable = this._disposables.pop();
      if (disposable) {
        disposable.dispose();
      }
    }
  }

  private _handleMessage(message: any): void {
    switch (message.command) {
      case 'connect':
        this._connect(message.url);
        break;
      case 'disconnect':
        this._disconnect();
        break;
      case 'jumpTo':
        this._sendToServer({ type: 'jumpTo', index: message.index });
        break;
      case 'stepForward':
        this._sendToServer({ type: 'stepForward' });
        break;
      case 'stepBackward':
        this._sendToServer({ type: 'stepBackward' });
        break;
      case 'export':
        this._exportSession();
        break;
      case 'import':
        this._importSession();
        break;
      case 'clearHistory':
        this._sendToServer({ type: 'clearHistory' });
        this._state.history = [];
        this._state.currentIndex = -1;
        this._updateWebview();
        break;
    }
  }

  private _connect(url: string): void {
    if (this._websocket) {
      this._websocket.close();
    }

    try {
      this._websocket = new (require('ws'))(url + '?type=vscode');

      this._websocket.onopen = () => {
        this._state.isConnected = true;
        this._updateWebview();
        this._sendToServer({ type: 'handshake', version: '1.0.0', client: 'vscode' });
        this._sendToServer({ type: 'getHistory' });
        vscode.window.showInformationMessage('Connected to Canopy Debug Server');
      };

      this._websocket.onmessage = (event: any) => {
        try {
          const data = JSON.parse(event.data);
          this._handleServerMessage(data);
        } catch (e) {
          console.error('Failed to parse message:', e);
        }
      };

      this._websocket.onclose = () => {
        this._state.isConnected = false;
        this._updateWebview();
      };

      this._websocket.onerror = (error: any) => {
        console.error('WebSocket error:', error);
        vscode.window.showErrorMessage('Failed to connect to Canopy Debug Server');
      };
    } catch (e) {
      vscode.window.showErrorMessage('Failed to connect: ' + (e as Error).message);
    }
  }

  private _disconnect(): void {
    if (this._websocket) {
      this._websocket.close();
      this._websocket = null;
    }
    this._state.isConnected = false;
    this._updateWebview();
  }

  private _sendToServer(message: any): void {
    if (this._websocket && this._websocket.readyState === 1) {
      this._websocket.send(JSON.stringify(message));
    }
  }

  private _handleServerMessage(data: any): void {
    switch (data.type) {
      case 'entry':
        this._state.history.push(data.entry);
        this._state.currentIndex = this._state.history.length - 1;
        this._updateWebview();
        break;

      case 'history':
      case 'sync':
        this._state.history = data.history || [];
        this._state.currentIndex = this._state.history.length - 1;
        this._updateWebview();
        break;

      case 'jumped':
        this._state.currentIndex = data.index;
        this._updateWebview();
        break;

      case 'historyCleared':
        this._state.history = [];
        this._state.currentIndex = -1;
        this._updateWebview();
        break;
    }
  }

  private async _exportSession(): Promise<void> {
    const session = {
      version: '1.0.0',
      timestamp: Date.now(),
      history: this._state.history,
      currentIndex: this._state.currentIndex
    };

    const uri = await vscode.window.showSaveDialog({
      defaultUri: vscode.Uri.file(`canopy-debug-${Date.now()}.json`),
      filters: { 'JSON': ['json'] }
    });

    if (uri) {
      const content = JSON.stringify(session, null, 2);
      await vscode.workspace.fs.writeFile(uri, Buffer.from(content, 'utf8'));
      vscode.window.showInformationMessage('Debug session exported');
    }
  }

  private async _importSession(): Promise<void> {
    const uris = await vscode.window.showOpenDialog({
      canSelectMany: false,
      filters: { 'JSON': ['json'] }
    });

    if (uris && uris.length > 0) {
      const content = await vscode.workspace.fs.readFile(uris[0]);
      try {
        const session = JSON.parse(content.toString());
        this._state.history = session.history || [];
        this._state.currentIndex = session.currentIndex || 0;
        this._updateWebview();

        if (this._websocket) {
          this._sendToServer({ type: 'import', session });
        }

        vscode.window.showInformationMessage('Debug session imported');
      } catch (e) {
        vscode.window.showErrorMessage('Failed to import session: Invalid file format');
      }
    }
  }

  private _updateWebview(): void {
    this._panel.webview.postMessage({
      type: 'update',
      state: this._state
    });
  }

  private _update(): void {
    this._panel.title = 'Canopy Debugger';
    this._panel.webview.html = this._getHtmlForWebview();
  }

  private _getHtmlForWebview(): string {
    const nonce = getNonce();

    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';">
  <title>Canopy Debugger</title>
  <style>
    :root {
      --vscode-bg: var(--vscode-editor-background);
      --vscode-fg: var(--vscode-editor-foreground);
      --vscode-border: var(--vscode-panel-border);
      --vscode-button-bg: var(--vscode-button-background);
      --vscode-button-fg: var(--vscode-button-foreground);
      --vscode-input-bg: var(--vscode-input-background);
      --vscode-input-fg: var(--vscode-input-foreground);
      --vscode-input-border: var(--vscode-input-border);
      --vscode-list-hover: var(--vscode-list-hoverBackground);
      --vscode-list-active: var(--vscode-list-activeSelectionBackground);
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: var(--vscode-font-family);
      font-size: var(--vscode-font-size);
      color: var(--vscode-fg);
      background: var(--vscode-bg);
      padding: 16px;
    }

    .header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 16px;
      padding-bottom: 16px;
      border-bottom: 1px solid var(--vscode-border);
    }

    h1 {
      font-size: 18px;
      font-weight: 600;
    }

    .connection {
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .status-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #6e6e6e;
    }

    .status-dot.connected {
      background: #4caf50;
    }

    input {
      padding: 6px 10px;
      background: var(--vscode-input-bg);
      color: var(--vscode-input-fg);
      border: 1px solid var(--vscode-input-border);
      border-radius: 4px;
      font-size: 12px;
      width: 200px;
    }

    button {
      padding: 6px 12px;
      background: var(--vscode-button-bg);
      color: var(--vscode-button-fg);
      border: none;
      border-radius: 4px;
      cursor: pointer;
      font-size: 12px;
    }

    button:hover {
      opacity: 0.9;
    }

    button:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }

    .controls {
      display: flex;
      align-items: center;
      gap: 8px;
      margin-bottom: 16px;
    }

    .time-controls {
      display: flex;
      gap: 4px;
    }

    .time-controls button {
      padding: 4px 8px;
    }

    .content {
      display: flex;
      gap: 16px;
      height: calc(100vh - 150px);
    }

    .timeline {
      width: 300px;
      border: 1px solid var(--vscode-border);
      border-radius: 4px;
      overflow: hidden;
      display: flex;
      flex-direction: column;
    }

    .timeline-header {
      padding: 8px 12px;
      background: var(--vscode-sideBar-background);
      border-bottom: 1px solid var(--vscode-border);
      font-weight: 500;
      font-size: 12px;
    }

    .timeline-list {
      flex: 1;
      overflow-y: auto;
    }

    .timeline-entry {
      padding: 8px 12px;
      border-bottom: 1px solid var(--vscode-border);
      cursor: pointer;
      font-size: 12px;
    }

    .timeline-entry:hover {
      background: var(--vscode-list-hover);
    }

    .timeline-entry.selected {
      background: var(--vscode-list-active);
    }

    .timeline-entry.current {
      border-left: 3px solid #4caf50;
    }

    .entry-header {
      display: flex;
      justify-content: space-between;
      margin-bottom: 4px;
      color: var(--vscode-descriptionForeground);
      font-size: 11px;
    }

    .entry-message {
      font-family: var(--vscode-editor-font-family);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .inspector {
      flex: 1;
      border: 1px solid var(--vscode-border);
      border-radius: 4px;
      overflow: hidden;
      display: flex;
      flex-direction: column;
    }

    .inspector-header {
      padding: 8px 12px;
      background: var(--vscode-sideBar-background);
      border-bottom: 1px solid var(--vscode-border);
      font-weight: 500;
      font-size: 12px;
    }

    .inspector-content {
      flex: 1;
      padding: 12px;
      overflow: auto;
    }

    .state-view {
      font-family: var(--vscode-editor-font-family);
      font-size: 12px;
      white-space: pre-wrap;
      word-break: break-all;
    }

    .no-selection {
      color: var(--vscode-descriptionForeground);
      text-align: center;
      padding: 24px;
    }

    .empty-state {
      color: var(--vscode-descriptionForeground);
      text-align: center;
      padding: 24px;
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>Canopy Debugger</h1>
    <div class="connection">
      <span class="status-dot" id="statusDot"></span>
      <input type="text" id="urlInput" value="ws://localhost:8765" placeholder="WebSocket URL">
      <button id="connectBtn">Connect</button>
    </div>
  </div>

  <div class="controls">
    <div class="time-controls">
      <button id="stepBackBtn" disabled title="Step Backward">&#9664;&#9664;</button>
      <button id="stepForwardBtn" disabled title="Step Forward">&#9654;&#9654;</button>
    </div>
    <button id="exportBtn">Export</button>
    <button id="importBtn">Import</button>
    <button id="clearBtn">Clear</button>
  </div>

  <div class="content">
    <div class="timeline">
      <div class="timeline-header">
        Timeline (<span id="entryCount">0</span> entries)
      </div>
      <div class="timeline-list" id="timelineList">
        <div class="empty-state">No messages recorded</div>
      </div>
    </div>

    <div class="inspector">
      <div class="inspector-header">State Inspector</div>
      <div class="inspector-content" id="inspectorContent">
        <div class="no-selection">Select a message to inspect state</div>
      </div>
    </div>
  </div>

  <script nonce="${nonce}">
    const vscode = acquireVsCodeApi();

    let state = {
      isConnected: false,
      history: [],
      currentIndex: -1,
      selectedIndex: null
    };

    const statusDot = document.getElementById('statusDot');
    const urlInput = document.getElementById('urlInput');
    const connectBtn = document.getElementById('connectBtn');
    const stepBackBtn = document.getElementById('stepBackBtn');
    const stepForwardBtn = document.getElementById('stepForwardBtn');
    const exportBtn = document.getElementById('exportBtn');
    const importBtn = document.getElementById('importBtn');
    const clearBtn = document.getElementById('clearBtn');
    const entryCount = document.getElementById('entryCount');
    const timelineList = document.getElementById('timelineList');
    const inspectorContent = document.getElementById('inspectorContent');

    connectBtn.addEventListener('click', () => {
      if (state.isConnected) {
        vscode.postMessage({ command: 'disconnect' });
      } else {
        vscode.postMessage({ command: 'connect', url: urlInput.value });
      }
    });

    stepBackBtn.addEventListener('click', () => {
      vscode.postMessage({ command: 'stepBackward' });
    });

    stepForwardBtn.addEventListener('click', () => {
      vscode.postMessage({ command: 'stepForward' });
    });

    exportBtn.addEventListener('click', () => {
      vscode.postMessage({ command: 'export' });
    });

    importBtn.addEventListener('click', () => {
      vscode.postMessage({ command: 'import' });
    });

    clearBtn.addEventListener('click', () => {
      vscode.postMessage({ command: 'clearHistory' });
    });

    window.addEventListener('message', event => {
      const message = event.data;
      if (message.type === 'update') {
        state = message.state;
        render();
      }
    });

    function render() {
      // Update connection status
      statusDot.className = 'status-dot' + (state.isConnected ? ' connected' : '');
      connectBtn.textContent = state.isConnected ? 'Disconnect' : 'Connect';

      // Update controls
      stepBackBtn.disabled = !state.isConnected || state.currentIndex <= 0;
      stepForwardBtn.disabled = !state.isConnected || state.currentIndex >= state.history.length - 1;

      // Update entry count
      entryCount.textContent = state.history.length;

      // Render timeline
      if (state.history.length === 0) {
        timelineList.innerHTML = '<div class="empty-state">No messages recorded</div>';
      } else {
        timelineList.innerHTML = state.history.map((entry, idx) => {
          const isSelected = state.selectedIndex === idx;
          const isCurrent = state.currentIndex === idx;
          const classes = ['timeline-entry'];
          if (isSelected) classes.push('selected');
          if (isCurrent) classes.push('current');

          return \`
            <div class="\${classes.join(' ')}" data-index="\${idx}">
              <div class="entry-header">
                <span>#\${entry.index}</span>
                <span>\${formatTime(entry.timestamp)}</span>
              </div>
              <div class="entry-message">\${truncate(entry.message, 40)}</div>
            </div>
          \`;
        }).join('');

        // Add click handlers
        timelineList.querySelectorAll('.timeline-entry').forEach(el => {
          el.addEventListener('click', () => {
            const index = parseInt(el.dataset.index, 10);
            state.selectedIndex = index;
            render();
          });

          el.addEventListener('dblclick', () => {
            const index = parseInt(el.dataset.index, 10);
            vscode.postMessage({ command: 'jumpTo', index });
          });
        });
      }

      // Render inspector
      if (state.selectedIndex !== null && state.history[state.selectedIndex]) {
        const entry = state.history[state.selectedIndex];
        inspectorContent.innerHTML = \`
          <div class="state-view">\${formatState(entry.state)}</div>
        \`;
      } else {
        inspectorContent.innerHTML = '<div class="no-selection">Select a message to inspect state</div>';
      }
    }

    function formatTime(timestamp) {
      const date = new Date(timestamp);
      return date.toLocaleTimeString() + '.' + String(date.getMilliseconds()).padStart(3, '0');
    }

    function truncate(str, maxLen) {
      if (str.length <= maxLen) return str;
      return str.substring(0, maxLen - 3) + '...';
    }

    function formatState(state) {
      // Basic pretty printing
      let result = '';
      let depth = 0;
      let inString = false;

      for (let i = 0; i < state.length; i++) {
        const char = state[i];

        if (char === '"' && state[i-1] !== '\\\\') {
          inString = !inString;
          result += char;
          continue;
        }

        if (inString) {
          result += char;
          continue;
        }

        if (char === '{' || char === '[') {
          depth++;
          result += char + '\\n' + '  '.repeat(depth);
        } else if (char === '}' || char === ']') {
          depth--;
          result += '\\n' + '  '.repeat(depth) + char;
        } else if (char === ',') {
          result += char + '\\n' + '  '.repeat(depth);
        } else {
          result += char;
        }
      }

      return result;
    }

    // Initial render
    render();
  </script>
</body>
</html>`;
  }
}

function getNonce(): string {
  let text = '';
  const possible = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  for (let i = 0; i < 32; i++) {
    text += possible.charAt(Math.floor(Math.random() * possible.length));
  }
  return text;
}
