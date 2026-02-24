import { useState, useCallback, useEffect, useRef } from 'react';
import type { PlaygroundFile, CompilationError, OutputTab } from '../types';
import { compileCanopy } from '../utils/compiler';
import { decodeShareUrl, encodeShareUrl } from '../utils/sharing';
import { EXAMPLES, DEFAULT_EXAMPLE } from '../examples';

interface UsePlaygroundReturn {
  files: PlaygroundFile[];
  activeFileIndex: number;
  compiledOutput: string;
  errors: CompilationError[];
  isCompiling: boolean;
  theme: 'dark' | 'light';
  activeOutputTab: OutputTab;
  setActiveFileIndex: (index: number) => void;
  updateFileContent: (index: number, content: string) => void;
  addFile: (file: PlaygroundFile) => void;
  removeFile: (index: number) => void;
  loadExample: (exampleId: string) => void;
  compile: () => Promise<void>;
  toggleTheme: () => void;
  setActiveOutputTab: (tab: OutputTab) => void;
  getShareUrl: () => string;
}

const COMPILE_DEBOUNCE_MS = 500;

export function usePlayground(): UsePlaygroundReturn {
  const [files, setFiles] = useState<PlaygroundFile[]>(() => {
    const shared = decodeShareUrl();
    if (shared) {
      return shared.files;
    }
    return DEFAULT_EXAMPLE.files;
  });

  const [activeFileIndex, setActiveFileIndex] = useState(() => {
    const shared = decodeShareUrl();
    return shared?.activeFileIndex ?? 0;
  });

  const [compiledOutput, setCompiledOutput] = useState('');
  const [errors, setErrors] = useState<CompilationError[]>([]);
  const [isCompiling, setIsCompiling] = useState(false);
  const [theme, setTheme] = useState<'dark' | 'light'>(() => {
    const stored = localStorage.getItem('canopy-playground-theme');
    return (stored === 'light' ? 'light' : 'dark');
  });
  const [activeOutputTab, setActiveOutputTab] = useState<OutputTab>('preview');

  const compileTimeoutRef = useRef<number | null>(null);

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('canopy-playground-theme', theme);
  }, [theme]);

  const compile = useCallback(async () => {
    setIsCompiling(true);
    setErrors([]);

    try {
      const result = await compileCanopy(files);

      if (result.success && result.output) {
        setCompiledOutput(result.output);
        setErrors([]);
      } else {
        setErrors(result.errors ?? []);
        if (result.errors && result.errors.length > 0) {
          setActiveOutputTab('errors');
        }
      }
    } catch (error) {
      setErrors([{
        line: 1,
        column: 1,
        message: error instanceof Error ? error.message : 'Compilation failed',
        severity: 'error',
      }]);
      setActiveOutputTab('errors');
    } finally {
      setIsCompiling(false);
    }
  }, [files]);

  const updateFileContent = useCallback((index: number, content: string) => {
    setFiles(prev => {
      const newFiles = [...prev];
      newFiles[index] = { ...newFiles[index], content };
      return newFiles;
    });

    if (compileTimeoutRef.current) {
      clearTimeout(compileTimeoutRef.current);
    }
    compileTimeoutRef.current = window.setTimeout(() => {
      compile();
    }, COMPILE_DEBOUNCE_MS);
  }, [compile]);

  const addFile = useCallback((file: PlaygroundFile) => {
    setFiles(prev => [...prev, file]);
    setActiveFileIndex(files.length);
  }, [files.length]);

  const removeFile = useCallback((index: number) => {
    if (files.length <= 1) return;

    setFiles(prev => prev.filter((_, i) => i !== index));

    if (activeFileIndex >= index && activeFileIndex > 0) {
      setActiveFileIndex(activeFileIndex - 1);
    }
  }, [files.length, activeFileIndex]);

  const loadExample = useCallback((exampleId: string) => {
    const example = EXAMPLES.find(e => e.id === exampleId);
    if (example) {
      setFiles(example.files);
      setActiveFileIndex(0);
      setErrors([]);
      setCompiledOutput('');

      window.setTimeout(() => compile(), 100);
    }
  }, [compile]);

  const toggleTheme = useCallback(() => {
    setTheme(prev => prev === 'dark' ? 'light' : 'dark');
  }, []);

  const getShareUrl = useCallback(() => {
    return encodeShareUrl(files, activeFileIndex);
  }, [files, activeFileIndex]);

  useEffect(() => {
    compile();
  }, []);

  return {
    files,
    activeFileIndex,
    compiledOutput,
    errors,
    isCompiling,
    theme,
    activeOutputTab,
    setActiveFileIndex,
    updateFileContent,
    addFile,
    removeFile,
    loadExample,
    compile,
    toggleTheme,
    setActiveOutputTab,
    getShareUrl,
  };
}
