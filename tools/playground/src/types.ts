export interface CompilationResult {
  success: boolean;
  output?: string;
  errors?: CompilationError[];
  warnings?: CompilationWarning[];
  compilationTime?: number;
}

export interface CompilationError {
  line: number;
  column: number;
  endLine?: number;
  endColumn?: number;
  message: string;
  severity: 'error' | 'warning';
  code?: string;
}

export interface CompilationWarning {
  line: number;
  column: number;
  message: string;
}

export interface PlaygroundFile {
  name: string;
  content: string;
  language: 'canopy' | 'json';
}

export interface PlaygroundState {
  files: PlaygroundFile[];
  activeFileIndex: number;
  compiledOutput: string;
  errors: CompilationError[];
  isCompiling: boolean;
  theme: 'dark' | 'light';
}

export interface Example {
  id: string;
  name: string;
  description: string;
  files: PlaygroundFile[];
}

export type OutputTab = 'preview' | 'javascript' | 'errors';
