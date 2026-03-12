# CLI Reference

Complete reference for all Canopy CLI commands.

## Project Commands

### `canopy init`

Start a Canopy project in the current directory. Creates a starter `canopy.json` file.

```bash
canopy init
```

### `canopy new`

Create a complete new Canopy project in a fresh directory.

```bash
canopy new my-app
canopy new my-lib --template=package
canopy new my-app --no-git
```

| Flag | Default | Description |
|------|---------|-------------|
| `--template` | `app` | Project template: `app` or `package` |
| `--no-git` | off | Skip git repository initialization |

### `canopy setup`

Set up the Canopy package environment. Downloads the package registry and locates standard library packages.

```bash
canopy setup
canopy setup --verbose
```

| Flag | Default | Description |
|------|---------|-------------|
| `--verbose` | off | Show verbose output during setup |


## Build Commands

### `canopy make`

Compile Canopy code into JavaScript or HTML.

```bash
canopy make src/Main.can
canopy make src/Main.can --optimize --output=assets/canopy.js
canopy make --watch --debug
canopy make --output-format=iife --output=bundle.js src/Main.can
```

| Flag | Default | Description |
|------|---------|-------------|
| `--debug` | off | Enable time-travelling debugger |
| `--optimize` | off | Enable optimizations (smaller, faster output) |
| `--watch` | off | Watch for file changes and rebuild |
| `--output` | none | Override output file path |
| `--report` | none | Error format: `json` for machine-readable output |
| `--docs` | none | Generate a JSON documentation file at this path |
| `--verbose` | off | Verbose compiler logging |
| `--no-split` | off | Force single-file output (disable code splitting) |
| `--ffi-unsafe` | off | Disable runtime FFI type validation |
| `--ffi-debug` | off | Enable verbose FFI validation logging |
| `--jobs` | auto | Max parallel compilation workers (0 = auto, 1 = sequential) |
| `--verify-reproducible` | off | Build twice and verify byte-for-byte identical output |
| `--allow-kernel` | off | Allow packages using legacy kernel code |
| `--output-format` | `esm` | Output format: `esm` (ES modules) or `iife` (bundle) |

### `canopy check`

Type-check Canopy files without generating output.

```bash
canopy check src/Main.can
canopy check --report=json src/
```

| Flag | Default | Description |
|------|---------|-------------|
| `--report` | none | Error format: `json` |
| `--verbose` | off | Verbose compiler logging |

### `canopy reactor`

Start a local development server with a file browser. Clicking a `.can` file compiles and displays it.

```bash
canopy reactor
canopy reactor --port=3000
```

| Flag | Default | Description |
|------|---------|-------------|
| `--port` | `8000` | Server port |


## Developer Tools

### `canopy repl`

Open an interactive Canopy programming session.

```bash
canopy repl
canopy repl --interpreter=nodejs --no-colors
```

| Flag | Default | Description |
|------|---------|-------------|
| `--interpreter` | system `node` | Path to a JavaScript interpreter |
| `--no-colors` | off | Disable ANSI color output |

### `canopy fmt`

Format Canopy source files.

```bash
canopy fmt src/Main.can
canopy fmt --check src/
canopy fmt --stdin < MyFile.can
canopy fmt --indent=2 --line-width=100 src/
```

| Flag | Default | Description |
|------|---------|-------------|
| `--check` | off | Report files needing formatting without writing |
| `--stdin` | off | Read from stdin, write to stdout |
| `--indent` | `4` | Spaces per indentation level |
| `--line-width` | `80` | Target maximum line width |

### `canopy lint`

Run static analysis on Canopy source files.

```bash
canopy lint src/Main.can
canopy lint --fix src/
canopy lint --report=json src/
```

| Flag | Default | Description |
|------|---------|-------------|
| `--fix` | off | Apply auto-fixes for fixable warnings |
| `--report` | none | Output format: `json` |

### `canopy test`

Run Canopy test files. Browser tests are auto-detected and run via Playwright.

```bash
canopy test tests/MyTest.can
canopy test --filter "MyModule"
canopy test --watch
canopy test --headed --app src/Main.can test/BrowserTests.can
canopy test --coverage --coverage-format=lcov --min-coverage=80
```

| Flag | Default | Description |
|------|---------|-------------|
| `--filter` | none | Only run tests matching this pattern |
| `--watch` | off | Watch for changes and re-run |
| `--verbose` | off | Verbose output |
| `--headed` | off | Show browser window for browser tests |
| `--app` | none | Application entry point for browser tests |
| `--slowmo` | none | Slow down Playwright actions by N milliseconds |
| `--coverage` | off | Instrument code and show coverage report |
| `--coverage-format` | none | Coverage format: `istanbul` or `lcov` |
| `--coverage-output` | none | Write coverage report to this file |
| `--min-coverage` | none | Minimum required coverage percentage (0-100) |

### `canopy docs`

Generate documentation for your project.

```bash
canopy docs
canopy docs --format=markdown --output=docs.md
```

| Flag | Default | Description |
|------|---------|-------------|
| `--format` | `json` | Output format: `json` or `markdown` |
| `--output` | stdout | Write documentation to a file |

