# Canopy Language Support for VS Code

Full-featured language support for the Canopy programming language, including syntax highlighting, LSP integration, snippets, and build tools.

## Features

### Language Server Protocol (LSP) Integration

When `canopy-language-server` is installed, the extension provides:

- **Real-time Diagnostics**: See errors and warnings as you type
- **Hover Information**: View type information and documentation on hover
- **Go to Definition**: Jump to function and type definitions
- **Find References**: Find all usages of a symbol
- **Code Completion**: Intelligent autocompletion for functions, types, and modules
- **Rename Symbol**: Safely rename across your codebase
- **Code Formatting**: Format your code with `canopy format`

### Syntax Highlighting

Comprehensive syntax highlighting for all Canopy constructs:

- Module declarations and imports
- Foreign Function Interface (FFI) imports
- Type definitions and aliases
- Function definitions and type annotations
- Pattern matching (case expressions)
- String literals, characters, and numbers
- Comments and documentation comments
- All operators and keywords

### Code Snippets

Over 50 snippets for common patterns:

- Module and import declarations
- Type definitions and aliases
- Functions and lambdas
- Control flow (if/case/let)
- TEA architecture (Model, Msg, Update, View)
- HTTP requests and JSON encoding/decoding
- HTML elements
- Test scaffolding

Type the snippet prefix and press Tab to expand.

### Build Integration

Integrated tasks for building and checking your project:

- **Canopy: Build Project** (`Ctrl+Shift+B` / `Cmd+Shift+B`)
- **Canopy: Check Project** (`Ctrl+Shift+C` / `Cmd+Shift+C`)
- **Canopy: Build (Optimized)** - Production build with optimizations
- **Canopy: Watch** - Continuous compilation on file changes
- **Canopy: REPL** - Interactive REPL session

### Commands

Access via the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`):

- `Canopy: Build Project` - Compile the project
- `Canopy: Check Project` - Type-check without generating output
- `Canopy: Restart Language Server` - Restart the LSP server
- `Canopy: Show Language Server Output` - View LSP logs
- `Canopy: Initialize New Project` - Create a new Canopy project
- `Canopy: Install Package` - Install a Canopy package

## Installation

### From VS Code Marketplace

1. Open VS Code
2. Go to Extensions (`Ctrl+Shift+X` / `Cmd+Shift+X`)
3. Search for "Canopy Language"
4. Click Install

### From VSIX File

1. Download the `.vsix` file from the [releases page](https://github.com/canopy-lang/canopy/releases)
2. In VS Code, open the Command Palette
3. Run "Extensions: Install from VSIX..."
4. Select the downloaded file

### From Source (Development)

```bash
# Clone the repository
git clone https://github.com/canopy-lang/canopy.git
cd canopy/editors/vscode-canopy

# Install dependencies
npm install

# Compile TypeScript
npm run compile

# Open in VS Code
code .

