# CLAUDE.md - Canopy Compiler Coding Standards

This document outlines the coding standards and best practices for the Canopy compiler project (Elm language fork). These guidelines ensure code quality, maintainability, and consistency across the project.

## Core Principles

Our codebase follows these fundamental principles:

**Code Quality**: Write clear, maintainable, and efficient code that serves as living documentation
**Consistency**: Maintain uniform coding style and patterns throughout the project
**Modularity**: Design with single responsibility and clear separation of concerns
**Testability**: Write code that is easy to test and verify
**Collaboration**: Enable effective teamwork through clear standards and practices

## Function Design Rules

### Size and Complexity Constraints

- **Maximum 15 lines per function**: Keep functions concise and focused on a single task
- **Maximum 4 parameters**: If more parameters are needed, consider using record types or breaking the function down
- **Maximum 4 branching points**: Limit conditional complexity (if/else, case statements, pattern matches)
- **No code duplication**: Extract common functionality into reusable functions

### Examples

```haskell
-- Good: Concise function with clear purpose
validateOutline :: Outline -> Either Exit.Outline Outline
validateOutline outline =
  case outline of
    Pkg (PkgOutline pkg _ _ _ _ deps _ _)
      | Map.notMember Pkg.core deps && pkg /= Pkg.core -> Left Exit.OutlineNoPkgCore
      | otherwise -> Right outline
    App _ -> Right outline

-- Bad: Too many parameters and branches
processModuleWithComplexLogic :: FilePath -> Text -> Bool -> Maybe Text -> [Import] -> IO (Either Error Module)
```

## Import Style Guidelines

### Qualified Imports (Following Project Convention)

The codebase follows a mixed import strategy. Most Data.* modules are qualified, while some utility modules may be imported unqualified:

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Canopy.Outline where

import Control.Monad (filterM, liftM)
import Data.Binary (Binary, get, getWord8, put, putWord8)
import qualified Data.Map as Map
import Data.Maybe (mapMaybe)
import qualified Data.NonEmptyList as NE
import qualified Canopy.Constraint as Con
import qualified Canopy.ModuleName as ModuleName
```

## Code Style Preferences

### Syntax Choices

- **Prefer `where` over `let`**: Use `where` clauses for local definitions
- **Use both `$` and `()` pragmatically**: Choose based on readability in context
- **Prefer explicit pattern matching**: Use case expressions and pattern guards
- **Follow project record syntax**: Use standard Haskell record syntax (not lens-heavy patterns)

### Examples

```haskell
-- Good: Using where, explicit patterns
parseOutline :: ByteString -> Either Exit.OutlineProblem Outline
parseOutline bytes =
  case D.fromByteString decoder bytes of
    Left err -> Left (Exit.OutlineHasBadStructure err)
    Right outline -> validateOutline outline
  where
    decoder = 
      case tipe of
        application -> App <$> appDecoder
        package -> Pkg <$> pkgDecoder
        _ -> D.failure Exit.OP_BadType

-- Good: Pattern matching with guards
isSrcDirMissing :: FilePath -> SrcDir -> IO Bool
isSrcDirMissing root srcDir =
  not <$> Dir.doesDirectoryExist (toAbsolute root srcDir)
  where
    toAbsolute r s = case s of
      AbsoluteSrcDir dir -> dir
      RelativeSrcDir dir -> r </> dir
```

## Module Organization

### Single Responsibility Principle

Each module should have one clear responsibility:

```haskell
-- Good: Clear, focused module
module Canopy.Outline
  ( Outline(..)
  , read
  , write
  , encode
  , decoder
  ) where

-- Good: Specific parser module
module Parse.Expression
  ( expression
  ) where

-- Bad: Mixed responsibilities
module Everything where
```

### Module Structure Template

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}
module Path.To.Module
  ( exportedFunction
  , ExportedType(..)
  ) where

-- Standard library imports
import Control.Monad (when, unless)
import Data.Maybe (fromMaybe)

-- Qualified imports
import qualified Data.Map as Map
import qualified Data.Text as Text

-- Local project imports
import qualified Canopy.Package as Pkg
import qualified Reporting.Exit as Exit
```

## Project Structure

The Canopy compiler is organized into several main components:

