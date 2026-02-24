/**
 * Message Details component for displaying message information
 */

import React from 'react';
import type { MessageDetailsProps } from '../types';
import { formatTimestamp, formatTimeDelta } from '../utils/formatTime';

export const MessageDetails: React.FC<MessageDetailsProps> = ({
  entry,
  previousEntry
}) => {
  const messageType = extractMessageType(entry.message);
  const messageArgs = extractMessageArgs(entry.message);
  const timeDelta = previousEntry
    ? formatTimeDelta(entry.timestamp, previousEntry.timestamp)
    : null;

  return (
    <div className="message-details">
      <div className="message-header">
        <span className="message-index">#{entry.index}</span>
        <span className="message-type">{messageType}</span>
        <span className="message-timestamp">{formatTimestamp(entry.timestamp)}</span>
        {timeDelta && (
          <span className="message-delta" title="Time since previous message">
            {timeDelta}
          </span>
        )}
      </div>

      <div className="message-body">
        {messageArgs.length > 0 ? (
          <div className="message-args">
            <h4>Arguments</h4>
            <table className="args-table">
              <tbody>
                {messageArgs.map((arg, index) => (
                  <tr key={index}>
                    <td className="arg-index">{index}</td>
                    <td className="arg-value">
                      <code>{formatArgValue(arg)}</code>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="message-raw">
            <h4>Raw Message</h4>
            <pre className="raw-message">{entry.message}</pre>
          </div>
        )}
      </div>

      <div className="message-actions">
        <button
          className="action-link"
          onClick={() => copyToClipboard(entry.message)}
          title="Copy message"
        >
          Copy Message
        </button>
        <button
          className="action-link"
          onClick={() => copyToClipboard(JSON.stringify(entry, null, 2))}
          title="Copy full entry as JSON"
        >
          Copy as JSON
        </button>
      </div>
    </div>
  );
};

/**
 * Extract the message type (constructor name) from a message string
 */
function extractMessageType(message: string): string {
  const trimmed = message.trim();

  // Handle Canopy/Elm custom type format: "TypeName arg1 arg2"
  const match = trimmed.match(/^([A-Z][a-zA-Z0-9_]*)/);
  if (match) {
    return match[1];
  }

  // Handle record format
  if (trimmed.startsWith('{')) {
    return 'Record';
  }

  // Handle list format
  if (trimmed.startsWith('[')) {
    return 'List';
  }

  return 'Message';
}

/**
 * Extract arguments from a message string
 */
function extractMessageArgs(message: string): string[] {
  const trimmed = message.trim();

  // Handle Canopy/Elm custom type format: "TypeName arg1 arg2"
  const match = trimmed.match(/^[A-Z][a-zA-Z0-9_]*\s+(.+)$/);
  if (match) {
    return parseArgs(match[1]);
  }

  return [];
}

/**
 * Parse space-separated arguments, respecting nested structures
 */
function parseArgs(argsString: string): string[] {
  const args: string[] = [];
  let current = '';
  let depth = 0;
  let inString = false;

  for (let i = 0; i < argsString.length; i++) {
    const char = argsString[i];

    if (char === '"' && argsString[i - 1] !== '\\') {
      inString = !inString;
      current += char;
      continue;
    }

    if (inString) {
      current += char;
      continue;
    }

    if (char === '(' || char === '{' || char === '[') {
      depth++;
      current += char;
      continue;
    }

    if (char === ')' || char === '}' || char === ']') {
      depth--;
      current += char;
      continue;
    }

    if (char === ' ' && depth === 0) {
      if (current.trim()) {
        args.push(current.trim());
      }
      current = '';
      continue;
    }

    current += char;
  }

  if (current.trim()) {
    args.push(current.trim());
  }

  return args;
}

/**
 * Format an argument value for display
 */
function formatArgValue(value: string): string {
  // Pretty print if it's a nested structure
  if (value.startsWith('{') || value.startsWith('[')) {
    return formatNestedValue(value);
  }

  return value;
}

/**
 * Format a nested value with indentation
 */
function formatNestedValue(value: string): string {
  let result = '';
  let depth = 0;
  let inString = false;

  for (let i = 0; i < value.length; i++) {
    const char = value[i];

    if (char === '"' && value[i - 1] !== '\\') {
      inString = !inString;
      result += char;
      continue;
    }

    if (inString) {
      result += char;
      continue;
    }

    if (char === '{' || char === '[') {
      depth++;
      result += char;
      if (value[i + 1] !== '}' && value[i + 1] !== ']') {
        result += '\n' + '  '.repeat(depth);
      }
      continue;
    }

    if (char === '}' || char === ']') {
      depth--;
      if (value[i - 1] !== '{' && value[i - 1] !== '[') {
        result += '\n' + '  '.repeat(depth);
      }
      result += char;
      continue;
    }

    if (char === ',') {
      result += char + '\n' + '  '.repeat(depth);
      // Skip following space
      if (value[i + 1] === ' ') {
        i++;
      }
      continue;
    }

    result += char;
  }

  return result;
}

/**
 * Copy text to clipboard
 */
async function copyToClipboard(text: string): Promise<void> {
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    // Fallback
    const textarea = document.createElement('textarea');
    textarea.value = text;
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand('copy');
    document.body.removeChild(textarea);
  }
}

export default MessageDetails;
