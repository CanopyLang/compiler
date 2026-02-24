/**
 * Utilities for computing and rendering state diffs
 */

import * as Diff from 'diff';
import type { StateDiff, StateTreeNode } from '../types';

/**
 * Compute a diff between two state strings
 */
export function computeStateDiff(oldState: string, newState: string): StateDiff[] {
  const changes = Diff.diffLines(oldState, newState);
  const result: StateDiff[] = [];

  for (const change of changes) {
    if (change.added) {
      result.push({ type: 'added', value: change.value });
    } else if (change.removed) {
      result.push({ type: 'removed', value: change.value });
    } else {
      result.push({ type: 'unchanged', value: change.value });
    }
  }

  return result;
}

/**
 * Compute a word-level diff for inline comparison
 */
export function computeWordDiff(
  oldState: string,
  newState: string
): Array<{ type: 'added' | 'removed' | 'unchanged'; value: string }> {
  const changes = Diff.diffWords(oldState, newState);
  return changes.map((change) => ({
    type: change.added ? 'added' : change.removed ? 'removed' : 'unchanged',
    value: change.value
  }));
}

/**
 * Parse a Canopy/Elm value string into a tree structure
 */
export function parseStateTree(stateString: string): StateTreeNode[] {
  const trimmed = stateString.trim();
  return parseNodes(trimmed, 0).nodes;
}

interface ParseResult {
  nodes: StateTreeNode[];
  endIndex: number;
}

function parseNodes(str: string, startIndex: number): ParseResult {
  const nodes: StateTreeNode[] = [];
  let i = startIndex;

  while (i < str.length) {
    const char = str[i];

    // Skip whitespace
    if (/\s/.test(char)) {
      i++;
      continue;
    }

    // Record
    if (char === '{') {
      const result = parseRecord(str, i);
      nodes.push(...result.nodes);
      i = result.endIndex;
      continue;
    }

    // List
    if (char === '[') {
      const result = parseList(str, i);
      nodes.push(...result.nodes);
      i = result.endIndex;
      continue;
    }

    // End of current context
    if (char === '}' || char === ']' || char === ',') {
      break;
    }

    // Value or custom type
    const result = parseValue(str, i);
    if (result.node) {
      nodes.push(result.node);
    }
    i = result.endIndex;
  }

  return { nodes, endIndex: i };
}

function parseRecord(str: string, startIndex: number): ParseResult {
  const nodes: StateTreeNode[] = [];
  let i = startIndex + 1; // Skip opening brace

  while (i < str.length) {
    // Skip whitespace
    while (i < str.length && /\s/.test(str[i])) {
      i++;
    }

    // End of record
    if (str[i] === '}') {
      return { nodes, endIndex: i + 1 };
    }

    // Skip comma
    if (str[i] === ',') {
      i++;
      continue;
    }

    // Parse field
    const fieldResult = parseField(str, i);
    if (fieldResult.node) {
      nodes.push(fieldResult.node);
    }
    i = fieldResult.endIndex;
  }

  return { nodes, endIndex: i };
}

function parseField(
  str: string,
  startIndex: number
): { node: StateTreeNode | null; endIndex: number } {
  let i = startIndex;

  // Skip whitespace
  while (i < str.length && /\s/.test(str[i])) {
    i++;
  }

  // Read field name
  let fieldName = '';
  while (i < str.length && /[a-zA-Z0-9_]/.test(str[i])) {
    fieldName += str[i];
    i++;
  }

  if (!fieldName) {
    return { node: null, endIndex: i };
  }

  // Skip whitespace and equals sign
  while (i < str.length && /[\s=]/.test(str[i])) {
    i++;
  }

  // Parse field value
  const valueResult = parseFieldValue(str, i);

  return {
    node: {
      key: fieldName,
      value: valueResult.value,
      type: valueResult.type
    },
    endIndex: valueResult.endIndex
  };
}

