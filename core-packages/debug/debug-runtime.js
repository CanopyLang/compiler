/**
 * Canopy Time-Travel Debugger Runtime
 *
 * This JavaScript module provides the runtime support for the Canopy time-travel
 * debugger, including WebSocket communication, state serialization, and
 * integration with the Canopy/Elm runtime.
 */

(function (global) {
  'use strict';

  // Constants
  const DEFAULT_WEBSOCKET_URL = 'ws://localhost:8765';
  const RECONNECT_DELAY = 3000;
  const MAX_RECONNECT_ATTEMPTS = 10;

  // State
  let websocket = null;
  let reconnectAttempts = 0;
  let messageQueue = [];
  let isConnected = false;
  let debuggerConfig = {
    maxHistory: 1000,
    enableWebSocket: true,
    websocketUrl: DEFAULT_WEBSOCKET_URL,
    pauseOnStart: false,
    filterMessages: []
  };

  // Callbacks registered by the Canopy runtime
  const callbacks = {
    onMessage: null,
    onConnect: null,
    onDisconnect: null
  };

  /**
   * Initialize the debugger runtime with the given configuration.
   * @param {Object} config - Configuration options
   */
  function init(config) {
    debuggerConfig = { ...debuggerConfig, ...config };

    if (debuggerConfig.enableWebSocket) {
      connectWebSocket(debuggerConfig.websocketUrl);
    }

    // Expose global API for browser devtools
    global.__CANOPY_DEBUGGER__ = {
      getHistory: getHistory,
      jumpTo: jumpTo,
      stepForward: stepForward,
      stepBackward: stepBackward,
      exportSession: exportSession,
      importSession: importSession,
      getState: getState,
      isConnected: () => isConnected
    };

    console.log('[Canopy Debugger] Runtime initialized');
  }

  /**
   * Connect to the WebSocket server.
   * @param {string} url - WebSocket URL
   */
  function connectWebSocket(url) {
    try {
      websocket = new WebSocket(url);

      websocket.onopen = function () {
        isConnected = true;
        reconnectAttempts = 0;
        console.log('[Canopy Debugger] WebSocket connected');

        // Send queued messages
        while (messageQueue.length > 0) {
          const message = messageQueue.shift();
          sendMessage(message);
        }

        // Notify Canopy runtime
        if (callbacks.onConnect) {
          callbacks.onConnect();
        }

        // Send initial handshake
        sendMessage({
          type: 'handshake',
          version: '1.0.0',
          timestamp: Date.now()
        });
      };

      websocket.onmessage = function (event) {
        try {
          const data = JSON.parse(event.data);
          handleIncomingMessage(data);
        } catch (e) {
          console.error('[Canopy Debugger] Failed to parse message:', e);
        }
      };

      websocket.onclose = function () {
        isConnected = false;
        console.log('[Canopy Debugger] WebSocket disconnected');

        if (callbacks.onDisconnect) {
          callbacks.onDisconnect();
        }

        // Attempt to reconnect
        if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
          reconnectAttempts++;
          setTimeout(() => connectWebSocket(url), RECONNECT_DELAY);
        }
      };

      websocket.onerror = function (error) {
        console.error('[Canopy Debugger] WebSocket error:', error);
      };
    } catch (e) {
      console.error('[Canopy Debugger] Failed to connect:', e);
    }
  }

  /**
   * Send a message through the WebSocket.
   * @param {Object|string} message - Message to send
   */
  function sendMessage(message) {
    const payload = typeof message === 'string' ? message : JSON.stringify(message);

    if (isConnected && websocket && websocket.readyState === WebSocket.OPEN) {
      websocket.send(payload);
    } else {
      // Queue message for later
      messageQueue.push(message);
    }
  }

  /**
   * Handle incoming WebSocket messages.
   * @param {Object} data - Parsed message data
   */
  function handleIncomingMessage(data) {
    switch (data.type) {
      case 'command':
        handleCommand(data.command, data.payload);
        break;

      case 'jumpTo':
        jumpTo(data.index);
        break;

      case 'stepForward':
        stepForward();
        break;

      case 'stepBackward':
        stepBackward();
        break;

      case 'export':
        exportSession();
        break;

      case 'import':
        importSession(data.session);
        break;

      case 'getState':
        sendMessage({
          type: 'state',
          state: getState(),
          history: getHistory()
        });
        break;

      case 'ping':
        sendMessage({ type: 'pong', timestamp: Date.now() });
        break;

      default:
        if (callbacks.onMessage) {
          callbacks.onMessage(JSON.stringify(data));
        }
    }
  }

  /**
   * Handle debugger commands.
   * @param {string} command - Command name
   * @param {any} payload - Command payload
   */
  function handleCommand(command, payload) {
    const commandHandlers = {
      'pause': () => {
        debuggerConfig.isPaused = true;
        sendMessage({ type: 'paused' });
      },
      'resume': () => {
        debuggerConfig.isPaused = false;
        sendMessage({ type: 'resumed' });
      },
      'setFilter': (filters) => {
        debuggerConfig.filterMessages = filters;
      },
      'clearHistory': () => {
        clearHistory();
      }
    };

    const handler = commandHandlers[command];
    if (handler) {
      handler(payload);
    }
  }

  // History management
  let history = [];
  let currentIndex = -1;
  let initialModel = null;

  /**
   * Record a state entry in the history.
   * @param {string} message - The message that caused the update
   * @param {any} model - The new model state
   */
  function recordEntry(message, model) {
    // Check if message should be filtered
    if (shouldFilterMessage(message)) {
      return;
    }

    const entry = {
      index: history.length,
      timestamp: Date.now(),
      message: message,
      messageString: serializeValue(message),
      model: model,
      modelString: serializeValue(model)
    };

    history.push(entry);
    currentIndex = history.length - 1;

    // Truncate if needed
    if (history.length > debuggerConfig.maxHistory) {
      const excess = history.length - debuggerConfig.maxHistory;
      history = history.slice(excess);
      currentIndex -= excess;
    }

    // Send to debugger UI
    sendMessage({
      type: 'entry',
      entry: {
        index: entry.index,
        timestamp: entry.timestamp,
        message: entry.messageString,
        state: entry.modelString
      }
    });
  }

  /**
   * Check if a message should be filtered out.
   * @param {string} message - Message to check
   * @returns {boolean} True if message should be filtered
   */
  function shouldFilterMessage(message) {
    if (debuggerConfig.filterMessages.length === 0) {
      return false;
    }

    const messageStr = serializeValue(message);
    return debuggerConfig.filterMessages.some(filter => messageStr.includes(filter));
  }

  /**
   * Serialize a value to a string representation.
   * @param {any} value - Value to serialize
   * @returns {string} String representation
   */
  function serializeValue(value) {
    if (value === null || value === undefined) {
      return String(value);
    }

    // Handle Canopy/Elm custom types
    if (value && typeof value === 'object' && value.$ !== undefined) {
      return serializeCustomType(value);
    }

    // Handle arrays/lists
    if (Array.isArray(value)) {
      return '[' + value.map(serializeValue).join(', ') + ']';
    }

    // Handle records/objects
    if (typeof value === 'object') {
      return serializeRecord(value);
    }

    // Handle primitives
    if (typeof value === 'string') {
      return '"' + value + '"';
    }

    return String(value);
  }

  /**
   * Serialize a Canopy/Elm custom type.
   * @param {Object} value - Custom type value
   * @returns {string} String representation
   */
  function serializeCustomType(value) {
    const ctor = value.$;
    const args = Object.keys(value)
      .filter(k => k !== '$')
      .sort()
      .map(k => serializeValue(value[k]));

    if (args.length === 0) {
      return ctor;
    }

    return ctor + ' ' + args.join(' ');
  }

  /**
   * Serialize a record/object.
   * @param {Object} value - Record value
   * @returns {string} String representation
   */
  function serializeRecord(value) {
    const pairs = Object.keys(value)
      .filter(k => !k.startsWith('_'))
      .sort()
      .map(k => k + ' = ' + serializeValue(value[k]));

    return '{ ' + pairs.join(', ') + ' }';
  }

  /**
   * Get the current history.
   * @returns {Array} History entries
   */
  function getHistory() {
    return history.map(entry => ({
      index: entry.index,
      timestamp: entry.timestamp,
      message: entry.messageString,
      state: entry.modelString
    }));
  }

  /**
   * Get the current state.
   * @returns {any} Current model state
   */
  function getState() {
    if (currentIndex >= 0 && currentIndex < history.length) {
      return history[currentIndex].model;
    }
    return initialModel;
  }

  /**
   * Get the state at a specific index.
   * @param {number} index - History index
   * @returns {any} Model state at index
   */
  function getStateAt(index) {
    if (index < 0) {
      return initialModel;
    }
    if (index < history.length) {
      return history[index].model;
    }
    return null;
  }

  /**
   * Jump to a specific index in the history.
   * @param {number} index - Target index
   */
  function jumpTo(index) {
    if (index < 0 || index >= history.length) {
      return;
    }

    currentIndex = index;
    const state = history[index].model;

    // Notify the application to restore this state
    if (global.__CANOPY_APP__ && global.__CANOPY_APP__.restoreState) {
      global.__CANOPY_APP__.restoreState(state);
    }

    sendMessage({
      type: 'jumped',
      index: currentIndex,
      state: history[index].modelString
    });
  }

  /**
   * Step forward one entry in the history.
   */
  function stepForward() {
    if (currentIndex < history.length - 1) {
      jumpTo(currentIndex + 1);
    }
  }

  /**
   * Step backward one entry in the history.
   */
  function stepBackward() {
    if (currentIndex > 0) {
      jumpTo(currentIndex - 1);
    }
  }

  /**
   * Clear the history.
   */
  function clearHistory() {
    history = [];
    currentIndex = -1;
    sendMessage({ type: 'historyCleared' });
  }

  /**
   * Export the current session.
   * @returns {string} JSON representation of the session
   */
  function exportSession() {
    const session = {
      version: '1.0.0',
      timestamp: Date.now(),
      config: debuggerConfig,
      initialModel: serializeValue(initialModel),
      history: history.map(entry => ({
        index: entry.index,
        timestamp: entry.timestamp,
        message: entry.messageString,
        state: entry.modelString
      })),
      currentIndex: currentIndex
    };

    const json = JSON.stringify(session, null, 2);

    sendMessage({
      type: 'sessionExported',
      session: json
    });

    return json;
  }

  /**
   * Import a session.
   * @param {string} sessionJson - JSON representation of the session
   */
  function importSession(sessionJson) {
    try {
      const session = typeof sessionJson === 'string'
        ? JSON.parse(sessionJson)
        : sessionJson;

      history = session.history.map((entry, i) => ({
        index: i,
        timestamp: entry.timestamp,
        message: entry.message,
        messageString: entry.message,
        model: null, // Cannot restore actual model from string
        modelString: entry.state
      }));

      currentIndex = session.currentIndex || 0;

      sendMessage({
        type: 'sessionImported',
        historyLength: history.length
      });
    } catch (e) {
      console.error('[Canopy Debugger] Failed to import session:', e);
      sendMessage({
        type: 'importError',
        error: e.message
      });
    }
  }

  /**
   * Download the session as a file.
   * @param {string} json - Session JSON
   */
  function downloadSession(json) {
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'canopy-debug-session-' + Date.now() + '.json';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }

  /**
   * Compute diff between two state strings.
   * @param {string} oldState - Old state string
   * @param {string} newState - New state string
   * @returns {Object} Diff result
   */
  function computeStateDiff(oldState, newState) {
    const oldLines = oldState.split('\n');
    const newLines = newState.split('\n');
    const diff = [];

    const maxLen = Math.max(oldLines.length, newLines.length);

    for (let i = 0; i < maxLen; i++) {
      const oldLine = oldLines[i] || '';
      const newLine = newLines[i] || '';

      if (oldLine === newLine) {
        diff.push({ type: 'unchanged', value: oldLine });
      } else if (oldLine === '') {
        diff.push({ type: 'added', value: newLine });
      } else if (newLine === '') {
        diff.push({ type: 'removed', value: oldLine });
      } else {
        diff.push({ type: 'changed', oldValue: oldLine, newValue: newLine });
      }
    }

    return diff;
  }

  /**
   * Wrap a Canopy/Elm application with debugger capabilities.
   * @param {Object} app - The Canopy/Elm application
   * @returns {Object} Wrapped application
   */
  function wrapApplication(app) {
    const originalUpdate = app.update;

    // Store initial model
    initialModel = app.init ? app.init() : null;

    // Override update function
    app.update = function (msg, model) {
      const newModel = originalUpdate(msg, model);
      recordEntry(msg, newModel);
      return newModel;
    };

    // Add restore capability
    app.restoreState = function (state) {
      if (app.ports && app.ports.restoreState) {
        app.ports.restoreState.send(state);
      }
    };

    // Store reference for global access
    global.__CANOPY_APP__ = app;

    return app;
  }

  /**
   * Register port handlers for Canopy/Elm interop.
   * @param {Object} ports - Elm ports object
   */
  function registerPorts(ports) {
    if (ports.connectWebSocket) {
      ports.connectWebSocket.subscribe(function (url) {
        connectWebSocket(url);
      });
    }

    if (ports.sendToWebSocket) {
      ports.sendToWebSocket.subscribe(function (message) {
        sendMessage(message);
      });
    }

    if (ports.downloadSession) {
      ports.downloadSession.subscribe(function (json) {
        downloadSession(json);
      });
    }

    // Set up callbacks for incoming messages
    callbacks.onMessage = function (message) {
      if (ports.onWebSocketMessage) {
        ports.onWebSocketMessage.send(message);
      }
    };

    callbacks.onConnect = function () {
      if (ports.onWebSocketConnect) {
        ports.onWebSocketConnect.send(null);
      }
    };

    callbacks.onDisconnect = function () {
      if (ports.onWebSocketDisconnect) {
        ports.onWebSocketDisconnect.send(null);
      }
    };
  }

  // Export public API
  const CanopyDebugger = {
    init: init,
    connectWebSocket: connectWebSocket,
    sendMessage: sendMessage,
    recordEntry: recordEntry,
    getHistory: getHistory,
    getState: getState,
    getStateAt: getStateAt,
    jumpTo: jumpTo,
    stepForward: stepForward,
    stepBackward: stepBackward,
    exportSession: exportSession,
    importSession: importSession,
    downloadSession: downloadSession,
    computeStateDiff: computeStateDiff,
    wrapApplication: wrapApplication,
    registerPorts: registerPorts,
    serializeValue: serializeValue
  };

  // Export for different environments
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = CanopyDebugger;
  } else if (typeof define === 'function' && define.amd) {
    define([], function () { return CanopyDebugger; });
  } else {
    global.CanopyDebugger = CanopyDebugger;
  }

})(typeof window !== 'undefined' ? window : typeof global !== 'undefined' ? global : this);
