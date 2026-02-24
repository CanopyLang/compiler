/**
 * State Inspector component for viewing and diffing application state
 */

import React, { useState, useMemo } from 'react';
import type { StateInspectorProps, StateTreeNode } from '../types';
import { parseStateTree, markChanges, computeStateDiff } from '../utils/stateDiff';

export const StateInspector: React.FC<StateInspectorProps> = ({
  state,
  previousState,
  showDiff = true
}) => {
  const [viewMode, setViewMode] = useState<'tree' | 'raw' | 'diff'>('tree');
  const [expandAll, setExpandAll] = useState(false);

  const stateTree = useMemo(() => {
    const tree = parseStateTree(state);
    if (showDiff && previousState) {
      const prevTree = parseStateTree(previousState);
      return markChanges(prevTree, tree);
    }
    return tree;
  }, [state, previousState, showDiff]);

  const diff = useMemo(() => {
    if (!previousState || !showDiff) {
      return [];
    }
    return computeStateDiff(previousState, state);
  }, [state, previousState, showDiff]);

  return (
    <div className="state-inspector">
      <div className="inspector-toolbar">
        <div className="view-mode-buttons">
          <button
            className={viewMode === 'tree' ? 'active' : ''}
            onClick={() => setViewMode('tree')}
            title="Tree view"
          >
            <TreeIcon />
          </button>
          <button
            className={viewMode === 'raw' ? 'active' : ''}
            onClick={() => setViewMode('raw')}
            title="Raw view"
          >
            <CodeIcon />
          </button>
          {previousState && (
            <button
              className={viewMode === 'diff' ? 'active' : ''}
              onClick={() => setViewMode('diff')}
              title="Diff view"
            >
              <DiffIcon />
            </button>
          )}
        </div>

        <div className="inspector-actions">
          {viewMode === 'tree' && (
            <button
              onClick={() => setExpandAll(!expandAll)}
              title={expandAll ? 'Collapse all' : 'Expand all'}
            >
              {expandAll ? <CollapseIcon /> : <ExpandIcon />}
            </button>
          )}
          <button onClick={() => copyToClipboard(state)} title="Copy state">
            <CopyIcon />
          </button>
        </div>
      </div>

      <div className="inspector-content">
        {viewMode === 'tree' && (
          <TreeView nodes={stateTree} expandAll={expandAll} depth={0} />
        )}

        {viewMode === 'raw' && (
          <pre className="raw-view">{formatState(state)}</pre>
        )}

        {viewMode === 'diff' && previousState && (
          <DiffView diff={diff} />
        )}
      </div>
    </div>
  );
};

interface TreeViewProps {
  nodes: StateTreeNode[];
  expandAll: boolean;
  depth: number;
}

const TreeView: React.FC<TreeViewProps> = ({ nodes, expandAll, depth }) => {
  return (
    <div className="tree-view" style={{ paddingLeft: depth * 16 }}>
      {nodes.map((node, index) => (
        <TreeNode
          key={`${node.key}-${index}`}
          node={node}
          expandAll={expandAll}
          depth={depth}
        />
      ))}
    </div>
  );
};

interface TreeNodeProps {
  node: StateTreeNode;
  expandAll: boolean;
  depth: number;
}

const TreeNode: React.FC<TreeNodeProps> = ({ node, expandAll, depth }) => {
  const [isExpanded, setIsExpanded] = useState(expandAll || depth < 2);
  const hasChildren = Array.isArray(node.value) && node.value.length > 0;

  React.useEffect(() => {
    setIsExpanded(expandAll || depth < 2);
  }, [expandAll, depth]);

  const classNames = [
    'tree-node',
    node.changed ? 'changed' : '',
    hasChildren ? 'has-children' : '',
    isExpanded ? 'expanded' : ''
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <div className={classNames}>
      <div
        className="node-header"
        onClick={() => hasChildren && setIsExpanded(!isExpanded)}
      >
        {hasChildren && (
          <span className="expand-icon">{isExpanded ? '▼' : '▶'}</span>
        )}
        <span className="node-key">{node.key}</span>
        <span className="node-colon">:</span>
        {!hasChildren && (
          <span className={`node-value type-${node.type}`}>
            {formatValue(node.value as string, node.type)}
          </span>
        )}
        {hasChildren && !isExpanded && (
          <span className="node-preview">
            {node.type === 'record' ? '{ ... }' : '[ ... ]'}
          </span>
        )}
      </div>

      {hasChildren && isExpanded && (
        <TreeView
          nodes={node.value as StateTreeNode[]}
          expandAll={expandAll}
          depth={depth + 1}
        />
      )}
    </div>
  );
};

