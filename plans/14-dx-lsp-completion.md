# Plan 14: LSP Feature Completion

**Priority**: HIGH
**Effort**: Large (2-3 weeks)
**Risk**: Medium
**Audit Finding**: LSP exists but is basic — missing inline type hints, quick fixes, signature help, call hierarchy; IDE setup is undocumented and adoption dies here

---

## Problem

The Canopy LSP (`packages/canopy-lsp/`) is a partial fork of elm-language-server. It provides basic functionality (diagnostics, go-to-definition, completions) but lacks the features developers expect from a modern language server:

1. **No inline type hints** — users can't see inferred types without hovering
2. **No quick fixes** — compiler errors don't offer automatic fixes
3. **No signature help** — no parameter info when calling functions
4. **No call hierarchy** — can't trace who calls what
5. **No semantic tokens** — syntax highlighting relies on TextMate grammars
6. **No code actions** — no "extract function", "add type annotation", etc.
7. **No setup documentation** — users don't know how to install/configure

---

## Solution

Complete the LSP implementation and create setup documentation for all major editors.

---

## Implementation

### Step 1: Inline Type Hints (Inlay Hints)

**File: `packages/canopy-lsp/src/common/providers/inlayHints.ts`** (new)

Implement LSP `textDocument/inlayHint` to show inferred types inline:

```typescript
// Show type annotations for let-bindings without explicit annotations
// Before: myFunc x = x + 1
// With hints: myFunc (x : Int) : Int = x + 1

export class InlayHintsProvider {
  async provideInlayHints(
    params: InlayHintParams
  ): Promise<InlayHint[]> {
    const tree = this.getTree(params.textDocument.uri);
    const hints: InlayHint[] = [];

    // Find all function definitions without type annotations
    const defs = findUnannotatedDefinitions(tree);
    for (const def of defs) {
      const inferredType = await this.getInferredType(def);
      if (inferredType) {
        hints.push({
          position: def.nameEnd,
          label: ` : ${inferredType}`,
          kind: InlayHintKind.Type,
          paddingLeft: true,
        });
      }
    }

    // Show parameter types
    const params = findUnannotatedParameters(tree);
    for (const param of params) {
      const paramType = await this.getParamType(param);
      if (paramType) {
        hints.push({
          position: param.end,
          label: ` : ${paramType}`,
          kind: InlayHintKind.Type,
        });
      }
    }

    return hints;
  }
}
```

### Step 2: Quick Fixes (Code Actions)

**File: `packages/canopy-lsp/src/common/providers/codeActions.ts`** (new)

Provide automatic fixes for common compiler errors:

```typescript
export class CodeActionsProvider {
  async provideCodeActions(
    params: CodeActionParams
  ): Promise<CodeAction[]> {
    const diagnostics = params.context.diagnostics;
    const actions: CodeAction[] = [];

    for (const diag of diagnostics) {
      // Missing type annotation → add inferred annotation
      if (diag.code === 'MISSING_ANNOTATION') {
        actions.push(this.addTypeAnnotation(diag, params));
      }

      // Missing import → add import statement
      if (diag.code === 'NAME_NOT_FOUND') {
        const imports = await this.findPossibleImports(diag);
        for (const imp of imports) {
          actions.push(this.addImport(imp, params));
        }
      }

      // Unused import → remove import
      if (diag.code === 'UNUSED_IMPORT') {
        actions.push(this.removeImport(diag, params));
      }

      // Missing case branch → add branch
      if (diag.code === 'INCOMPLETE_PATTERN') {
        actions.push(this.addMissingBranch(diag, params));
      }

      // Type mismatch with suggestion → apply suggestion
      if (diag.code === 'TYPE_MISMATCH' && diag.data?.suggestion) {
        actions.push(this.applySuggestion(diag, params));
      }
    }

    return actions;
  }
}
```

### Step 3: Signature Help

**File: `packages/canopy-lsp/src/common/providers/signatureHelp.ts`** (new)

Show parameter information when typing function arguments:

