# Contributing to Canopy

Thank you for considering a contribution to the Canopy compiler. This guide
covers everything you need to get started, from setting up your development
environment to opening a pull request.

For a high-level overview of the compiler architecture, see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| [GHC](https://www.haskell.org/ghc/) | 9.8.4 | Installed automatically by Stack |
| [Stack](https://docs.haskellstack.org/) | >= 2.13 | Haskell build tool |
| [Node.js](https://nodejs.org/) | >= 18 | Used by integration tests |
| [hlint](https://github.com/ndmitchell/hlint) | >= 3.5 | Haskell linter |
| [ormolu](https://github.com/tweag/ormolu) | >= 0.7 | Haskell formatter |

### Quick Setup

Run the setup script to install all dependencies, build, and verify tests:

```bash
./scripts/setup-dev.sh
```

Or do it manually:

```bash
stack setup            # Install the correct GHC version
make build             # Build all packages
make test              # Run full test suite (should pass)
```

## Getting Started

1. Fork and clone the repository
2. Run `./scripts/setup-dev.sh` (or `stack setup && make build && make test`)
3. Create a feature branch: `git checkout -b feature/your-feature`
4. Make your changes
5. Open a pull request

## Development Workflow

```
1. Branch     git checkout -b feature/your-feature
2. Code       Follow CLAUDE.md standards (see below)
3. Lint       make lint
4. Format     make format
5. Test       make test
6. Commit     feat(parser): add record wildcards
7. Push       git push origin feature/your-feature
8. PR         Open a pull request on GitHub
```

## Code Standards

All code must follow [CLAUDE.md](CLAUDE.md). The most important rules:

- **Function size**: <= 15 lines, <= 4 parameters, <= 4 branches
- **Imports**: All qualified (types unqualified, functions qualified)
- **Records**: Lenses for access/updates; record syntax for construction
- **Documentation**: Haddock on all exported types and functions
- **Safety**: No partial functions (`head`, `tail`, `fromJust`, `!!`, `error`)
- **Style**: `where` over `let`; parentheses over `$`; no nested `case`
- **Warnings**: Zero warnings required (GHC `-Wall`)

## Package Structure

The compiler is split into five packages with a strict dependency DAG:

```
canopy-terminal  (106 modules)  CLI commands, REPL, dev server
       |
canopy-builder   ( 24 modules)  Build system, deps, HTTP, caching
       |
canopy-driver    (  9 modules)  Compilation orchestration, worker pool
       |
canopy-query     (  3 modules)  Query engine, parse caching
       |
canopy-core      (196 modules)  Parser, type checker, optimizer, codegen
```

| Package | Key Modules |
|---------|-------------|
| `canopy-core` | `Parse.*`, `Canonicalize.*`, `Type.*`, `Optimize.*`, `Generate.*`, `AST.*` |
| `canopy-query` | `Query.Engine`, `Query.Simple` |
| `canopy-driver` | `Driver`, `Worker.Pool`, `Queries.*` |
| `canopy-builder` | `Build.*`, `Compiler`, `Http.*`, `PackageCache.*` |
| `canopy-terminal` | `Make`, `Install`, `Develop`, `Repl`, `CLI.*` |

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full compilation
pipeline and data flow.

## Testing

### Running Tests

```bash
make test                          # All tests (~2700 tests)
make test-unit                     # Unit tests only
make test-property                 # Property tests only
make test-integration              # Integration tests only
make test-match PATTERN="Parser"   # Run matching tests
make test-coverage                 # Run with coverage report
make test-watch                    # Continuous testing (file-watch)
```

### Test Organization

Tests live in `test/` with four categories:

| Directory | Framework | Purpose |
|-----------|-----------|---------|
| `test/Unit/` | tasty-hunit | Per-function behavior verification |
| `test/Property/` | tasty-quickcheck | Invariant and law checking |
| `test/Integration/` | tasty-hunit | End-to-end pipeline tests |
| `test/Golden/` | tasty-golden | Output regression tests |

### Writing Tests

- Tests must verify actual behavior, not implementation details
- No mock functions (`isValid _ = True` is forbidden)
- No reflexive equality tests (`x @?= x` tests nothing)
- Use exact value assertions (`@?=`), not weak contains checks
- See the testing section in [CLAUDE.md](CLAUDE.md) for a full list of
  anti-patterns

### Adding a New Test Module

1. Create the test file in the appropriate `test/` subdirectory
2. Export a `tests :: TestTree` value
3. Add a qualified import in `test/Main.hs`
4. Add the `tests` value to the relevant test group
5. Run `stack exec -- hpack` to regenerate the cabal file

## Profiling and Benchmarks

```bash
make bench                # Full benchmark suite (HTML report)
make bench-quick          # Quick benchmarks (1s time limit)
make bench-csv            # Benchmarks with CSV output
make profile-build        # Build with profiling enabled
make profile-run          # Time/allocation profiling
make profile-heap         # Heap profiling
```

## Commit Messages

Follow [conventional commits](https://www.conventionalcommits.org/):

```
feat(parser): add support for record wildcards
fix(typecheck): handle recursive type aliases correctly
perf(optimizer): improve dead code elimination by 15%
docs(api): add examples for Parser module
refactor(ast): split Expression into separate modules
test(integration): add tests for .canopy file support
build(deps): update to lts-23.0
```

The scope in parentheses should match a package or module area:
`parser`, `typecheck`, `optimizer`, `codegen`, `builder`, `cli`, `ast`,
`driver`, `query`, `deps`, `api`.

## Pull Request Checklist

- [ ] All tests pass (`make test`)
- [ ] Code follows [CLAUDE.md](CLAUDE.md) standards
- [ ] Linting passes (`make lint`)
- [ ] Formatting passes (`make format`)
- [ ] Zero compiler warnings
- [ ] Haddock documentation added for new exports
- [ ] Tests added for new functionality
- [ ] Commit messages follow conventional format

## Common Tasks

### Adding a new CLI command

1. Create a module in `packages/canopy-terminal/src/` (e.g., `MyCommand.hs`)
2. Register it in `packages/canopy-terminal/src/CLI/Commands.hs`
3. Add integration tests in `test/Integration/`

### Adding a new optimization pass

1. Create a module in `packages/canopy-core/src/Optimize/`
2. Wire it into `Optimize.Module` or `Optimize.Expression`
3. Add unit tests in `test/Unit/Optimize/`
4. Update golden tests if codegen output changes

### Modifying the parser

1. Edit modules under `packages/canopy-core/src/Parse/`
2. Update `AST.Source` if adding new AST nodes
3. Update `Canonicalize.*` to handle the new syntax
4. Add parser tests in `test/Unit/Parse/`
5. Add golden tests in `test/Golden/`

## Need Help?

Open an issue for questions about the codebase or contribution process.