# Press F5 to launch Extension Development Host
```

## Language Server Setup

For full LSP features, you need `canopy-language-server` installed.

### Option 1: Install from npm (Recommended)

```bash
npm install -g @canopy-lang/canopy-language-server
```

### Option 2: Build from Source

```bash
cd canopy/packages/canopy-lsp
npm install
npm run build
npm link
```

### Option 3: Configure Custom Path

If the language server is installed in a non-standard location:

1. Open VS Code Settings (`Ctrl+,` / `Cmd+,`)
2. Search for "canopy.serverPath"
3. Enter the full path to the `canopy-language-server` executable

## Configuration

Configure the extension via VS Code Settings:

### Language Server

| Setting | Default | Description |
|---------|---------|-------------|
| `canopy.serverPath` | `""` | Path to canopy-language-server executable |
| `canopy.serverArgs` | `[]` | Additional arguments for the language server |
| `canopy.trace.server` | `"off"` | Trace level for LSP communication (`off`, `messages`, `verbose`) |

### Compiler

| Setting | Default | Description |
|---------|---------|-------------|
| `canopy.compiler.path` | `""` | Path to the canopy compiler |
| `canopy.compiler.outputDirectory` | `"build"` | Output directory for compiled files |
| `canopy.compiler.optimize` | `false` | Enable optimizations by default |

### Features

| Setting | Default | Description |
|---------|---------|-------------|
| `canopy.diagnostics.enable` | `true` | Enable real-time diagnostics |
| `canopy.format.enable` | `true` | Enable code formatting |
| `canopy.hover.enable` | `true` | Enable hover information |

## Snippet Reference

### Module Structure

| Prefix | Description |
|--------|-------------|
| `module` | Module declaration |
| `module-port` | Port module declaration |
| `import` | Import statement |
| `import-exposing` | Import with exposing |
| `import-as` | Import with alias |
| `foreign-import` | FFI JavaScript import |

### Types

| Prefix | Description |
|--------|-------------|
| `type` | Custom type (union type) |
| `type-param` | Custom type with type parameter |
| `type-alias` | Type alias (record) |
| `type-alias-simple` | Simple type alias |

### Functions

| Prefix | Description |
|--------|-------------|
| `fn` | Function with type annotation |
| `fn2` | Function with 2 parameters |
| `fn3` | Function with 3 parameters |
| `lambda` | Anonymous function |
| `lambda2` | Anonymous function (2 params) |

### Control Flow

| Prefix | Description |
|--------|-------------|
| `if` | If-then-else expression |
| `if-inline` | Inline if expression |
| `case` | Case expression |
| `case-maybe` | Case on Maybe |
| `case-result` | Case on Result |
| `case-list` | Case on List |
| `let` | Let expression |
| `let-multi` | Let with multiple bindings |

### TEA (The Elm Architecture)

| Prefix | Description |
|--------|-------------|
| `main` | Browser.sandbox main |
| `main-element` | Browser.element main |
| `main-document` | Browser.document main |
| `main-application` | Browser.application main |
| `model` | Model type alias |
| `msg` | Msg type |
| `init` | Init function |
| `init-cmd` | Init with Cmd |
| `update` | Update function (sandbox) |
| `update-cmd` | Update with Cmd |
| `view` | View function |
| `view-document` | Document view |
| `subscriptions` | Subscriptions function |

### HTML Elements

| Prefix | Description |
|--------|-------------|
| `div` | Div element |
| `button` | Button with onClick |
| `input` | Input element |
| `a` | Anchor element |
| `ul` | Unordered list |

### Testing

| Prefix | Description |
|--------|-------------|
| `test-module` | Test module scaffold |
| `test` | Single test case |
| `describe` | Test describe block |

## File Extensions

The extension recognizes the following file extensions:

- `.can` - Canopy source files
- `.canopy` - Canopy source files (alternative)

## Troubleshooting

### Language Server Not Starting

1. Check the Output panel (`View > Output`) and select "Canopy" from the dropdown
2. Verify `canopy-language-server` is installed: `which canopy-language-server`
3. Check the configured path in settings
4. Try restarting the language server: `Canopy: Restart Language Server`

### No Syntax Highlighting

1. Ensure the file has a `.can` or `.canopy` extension
2. Check that the language mode is set to "Canopy" (bottom-right of VS Code)
3. Try reloading VS Code: `Developer: Reload Window`

### Build Tasks Not Working

1. Ensure you have a `canopy.json` file in your workspace root
2. Verify the `canopy` compiler is installed and in PATH
3. Check the terminal output for error messages

## Contributing

Contributions are welcome! Please submit issues and pull requests to the [Canopy repository](https://github.com/canopy-lang/canopy).

### Development Setup

```bash
# Install dependencies
npm install

# Watch for changes
npm run watch

# In a new terminal, press F5 to launch Extension Development Host
```

### Building the Extension

```bash
# Compile TypeScript
npm run compile

# Run linter
npm run lint

# Package as VSIX
npm run package
```

## License

BSD-3-Clause - see the main Canopy project for details.

## Acknowledgments

- The Elm language team for inspiration
- VS Code extension ecosystem contributors
- The Canopy community