```typescript
export class SignatureHelpProvider {
  async provideSignatureHelp(
    params: SignatureHelpParams
  ): Promise<SignatureHelp | null> {
    const tree = this.getTree(params.textDocument.uri);
    const node = findNodeAtPosition(tree, params.position);

    // Check if we're inside a function call
    const callExpr = findParentCallExpression(node);
    if (!callExpr) return null;

    const funcName = getFunctionName(callExpr);
    const funcType = await this.lookupFunctionType(funcName);
    if (!funcType) return null;

    const paramIndex = getActiveParameterIndex(callExpr, params.position);

    return {
      signatures: [{
        label: `${funcName} : ${formatType(funcType)}`,
        parameters: extractParameters(funcType).map(p => ({
          label: formatType(p.type),
          documentation: p.doc,
        })),
        activeParameter: paramIndex,
      }],
      activeSignature: 0,
      activeParameter: paramIndex,
    };
  }
}
```

### Step 4: Semantic Tokens

**File: `packages/canopy-lsp/src/common/providers/semanticTokens.ts`** (new)

Provide rich semantic highlighting:

```typescript
const tokenTypes = [
  'namespace',   // module names
  'type',        // type names
  'typeParameter', // type variables
  'function',    // function names
  'variable',    // local variables
  'keyword',     // language keywords
  'string',      // string literals
  'number',      // numeric literals
  'operator',    // operators
  'decorator',   // annotations
];

export class SemanticTokensProvider {
  async provideSemanticTokens(
    params: SemanticTokensParams
  ): Promise<SemanticTokens> {
    const tree = this.getTree(params.textDocument.uri);
    const builder = new SemanticTokensBuilder();

    // Walk the tree and classify each token
    walkTree(tree.rootNode, (node) => {
      switch (node.type) {
        case 'module_name':
          builder.push(node, 'namespace', []);
          break;
        case 'type_name':
          builder.push(node, 'type', ['declaration']);
          break;
        case 'type_variable':
          builder.push(node, 'typeParameter', []);
          break;
        case 'function_name':
          builder.push(node, 'function', ['declaration']);
          break;
        // ... all token types
      }
    });

    return builder.build();
  }
}
```

### Step 5: Editor Setup Documentation

**File: `docs/editors/README.md`** (new)

```markdown
# Canopy Editor Setup

## VS Code

1. Install the Canopy extension from the marketplace:
   ```
   code --install-extension canopy-lang.canopy-vscode
   ```

2. The extension will:
   - Download the Canopy LSP automatically
   - Configure syntax highlighting
   - Enable inline type hints, quick fixes, and completions

### Configuration

Add to your `settings.json`:
```json
{
  "canopy.serverPath": "/path/to/canopy-lsp",
  "canopy.inlayHints.enabled": true,
  "canopy.inlayHints.parameterTypes": true,
  "canopy.formatOnSave": true
}
```

## Neovim

Using `nvim-lspconfig`:
```lua
require('lspconfig').canopy.setup({
  cmd = { 'canopy-lsp', '--stdio' },
  filetypes = { 'canopy', 'elm' },
  root_dir = require('lspconfig.util').root_pattern('canopy.json', 'elm.json'),
})
```

## Helix

Add to `~/.config/helix/languages.toml`:
```toml
[[language]]
name = "canopy"
scope = "source.canopy"
file-types = ["can", "canopy"]
language-servers = ["canopy-lsp"]

[language-server.canopy-lsp]
command = "canopy-lsp"
args = ["--stdio"]
```

## Zed

Add to your Zed settings:
```json
{
  "lsp": {
    "canopy-lsp": {
      "binary": { "path": "canopy-lsp" }
    }
  }
}
```

## Emacs

Using `eglot`:
```elisp
(add-to-list 'eglot-server-programs
  '(canopy-mode . ("canopy-lsp" "--stdio")))
```
```

---

## Validation

```bash
# Build LSP
cd packages/canopy-lsp && npm run compile

# Run LSP tests
cd packages/canopy-lsp && npm test

# Manual testing with VS Code
code --extensionDevelopmentPath=packages/canopy-lsp
```

---

## Success Criteria

- [ ] Inline type hints show inferred types for unannotated definitions
- [ ] Quick fixes for: missing import, unused import, missing annotation, incomplete pattern
- [ ] Signature help shows parameter info during function calls
- [ ] Semantic tokens provide rich syntax highlighting
- [ ] Setup documentation for VS Code, Neovim, Helix, Zed, Emacs
- [ ] All existing LSP tests pass
- [ ] New tests for each provider
