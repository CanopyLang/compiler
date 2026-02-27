# Contributing to Canopy

## Getting Started

1. Fork and clone the repository
2. Install [Stack](https://docs.haskellstack.org/)
3. Build: `make build`
4. Test: `make test` (all tests should pass)

## Development Workflow

1. Create a feature branch: `git checkout -b feature/your-feature`
2. Make changes following [CLAUDE.md](CLAUDE.md) standards
3. Run `make lint` and `make format`
4. Run `make test` -- all tests must pass
5. Commit with conventional format: `feat(parser): add record wildcards`
6. Open a pull request

## Code Standards

All code must follow [CLAUDE.md](CLAUDE.md). Key requirements:

- Functions <= 15 lines
- <= 4 parameters per function
- Qualified imports (types unqualified, functions qualified)
- Lenses for record access/updates
- Haddock documentation on all exports
- No partial functions (`head`, `tail`, `fromJust`, `!!`, `error`)
- `where` preferred over `let`
- Parentheses preferred over `$`

## Package Structure

| Package | Purpose |
|---------|---------|
| `canopy-core` | Compiler: parsing, type checking, optimization, codegen |
| `canopy-query` | Query engine and parse caching |
| `canopy-driver` | Compilation orchestration |
| `canopy-builder` | Build system, dependency resolution, HTTP |
| `canopy-terminal` | CLI commands, test runner, REPL |

## Testing

```bash
make test                          # Run all tests
make test-unit                     # Unit tests only
make test-property                 # Property tests only
make test-integration              # Integration tests only
make test-match PATTERN="Parser"   # Run matching tests
make test-coverage                 # Run with coverage report
make test-watch                    # Continuous testing
```

Tests must verify actual behavior, not implementation details.
See the testing section in [CLAUDE.md](CLAUDE.md) for anti-patterns to avoid.

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

## Pull Request Checklist

- [ ] All tests pass (`make test`)
- [ ] Code follows [CLAUDE.md](CLAUDE.md) standards
- [ ] Linting passes (`make lint`)
- [ ] Haddock documentation added for new exports
- [ ] Tests added for new functionality

## Need Help?

Open an issue for questions about the codebase or contribution process.
