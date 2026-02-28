# Plan 37: Editor Integration (LSP Publishing)

## Priority: HIGH
## Effort: Medium (2-3 days)
## Risk: Low — LSP exists, just needs packaging and publishing

## Problem

The LSP exists in `packages/canopy-lsp/` as a **TypeScript** implementation (not Haskell). It has source code in `src/` with `browser/`, `common/`, `compiler/`, `node/` directories, and `.ts` files. However, there's no `.cabal` file — it's a Node.js/TypeScript package, not part of the Haskell build system.

The LSP is not published to any package manager. Editors can't discover or install it automatically.

## Implementation Plan

### Step 1: Set up npm/yarn build

**File**: `packages/canopy-lsp/package.json` (NEW or verify existing)

Ensure the TypeScript LSP has proper build tooling:
- `npm run build` compiles TypeScript to JavaScript
- `npm run test` runs LSP tests
- Output produces a runnable `canopy-lsp` binary (via Node.js)

### Step 2: VS Code Extension

**File**: `editors/vscode/` (NEW directory)

Create a VS Code extension that:
- Bundles or downloads the canopy-lsp Node.js package
- Registers .can and .canopy file associations
- Provides syntax highlighting (TextMate grammar)
- Configures LSP client settings

```json
{
    "name": "canopy-language",
    "displayName": "Canopy Language Support",
    "description": "Language support for the Canopy programming language",
    "engines": { "vscode": "^1.80.0" },
    "activationEvents": ["onLanguage:canopy"],
    "contributes": {
        "languages": [{
            "id": "canopy",
            "extensions": [".can", ".canopy"],
            "aliases": ["Canopy"]
        }]
    }
}
```

### Step 2: Neovim integration

**File**: `editors/nvim/` (NEW directory)

Provide a Lua config snippet for nvim-lspconfig:

```lua
local lspconfig = require('lspconfig')
lspconfig.canopy.setup({
    cmd = { 'canopy-lsp' },
    filetypes = { 'canopy' },
    root_dir = lspconfig.util.root_pattern('canopy.json', 'elm.json'),
})
```

### Step 3: Binary distribution

- Add canopy-lsp to the release build matrix
- Provide pre-built binaries for Linux, macOS, Windows
- Add to the VS Code extension's download mechanism

### Step 4: Publish VS Code extension

Publish to the VS Code marketplace and Open VSX Registry.

### Step 5: Documentation

Document LSP features:
- Diagnostics (type errors, parse errors, lint warnings)
- Go to definition
- Find references
- Hover information
- Code completion
- Code actions (quick fixes)

## Dependencies
- None (LSP TypeScript implementation exists in packages/canopy-lsp/)
