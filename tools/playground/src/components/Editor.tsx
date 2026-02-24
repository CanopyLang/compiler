import { useRef, useEffect, useCallback } from 'react';
import MonacoEditor, { Monaco, OnMount } from '@monaco-editor/react';
import type { editor } from 'monaco-editor';
import type { CompilationError } from '../types';

interface EditorProps {
  value: string;
  onChange: (value: string) => void;
  language: string;
  theme: 'dark' | 'light';
  errors: CompilationError[];
}

function registerCanopyLanguage(monaco: Monaco): void {
  if (monaco.languages.getLanguages().some(lang => lang.id === 'canopy')) {
    return;
  }

  monaco.languages.register({ id: 'canopy' });

  monaco.languages.setMonarchTokensProvider('canopy', {
    keywords: [
      'module', 'exposing', 'import', 'as', 'type', 'alias', 'port',
      'if', 'then', 'else', 'case', 'of', 'let', 'in', 'where',
      'foreign', 'javascript'
    ],
    typeKeywords: [
      'Int', 'Float', 'Bool', 'String', 'Char', 'List', 'Maybe',
      'Result', 'Cmd', 'Sub', 'Html', 'Program'
    ],
    operators: [
      '=', '|', '\\\\', '->', '<-', '::', '++', '+', '-', '*', '/',
      '//', '^', '==', '/=', '<', '>', '<=', '>=', '&&', '||', '|>',
      '<|', '>>', '<<', '..'
    ],
    symbols: /[=><!~?:&|+\-*\/\^%]+/,
    escapes: /\\\\(?:[abfnrtv\\\\"']|x[0-9A-Fa-f]{1,4}|u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{8})/,

    tokenizer: {
      root: [
        [/--.*$/, 'comment'],
        [/\{-/, 'comment', '@comment'],
        [/"/, 'string', '@string'],
        [/'[^\\']'/, 'string'],
        [/'/, 'string', '@char'],
        [/[A-Z][a-zA-Z0-9_]*/, {
          cases: {
            '@typeKeywords': 'type',
            '@default': 'type.identifier'
          }
        }],
        [/[a-z_][a-zA-Z0-9_]*/, {
          cases: {
            '@keywords': 'keyword',
            '@default': 'identifier'
          }
        }],
        [/[0-9]+\.[0-9]+([eE][-+]?[0-9]+)?/, 'number.float'],
        [/[0-9]+/, 'number'],
        [/@symbols/, {
          cases: {
            '@operators': 'operator',
            '@default': ''
          }
        }],
        [/[{}()\[\]]/, '@brackets'],
        [/[,;]/, 'delimiter'],
      ],
      comment: [
        [/[^{-]+/, 'comment'],
        [/\{-/, 'comment', '@push'],
        [/-\}/, 'comment', '@pop'],
        [/[{-]/, 'comment'],
      ],
      string: [
        [/[^\\"]+/, 'string'],
        [/@escapes/, 'string.escape'],
        [/\\./, 'string.escape.invalid'],
        [/"/, 'string', '@pop'],
      ],
      char: [
        [/[^\\']+/, 'string'],
        [/@escapes/, 'string.escape'],
        [/\\./, 'string.escape.invalid'],
        [/'/, 'string', '@pop'],
      ],
    },
  });

  monaco.languages.setLanguageConfiguration('canopy', {
    comments: {
      lineComment: '--',
      blockComment: ['{-', '-}'],
    },
    brackets: [
      ['{', '}'],
      ['[', ']'],
      ['(', ')'],
    ],
    autoClosingPairs: [
      { open: '{', close: '}' },
      { open: '[', close: ']' },
      { open: '(', close: ')' },
      { open: '"', close: '"' },
      { open: "'", close: "'" },
    ],
    surroundingPairs: [
      { open: '{', close: '}' },
      { open: '[', close: ']' },
      { open: '(', close: ')' },
      { open: '"', close: '"' },
      { open: "'", close: "'" },
    ],
    indentationRules: {
      increaseIndentPattern: /^\s*(let|if|case|type)\b.*$/,
      decreaseIndentPattern: /^\s*(in|else)\b.*$/,
    },
  });

  monaco.languages.registerCompletionItemProvider('canopy', {
    provideCompletionItems: (model, position) => {
      const word = model.getWordUntilPosition(position);
      const range = {
        startLineNumber: position.lineNumber,
        endLineNumber: position.lineNumber,
        startColumn: word.startColumn,
        endColumn: word.endColumn,
      };

      const suggestions = [
        { label: 'module', kind: monaco.languages.CompletionItemKind.Keyword, insertText: 'module ${1:ModuleName} exposing (..)\n\n$0', insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet },
        { label: 'import', kind: monaco.languages.CompletionItemKind.Keyword, insertText: 'import ${1:Module}', insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet },
        { label: 'type alias', kind: monaco.languages.CompletionItemKind.Keyword, insertText: 'type alias ${1:Name} =\n    { ${2:field} : ${3:Type}\n    }', insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet },
        { label: 'type', kind: monaco.languages.CompletionItemKind.Keyword, insertText: 'type ${1:Name}\n    = ${2:Constructor}\n    | ${3:Constructor2}', insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet },
        { label: 'case', kind: monaco.languages.CompletionItemKind.Keyword, insertText: 'case ${1:expression} of\n    ${2:pattern} ->\n        ${3:result}', insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet },
        { label: 'if', kind: monaco.languages.CompletionItemKind.Keyword, insertText: 'if ${1:condition} then\n    ${2:thenBranch}\nelse\n    ${3:elseBranch}', insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet },
        { label: 'let', kind: monaco.languages.CompletionItemKind.Keyword, insertText: 'let\n    ${1:binding} = ${2:value}\nin\n${3:expression}', insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet },
        { label: 'main', kind: monaco.languages.CompletionItemKind.Function, insertText: 'main : Html msg\nmain =\n    $0', insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet },
        { label: 'view', kind: monaco.languages.CompletionItemKind.Function, insertText: 'view : Model -> Html Msg\nview model =\n    $0', insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet },
        { label: 'update', kind: monaco.languages.CompletionItemKind.Function, insertText: 'update : Msg -> Model -> Model\nupdate msg model =\n    case msg of\n        $0', insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet },
      ].map(s => ({ ...s, range }));

      return { suggestions };
    },
  });
}

function defineCanopyThemes(monaco: Monaco): void {
  monaco.editor.defineTheme('canopy-dark', {
    base: 'vs-dark',
    inherit: true,
    rules: [
      { token: 'comment', foreground: '6A9955', fontStyle: 'italic' },
      { token: 'keyword', foreground: 'C586C0' },
      { token: 'type', foreground: '4EC9B0' },
      { token: 'type.identifier', foreground: '4EC9B0' },
      { token: 'string', foreground: 'CE9178' },
      { token: 'number', foreground: 'B5CEA8' },
      { token: 'operator', foreground: 'D4D4D4' },
      { token: 'identifier', foreground: '9CDCFE' },
    ],
    colors: {
      'editor.background': '#0f172a',
      'editor.foreground': '#e2e8f0',
      'editor.lineHighlightBackground': '#1e293b',
      'editor.selectionBackground': '#334155',
      'editorCursor.foreground': '#38bdf8',
      'editorLineNumber.foreground': '#64748b',
      'editorLineNumber.activeForeground': '#94a3b8',
    },
  });

  monaco.editor.defineTheme('canopy-light', {
    base: 'vs',
    inherit: true,
    rules: [
      { token: 'comment', foreground: '008000', fontStyle: 'italic' },
      { token: 'keyword', foreground: 'AF00DB' },
      { token: 'type', foreground: '267F99' },
      { token: 'type.identifier', foreground: '267F99' },
      { token: 'string', foreground: 'A31515' },
      { token: 'number', foreground: '098658' },
      { token: 'operator', foreground: '000000' },
      { token: 'identifier', foreground: '001080' },
    ],
    colors: {
      'editor.background': '#ffffff',
      'editor.foreground': '#0f172a',
      'editor.lineHighlightBackground': '#f8fafc',
      'editor.selectionBackground': '#e2e8f0',
      'editorCursor.foreground': '#0284c7',
      'editorLineNumber.foreground': '#94a3b8',
      'editorLineNumber.activeForeground': '#475569',
    },
  });
}

export function Editor({ value, onChange, language, theme, errors }: EditorProps): JSX.Element {
  const editorRef = useRef<editor.IStandaloneCodeEditor | null>(null);
  const monacoRef = useRef<Monaco | null>(null);

  const handleEditorDidMount: OnMount = useCallback((editor, monaco) => {
    editorRef.current = editor;
    monacoRef.current = monaco;

    registerCanopyLanguage(monaco);
    defineCanopyThemes(monaco);

    monaco.editor.setTheme(theme === 'dark' ? 'canopy-dark' : 'canopy-light');

    editor.addAction({
      id: 'canopy-format',
      label: 'Format Document',
      keybindings: [monaco.KeyMod.Shift | monaco.KeyMod.Alt | monaco.KeyCode.KeyF],
      run: () => {
        editor.trigger('', 'editor.action.formatDocument', {});
      },
    });
  }, [theme]);

  useEffect(() => {
    if (monacoRef.current) {
      monacoRef.current.editor.setTheme(theme === 'dark' ? 'canopy-dark' : 'canopy-light');
    }
  }, [theme]);

  useEffect(() => {
    if (!editorRef.current || !monacoRef.current) return;

    const model = editorRef.current.getModel();
    if (!model) return;

    const markers = errors.map(error => ({
      severity: error.severity === 'error'
        ? monacoRef.current!.MarkerSeverity.Error
        : monacoRef.current!.MarkerSeverity.Warning,
      startLineNumber: error.line,
      startColumn: error.column,
      endLineNumber: error.endLine ?? error.line,
      endColumn: error.endColumn ?? (error.column + 10),
      message: error.message,
    }));

    monacoRef.current.editor.setModelMarkers(model, 'canopy', markers);
  }, [errors]);

  const handleChange = useCallback((newValue: string | undefined) => {
    if (newValue !== undefined) {
      onChange(newValue);
    }
  }, [onChange]);

  const editorLanguage = language === 'canopy' ? 'canopy' : language;

  return (
    <div className="editor-container">
      <MonacoEditor
        height="100%"
        language={editorLanguage}
        value={value}
        onChange={handleChange}
        onMount={handleEditorDidMount}
        theme={theme === 'dark' ? 'canopy-dark' : 'canopy-light'}
        options={{
          fontSize: 14,
          fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
          fontLigatures: true,
          lineNumbers: 'on',
          minimap: { enabled: false },
          scrollBeyondLastLine: false,
          automaticLayout: true,
          tabSize: 4,
          insertSpaces: true,
          wordWrap: 'on',
          renderWhitespace: 'selection',
          bracketPairColorization: { enabled: true },
          guides: {
            indentation: true,
            bracketPairs: true,
          },
          padding: { top: 16, bottom: 16 },
          smoothScrolling: true,
          cursorSmoothCaretAnimation: 'on',
          cursorBlinking: 'smooth',
        }}
        loading={
          <div style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            height: '100%',
            color: 'var(--color-text-secondary)',
          }}>
            <div className="loading-spinner" />
          </div>
        }
      />
    </div>
  );
}
