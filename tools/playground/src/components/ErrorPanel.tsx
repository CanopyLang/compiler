import type { CompilationError } from '../types';

interface ErrorPanelProps {
  errors: CompilationError[];
  onErrorClick?: (error: CompilationError) => void;
}

export function ErrorPanel({ errors, onErrorClick }: ErrorPanelProps): JSX.Element | null {
  if (errors.length === 0) {
    return (
      <div className="error-panel">
        <div className="panel-content" style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          height: '100%',
          color: 'var(--color-success)',
          padding: 'var(--spacing-md)',
        }}>
          <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" style={{ marginRight: '0.5rem' }}>
            <path d="M8 0a8 8 0 1 0 0 16A8 8 0 0 0 8 0zm3.78 5.28l-5 5a.75.75 0 0 1-1.06 0l-2-2a.75.75 0 1 1 1.06-1.06L6.25 8.69l4.47-4.47a.75.75 0 0 1 1.06 1.06z"/>
          </svg>
          No errors
        </div>
      </div>
    );
  }

  return (
    <div className="error-panel">
      <div className="error-list">
        {errors.map((error, index) => (
          <div
            key={index}
            className={`error-item ${error.severity === 'warning' ? 'warning' : ''}`}
            onClick={() => onErrorClick?.(error)}
            style={{ cursor: onErrorClick ? 'pointer' : 'default' }}
          >
            <div>
              <ErrorIcon severity={error.severity} />
            </div>
            <div>
              <div className="error-location">
                Line {error.line}, Column {error.column}
              </div>
              <div className="error-message">{error.message}</div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function ErrorIcon({ severity }: { severity: 'error' | 'warning' }): JSX.Element {
  if (severity === 'warning') {
    return (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="var(--color-warning)">
        <path d="M8.893 1.5c-.183-.31-.52-.5-.887-.5s-.703.19-.886.5L.138 13.499a.98.98 0 0 0 0 1.001c.193.31.53.501.886.501h13.964c.367 0 .704-.19.877-.5a1.03 1.03 0 0 0 .01-1.002L8.893 1.5zM8 5c.535 0 .954.462.9.995l-.35 3.507a.552.552 0 0 1-1.1 0L7.1 5.995A.905.905 0 0 1 8 5zm.002 6a1 1 0 1 1 0 2 1 1 0 0 1 0-2z"/>
      </svg>
    );
  }

  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="var(--color-error)">
      <path d="M8 0a8 8 0 1 0 0 16A8 8 0 0 0 8 0zm3.78 10.72a.75.75 0 1 1-1.06 1.06L8 9.06l-2.72 2.72a.75.75 0 0 1-1.06-1.06L6.94 8 4.22 5.28a.75.75 0 0 1 1.06-1.06L8 6.94l2.72-2.72a.75.75 0 1 1 1.06 1.06L9.06 8l2.72 2.72z"/>
    </svg>
  );
}
