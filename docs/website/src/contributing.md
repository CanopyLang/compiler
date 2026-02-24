# Contributing to Canopy

Thank you for your interest in contributing to Canopy! This guide will help you get started.

## Ways to Contribute

### Report Issues

Found a bug or have a feature request? Open an issue on GitHub:

1. Search existing issues to avoid duplicates
2. Use a clear, descriptive title
3. Provide steps to reproduce (for bugs)
4. Include Canopy version and OS

### Improve Documentation

Documentation improvements are always welcome:

- Fix typos and unclear explanations
- Add examples
- Translate documentation
- Write tutorials

### Contribute Code

Ready to contribute code? Here's how:

1. Fork the repository
2. Create a feature branch
3. Write your code
4. Add tests
5. Submit a pull request

## Development Setup

### Prerequisites

- GHC 9.4 or later
- Stack or Cabal
- Node.js 16+

### Clone and Build

```bash
# Clone the repository
git clone https://github.com/canopy-lang/canopy.git
cd canopy

# Build with Stack
stack build

# Run tests
stack test

# Build documentation
stack haddock
```

### Project Structure

```
canopy/
├── packages/
│   ├── canopy-core/      # Compiler core
│   ├── canopy-terminal/  # CLI
│   └── canopy-lsp/       # Language server
├── core-packages/        # Standard library
├── test/                 # Test suites
├── docs/                 # Documentation
└── examples/             # Example projects
```

## Code Style

### Haskell

Follow the project's coding standards:

- Qualified imports (except types and operators)
- `where` over `let` for local definitions
- No partial functions
- Maximum 15 lines per function
- Haddock documentation for public APIs

```haskell
-- Good
module Parser.Expression
  ( parseExpression
  , Expression(..)
  ) where

import qualified Data.Text as Text
import Data.Maybe (Maybe)

parseExpression :: Text -> Either ParseError Expression
parseExpression input =
    runParser expressionParser input
  where
    expressionParser = ...
```

### Canopy

For standard library code:

- Clear, descriptive names
- Comprehensive documentation
- Example usage in docs
- Full test coverage

```canopy
{-| Transform each element in a list.

    List.map sqrt [ 1, 4, 9 ] == [ 1, 2, 3 ]

-}
map : (a -> b) -> List a -> List b
map f list =
    case list of
        [] ->
            []

        x :: xs ->
            f x :: map f xs
```

## Testing

### Running Tests

```bash
# All tests
stack test

# Specific test suite
stack test --ta="--pattern Parser"

# With coverage
stack test --coverage
```

### Writing Tests

```haskell
-- Unit tests
describe "Parser" $ do
    it "parses simple expressions" $
        parse "1 + 2" `shouldBe` Right (Add (Num 1) (Num 2))

-- Property tests
prop "roundtrip" $ \expr ->
    parse (render expr) == Right expr
```

## Pull Request Process

### Before Submitting

1. **Run all tests**: `stack test`
2. **Check formatting**: `fourmolu -i .`
3. **Run linter**: `hlint .`
4. **Update documentation** if needed
5. **Add changelog entry** for user-facing changes

### PR Guidelines

- One feature/fix per PR
- Clear description of changes
- Reference related issues
- Include tests for new features
- Keep commits atomic and well-described

### Review Process

1. Automated CI runs tests and checks
2. Maintainer reviews code
3. Address feedback
4. Maintainer merges when approved

## Commit Messages

Follow conventional commits:

```
feat(parser): add support for do-notation

Add do-notation support for Task, Maybe, and Result types.
Implements desugaring in the canonicalization phase.

Closes #123
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `refactor`: Code change that neither fixes a bug nor adds a feature
- `test`: Adding or updating tests
- `perf`: Performance improvement
- `build`: Build system changes
- `ci`: CI configuration changes

## Getting Help

- **Discord**: Join our community server
- **GitHub Discussions**: Ask questions
- **Issues**: Report bugs or request features

## Code of Conduct

Be respectful and inclusive. We follow the Contributor Covenant:

- Use welcoming and inclusive language
- Be respectful of differing viewpoints
- Accept constructive criticism gracefully
- Focus on what's best for the community

## Recognition

Contributors are recognized in:

- CONTRIBUTORS.md file
- Release notes
- Project documentation

Thank you for contributing to Canopy!
