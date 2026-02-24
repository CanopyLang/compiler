interface StatusBarProps {
  isCompiling: boolean;
  errorCount: number;
  cursorPosition?: { line: number; column: number };
  fileName?: string;
}

export function StatusBar({
  isCompiling,
  errorCount,
  cursorPosition,
  fileName,
}: StatusBarProps): JSX.Element {
  return (
    <div className="status-bar">
      <div className="status-left">
        <div className="status-item">
          <span
            className={`status-indicator ${isCompiling ? 'compiling' : errorCount > 0 ? 'error' : ''}`}
          />
          <span>
            {isCompiling ? 'Compiling...' : errorCount > 0 ? `${errorCount} error${errorCount > 1 ? 's' : ''}` : 'Ready'}
          </span>
        </div>
        {fileName && (
          <div className="status-item">
            <span>{fileName}</span>
          </div>
        )}
      </div>
      <div className="status-right">
        {cursorPosition && (
          <div className="status-item">
            <span>Ln {cursorPosition.line}, Col {cursorPosition.column}</span>
          </div>
        )}
        <div className="status-item">
          <span>Canopy</span>
        </div>
        <div className="status-item">
          <span>UTF-8</span>
        </div>
      </div>
    </div>
  );
}
