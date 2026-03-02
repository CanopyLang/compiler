# Canopy Editor Setup

This guide covers how to set up the Canopy Language Server (LSP) with popular
editors. The language server provides:

- **Diagnostics** -- real-time error and warning reporting
- **Go to Definition** -- jump to any symbol's definition
- **Hover** -- see type signatures and documentation on hover
- **Completions** -- context-aware autocompletion
- **Inline Type Hints** -- see inferred types for unannotated definitions
- **Signature Help** -- parameter info when calling functions
- **Semantic Highlighting** -- rich, AST-based syntax coloring
- **Code Actions** -- quick fixes for common compiler errors
- **Rename** -- project-wide rename refactoring
- **Find References** -- find all usages of a symbol
- **Code Lenses** -- inline reference counts
- **Document Symbols** -- outline view of the current file
- **Formatting** -- auto-format via `canopy-format`

## Prerequisites

1. Install Canopy:
   ```bash
   npm install -g @canopy-lang/canopy-language-server
   ```

   Or build from source:
   ```bash
   cd packages/canopy-lsp
   npm install
   npm run compile
   ```

2. Ensure the `canopy-language-server` binary is on your `$PATH`.

---

## VS Code

Install the Canopy extension from the marketplace:

```bash
code --install-extension canopy-lang.canopy-vscode
```

The extension will automatically download and manage the Canopy LSP.

### Configuration

Add to your `settings.json`:

```json
{
  "canopy.serverPath": "/path/to/canopy-language-server",
  "canopy.trace.server": "messages",
  "canopy.inlayHints.enabled": true,
  "canopy.inlayHints.parameterTypes": true,
  "canopy.formatOnSave": true,
  "editor.semanticHighlighting.enabled": true
}
```

### Features

| Feature | Status |
|---------|--------|
| Diagnostics | Supported |
| Go to Definition | Supported |
| Hover | Supported |
| Completions | Supported |
| Inline Type Hints | Supported |
| Signature Help | Supported |
| Semantic Highlighting | Supported |
| Code Actions | Supported |
| Formatting | Supported |
| Rename | Supported |
| Find References | Supported |

---

## Neovim

### Using nvim-lspconfig

Add to your Neovim configuration (e.g., `init.lua`):

```lua
require('lspconfig').canopy.setup({
  cmd = { 'canopy-language-server', '--stdio' },
  filetypes = { 'canopy', 'elm' },
  root_dir = require('lspconfig.util').root_pattern('canopy.json', 'elm.json'),
  settings = {
    canopy = {
      disableElmLSDiagnostics = false,
    },
  },
})
```

### Manual configuration (without nvim-lspconfig)

```lua
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'canopy', 'elm' },
  callback = function()
    vim.lsp.start({
      name = 'canopy-language-server',
      cmd = { 'canopy-language-server', '--stdio' },
      root_dir = vim.fs.dirname(
        vim.fs.find({ 'canopy.json', 'elm.json' }, { upward = true })[1]
      ),
    })
  end,
})
```

### Inlay hints (Neovim 0.10+)

```lua
vim.lsp.inlay_hint.enable(true)
```

### Semantic highlighting

Neovim supports LSP semantic tokens natively. Ensure your color scheme
supports the `@lsp.*` highlight groups, or define custom mappings:

```lua
vim.api.nvim_set_hl(0, '@lsp.type.typeParameter.canopy', { link = 'Type' })
vim.api.nvim_set_hl(0, '@lsp.type.enumMember.canopy', { link = 'Constant' })
vim.api.nvim_set_hl(0, '@lsp.type.property.canopy', { link = 'Identifier' })
```

---

## Helix

Add to `~/.config/helix/languages.toml`:

```toml
[[language]]
name = "canopy"
scope = "source.canopy"
injection-regex = "canopy"
file-types = ["can", "canopy"]
roots = ["canopy.json", "elm.json"]
language-servers = ["canopy-lsp"]
comment-token = "--"
indent = { tab-width = 4, unit = "    " }

[language-server.canopy-lsp]
command = "canopy-language-server"
args = ["--stdio"]
```

Helix has built-in support for LSP inlay hints (`:toggle-option lsp.display-inlay-hints`),
semantic tokens, and signature help.

---

## Zed

Add to your Zed settings (`~/.config/zed/settings.json`):

```json
{
  "languages": {
    "Canopy": {
      "language_servers": ["canopy-lsp"]
    }
  },
  "lsp": {
    "canopy-lsp": {
      "binary": {
        "path": "canopy-language-server",
        "arguments": ["--stdio"]
      }
    }
  }
}
```

Zed natively supports inlay hints, semantic highlighting, and all standard
LSP features.

---

## Emacs

### Using eglot (built-in since Emacs 29)

```elisp
(add-to-list 'eglot-server-programs
  '((canopy-mode elm-mode) . ("canopy-language-server" "--stdio")))

;; Start automatically when opening .can or .canopy files
(add-hook 'canopy-mode-hook 'eglot-ensure)
(add-hook 'elm-mode-hook 'eglot-ensure)
```

### Using lsp-mode

```elisp
(lsp-register-client
  (make-lsp-client
    :new-connection (lsp-stdio-connection '("canopy-language-server" "--stdio"))
    :major-modes '(canopy-mode elm-mode)
    :server-id 'canopy-ls))

(add-hook 'canopy-mode-hook #'lsp)
```

### Inlay hints with lsp-mode

```elisp
(setq lsp-inlay-hint-enable t)
```

---

## Sublime Text

Install the [LSP package](https://github.com/sublimelsp/LSP) and add to
`Preferences > Package Settings > LSP > Settings`:

```json
{
  "clients": {
    "canopy": {
      "enabled": true,
      "command": ["canopy-language-server", "--stdio"],
      "selector": "source.canopy, source.elm",
      "initializationOptions": {}
    }
  }
}
```

---

## Troubleshooting

### Server does not start

1. Verify the binary is on your path:
   ```bash
   which canopy-language-server
   ```
2. Check that you have a `canopy.json` or `elm.json` in your project root.
3. Run the server manually to see startup errors:
   ```bash
   canopy-language-server --stdio
   ```

### Missing features

- Ensure your editor supports the LSP protocol version the server uses (3.17).
- Some features (inlay hints, semantic tokens) require recent editor versions.
- Check your editor's LSP log for capability negotiation messages.

### Performance

The language server indexes your project on startup. For large projects:

- Use `source-directories` in `canopy.json` to limit the scope.
- Close unused workspaces if using a multi-root editor setup.
- Enable incremental diagnostics if your editor supports them.
