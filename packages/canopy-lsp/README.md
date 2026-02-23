# canopy-language-server

<img src="images/canopy.png" alt="Canopy Logo" width="100" height="100">

[![Build Status](https://github.com/CanopyLang/canopy-language-server/workflows/Lint%20and%20test/badge.svg)](https://github.com/CanopyLang/canopy-language-server/actions)

**Canopy Language Server** provides comprehensive language support for the Canopy programming language - a modern functional language that builds upon Elm's foundation with enhanced tooling and compilation features.

## What is Canopy?

Canopy is a delightful functional programming language that maintains compatibility with the Elm ecosystem while adding enhanced language features. This language server supports both:

- **`.can` files** - Native Canopy source files with enhanced language features
- **`.elm` files** - Standard Elm files for full backward compatibility

The server extends the proven `elm-language-server` foundation with Canopy-specific enhancements while maintaining all the robust features you expect from a modern language server.

## Features

- **Dual File Support**: Work seamlessly with both `.can` and `.elm` files
- **Project Configuration**: Support for both `canopy.json` and `elm.json` project files
- **Diagnostics**: Real-time error checking and compiler diagnostics
- **Completions**: Intelligent code completions and suggestions
- **Go to Definition**: Navigate to type definitions, functions, and modules
- **Find References**: Locate all references to symbols across your codebase
- **Hover Information**: Type signatures and documentation on hover
- **Rename Symbol**: Rename symbols across your entire project
- **Workspace Symbols**: Search and navigate by symbols
- **Code Actions**: Quick fixes and refactoring suggestions
- **Formatting**: Code formatting via `elm-format`
- **Linting**: Code analysis via `elm-review`

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**

- [Installation](#installation)
  - [Alternative: Compile and install from source](#alternative-compile-and-install-from-source)
  - [Alternative: Install with Nix](#alternative-install-with-nix)
- [Requirements](#requirements)
- [Configuration](#configuration)
  - [Linting](#linting)
- [Server Settings](#server-settings)
- [Editor Support](#editor-support)
  - [VSCode](#vscode)
  - [Vim](#vim)
    - [coc.nvim](#cocnvim)
    - [ALE](#ale)
    - [LanguageClient](#languageclient)
  - [Kakoune](#kakoune)
    - [kak-lsp](#kak-lsp)
  - [Emacs](#emacs)
    - [lsp-mode](#lsp-mode)
  - [Sublime](#sublime)
  - [Atom (DEPRECATED)](#atom-deprecated)
- [Awesome libraries this project uses](#awesome-libraries-this-project-uses)
- [Contributing](#contributing)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Installation

### npm

```sh
npm install -g @canopy-lang/canopy-language-server
```

### Alternative: Compile and install from source

First, clone this repo and compile it. `npm link` will add `canopy-language-server` to the PATH.

```sh
git clone https://github.com/CanopyLang/canopy-language-server.git
cd canopy-language-server
npm install
npm run compile
npm link
```

### Alternative: Install with Nix

You can install the language server with Nix by running `nix-env -iA nixpkgs.canopy-language-server`.

## Requirements

You will need to install `canopy` and `elm-test` to get all diagnostics and `elm-format` for formatting.
You can also use `elm-review` for linting.

```sh
# Install Canopy compiler
npm install -g canopy

# Install Elm ecosystem tools
npm install -g elm-test elm-format elm-review
```

The language server will try to use local versions first (`node_modules`), then global versions.

## Configuration

The server can be configured using a JSON file placed in your project root called `canopy-language-server.json` or `.canopy-language-server.json`.

Here are the configuration options:

```json
{
  "canopyPath": "canopy",
  "canopyFormatPath": "elm-format",
  "canopyTestPath": "elm-test",
  "canopyReviewPath": "elm-review",
  "trace": "off"
}
```

### Linting

You can enable linting by installing `elm-review`:

```sh
npm install elm-review --save-dev
```

And running `elm-review init` in your project. The language server will automatically detect and use elm-review if it's available.

## Server Settings

These settings are sent from the client to configure the server:

- `canopyPath`: Path to the `canopy` binary (default: finds automatically)
- `canopyFormatPath`: Path to `elm-format` (default: finds automatically)
- `canopyTestPath`: Path to `elm-test` (default: finds automatically)
- `canopyReviewPath`: Path to `elm-review` (default: finds automatically)
- `trace`: Tracing level ("off" | "messages" | "verbose")
- `disableCanopyLSDiagnostics`: Disable built-in diagnostics
- `skipInstallPackageConfirmation`: Skip package install confirmations
- `onlyUpdateDiagnosticsOnSave`: Only update diagnostics on save

## Editor Support

Most editors with LSP support can use this language server. Here are specific setup instructions:

### VSCode

Use the official [Canopy VSCode Extension](https://github.com/CanopyLang/canopy-vscode) which includes this language server.

### Vim

#### coc.nvim

To use this language server with [coc.nvim](https://github.com/neoclide/coc.nvim), add this to your `coc-settings.json`:

```json
{
  "languageserver": {
    "canopy": {
      "command": "canopy-language-server",
      "args": ["--stdio"],
      "filetypes": ["canopy", "elm"],
      "rootPatterns": ["canopy.json", "elm.json"],
      "initializationOptions": {
        "canopyPath": "canopy",
        "canopyFormatPath": "elm-format",
        "canopyTestPath": "elm-test"
      }
    }
  }
}
```

#### ALE

To use this language server with [ALE](https://github.com/dense-analysis/ale):

```vim
let g:ale_linters = { 'canopy': ['canopy_language_server'], 'elm': ['canopy_language_server'] }
```

#### LanguageClient

To use this language server with [LanguageClient](https://github.com/autozimu/LanguageClient-neovim):

```vim
let g:LanguageClient_serverCommands = {
    \ 'canopy': ['canopy-language-server', '--stdio'],
    \ 'elm': ['canopy-language-server', '--stdio'],
    \ }
```

### Kakoune

#### kak-lsp

To use this language server with [kak-lsp](https://github.com/kak-lsp/kak-lsp), add this to your `kak-lsp.toml`:

```toml
[language.canopy]
filetypes = ["canopy", "elm"]
roots = ["canopy.json", "elm.json"]
command = "canopy-language-server"
args = ["--stdio"]

[language.canopy.initialization_options]
canopyPath = "canopy"
canopyFormatPath = "elm-format"
canopyTestPath = "elm-test"
```

### Emacs

#### lsp-mode

To use this language server with [lsp-mode](https://github.com/emacs-lsp/lsp-mode):

```elisp
(require 'lsp-mode)

(add-to-list 'lsp-language-id-configuration '(canopy-mode . "canopy"))
(add-to-list 'lsp-language-id-configuration '(elm-mode . "canopy"))

(lsp-register-client
 (make-lsp-client :new-connection (lsp-stdio-connection "canopy-language-server")
                  :major-modes '(canopy-mode elm-mode)
                  :initialization-options (lambda () '(:canopyPath "canopy" :canopyFormatPath "elm-format"))
                  :server-id 'canopy-language-server))
```

### Sublime

Install [LSP for Sublime](https://github.com/sublimelsp/LSP) and add this to your settings:

```json
{
  "clients": {
    "canopy-language-server": {
      "enabled": true,
      "command": ["canopy-language-server", "--stdio"],
      "selector": "source.canopy | source.elm",
      "initializationOptions": {
        "canopyPath": "canopy",
        "canopyFormatPath": "elm-format"
      }
    }
  }
}
```

## Architecture

The Canopy Language Server is built on these key components:

- **Compiler Integration**: Uses the `canopy` binary for compilation and type checking
- **Elm Toolchain**: Leverages `elm-format`, `elm-test`, and `elm-review` for formatting, testing, and linting
- **Tree-sitter**: Uses `tree-sitter-canopy` for fast, accurate parsing
- **LSP Protocol**: Full Language Server Protocol compliance for editor integration
- **Dual File Support**: Seamless handling of both `.can` and `.elm` files

## Awesome libraries this project uses

- [Tree-sitter](https://tree-sitter.github.io/) and [tree-sitter-canopy](https://github.com/CanopyLang/tree-sitter-canopy) for parsing
- [vscode-languageserver-node](https://github.com/Microsoft/vscode-languageserver-node) for LSP protocol

## Contributing

Please do :) We need all the help we can get to make this language server awesome!

- [Language Server Protocol Specification](https://microsoft.github.io/language-server-protocol/specification)
- [Tree-sitter Documentation](https://tree-sitter.github.io/)

### Development Setup

```sh
git clone https://github.com/CanopyLang/canopy-language-server.git
cd canopy-language-server
npm install
npm run compile
npm run test
```

### Testing

```sh
npm test
```

## License

MIT