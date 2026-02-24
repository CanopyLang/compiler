import type { OutputTab } from '../types';

interface OutputTabsProps {
  activeTab: OutputTab;
  onTabChange: (tab: OutputTab) => void;
  errorCount: number;
}

export function OutputTabs({ activeTab, onTabChange, errorCount }: OutputTabsProps): JSX.Element {
  return (
    <div className="tabs">
      <button
        className={`tab ${activeTab === 'preview' ? 'active' : ''}`}
        onClick={() => onTabChange('preview')}
      >
        <svg width="14" height="14" viewBox="0 0 14 14" fill="currentColor">
          <path d="M7 2.5a4.5 4.5 0 0 0-4.5 4.5 4.5 4.5 0 0 0 4.5 4.5 4.5 4.5 0 0 0 4.5-4.5A4.5 4.5 0 0 0 7 2.5zm0 1.5a3 3 0 0 1 3 3 3 3 0 0 1-3 3 3 3 0 0 1-3-3 3 3 0 0 1 3-3zm0 1a2 2 0 1 0 0 4 2 2 0 0 0 0-4z"/>
        </svg>
        Preview
      </button>
      <button
        className={`tab ${activeTab === 'javascript' ? 'active' : ''}`}
        onClick={() => onTabChange('javascript')}
      >
        <svg width="14" height="14" viewBox="0 0 14 14" fill="currentColor">
          <path d="M0 2a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H2a2 2 0 0 1-2-2V2zm12 1H2v9h10V3zM5.5 5L4 6.5 5.5 8 4.44 9.06 2.5 7.12v-1.24l1.94-1.94L5.5 5zm3-1.06L10.44 5.88v1.24l-1.94 1.94L7.44 8 9 6.5 7.44 5l1.06-1.06z"/>
        </svg>
        JavaScript
      </button>
      <button
        className={`tab ${activeTab === 'errors' ? 'active' : ''}`}
        onClick={() => onTabChange('errors')}
      >
        <svg width="14" height="14" viewBox="0 0 14 14" fill="currentColor">
          <path d="M7 0a7 7 0 1 0 0 14A7 7 0 0 0 7 0zm0 1.5a5.5 5.5 0 1 1 0 11 5.5 5.5 0 0 1 0-11zM6.25 4v4h1.5V4h-1.5zm0 5v1.5h1.5V9h-1.5z"/>
        </svg>
        Problems
        {errorCount > 0 && (
          <span style={{
            marginLeft: '0.25rem',
            padding: '0.125rem 0.5rem',
            fontSize: '0.75rem',
            backgroundColor: 'var(--color-error)',
            color: 'white',
            borderRadius: 'var(--radius-sm)',
          }}>
            {errorCount}
          </span>
        )}
      </button>
    </div>
  );
}
