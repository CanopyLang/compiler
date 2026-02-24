# Changelog

All notable changes to the Canopy Language extension will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-02-21

### Added

- **Language Server Protocol (LSP) integration**
  - Real-time diagnostics and error reporting
  - Hover information for types and documentation
  - Go to definition support
  - Find references support
  - Code completion
  - Code formatting

- **Build and task integration**
  - Canopy task provider for `canopy make`, `canopy check`
  - Problem matchers for compiler output
  - Build tasks accessible from Command Palette
  - Watch mode task for continuous compilation
  - REPL task

- **Commands**
  - `Canopy: Restart Language Server` - Restart the LSP server
  - `Canopy: Build Project` - Build the current project
  - `Canopy: Check Project` - Type-check without code generation
  - `Canopy: Show Language Server Output` - View LSP logs
  - `Canopy: Initialize New Project` - Create new canopy.json
  - `Canopy: Install Package` - Install a Canopy package

- **Code snippets**
  - Module and import declarations
  - Type definitions (custom types, type aliases)
  - Function definitions with type annotations
  - Control flow (if, case, let)
  - TEA architecture (Model, Msg, Update, View)
  - HTTP and JSON snippets
  - HTML element snippets
  - Testing scaffolds

- **Configuration options**
  - `canopy.serverPath` - Custom path to language server
  - `canopy.serverArgs` - Additional language server arguments
  - `canopy.trace.server` - LSP trace level
  - `canopy.compiler.path` - Custom path to compiler
  - `canopy.compiler.outputDirectory` - Build output directory
  - `canopy.compiler.optimize` - Enable optimizations by default
  - Feature toggles for diagnostics, formatting, and hover

- **Keyboard shortcuts**
  - `Ctrl+Shift+B` / `Cmd+Shift+B` - Build project
  - `Ctrl+Shift+C` / `Cmd+Shift+C` - Check project

- **Status bar integration**
  - Shows language server status
  - Click to view server output

### Changed

- Updated package.json with all new contributions
- Extension now activates on `workspaceContains:canopy.json`
- Improved file icon for .can files

## [0.1.0] - 2026-01-15

### Added

- Initial release
- Basic syntax highlighting for Canopy files
- Support for `.can` and `.canopy` file extensions
- Language configuration (comments, brackets, indentation)
- Highlighting for:
  - Keywords and control flow
  - Type definitions and constructors
  - Function definitions
  - String and character literals
  - Numbers (integers, floats, hex)
  - Comments (line, block, documentation)
  - Operators
  - FFI imports
