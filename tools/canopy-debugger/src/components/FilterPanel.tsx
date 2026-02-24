/**
 * Filter Panel component for message filtering and search
 */

import React, { useState } from 'react';
import type { MessageFilter } from '../types';

interface FilterPanelProps {
  filters: MessageFilter[];
  searchQuery: string;
  onSearchChange: (query: string) => void;
  onAddFilter: (filter: Omit<MessageFilter, 'id'>) => void;
  onRemoveFilter: (id: string) => void;
  onToggleFilter: (id: string) => void;
  onClose: () => void;
}

export const FilterPanel: React.FC<FilterPanelProps> = ({
  filters,
  searchQuery,
  onSearchChange,
  onAddFilter,
  onRemoveFilter,
  onToggleFilter,
  onClose
}) => {
  const [newPattern, setNewPattern] = useState('');
  const [newType, setNewType] = useState<'include' | 'exclude'>('exclude');

  const handleAddFilter = () => {
    if (!newPattern.trim()) return;

    onAddFilter({
      pattern: newPattern.trim(),
      enabled: true,
      type: newType
    });

    setNewPattern('');
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      handleAddFilter();
    }
    if (e.key === 'Escape') {
      onClose();
    }
  };

  return (
    <div className="filter-panel">
      <div className="filter-header">
        <h3>Filters</h3>
        <button className="close-button" onClick={onClose} title="Close">
          <CloseIcon />
        </button>
      </div>

      <div className="filter-search">
        <label htmlFor="search-input">Search</label>
        <div className="search-input-wrapper">
          <SearchIcon />
          <input
            id="search-input"
            type="text"
            placeholder="Search messages and state..."
            value={searchQuery}
            onChange={(e) => onSearchChange(e.target.value)}
          />
          {searchQuery && (
            <button
              className="clear-search"
              onClick={() => onSearchChange('')}
              title="Clear search"
            >
              <CloseIcon />
            </button>
          )}
        </div>
      </div>

      <div className="filter-add">
        <label>Add Filter</label>
        <div className="add-filter-form">
          <input
            type="text"
            placeholder="Message pattern..."
            value={newPattern}
            onChange={(e) => setNewPattern(e.target.value)}
            onKeyDown={handleKeyDown}
          />
          <select
            value={newType}
            onChange={(e) => setNewType(e.target.value as 'include' | 'exclude')}
          >
            <option value="exclude">Exclude</option>
            <option value="include">Include</option>
          </select>
          <button
            className="add-button"
            onClick={handleAddFilter}
            disabled={!newPattern.trim()}
          >
            Add
          </button>
        </div>
      </div>

      <div className="filter-list">
        <label>Active Filters</label>
        {filters.length === 0 ? (
          <p className="no-filters">No filters configured</p>
        ) : (
          <ul>
            {filters.map((filter) => (
              <FilterItem
                key={filter.id}
                filter={filter}
                onToggle={() => onToggleFilter(filter.id)}
                onRemove={() => onRemoveFilter(filter.id)}
              />
            ))}
          </ul>
        )}
      </div>

      <div className="filter-presets">
        <label>Quick Filters</label>
        <div className="preset-buttons">
          <button
            onClick={() =>
              onAddFilter({ pattern: 'Tick', enabled: true, type: 'exclude' })
            }
          >
            Hide Tick messages
          </button>
          <button
            onClick={() =>
              onAddFilter({ pattern: 'Animation', enabled: true, type: 'exclude' })
            }
          >
            Hide Animation
          </button>
          <button
            onClick={() =>
              onAddFilter({ pattern: 'Click', enabled: true, type: 'include' })
            }
          >
            Only Click events
          </button>
          <button
            onClick={() =>
              onAddFilter({ pattern: 'Http', enabled: true, type: 'include' })
            }
          >
            Only HTTP
          </button>
        </div>
      </div>
    </div>
  );
};

interface FilterItemProps {
  filter: MessageFilter;
  onToggle: () => void;
  onRemove: () => void;
}

const FilterItem: React.FC<FilterItemProps> = ({ filter, onToggle, onRemove }) => {
  return (
    <li className={`filter-item ${filter.enabled ? '' : 'disabled'}`}>
      <button
        className="toggle-checkbox"
        onClick={onToggle}
        aria-checked={filter.enabled}
        role="checkbox"
      >
        {filter.enabled ? <CheckboxCheckedIcon /> : <CheckboxUncheckedIcon />}
      </button>

      <span className={`filter-type filter-type-${filter.type}`}>
        {filter.type === 'include' ? 'INCLUDE' : 'EXCLUDE'}
      </span>

      <span className="filter-pattern">{filter.pattern}</span>

      <button className="remove-button" onClick={onRemove} title="Remove filter">
        <CloseIcon />
      </button>
    </li>
  );
};

// Icons

const SearchIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path
      fill="currentColor"
      d="M15.5 14h-.79l-.28-.27a6.5 6.5 0 10-.7.7l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0a4.5 4.5 0 110-9 4.5 4.5 0 010 9z"
    />
  </svg>
);

const CloseIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="16" height="16">
    <path
      fill="currentColor"
      d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"
    />
  </svg>
);

const CheckboxCheckedIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="18" height="18">
    <path
      fill="currentColor"
      d="M19 3H5a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2V5a2 2 0 00-2-2zm-9 14l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"
    />
  </svg>
);

const CheckboxUncheckedIcon: React.FC = () => (
  <svg viewBox="0 0 24 24" width="18" height="18">
    <path
      fill="currentColor"
      d="M19 5v14H5V5h14m0-2H5a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2V5a2 2 0 00-2-2z"
    />
  </svg>
);

export default FilterPanel;
