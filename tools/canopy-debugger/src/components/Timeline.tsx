/**
 * Timeline component for displaying message history
 */

import React, { useRef, useEffect } from 'react';
import type { TimelineProps, HistoryEntry } from '../types';
import { formatTimestamp, formatTimeDelta } from '../utils/formatTime';

export const Timeline: React.FC<TimelineProps> = ({
  entries,
  currentIndex,
  selectedIndex,
  onSelect,
  onJump,
  compactMode = false
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const selectedRef = useRef<HTMLDivElement>(null);

  // Scroll to selected entry when it changes
  useEffect(() => {
    if (selectedRef.current && containerRef.current) {
      selectedRef.current.scrollIntoView({
        behavior: 'smooth',
        block: 'nearest'
      });
    }
  }, [selectedIndex]);

  if (entries.length === 0) {
    return (
      <div className="timeline-empty">
        <p>No messages recorded yet.</p>
        <p className="text-muted">
          Messages will appear here as your application runs.
        </p>
      </div>
    );
  }

  return (
    <div className="timeline" ref={containerRef}>
      <div className="timeline-header">
        <span className="timeline-count">{entries.length} messages</span>
      </div>

      <div className="timeline-entries">
        {entries.map((entry, index) => (
          <TimelineEntry
            key={entry.index}
            entry={entry}
            previousEntry={index > 0 ? entries[index - 1] : undefined}
            isSelected={selectedIndex === entry.index}
            isCurrent={currentIndex === entry.index}
            compactMode={compactMode}
            onSelect={() => onSelect(entry.index)}
            onJump={() => onJump(entry.index)}
            ref={selectedIndex === entry.index ? selectedRef : undefined}
          />
        ))}
      </div>
    </div>
  );
};

interface TimelineEntryProps {
  entry: HistoryEntry;
  previousEntry?: HistoryEntry;
  isSelected: boolean;
  isCurrent: boolean;
  compactMode: boolean;
  onSelect: () => void;
  onJump: () => void;
}

const TimelineEntry = React.forwardRef<HTMLDivElement, TimelineEntryProps>(
  (
    { entry, previousEntry, isSelected, isCurrent, compactMode, onSelect, onJump },
    ref
  ) => {
    const messageType = extractMessageType(entry.message);
    const timeDelta = previousEntry
      ? formatTimeDelta(entry.timestamp, previousEntry.timestamp)
      : null;

    const classNames = [
      'timeline-entry',
      isSelected ? 'selected' : '',
      isCurrent ? 'current' : '',
      compactMode ? 'compact' : ''
    ]
      .filter(Boolean)
      .join(' ');

    return (
      <div ref={ref} className={classNames} onClick={onSelect} onDoubleClick={onJump}>
        <div className="entry-header">
          <span className="entry-index">#{entry.index}</span>
          <span className="entry-timestamp">{formatTimestamp(entry.timestamp)}</span>
          {timeDelta && <span className="entry-delta">{timeDelta}</span>}
        </div>

        <div className="entry-content">
          <span className="entry-type" data-type={getTypeCategory(messageType)}>
            {messageType}
          </span>
          {!compactMode && (
            <span className="entry-message">{truncateMessage(entry.message)}</span>
          )}
        </div>

        {isCurrent && (
          <div className="entry-current-indicator" title="Current state">
            <svg viewBox="0 0 24 24" width="16" height="16">
              <path
                fill="currentColor"
                d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"
              />
            </svg>
          </div>
        )}

        <button
          className="entry-jump-button"
          onClick={(e) => {
            e.stopPropagation();
            onJump();
          }}
          title="Jump to this state"
        >
          <svg viewBox="0 0 24 24" width="14" height="14">
            <path
              fill="currentColor"
              d="M4 18l8.5-6L4 6v12zm9-12v12l8.5-6L13 6z"
            />
          </svg>
        </button>
      </div>
    );
  }
);

TimelineEntry.displayName = 'TimelineEntry';

/**
 * Extract the message type from a message string
 */
function extractMessageType(message: string): string {
  // Handle Canopy/Elm custom type format: "TypeName arg1 arg2"
  const match = message.match(/^([A-Z][a-zA-Z0-9_]*)/);
  if (match) {
    return match[1];
  }

  // Handle record format: "{ type = \"something\" }"
  const recordMatch = message.match(/type\s*=\s*"?([^"}\s]+)"?/);
  if (recordMatch) {
    return recordMatch[1];
  }

  return 'Message';
}

/**
 * Categorize message types for styling
 */
function getTypeCategory(type: string): string {
  const lowerType = type.toLowerCase();

  if (lowerType.includes('click') || lowerType.includes('press') || lowerType.includes('input')) {
    return 'user';
  }

  if (lowerType.includes('http') || lowerType.includes('fetch') || lowerType.includes('request')) {
    return 'network';
  }

  if (lowerType.includes('tick') || lowerType.includes('time') || lowerType.includes('animation')) {
    return 'time';
  }

  if (lowerType.includes('error') || lowerType.includes('fail')) {
    return 'error';
  }

  if (lowerType.includes('success') || lowerType.includes('complete')) {
    return 'success';
  }

  return 'default';
}

/**
 * Truncate a long message for display
 */
function truncateMessage(message: string, maxLength: number = 100): string {
  const cleaned = message.replace(/\s+/g, ' ').trim();

  if (cleaned.length <= maxLength) {
    return cleaned;
  }

  return cleaned.substring(0, maxLength - 3) + '...';
}

export default Timeline;
