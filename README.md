# Canopy

A compiled, pure functional language for reliable web applications.
Canopy extends Elm with JavaScript FFI, code splitting, and a built-in test runner.

## Quick Start

### Install from source

```bash
git clone https://github.com/quinten/canopy.git
cd canopy
make build
cp $(stack path --local-install-root)/bin/canopy ~/.local/bin/canopy
```

### Create a project

```bash
canopy init my-app
cd my-app
canopy reactor
```

## What Makes Canopy Different

- **JavaScript FFI** -- Call JS functions with type-safe bindings via `foreign import javascript`
- **Code Splitting** -- Automatic chunk splitting via `lazy import` for faster initial loads
- **Built-in Test Runner** -- Unit, async, and browser tests with Playwright integration
- **Native Arithmetic** -- Compile-time constant folding for numeric operations
- **Elm Compatible** -- Reads existing Elm projects, falls back to Elm package registry

## Commands

| Command | Description |
|---------|-------------|
| `canopy init` | Create a new project |
| `canopy make` | Compile to JavaScript |
| `canopy test` | Run test suite |
| `canopy repl` | Interactive session |
| `canopy reactor` | Development server with hot reload |
| `canopy fmt` | Format source code |
| `canopy lint` | Static analysis |
| `canopy check` | Type-check without compiling |
| `canopy install` | Install a package |
| `canopy diff` | Show API changes between package versions |
| `canopy bump` | Bump package version based on API changes |
| `canopy publish` | Publish a package |

## Project Structure

```
canopy/
  packages/
    canopy-core/       -- Compiler: parsing, type checking, optimization, codegen
    canopy-query/      -- Query engine and parse caching
    canopy-driver/     -- Compilation orchestration
    canopy-builder/    -- Build system, dependency resolution, HTTP
    canopy-terminal/   -- CLI commands, test runner, REPL
  test/                -- Test suites (unit, property, integration, golden)
  core-packages/       -- Standard library packages (test, debug)
  example/             -- Example Canopy project
  docs/                -- Architecture and planning documents
```

## Building from Source

### Prerequisites

- [Stack](https://docs.haskellstack.org/) 2.x (manages GHC automatically via LTS-23.0)
- Node.js 18+ (for the test runner's browser integration)

### Build

```bash
make build
```

### Test

```bash
make test          # Run all tests
make test-unit     # Unit tests only
make test-property # Property tests only
make test-match PATTERN="Parser"  # Run matching tests
```

### Development

```bash
make lint          # hlint + ormolu check
make format        # Auto-format all Haskell files
make fix-lint      # Auto-apply hlint suggestions + format
```

## Documentation

- [CLAUDE.md](CLAUDE.md) -- Coding standards and development guidelines
- [CONTRIBUTING.md](CONTRIBUTING.md) -- How to contribute
- [docs/](docs/) -- Architecture documents and planning

## License

BSD-3-Clause. See [LICENSE](LICENSE) for details.