```
canopy/
├── builder/               -- Build system and dependency resolution
│   └── src/
│       ├── Canopy/        -- Core types (Package, Version, Outline, etc.)
│       ├── Deps/          -- Dependency resolution (Solver, Registry)
│       ├── Reporting/     -- Error reporting
│       └── Stuff.hs       -- Utilities and paths
├── compiler/              -- Core compiler logic
│   └── src/
│       ├── AST/           -- Abstract syntax tree definitions
│       ├── Canonicalize/  -- Name resolution and canonicalization
│       ├── Parse/         -- Parser modules
│       ├── Type/          -- Type inference and checking
│       ├── Optimize/      -- Code optimization
│       └── Generate/      -- Code generation
├── terminal/              -- CLI interface
│   ├── impl/              -- Terminal implementation
│   └── src/               -- CLI commands (Make, Install, Repl, etc.)
└── test/                  -- Test suites
    ├── Unit/              -- Unit tests
    ├── Property/          -- Property-based tests
    ├── Integration/       -- Integration tests
    └── Golden/            -- Golden file tests
```

## Testing and Quality Assurance

### Test Organization

The project uses Stack for testing with multiple test suites:

```haskell
-- Test modules follow the source structure
-- Unit tests in test/Unit/
-- Property tests in test/Property/
-- Integration tests in test/Integration/
-- Golden tests in test/Golden/
```

### Testing Commands

```bash
# Build project
make build

# Run all tests
make test

# Run specific test types
make test-unit          # Unit tests only
make test-property      # Property tests only  
make test-integration   # Integration tests only

# Test with coverage
make test-coverage

# Build tests without running
make test-build

# Watch mode for development
make test-watch

# Run specific test pattern
make test-match PATTERN="Parser"
```

### Unit Testing Requirements

- Every public function should have unit tests
- Test both happy path and error cases
- Use property-based testing for complex functions
- Golden file tests for parser and code generation

## Error Handling

### Robust Error Management

The codebase uses explicit error types throughout:

```haskell
-- Good: Explicit error types following project patterns
data Exit.Outline
  = OutlineHasBadStructure D.Error
  | OutlineHasMissingSrcDirs FilePath [FilePath]
  | OutlineNoPkgCore
  | OutlineNoAppCore
  | OutlineNoAppJson

-- Good: Explicit Either return types
read :: FilePath -> IO (Either Exit.Outline Outline)
read root = do
  canopyExists <- Dir.doesFileExist (root </> "canopy.json")
  if canopyExists
    then parseCanopyJson root
    else parseElmJson root
```

### Input Validation

Always validate inputs and handle edge cases:

```haskell
-- Validate file paths and handle missing files
readOutline :: FilePath -> IO (Either Exit.Outline Outline)
readOutline root = do
  canopyExists <- Dir.doesFileExist canopyFile
  elmExists <- Dir.doesFileExist elmFile
  case (canopyExists, elmExists) of
    (True, _) -> parseFile canopyFile decoder
    (False, True) -> parseFile elmFile elmDecoder
    (False, False) -> return $ Left Exit.OutlineMissing
  where
    canopyFile = root </> "canopy.json"
    elmFile = root </> "elm.json"
```

## Performance Guidelines

### Optimization Principles

- Profile before optimizing
- Use strict evaluation where appropriate (especially in data types)
- Minimize memory allocations in hot paths
- Prefer immutable data structures

```haskell
-- Use strict fields in performance-critical data structures
data AppOutline = AppOutline
  { _app_canopy_version :: !V.Version
  , _app_source_dirs :: !(NE.List SrcDir)
  , _app_deps_direct :: !(Map.Map Pkg.Name V.Version)
  , _app_deps_indirect :: !(Map.Map Pkg.Name V.Version)
  }
```

## Development Workflow

### Build and Development

```bash
# Primary development commands
make build              # Build the project
make test              # Run all tests
make clean             # Clean build artifacts
make format            # Format code with ormolu
make fix-lint          # Fix linting issues automatically
```

### Code Quality Tools

The project uses:
- **Stack**: Build system and dependency management  
- **Ormolu**: Code formatting
- **HLint**: Linting and suggestions
- **Wall**: Comprehensive GHC warnings

### Git Workflow

- Use descriptive commit messages
- Keep commits focused and atomic
- Test changes before committing
- Follow the existing code style

## Security Considerations

### Secure Coding Practices

- Validate all file inputs
- Use safe file operations
- Sanitize user-provided data
- Handle IO exceptions properly

```haskell
-- Safe file operations with proper error handling
readModuleFile :: FilePath -> IO (Either Exit.ReadError Text)
readModuleFile path = do
  exists <- Dir.doesFileExist path
  if not exists
    then return $ Left (Exit.FileNotFound path)
    else do
      result <- try (File.readUtf8 path)
      case result of
        Left ioErr -> return $ Left (Exit.IOError (show ioErr))
        Right content -> return $ Right content
```

## Conclusion

Following these guidelines ensures the Canopy compiler maintains high code quality, remains maintainable, and facilitates effective collaboration. These standards reflect the actual patterns used in the codebase and should be followed for consistency.

For questions or suggestions regarding these standards, please open an issue or discussion in the project repository.