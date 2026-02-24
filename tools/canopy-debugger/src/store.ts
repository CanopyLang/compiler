/**
 * Zustand store for debugger state management
 */

import { create } from 'zustand';
import type {
  DebuggerState,
  HistoryEntry,
  MessageFilter,
  ConnectionState,
  DebugSession,
  WebSocketMessage
} from './types';

const DEFAULT_WEBSOCKET_URL = 'ws://localhost:8765';

let websocket: WebSocket | null = null;

export const useDebuggerStore = create<DebuggerState>((set, get) => ({
  // Initial state
  connectionState: 'disconnected',
  websocketUrl: DEFAULT_WEBSOCKET_URL,
  history: [],
  currentIndex: -1,
  selectedIndex: null,
  filters: [],
  searchQuery: '',
  isPaused: false,
  showDiff: true,
  autoScroll: true,
  compactMode: false,

  // Connection actions
  connect: (url: string) => {
    const state = get();
    if (state.connectionState === 'connected' || state.connectionState === 'connecting') {
      return;
    }

    set({ connectionState: 'connecting', websocketUrl: url });

    try {
      websocket = new WebSocket(url + '?type=extension');

      websocket.onopen = () => {
        set({ connectionState: 'connected' });
        sendMessage({ type: 'handshake', version: '1.0.0' });
        sendMessage({ type: 'getHistory' });
      };

      websocket.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data) as WebSocketMessage;
          handleMessage(message, set, get);
        } catch (e) {
          console.error('[Debugger Extension] Failed to parse message:', e);
        }
      };

      websocket.onclose = () => {
        set({ connectionState: 'disconnected' });
        websocket = null;
      };

      websocket.onerror = () => {
        set({ connectionState: 'error' });
      };
    } catch (e) {
      set({ connectionState: 'error' });
      console.error('[Debugger Extension] Connection failed:', e);
    }
  },

  disconnect: () => {
    if (websocket) {
      websocket.close();
      websocket = null;
    }
    set({ connectionState: 'disconnected' });
  },

  // Time travel actions
  jumpTo: (index: number) => {
    const { history } = get();
    if (index < 0 || index >= history.length) {
      return;
    }

    set({ currentIndex: index, selectedIndex: index });
    sendMessage({ type: 'jumpTo', index });
  },

  stepForward: () => {
    const { currentIndex, history } = get();
    if (currentIndex < history.length - 1) {
      get().jumpTo(currentIndex + 1);
    }
  },

  stepBackward: () => {
    const { currentIndex } = get();
    if (currentIndex > 0) {
      get().jumpTo(currentIndex - 1);
    }
  },

  // Selection
  selectEntry: (index: number | null) => {
    set({ selectedIndex: index });
  },

  // Filtering
  setSearchQuery: (query: string) => {
    set({ searchQuery: query });
  },

  addFilter: (filter: Omit<MessageFilter, 'id'>) => {
    const id = `filter_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    set((state) => ({
      filters: [...state.filters, { ...filter, id }]
    }));
  },

  removeFilter: (id: string) => {
    set((state) => ({
      filters: state.filters.filter((f) => f.id !== id)
    }));
  },

  toggleFilter: (id: string) => {
    set((state) => ({
      filters: state.filters.map((f) =>
        f.id === id ? { ...f, enabled: !f.enabled } : f
      )
    }));
  },

  // UI toggles
  togglePause: () => {
    const { isPaused } = get();
    set({ isPaused: !isPaused });
    sendMessage({ type: 'command', command: isPaused ? 'resume' : 'pause' });
  },

  toggleDiff: () => {
    set((state) => ({ showDiff: !state.showDiff }));
  },

  toggleAutoScroll: () => {
    set((state) => ({ autoScroll: !state.autoScroll }));
  },

  toggleCompactMode: () => {
    set((state) => ({ compactMode: !state.compactMode }));
  },

  // History management
  clearHistory: () => {
    set({ history: [], currentIndex: -1, selectedIndex: null });
    sendMessage({ type: 'clearHistory' });
  },

  // Session export/import
  exportSession: async () => {
    const { history, currentIndex, filters } = get();
    const session: DebugSession = {
      version: '1.0.0',
      timestamp: Date.now(),
      history,
      currentIndex,
      config: {
        maxHistory: 1000,
        enableWebSocket: true,
        websocketUrl: get().websocketUrl,
        pauseOnStart: false,
        filterMessages: filters.filter((f) => f.enabled).map((f) => f.pattern)
      }
    };

    return JSON.stringify(session, null, 2);
  },

  importSession: (session: DebugSession) => {
    set({
      history: session.history,
      currentIndex: session.currentIndex,
      selectedIndex: null
    });

    // Optionally restore filters
    if (session.config?.filterMessages) {
      const filters = session.config.filterMessages.map((pattern, i) => ({
        id: `imported_${i}`,
        pattern,
        enabled: true,
        type: 'exclude' as const
      }));
      set({ filters });
    }

    sendMessage({ type: 'import', session });
  }
}));

/**
 * Send a message through the WebSocket
 */
function sendMessage(message: WebSocketMessage): void {
  if (websocket && websocket.readyState === WebSocket.OPEN) {
    websocket.send(JSON.stringify(message));
  }
}

/**
 * Handle incoming WebSocket messages
 */
function handleMessage(
  message: WebSocketMessage,
  set: (partial: Partial<DebuggerState>) => void,
  get: () => DebuggerState
): void {
  switch (message.type) {
    case 'entry':
      handleEntry(message.entry as HistoryEntry, set, get);
      break;

    case 'sync':
      set({
        history: message.history as HistoryEntry[],
        currentIndex: (message.history as HistoryEntry[]).length - 1
      });
      break;

    case 'history':
      set({
        history: message.history as HistoryEntry[],
        currentIndex: (message.history as HistoryEntry[]).length - 1
      });
      break;

    case 'jumped':
      set({
        currentIndex: message.index as number,
        selectedIndex: message.index as number
      });
      break;

    case 'historyCleared':
      set({ history: [], currentIndex: -1, selectedIndex: null });
      break;

    case 'sessionImported':
      // History was updated by the server
      sendMessage({ type: 'getHistory' });
      break;

    case 'handshakeAck':
      console.log('[Debugger Extension] Handshake complete');
      break;

    case 'pong':
      // Connection is alive
      break;
  }
}

/**
 * Handle a new history entry
 */
function handleEntry(
  entry: HistoryEntry,
  set: (partial: Partial<DebuggerState>) => void,
  get: () => DebuggerState
): void {
  const { filters, isPaused, autoScroll, history } = get();

  // Check if entry should be filtered
  const shouldFilter = filters.some(
    (f) => f.enabled && f.type === 'exclude' && entry.message.includes(f.pattern)
  );

  if (shouldFilter) {
    return;
  }

  // Don't add new entries when paused
  if (isPaused) {
    return;
  }

  const newHistory = [...history, entry];
  const newIndex = newHistory.length - 1;

  set({
    history: newHistory,
    currentIndex: newIndex,
    selectedIndex: autoScroll ? newIndex : get().selectedIndex
  });
}

/**
 * Get filtered history based on current search and filters
 */
export function getFilteredHistory(state: DebuggerState): HistoryEntry[] {
  const { history, searchQuery, filters } = state;

  return history.filter((entry) => {
    // Apply search query
    if (searchQuery) {
      const query = searchQuery.toLowerCase();
      const matchesMessage = entry.message.toLowerCase().includes(query);
      const matchesState = entry.state.toLowerCase().includes(query);
      if (!matchesMessage && !matchesState) {
        return false;
      }
    }

    // Apply include filters (if any enabled, entry must match at least one)
    const includeFilters = filters.filter((f) => f.enabled && f.type === 'include');
    if (includeFilters.length > 0) {
      const matchesInclude = includeFilters.some((f) =>
        entry.message.includes(f.pattern)
      );
      if (!matchesInclude) {
        return false;
      }
    }

    // Apply exclude filters
    const excludeFilters = filters.filter((f) => f.enabled && f.type === 'exclude');
    const matchesExclude = excludeFilters.some((f) =>
      entry.message.includes(f.pattern)
    );
    if (matchesExclude) {
      return false;
    }

    return true;
  });
}