interface DiffViewProps {
  diff: Array<{ type: string; value?: string; oldValue?: string; newValue?: string }>;
}

const DiffView: React.FC<DiffViewProps> = ({ diff }) => {
  return (
    <div className="diff-view">
      {diff.map((change, index) => (
        <div key={index} className={`diff-line diff-${change.type}`}>
          {change.type === 'added' && <span className="diff-marker">+</span>}
          {change.type === 'removed' && <span className="diff-marker">-</span>}
          {change.type === 'unchanged' && <span className="diff-marker"> </span>}
          <span className="diff-content">{change.value || change.newValue}</span>
        </div>
      ))}
    </div>
  );
};

/**
 * Format a value for display based on its type
 */
function formatValue(value: string, type: StateTreeNode['type']): string {
  switch (type) {
    case 'string':
      return `"${value}"`;
    case 'boolean':
      return value;
    case 'number':
      return value;
    case 'custom':
      return value;
    default:
      return value;
  }
}

/**
 * Format raw state with proper indentation
 */
function formatState(state: string): string {
  try {
    // Try to parse and re-format
    let depth = 0;
    let result = '';
    let inString = false;

    for (let i = 0; i < state.length; i++) {
      const char = state[i];

      if (char === '"' && state[i - 1] !== '\\') {
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
        result += char + '\n' + '  '.repeat(depth);
      } else if (char === '}' || char === ']') {
        depth--;
        result += '\n' + '  '.repeat(depth) + char;
      } else if (char === ',') {
        result += char + '\n' + '  '.repeat(depth);
      } else if (char === ' ' && (state[i - 1] === ',' || state[i - 1] === '{' || state[i - 1] === '[')) {
        // Skip extra spaces after delimiters
        continue;
      } else {
        result += char;
      }
    }

    return result;
  } catch {
    return state;
  }
}

/**
 * Copy text to clipboard
 */
async function copyToClipboard(text: string): Promise<void> {
  try {
    await navigator.clipboard.writeText(text);
  } catch (e) {
    // Fallback for older browsers
    const textarea = document.createElement('textarea');
    textarea.value = text;
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand('copy');
    document.body.removeChild(textarea);
  }
}

// Icon components
const TreeIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path
      fill="currentColor"
      d="M3 3h6v6H3V3zm8 0h10v2H11V3zm0 4h10v2H11V7zm-8 6h6v6H3v-6zm8 0h10v2H11v-2zm0 4h10v2H11v-2z"
    />
  </svg>
);

const CodeIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path
      fill="currentColor"
      d="M9.4 16.6L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4zm5.2 0l4.6-4.6-4.6-4.6L16 6l6 6-6 6-1.4-1.4z"
    />
  </svg>
);

const DiffIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path
      fill="currentColor"
      d="M9 7H7v2h2V7zm0 4H7v2h2v-2zm0-8a2 2 0 00-2 2v14a2 2 0 002 2h6v-2H9V5h6V3H9zm8 6h2v2h-2v-2zm-4 0h2v2h-2v-2zm8 0v6a2 2 0 01-2 2h-4v-2h4v-6h-4v-2h4a2 2 0 012 2z"
    />
  </svg>
);

const ExpandIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path fill="currentColor" d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z" />
  </svg>
);

const CollapseIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path fill="currentColor" d="M19 13H5v-2h14v2z" />
  </svg>
);

const CopyIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path
      fill="currentColor"
      d="M16 1H4a2 2 0 00-2 2v14h2V3h12V1zm3 4H8a2 2 0 00-2 2v14a2 2 0 002 2h11a2 2 0 002-2V7a2 2 0 00-2-2zm0 16H8V7h11v14z"
    />
  </svg>
);

export default StateInspector;
