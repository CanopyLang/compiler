/**
 * Time formatting utilities for the debugger
 */

import { format, formatDistanceToNow, differenceInMilliseconds } from 'date-fns';

/**
 * Format a timestamp for display in the timeline
 */
export function formatTimestamp(timestamp: number): string {
  return format(new Date(timestamp), 'HH:mm:ss.SSS');
}

/**
 * Format a timestamp as a relative time (e.g., "2 minutes ago")
 */
export function formatRelativeTime(timestamp: number): string {
  return formatDistanceToNow(new Date(timestamp), { addSuffix: true });
}

/**
 * Format the duration between two timestamps
 */
export function formatDuration(startTimestamp: number, endTimestamp: number): string {
  const ms = differenceInMilliseconds(endTimestamp, startTimestamp);

  if (ms < 1000) {
    return `${ms}ms`;
  }

  const seconds = Math.floor(ms / 1000);
  const remainingMs = ms % 1000;

  if (seconds < 60) {
    return `${seconds}.${String(remainingMs).padStart(3, '0')}s`;
  }

  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = seconds % 60;

  if (minutes < 60) {
    return `${minutes}m ${remainingSeconds}s`;
  }

  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;

  return `${hours}h ${remainingMinutes}m`;
}

/**
 * Format a full date and time for session export
 */
export function formatFullDateTime(timestamp: number): string {
  return format(new Date(timestamp), 'yyyy-MM-dd HH:mm:ss');
}

/**
 * Format a date for file names (no special characters)
 */
export function formatForFilename(timestamp: number): string {
  return format(new Date(timestamp), 'yyyy-MM-dd_HH-mm-ss');
}

/**
 * Calculate and format the time difference between two entries
 */
export function formatTimeDelta(currentTimestamp: number, previousTimestamp: number): string {
  const delta = currentTimestamp - previousTimestamp;

  if (delta < 0) {
    return '-' + formatDuration(currentTimestamp, previousTimestamp);
  }

  if (delta === 0) {
    return '0ms';
  }

  if (delta < 1) {
    return '<1ms';
  }

  return '+' + formatDuration(previousTimestamp, currentTimestamp);
}
