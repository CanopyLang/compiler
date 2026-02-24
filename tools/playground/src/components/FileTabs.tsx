import type { PlaygroundFile } from '../types';

interface FileTabsProps {
  files: PlaygroundFile[];
  activeIndex: number;
  onSelectFile: (index: number) => void;
  onCloseFile: (index: number) => void;
  onAddFile: () => void;
}

export function FileTabs({
  files,
  activeIndex,
  onSelectFile,
  onCloseFile,
  onAddFile,
}: FileTabsProps): JSX.Element {
  return (
    <div className="file-tabs">
      {files.map((file, index) => (
        <button
          key={index}
          className={`file-tab ${index === activeIndex ? 'active' : ''}`}
          onClick={() => onSelectFile(index)}
        >
          <FileIcon language={file.language} />
          <span>{file.name}</span>
          {files.length > 1 && (
            <button
              className="file-tab-close"
              onClick={(e) => {
                e.stopPropagation();
                onCloseFile(index);
              }}
              aria-label={`Close ${file.name}`}
            >
              x
            </button>
          )}
        </button>
      ))}
      <button
        className="file-tab"
        onClick={onAddFile}
        aria-label="Add new file"
        style={{ padding: '0.25rem 0.5rem' }}
      >
        <svg width="14" height="14" viewBox="0 0 14 14" fill="currentColor">
          <path d="M7 0a.75.75 0 0 1 .75.75V6.25h5.5a.75.75 0 0 1 0 1.5h-5.5v5.5a.75.75 0 0 1-1.5 0v-5.5H.75a.75.75 0 0 1 0-1.5h5.5V.75A.75.75 0 0 1 7 0z"/>
        </svg>
      </button>
    </div>
  );
}

function FileIcon({ language }: { language: string }): JSX.Element {
  const color = language === 'canopy' ? '#4EC9B0' : '#F1C40F';

  return (
    <svg width="14" height="14" viewBox="0 0 14 14" fill={color}>
      <path d="M4 0a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2V4.5L8.5 0H4zm4 1v3a1 1 0 0 0 1 1h3l-4-4z"/>
    </svg>
  );
}
