import { useState, useRef, useEffect } from 'react';
import { EXAMPLES } from '../examples';

interface ExamplePickerProps {
  onSelectExample: (exampleId: string) => void;
}

export function ExamplePicker({ onSelectExample }: ExamplePickerProps): JSX.Element {
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClickOutside(event: MouseEvent): void {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    }

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const handleSelect = (exampleId: string): void => {
    onSelectExample(exampleId);
    setIsOpen(false);
  };

  return (
    <div className="example-picker" ref={dropdownRef}>
      <button
        className="btn btn-secondary"
        onClick={() => setIsOpen(!isOpen)}
        aria-expanded={isOpen}
        aria-haspopup="listbox"
      >
        <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
          <path d="M2 4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V4zm2-.5a.5.5 0 0 0-.5.5v8a.5.5 0 0 0 .5.5h8a.5.5 0 0 0 .5-.5V4a.5.5 0 0 0-.5-.5H4zm4.5 6a.5.5 0 0 0-.5.5v1.5a.5.5 0 0 0 1 0V10a.5.5 0 0 0-.5-.5zm-2-4a.5.5 0 0 0-.5.5V8a.5.5 0 0 0 1 0V6a.5.5 0 0 0-.5-.5zm4 1.5a.5.5 0 0 0-.5.5v2a.5.5 0 0 0 1 0V7.5a.5.5 0 0 0-.5-.5z"/>
        </svg>
        <span>Examples</span>
        <svg
          width="12"
          height="12"
          viewBox="0 0 12 12"
          fill="currentColor"
          style={{ transform: isOpen ? 'rotate(180deg)' : 'none', transition: 'transform 0.15s' }}
        >
          <path d="M6 8.825L1.175 4 2.238 2.938 6 6.7l3.762-3.762L10.825 4z"/>
        </svg>
      </button>

      {isOpen && (
        <div className="example-dropdown" role="listbox">
          {EXAMPLES.map((example) => (
            <button
              key={example.id}
              className="example-option"
              onClick={() => handleSelect(example.id)}
              role="option"
            >
              {example.name}
              <span className="example-option-description">{example.description}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