function parseFieldValue(
  str: string,
  startIndex: number
): {
  value: string | StateTreeNode[];
  type: StateTreeNode['type'];
  endIndex: number;
} {
  let i = startIndex;

  // Skip whitespace
  while (i < str.length && /\s/.test(str[i])) {
    i++;
  }

  const char = str[i];

  // Nested record
  if (char === '{') {
    const result = parseRecord(str, i);
    return { value: result.nodes, type: 'record', endIndex: result.endIndex };
  }

  // List
  if (char === '[') {
    const result = parseList(str, i);
    return { value: result.nodes, type: 'list', endIndex: result.endIndex };
  }

  // String
  if (char === '"') {
    const result = parseString(str, i);
    return { value: result.value, type: 'string', endIndex: result.endIndex };
  }

  // Number or boolean or custom type
  return parseSimpleValue(str, i);
}

function parseList(str: string, startIndex: number): ParseResult {
  const nodes: StateTreeNode[] = [];
  let i = startIndex + 1; // Skip opening bracket
  let index = 0;

  while (i < str.length) {
    // Skip whitespace
    while (i < str.length && /\s/.test(str[i])) {
      i++;
    }

    // End of list
    if (str[i] === ']') {
      return { nodes, endIndex: i + 1 };
    }

    // Skip comma
    if (str[i] === ',') {
      i++;
      continue;
    }

    // Parse element
    const valueResult = parseFieldValue(str, i);
    nodes.push({
      key: String(index),
      value: valueResult.value,
      type: valueResult.type
    });
    index++;
    i = valueResult.endIndex;
  }

  return { nodes, endIndex: i };
}

function parseString(
  str: string,
  startIndex: number
): { value: string; endIndex: number } {
  let i = startIndex + 1; // Skip opening quote
  let value = '';

  while (i < str.length) {
    if (str[i] === '"' && str[i - 1] !== '\\') {
      return { value, endIndex: i + 1 };
    }
    value += str[i];
    i++;
  }

  return { value, endIndex: i };
}

function parseSimpleValue(
  str: string,
  startIndex: number
): {
  value: string;
  type: StateTreeNode['type'];
  endIndex: number;
} {
  let i = startIndex;
  let value = '';

  // Read until we hit a delimiter
  while (i < str.length && !/[\s,\}\]\)]/.test(str[i])) {
    value += str[i];
    i++;
  }

  // Determine type
  let type: StateTreeNode['type'] = 'string';
  if (value === 'True' || value === 'False') {
    type = 'boolean';
  } else if (/^-?\d+(\.\d+)?$/.test(value)) {
    type = 'number';
  } else if (/^[A-Z]/.test(value)) {
    type = 'custom';
  }

  return { value, type, endIndex: i };
}

function parseValue(
  str: string,
  startIndex: number
): { node: StateTreeNode | null; endIndex: number } {
  const result = parseFieldValue(str, startIndex);
  return {
    node: {
      key: 'value',
      value: result.value,
      type: result.type
    },
    endIndex: result.endIndex
  };
}

/**
 * Compare two state trees and mark changed nodes
 */
export function markChanges(
  oldTree: StateTreeNode[],
  newTree: StateTreeNode[]
): StateTreeNode[] {
  return newTree.map((newNode) => {
    const oldNode = oldTree.find((n) => n.key === newNode.key);

    if (!oldNode) {
      return { ...newNode, changed: true };
    }

    if (Array.isArray(newNode.value) && Array.isArray(oldNode.value)) {
      return {
        ...newNode,
        value: markChanges(oldNode.value, newNode.value),
        changed: false
      };
    }

    const changed = JSON.stringify(oldNode.value) !== JSON.stringify(newNode.value);
    return { ...newNode, changed };
  });
}

/**
 * Format a state tree for display
 */
export function formatStateTree(nodes: StateTreeNode[], indent: number = 0): string {
  const indentStr = '  '.repeat(indent);
  const lines: string[] = [];

  for (const node of nodes) {
    if (Array.isArray(node.value)) {
      const isRecord = node.type === 'record';
      const open = isRecord ? '{' : '[';
      const close = isRecord ? '}' : ']';

      if (node.value.length === 0) {
        lines.push(`${indentStr}${node.key} = ${open}${close}`);
      } else {
        lines.push(`${indentStr}${node.key} =`);
        lines.push(`${indentStr}${open}`);
        lines.push(formatStateTree(node.value, indent + 1));
        lines.push(`${indentStr}${close}`);
      }
    } else {
      const valueStr =
        node.type === 'string' ? `"${node.value}"` : node.value;
      lines.push(`${indentStr}${node.key} = ${valueStr}`);
    }
  }

  return lines.join('\n');
}
