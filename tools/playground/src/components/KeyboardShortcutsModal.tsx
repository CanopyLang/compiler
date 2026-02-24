import { KEYBOARD_SHORTCUTS } from '../hooks/useKeyboardShortcuts';

interface KeyboardShortcutsModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function KeyboardShortcutsModal({ isOpen, onClose }: KeyboardShortcutsModalProps): JSX.Element | null {
  if (!isOpen) return null;

  return (
    <div className="shortcuts-modal" onClick={onClose}>
      <div className="shortcuts-content" onClick={(e) => e.stopPropagation()}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--spacing-md)' }}>
          <h2 className="shortcuts-title">Keyboard Shortcuts</h2>
          <button className="btn btn-icon" onClick={onClose} aria-label="Close">
            <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
              <path d="M4.28 3.22a.75.75 0 0 0-1.06 1.06L6.94 8l-3.72 3.72a.75.75 0 1 0 1.06 1.06L8 9.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L9.06 8l3.72-3.72a.75.75 0 0 0-1.06-1.06L8 6.94 4.28 3.22z"/>
            </svg>
          </button>
        </div>
        <div className="shortcuts-list">
          {KEYBOARD_SHORTCUTS.map((shortcut, index) => (
            <div key={index} className="shortcut-item">
              <span>{shortcut.description}</span>
              <div className="shortcut-keys">
                {shortcut.keys.map((key, keyIndex) => (
                  <span key={keyIndex}>
                    <kbd className="shortcut-key">{key}</kbd>
                    {keyIndex < shortcut.keys.length - 1 && <span style={{ margin: '0 2px' }}>+</span>}
                  </span>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
