# Canopy Language Extension for Visual Studio Code (VSCode)

<img src="images/canopy.png" alt="Canopy Logo" width="100" height="100">

The official Canopy language extension for Visual Studio Code, providing comprehensive language support for both `.can` (Canopy) and `.elm` (Elm) files.

Supports Canopy with elm 0.19+ compatibility

## What is Canopy?

Canopy is a modern language that builds upon Elm's solid foundation, offering enhanced features while maintaining compatibility with the Elm ecosystem. This extension allows you to work seamlessly with both Canopy (`.can`) and Elm (`.elm`) files.

## Install

1. Install VSCode or Cursor from [VSCode](https://code.visualstudio.com/) or [Cursor](https://cursor.sh/)
2. Install this extension from the VSIX file: `canopy-ls-vscode-0.0.1.vsix`
3. Make sure you have [nodejs](https://nodejs.org/) and npm installed
4. Make sure you have [Canopy](https://github.com/CanopyLang) installed globally
5. Install Elm tooling: `npm install -g elm elm-test elm-format`
6. (Optional) Install `elm-review` via `npm install -g elm-review` and enable it in settings

## Highlighted Features

- **Dual file support**: Work with both `.can` (Canopy) and `.elm` (Elm) files
- **Language Server**: Full LSP support via `canopy-language-server`
- **Project files**: Support for both `canopy.json` and `elm.json` configuration
- **Syntax highlighting**: Beautiful syntax highlighting for Canopy syntax
- **Error checking**: Real-time errors and diagnostics when changing code and saving
- **Format on save**: Auto-formatting with elm-format (Control + S)
- **Completions**: Intelligent suggestions and snippets (Control + Space)
- **Test integration**: Test explorer support with elm-test

## Additional Features

- **Go to definition**: Jump to type aliases, modules, custom types, and functions
- **Find references**: Lists all references (Alt + Shift + F12)
- **Hover information**: Type annotations and documentation on hover
- **Rename**: Rename symbols across your codebase (F2)
- **Symbol navigation**: Browse files and workspace by symbols
- **CodeLenses**: Shows function usage and exposure information
- **Code folding**: Collapse code sections
- **Type inference**: Advanced type checking and inference

## Extension Settings

This extension contributes the following settings:

- `canopyLS.trace.server`: Enable/disable trace logging of client and server communication
- `canopyLS.canopyPath`: The path to your canopy executable
- `canopyLS.elmReviewPath`: The path to your elm-review executable
- `canopyLS.elmReviewDiagnostics`: Configure linting diagnostics from elm-review (`off`, `warning`, `error`)
- `canopyLS.elmFormatPath`: The path to your elm-format executable
- `canopyLS.elmTestPath`: The path to your elm-test executable
- `canopyLS.disableCanopyLSDiagnostics`: Disable linting diagnostics from the language server
- `canopyLS.skipInstallPackageConfirmation`: Skip confirmation for the Install Package code action
- `canopyLS.onlyUpdateDiagnosticsOnSave`: Only update compiler diagnostics on save, not on document change
- `canopyLS.canopyTestRunner.showCanopyTestOutput`: Show output of tests as terminal task

## Configuration

### Project Setup

Create either:
- `canopy.json` - Canopy project configuration (recommended)
- `elm.json` - Standard Elm project configuration (for compatibility)

The extension automatically detects and works with both project types.

### File Extensions

- `.can` - Canopy source files (new!)
- `.elm` - Elm source files (compatible)

## FAQ

**Q: What's the difference between Canopy and Elm files?**
A: Canopy (`.can`) files support enhanced language features while maintaining Elm compatibility. Elm (`.elm`) files work exactly as before.

**Q: Can I mix `.can` and `.elm` files in the same project?**
A: Yes! The extension handles both file types seamlessly in the same workspace.

**Q: Syntax highlighting not working?**
A: Make sure your VSCode theme supports the tokens used by the extension.

**Q: How to get logs?**
A: `F1` → `Output: Focus on Output View` → Select `Canopy (your project name)` from dropdown.

**Q: Features don't work?**
A: Ensure you have a valid `canopy.json` or `elm.json` file. Initialize with `elm init` if needed.

**Q: What's the relation to elm-language-server?**
A: This extension uses `canopy-language-server`, which extends elm-language-server with Canopy-specific features.

**Q: Why install Elm tools for Canopy?**
A: Canopy leverages the mature Elm ecosystem - `elm-format` for formatting, `elm-test` for testing, `elm-review` for linting. The `canopy` compiler handles compilation.

**Q: Don't like CodeLenses?**
A: Disable in settings: "Editor: Code Lens" → unchecked.

**Q: GLSL support?**
A: Install [vscode-glsllint](https://github.com/hsimpson/vscode-glsllint) for GLSL syntax support.

## Architecture

- **Compiler**: Uses `canopy` binary for compilation
- **Language Server**: `canopy-language-server` for LSP features
- **Formatting**: `elm-format` for code formatting
- **Testing**: `elm-test` for running tests
- **Linting**: `elm-review` for code analysis
- **Packages**: Compatible with Elm package ecosystem

## Contributing / Development

```shell
git clone git@github.com:CanopyLang/canopy-vscode.git
cd canopy-vscode
npm install
npm run compile
```

Open VSCode with this project (`code .`) and press `F5` to start debugging.

## License

MIT - See LICENSE file for details.

---

**Happy Canopy coding! 🌳**