/**
 * Type definitions for the Canopy Time-Travel Debugger
 */

/**
 * A single entry in the debug history
 */
export interface HistoryEntry {
  index: number;
  timestamp: number;
  message: string;
  state: string;
  clientId?: string;
}

/**
 * Diff result between two states
 */
export interface StateDiff {
  type: 'added' | 'removed' | 'changed' | 'unchanged';
  key?: string;
  value?: string;
  oldValue?: string;
  newValue?: string;
}

/**
 * Debug session for export/import
 */
export interface DebugSession {
  version: string;
  timestamp: number;
  config?: DebugConfig;
  history: HistoryEntry[];
  currentIndex: number;
}

/**
 * Debugger configuration
 */
export interface DebugConfig {
  maxHistory: number;
  enableWebSocket: boolean;
  websocketUrl: string;
  pauseOnStart: boolean;
  filterMessages: string[];
}

/**
 * WebSocket connection state
 */
export type ConnectionState = 'disconnected' | 'connecting' | 'connected' | 'error';

/**
 * Message filter configuration
 */
export interface MessageFilter {
  id: string;
  pattern: string;
  enabled: boolean;
  type: 'include' | 'exclude';
}

/**
 * Debugger UI state
 */
export interface DebuggerState {
  // Connection
  connectionState: ConnectionState;
  websocketUrl: string;

  // History
  history: HistoryEntry[];
  currentIndex: number;
  selectedIndex: number | null;

  // Filtering
  filters: MessageFilter[];
  searchQuery: string;

  // UI state
  isPaused: boolean;
  showDiff: boolean;
  autoScroll: boolean;
  compactMode: boolean;

  // Actions
  connect: (url: string) => void;
  disconnect: () => void;
  jumpTo: (index: number) => void;
  stepForward: () => void;
  stepBackward: () => void;
  selectEntry: (index: number | null) => void;
  setSearchQuery: (query: string) => void;
  addFilter: (filter: Omit<MessageFilter, 'id'>) => void;
  removeFilter: (id: string) => void;
  toggleFilter: (id: string) => void;
  togglePause: () => void;
  toggleDiff: () => void;
  toggleAutoScroll: () => void;
  toggleCompactMode: () => void;
  clearHistory: () => void;
  exportSession: () => Promise<string>;
  importSession: (session: DebugSession) => void;
}

/**
 * Props for the Timeline component
 */
export interface TimelineProps {
  entries: HistoryEntry[];
  currentIndex: number;
  selectedIndex: number | null;
  onSelect: (index: number) => void;
  onJump: (index: number) => void;
  compactMode?: boolean;
}

/**
 * Props for the StateInspector component
 */
export interface StateInspectorProps {
  state: string;
  previousState?: string;
  showDiff?: boolean;
}

/**
 * Props for the MessageDetails component
 */
export interface MessageDetailsProps {
  entry: HistoryEntry;
  previousEntry?: HistoryEntry;
}

/**
 * Tree node for state visualization
 */
export interface StateTreeNode {
  key: string;
  value: string | StateTreeNode[];
  type: 'string' | 'number' | 'boolean' | 'record' | 'list' | 'custom';
  expanded?: boolean;
  changed?: boolean;
}

/**
 * WebSocket message types
 */
export type WebSocketMessageType =
  | 'handshake'
  | 'handshakeAck'
  | 'entry'
  | 'command'
  | 'jumpTo'
  | 'stepForward'
  | 'stepBackward'
  | 'export'
  | 'import'
  | 'sync'
  | 'historyCleared'
  | 'sessionImported'
  | 'ping'
  | 'pong';

/**
 * WebSocket message structure
 */
export interface WebSocketMessage {
  type: WebSocketMessageType;
  [key: string]: unknown;
}
