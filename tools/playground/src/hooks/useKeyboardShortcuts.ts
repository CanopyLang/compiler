import { useEffect, useCallback } from 'react';

interface ShortcutHandlers {
  onCompile: () => void;
  onSave: () => void;
  onShare: () => void;
  onToggleTheme: () => void;
  onShowHelp: () => void;
}

export function useKeyboardShortcuts(handlers: ShortcutHandlers): void {
  const handleKeyDown = useCallback((event: KeyboardEvent) => {
    const isModKey = event.ctrlKey || event.metaKey;

    if (isModKey && event.key === 'Enter') {
      event.preventDefault();
      handlers.onCompile();
      return;
    }

    if (isModKey && event.key === 's') {
      event.preventDefault();
      handlers.onSave();
      return;
    }

    if (isModKey && event.shiftKey && event.key === 'S') {
      event.preventDefault();
      handlers.onShare();
      return;
    }

    if (isModKey && event.key === 'd') {
      event.preventDefault();
      handlers.onToggleTheme();
      return;
    }

    if (event.key === 'F1' || (isModKey && event.key === '/')) {
      event.preventDefault();
      handlers.onShowHelp();
      return;
    }
  }, [handlers]);

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);
}

export const KEYBOARD_SHORTCUTS = [
  { keys: ['Ctrl', 'Enter'], description: 'Compile code' },
  { keys: ['Ctrl', 'S'], description: 'Save/Download project' },
  { keys: ['Ctrl', 'Shift', 'S'], description: 'Share code' },
  { keys: ['Ctrl', 'D'], description: 'Toggle dark/light theme' },
  { keys: ['F1'], description: 'Show keyboard shortcuts' },
] as const;