### `canopy audit`

Analyze project dependencies for issues and capability usage.

```bash
canopy audit
canopy audit --json --level=warning
canopy audit --capabilities --verbose
```

| Flag | Default | Description |
|------|---------|-------------|
| `--json` | off | Output as JSON |
| `--level` | none | Minimum severity: `info`, `warning`, or `critical` |
| `--verbose` | off | Verbose details |
| `--capabilities` | off | Show capability usage per dependency |

### `canopy bench`

Measure compilation performance.

```bash
canopy bench
canopy bench --iterations=5 --json
```

| Flag | Default | Description |
|------|---------|-------------|
| `--iterations` | `3` | Number of iterations |
| `--json` | off | Output as JSON |
| `--verbose` | off | Verbose output |

### `canopy upgrade`

Migrate Elm projects to Canopy.

```bash
canopy upgrade
canopy upgrade --dry-run
```

| Flag | Default | Description |
|------|---------|-------------|
| `--dry-run` | off | Preview changes without applying |
| `--verbose` | off | Verbose output |


## Package Management

### `canopy install`

Install packages from the registry. With no argument, resolves dependencies from `canopy.json`.

```bash
canopy install
canopy install canopy/http
canopy install canopy/json --offline
```

| Flag | Default | Description |
|------|---------|-------------|
| `--no-fallback` | off | Don't fall back to elm-lang.org registry |
| `--offline` | off | Use only locally cached packages |
| `--no-verify` | off | Skip lock file verification |

### `canopy publish`

Publish your package to a repository.

```bash
canopy publish
canopy publish https://example.com/my-repo
```

### `canopy bump`

Determine the next version number based on API changes.

```bash
canopy bump
```

### `canopy diff`

Detect API changes between package versions.

```bash
canopy diff                        # local vs latest published
canopy diff 1.0.0                  # local vs specific version
canopy diff 1.0.0 2.0.0            # two local versions
canopy diff canopy/html 1.0.0 2.0.0  # any package, two versions
```

### `canopy vendor`

Copy all resolved dependencies into a local `vendor/` directory.

```bash
canopy vendor
canopy vendor --clean
```

| Flag | Default | Description |
|------|---------|-------------|
| `--clean` | off | Remove existing `vendor/` first |


## Link Commands

### `canopy link`

Register a local package in the global cache via symlink.

```bash
canopy link
canopy link ./packages/canopy/json
```

### `canopy unlink`

Remove a package symlink from the global cache.

```bash
canopy unlink
```


## Tool Commands

### `canopy test-ffi`

Test and validate FFI functions in your project.

```bash
canopy test-ffi
canopy test-ffi --validate-only
canopy test-ffi --generate --output=test-generation/
canopy test-ffi --browser --property-runs=500
```

| Flag | Default | Description |
|------|---------|-------------|
| `--generate` | off | Generate test files instead of running them |
| `--output` | `test-generation/` | Output directory for generated tests |
| `--watch` | off | Watch and re-run on changes |
| `--validate-only` | off | Only validate contracts |
| `--verbose` | off | Detailed progress |
| `--property-runs` | `100` | Number of property test iterations |
| `--browser` | off | Run tests in browser instead of Node.js |

### `canopy webidl`

Generate Canopy FFI bindings from WebIDL specification files.

```bash
canopy webidl specs/dom.webidl
canopy webidl --output=src/Web/ specs/dom.webidl specs/fetch.webidl
```

| Flag | Default | Description |
|------|---------|-------------|
| `--output` | current dir | Directory for generated modules |
| `--verbose` | off | Verbose output |

### `canopy self-update`

Check for and install Canopy compiler updates.

```bash
canopy self-update
canopy self-update --check
```

| Flag | Default | Description |
|------|---------|-------------|
| `--check` | off | Only check, don't install |
| `--force` | off | Force update even if current |


## Kit Framework

### `canopy kit-new`

Scaffold a new Kit application with file-system routing, layouts, and Vite.

```bash
canopy kit-new my-app
```

Creates a project with `src/routes/`, layout files, `canopy.json`, and Vite configuration.

### `canopy kit-dev`

Start the Kit development server with hot reloading and route watching.

```bash
canopy kit-dev
canopy kit-dev --port=4000 --open
```

| Flag | Default | Description |
|------|---------|-------------|
| `--port` | `5173` | Development server port |
| `--open` | off | Open browser automatically |

### `canopy kit-build`

Build a Kit application for production deployment.

```bash
canopy kit-build
canopy kit-build --optimize
canopy kit-build --optimize --output=dist/
```

| Flag | Default | Description |
|------|---------|-------------|
| `--optimize` | off | Enable Canopy optimizations |
| `--output` | `build/` | Output directory |

### `canopy kit-preview`

Preview a Kit production build locally.

```bash
canopy kit-preview
canopy kit-preview --port=4000 --open
```

| Flag | Default | Description |
|------|---------|-------------|
| `--port` | `4000` | Preview server port |
| `--open` | off | Open browser automatically |

Serves the `build/` directory for static targets, or starts the generated `server.js` for Node targets.
