# CLAUDE.md - Canopy Compiler Development Standards

This document defines comprehensive coding standards, best practices, and development guidelines for the Canopy compiler project (Elm language fork). These standards ensure the highest code quality, maintainability, performance, and team collaboration.

## 🎯 Core Principles

**Code Excellence**: Write clear, efficient, and self-documenting code that serves as the gold standard for compiler implementation
**Consistency**: Maintain uniform style and patterns throughout the entire codebase
**Modularity**: Design with single responsibility principle and clear separation of concerns
**Performance**: Optimize hot paths while maintaining readability; profile-driven optimization
**Robustness**: Comprehensive error handling with rich error types and graceful failure
**Testability**: Write code designed for thorough testing with high coverage
**Documentation**: Extensive Haddock documentation for all public APIs
**Security**: Treat all inputs as untrusted; validate and sanitize rigorously
**Collaboration**: Enable effective teamwork through clear standards and practices

## 🚫 Non-Negotiable Guardrails

These constraints are enforced by CI and must be followed without exception:

1. **Function size**: ≤ 15 lines (excluding blank lines and comments)
2. **Parameters**: ≤ 4 per function (use records/newtypes for grouping)
3. **Branching complexity**: ≤ 4 branching points (sum of if/case arms, guards, boolean splits)
4. **No duplication (DRY)**: Extract common logic into reusable functions
5. **Single responsibility**: One clear purpose per module
6. **Lens usage**: Use lenses for all record access/updates; NO record-dot syntax
7. **Qualified imports**: Everything qualified except types, lenses, and pragmas
8. **Test coverage**: Minimum 80% coverage for all modules

## 📁 Project Structure

```
canopy/
├── builder/               -- Build system and dependency resolution
│   └── src/
│       ├── Canopy/        -- Core types (Package, Version, Outline, etc.)
│       │   ├── Details.hs         -- Project details and configuration
│       │   ├── Outline.hs         -- Project outline (canopy.json structure)
│       │   ├── Package.hs         -- Package naming and validation
│       │   └── Version.hs         -- Version handling and constraints
│       ├── Deps/          -- Dependency resolution
│       │   ├── Solver.hs          -- Dependency solver algorithm
│       │   └── Registry.hs        -- Package registry interaction
│       ├── Reporting/     -- Error reporting
│       │   ├── Exit.hs            -- Exit codes and error types
│       │   └── Task.hs            -- Task monad for build operations
│       └── Stuff.hs       -- Utilities and paths
├── compiler/              -- Core compiler logic
│   └── src/
│       ├── AST/           -- Abstract syntax tree definitions
│       │   ├── Source.hs          -- Source AST (parsed)
│       │   ├── Canonical.hs       -- Canonical AST (name-resolved)
│       │   └── Optimized.hs       -- Optimized AST (pre-codegen)
│       ├── Canonicalize/  -- Name resolution and canonicalization
│       ├── Parse/         -- Parser modules
│       │   ├── Primitives.hs      -- Parser primitives
│       │   ├── Expression.hs      -- Expression parser
│       │   ├── Pattern.hs         -- Pattern parser
│       │   ├── Type.hs            -- Type parser
│       │   └── Module.hs          -- Module parser
│       ├── Type/          -- Type inference and checking
│       │   ├── Constrain.hs       -- Constraint generation
│       │   ├── Solve.hs           -- Constraint solving
│       │   └── Unify.hs           -- Type unification
│       ├── Optimize/      -- Code optimization
│       │   ├── Expression.hs      -- Expression optimization
│       │   ├── DecisionTree.hs    -- Pattern match optimization
│       │   └── Names.hs           -- Name optimization
│       └── Generate/      -- Code generation
│           ├── JavaScript.hs      -- JS backend
│           └── Html.hs            -- HTML generation
├── terminal/              -- CLI interface
│   ├── impl/              -- Terminal implementation
│   └── src/               -- CLI commands
│       ├── Make.hs               -- Build command
│       ├── Install.hs            -- Package installation
│       ├── Repl.hs               -- Interactive REPL
│       └── Watch.hs              -- File watcher
└── test/                  -- Test suites
    ├── Unit/              -- Unit tests
    ├── Property/          -- Property-based tests
    ├── Integration/       -- Integration tests
    └── Golden/            -- Golden file tests
```

## 🎨 Haskell Style Guide

### Import Style

**MANDATORY PATTERN: Import types/constructors unqualified, functions qualified**

This is the ONLY acceptable import pattern for the ENTIRE Canopy codebase. NO EXCEPTIONS.

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
{-# OPTIONS_GHC -Wall #-}

module Canopy.Parser.Expression
  ( parseExpression
  , Expression(..)
  ) where

-- Pattern 1: Types unqualified + module qualified
import Control.Monad.State.Strict (StateT)
import qualified Control.Monad.State.Strict as State
import qualified Control.Monad.Trans as Trans

-- Pattern 2: Multiple types from same module + qualified alias
import System.Console.Haskeline (InputT, Settings)
import qualified System.Console.Haskeline as Haskeline

-- Pattern 3: Specific operators unqualified + module qualified
import Reporting.Doc ((<+>))
import qualified Reporting.Doc as Doc

-- Pattern 4: Local project modules with selective type imports
import Repl.Types
  ( CategorizedInput,
    Env,
    Flags,
    Input,
    Lines,
    M,
    Output,
    Prefill,
    State
  )
import qualified Repl.Types as Types

-- Pattern 5: Standard library modules (types + qualified)
import System.Exit (ExitCode)
import qualified System.Exit as Exit
```

**Usage Rules (APPLY TO ENTIRE CODEBASE):**
- **Type signatures**: Use unqualified types (`StateT`, `InputT`, `ExitCode`, `ByteString`, `Map`, etc.)
- **Constructors**: Use qualified prefix (`Types.Skip`, `Types.Loop`, `Exit.ExitSuccess`, `Map.empty`)
- **Functions**: ALWAYS use qualified (`State.put`, `Haskeline.runInputT`, `Trans.liftIO`, `Map.insert`)
- **Operators**: Import unqualified when frequently used (`(<+>)`, `(</>)`)
- **Import aliases**: Use meaningful names, NOT abbreviations (`as Diff` NOT `as DD`, `as State` NOT `as S`)
- **NO COMMENTS**: NEVER add comments like "-- Qualified imports" or "-- Local imports" in import blocks

**WRONG:**
```haskell
-- Bad type signatures
processOutline :: FilePath -> IO (Either Exit.Outline Outline.Outline)
toByteString :: State.State -> Output.Output -> BS.ByteString

-- Bad import aliases
import qualified Deps.Diff as DD
import qualified Data.Map as M
import qualified Control.Monad.State as S
```

**CORRECT:**
```haskell
-- Good type signatures
processOutline :: FilePath -> IO (Either Exit Outline) 
toByteString :: State -> Output -> ByteString

-- Good import aliases
import qualified Deps.Diff as Diff
import qualified Data.Map as Map
import qualified Control.Monad.State as State
```

**Examples of correct usage:**
```haskell
-- Type signature uses unqualified types
loop :: Env -> State -> InputT M ExitCode

-- Function implementation uses qualified functions and qualified constructors
loop env state = do
  Haskeline.handleInterrupt (pure Types.Skip) (readInput state)
    >>= Trans.liftIO . Eval.eval env state
    >>= \case
      Types.Loop newState -> do
        Trans.lift (State.put newState)
        loop env newState
      Types.End exitCode -> pure exitCode
```

### Lens Usage (Mandatory)

**ALWAYS use lenses for record manipulation. NEVER use record-dot syntax.**

```haskell
-- Define records with lens support
data CompilerState = CompilerState
  { _stateModules :: !(Map.Map ModuleName Module)
  , _stateErrors :: ![Error]
  , _stateWarnings :: ![Warning]
  , _stateOptLevel :: !OptimizationLevel
  } deriving (Eq, Show)

-- Generate lenses
makeLenses ''CompilerState

-- Access with (^.)
getModules :: CompilerState -> Map.Map ModuleName Module
getModules state = state ^. stateModules

-- Update with (.~)
setOptLevel :: OptimizationLevel -> CompilerState -> CompilerState
setOptLevel level state = state & stateOptLevel .~ level

-- Modify with (%~)
addError :: Error -> CompilerState -> CompilerState
addError err state = state & stateErrors %~ (err :)

-- Complex updates with (&)
updateState :: CompilerState -> CompilerState
updateState state = state
  & stateOptLevel .~ O2
  & stateWarnings .~ []
  & stateModules %~ Map.filter isPublic

-- Nested access and updates
getModuleName :: CompilerState -> ModuleName -> Maybe Text
getModuleName state modName =
  state ^? stateModules . at modName . _Just . moduleName

-- NEVER DO THIS (record-dot syntax)
-- BAD: state.stateModules
-- BAD: state { stateModules = newModules }
```

### Function Composition Style

**Prefer binds (>>=, >=>) over do-notation when linear and readable:**

```haskell
-- GOOD: Linear bind composition
compileModule :: FilePath -> IO (Either Error ByteString)
compileModule path =
  fmap processContent (readFileUtf8 path)
  where
    processContent = parseModule >=> canonicalize >=> typeCheck >=> optimize >=> generateJS

-- GOOD: Kleisli composition  
processFile :: FilePath -> Either Error Result
processFile = readContent >=> parse >=> validate >=> transform

-- GOOD: Using fmap and where for cleaner code
compileWithDetails :: FilePath -> IO (Either Error (Module, Stats))
compileWithDetails path = 
  readFileUtf8 path >>= \content ->
    either (pure . Left) compileWithStats (parseModule content)
  where
    compileWithStats ast = do
      startTime <- Time.getCurrentTime
      result <- compileAST ast
      endTime <- Time.getCurrentTime
      pure (Right (result, computeStats startTime endTime))

-- AVOID: Unnecessary do-notation for simple chains
-- BAD:
badExample path = do
  content <- readFile path
  result <- parseModule content
  pure result
-- GOOD: Should be:
goodExample path = readFile path >>= parseModule
```

### Where vs Let

**Always prefer `where` over `let`:**

```haskell
-- GOOD: Using where and either function
parseExpression :: Text -> Either ParseError Expression
parseExpression input =
  runParser expressionParser input
    >>= validateExpression
  where
    validateExpression e
      | isValid e = Right e
      | otherwise = Left (InvalidExpression e)

-- BAD: Using let and case instead of either
parseExpressionBad input =
  let expr = expressionParser
      formatError = ParseError . Text.pack . show
  in case runParser expr input of
       Left err -> Left (formatError err)
       Right result -> Right result
-- GOOD: Should use either:
parseExpressionGood input = 
  either (Left . ParseError . Text.pack . show) Right (runParser expressionParser input)
```

### Parentheses vs ($)

**Prefer parentheses `()` over `$` for clarity:**

```haskell
-- GOOD: Clear parentheses with qualified imports
result = Map.lookup key (processMap inputMap)
output = Text.concat (List.map processItem items)

-- BAD: Excessive $ usage
bad = Map.lookup key $ processMap $ inputMap
worse = Text.concat $ List.map processItem $ items
```

## 📊 Function Design Rules

### Size and Complexity Limits

Every function must adhere to these limits:

```haskell
-- GOOD: Focused function under 15 lines, no nested control structures
validateOutline :: Outline -> Either Exit.Outline Outline
validateOutline (App appOutline) = validateAppOutline appOutline
validateOutline (Pkg pkgOutline) = validatePkgOutline pkgOutline

-- Extract package validation to separate function
validatePkgOutline :: PkgOutline -> Either Exit.Outline Outline
validatePkgOutline outline@(PkgOutline pkg _ _ _ _ deps _ _) =
  checkCoreDependency >> checkRequiredFields >> pure (Pkg outline)
  where
    checkCoreDependency
      | Map.notMember Pkg.core deps && pkg /= Pkg.core =
          Left Exit.OutlineNoPkgCore
      | otherwise = Right ()

    checkRequiredFields
      | hasRequiredFields outline = Right ()
      | otherwise = Left Exit.OutlineMissingFields

-- BAD: Function too long and complex
badFunction :: Text -> Maybe Int -> [String] -> Bool -> IO (Either Error Result)
badFunction input maybeCount items flag = do
  -- 50+ lines of complex logic...
  -- Multiple responsibilities...
  -- Deep nesting...
  -- No clear structure...
```

### Refactoring Patterns

When functions exceed limits, apply these patterns:

```haskell
-- Extract helper functions
compileModule :: Module -> Either Error CompiledModule
compileModule = 
  canonicalizeModule 
    >=> typeCheckModule
    >=> optimizeModule
    >=> generateCode

-- Use record types for many parameters
data CompileOptions = CompileOptions
  { _optLevel :: OptimizationLevel
  , _optTarget :: Target
  , _optDebug :: Bool
  , _optOutput :: FilePath
  }
makeLenses ''CompileOptions

compile :: CompileOptions -> Module -> IO (Either Error Result)

-- Replace boolean flags with sum types
data CompileMode = Development | Production | Testing
  deriving (Eq, Show)

-- Factor out complex conditions
shouldOptimize :: CompileOptions -> Module -> Bool
shouldOptimize opts mod =
  opts ^. optLevel > O0
    && not (mod ^. moduleDebug)
    && isProductionTarget (opts ^. optTarget)
```

## 🧪 Testing Strategy

### Test Organization

```haskell
-- Unit test structure
module Test.Unit.Canopy.VersionTest where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Canopy.Version as V

tests :: TestTree
tests = Test.testGroup "Canopy.Version Tests"
  [ Test.testGroup "version creation"
      [ Test.testCase "version one" $
          V.one @?= V.Version 1 0 0
      , Test.testCase "version from parts" $
          V.fromParts 2 1 3 @?= Maybe.Just (V.Version 2 1 3)
      ]
  , Test.testGroup "version comparison"
      [ Test.testCase "equality" $
          V.Version 1 2 3 == V.Version 1 2 3 @?= True
      , Test.testCase "ordering" $
          V.Version 1 2 3 < V.Version 2 0 0 @?= True
      ]
  ]

-- Property test example
module Test.Property.Canopy.VersionProps where

import Test.Tasty
import Test.Tasty.QuickCheck
import qualified Canopy.Version as V

props :: TestTree
props = Test.testGroup "Version Properties"
  [ Test.testProperty "roundtrip toChars/fromChars" $ \v ->
      V.fromChars (V.toChars v) == Maybe.Just v
  , Test.testProperty "ordering transitivity" $ \a b c ->
      (a < b && b < c) ==> (a < c)
  ]

-- Golden test example
module Test.Golden.JsGen where

import Test.Tasty.Golden
import qualified Generate

goldenTest :: TestTree
goldenTest = Test.goldenVsString
  "JS generation for module"
  "test/golden/expected/module.js"
  (Generate.dev testModule)
```

### Testing Requirements

1. **Unit tests** for every public function
2. **Property tests** for invariants and laws
3. **Golden tests** for parser output and code generation
4. **Integration tests** for end-to-end compilation
5. **Benchmark tests** for performance-critical paths

### Test Commands

```bash
# Build project
make build

# Run all tests
make test

# Run specific test suite
make test-unit
make test-property
make test-integration
make test-golden

# Run with coverage
make test-coverage

# Run specific test pattern
make test-match PATTERN="Parser"

# Continuous testing
make test-watch

# Benchmarks
make bench
```

## 🚨 Error Handling

### Rich Error Types

```haskell
-- Define comprehensive error types with all failure modes
data CompileError
  = ParseError !FilePath !Region !Text
  | NameError !ModuleName !Name !NameProblem
  | TypeError !Region !TypeProblem
  | OptimizeError !OptimizeProblem
  | GenerateError !GenerateProblem
  deriving (Eq, Show)

-- Use structured error information
data ParseError = ParseError
  { _parseErrorFile :: !FilePath
  , _parseErrorRegion :: !Region
  , _parseErrorMessage :: !Text
  , _parseErrorContext :: ![Text]
  , _parseErrorSuggestions :: ![Text]
  }
makeLenses ''ParseError

-- Provide helpful error messages
renderError :: CompileError -> Doc
renderError (ParseError file region msg) =
  Doc.vcat
    [ Doc.text "-- PARSE ERROR" <+> Doc.text file
    , Doc.indent 2 (renderRegion region)
    , Doc.empty
    , Doc.indent 2 (Doc.text msg)
    , Doc.empty
    , Doc.text "Hint: Check for missing parentheses or operators"
    ]
```

### Validation and Safety

```haskell
-- Validate all inputs
parseModuleName :: Text -> Either ValidationError ModuleName
parseModuleName input
  | Text.null input =
      Left (ValidationError "Module name cannot be empty")
  | not (Char.isUpper (Text.head input)) =
      Left (ValidationError "Module name must start with capital letter")
  | not (List.all isValidChar (Text.unpack input)) =
      Left (ValidationError "Module name contains invalid characters")
  | List.length parts > 5 =
      Left (ValidationError "Module name too deeply nested")
  | otherwise = Right (ModuleName parts)
  where
    parts = Text.splitOn "." input
    isValidChar c = Char.isAlphaNum c || c == '_'

-- Use total functions, document partial ones
safeHead :: [a] -> Maybe a
safeHead = List.listToMaybe

-- If partial function is necessary, document it clearly
-- | Get first element.
-- PARTIAL: Fails on empty list. Only use when list is guaranteed non-empty.
unsafeHead :: [a] -> a
unsafeHead (x:_) = x
unsafeHead [] = error "unsafeHead: empty list"
```

## 📝 Documentation Standards

### Haddock Documentation

Every public function must have comprehensive Haddock documentation:

```haskell
-- | Parse a Canopy module from source text.
--
-- This function performs the following steps:
--   1. Tokenizes the input
--   2. Parses the token stream into an AST
--   3. Validates the AST structure
--
-- The parser handles both .can and .canopy file extensions.
--
-- ==== Examples
--
-- >>> parseModule "module Main exposing (..)\n\nmain = text \"Hello\""
-- Right (Module {_moduleName = "Main", ...})
--
-- >>> parseModule "invalid syntax"
-- Left (ParseError ...)
--
-- ==== Errors
--
-- Returns 'ParseError' for:
--   * Syntax errors
--   * Invalid module structure
--   * Unrecognized tokens
--
-- @since 0.19.1
parseModule
  :: Text
  -- ^ Source code to parse
  -> Either ParseError Module
  -- ^ Parsed module or error
parseModule input =
  runParser moduleParser input
```

### Internal Documentation

```haskell
-- Complex algorithms need explanation
optimizeCase :: Expression -> Expression
optimizeCase =
  -- The decision tree optimization follows the algorithm from
  -- "Compiling Pattern Matching to Good Decision Trees" by Luc Maranget.
  -- We build a decision tree that minimizes the number of tests needed
  -- to determine which pattern matches.
  --
  -- Steps:
  -- 1. Collect all patterns into a matrix
  -- 2. Find the best column to split on (using heuristics)
  -- 3. Recursively build subtrees for each constructor
  -- 4. Generate optimized case expression from tree
  extractPatterns >>> buildDecisionTree >>> optimizeTree >>> generateOptimizedCase
```

## ⚡ Performance Guidelines

### Optimization Principles

```haskell
-- Use strict fields in data structures to prevent thunks
data ModuleCache = ModuleCache
  { _cacheModules :: !(Map.Map ModuleName Module)
  , _cacheInterfaces :: !(Map.Map ModuleName Interface)
  , _cacheLastAccess :: !UTCTime
  } deriving (Eq, Show)

-- Use BangPatterns for strict evaluation
sumTree :: Tree Int -> Int
sumTree = go 0
  where
    go !acc Leaf = acc
    go !acc (Node x left right) =
      go (go (acc + x) left) right

-- Prefer strict Map/Set variants
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

-- Use ByteString/Text for strings
import qualified Data.Text as Text
import qualified Data.ByteString.Builder as BB

-- Profile before optimizing
-- compile with: -prof -fprof-auto
-- run with: +RTS -p -h
```

### Memory Management

```haskell
-- Use streaming for large data
processLargeFile :: FilePath -> IO ()
processLargeFile path =
  IO.withFile path IO.ReadMode
    Stream.fromHandle handle
      |> Stream.lines
      |> Stream.map processLine
      |> Stream.mapM_ writeResult

-- Clear references when done
cleanupCache :: ModuleCache -> IO ModuleCache
cleanupCache cache =
  fmap filterOldEntries Time.getCurrentTime
  where
    filterOldEntries currentTime = 
      cache & cacheModules %~ Map.filter (isRecent (Time.addUTCTime (-3600) currentTime))
```

## 🔒 Security Considerations

### Input Validation

```haskell
-- Validate and sanitize all file paths
validateFilePath :: FilePath -> Either SecurityError FilePath
validateFilePath path
  | FP.isAbsolute path =
      Left (SecurityError "Absolute paths not allowed")
  | ".." `elem` FP.splitDirectories path =
      Left (SecurityError "Path traversal not allowed")
  | any isInvalidChar path =
      Left (SecurityError "Path contains invalid characters")
  | otherwise = Right (FP.normalise path)

-- Limit resource consumption
parseWithLimits :: Text -> Either ParseError Module
parseWithLimits input
  | Text.length input > maxModuleSize =
      Left (ParseError "Module too large")
  | countImports input > maxImports =
      Left (ParseError "Too many imports")
  | otherwise = parseModule input
  where
    maxModuleSize = 1000000  -- 1MB
    maxImports = 500
```

## 🔄 Version Control & Collaboration

### Commit Message Format

Follow conventional commits strictly:

```bash
feat(parser): add support for record wildcards
fix(typecheck): handle recursive type aliases correctly
perf(optimizer): improve dead code elimination by 15%
docs(api): add examples for Parser module
refactor(ast): split Expression into separate modules
test(integration): add tests for .canopy file support
build(deps): update to ghc 9.8.4
ci(github): add nightly benchmarks
style(format): apply fourmolu to all modules
```

### Pull Request Checklist

- [ ] All CI checks pass
- [ ] Functions meet size/complexity limits
- [ ] Lenses used for all record operations
- [ ] Qualified imports follow conventions
- [ ] Unit tests added/updated (coverage ≥80%)
- [ ] Property tests for invariants
- [ ] Golden tests updated if output changed
- [ ] Haddock documentation complete
- [ ] Performance impact assessed
- [ ] Security implications considered
- [ ] CHANGELOG.md updated

### Code Review Standards

Reviewers must verify:

1. **Correctness**: Logic is sound and handles edge cases
2. **Style**: Follows all conventions in this document
3. **Performance**: No obvious inefficiencies
4. **Security**: Input validation and resource limits
5. **Tests**: Comprehensive test coverage
6. **Documentation**: Clear and complete
7. **Maintainability**: Code is readable and modular

## 🛠️ Development Workflow

### Daily Development

```bash
# Start work on feature
git checkout -b feature/your-feature

# Ensure code quality before commit
make format           # Auto-format code
make lint            # Check for issues
make test-fast       # Run quick tests

# Commit with conventional format
git commit -m "feature(module): description"

# Before pushing
make test            # Run full test suite
make test-coverage   # Check coverage
make bench           # Run benchmarks if performance-critical

# Push and create PR
git push origin feature/your-feature
```

### Continuous Integration

Our CI pipeline enforces:

- **Build**: Project compiles without warnings
- **Tests**: All test suites pass
- **Coverage**: Minimum 80% code coverage
- **Lint**: No hlint warnings
- **Format**: Code formatted with fourmolu
- **Complexity**: Functions meet size/branching limits
- **Documentation**: Haddock builds successfully
- **Benchmarks**: No performance regressions

### Release Process

```bash
# Update version
make bump-version VERSION=0.19.2

# Run full validation
make validate-release

# Create release
make release

# Deploy documentation
make deploy-docs
```

## 📋 Quick Reference

### Mandatory Practices

✅ **ALWAYS**:

- Use lenses for records (no record-dot syntax)
- Qualify imports (except types/lenses/pragmas)
- Keep functions ≤15 lines, ≤4 params, ≤4 branches
- Write tests first (TDD)
- Document with Haddock
- Use `where` over `let`
- Prefer `()` over `$`
- Prefer binds over unnecessary `do`
- Validate all inputs
- Handle all error cases

❌ **NEVER**:

- Use record-dot syntax
- Write functions >15 lines
- Use partial functions without documentation
- Duplicate code
- Commit without tests
- Ignore compiler warnings
- Skip code review
- Use String (prefer Text/ByteString)

### Common Patterns

```haskell
-- Module header
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}
module Canopy.Feature (api) where

-- Record with lenses
data State = State { _stateField :: !Type }
makeLenses ''State

-- Error handling
processFile :: FilePath -> Either Error Result
processFile = readFile >=> parse >=> validate

-- Testing
spec :: Spec
spec = Test.describe "Feature" $ 
  Test.it "works correctly" $
    feature input `shouldBe` expected
```

## 🎓 Learning Resources

- [Haskell Style Guide](https://github.com/tibbe/haskell-style-guide)
- [Lens Tutorial](https://hackage.haskell.org/package/lens-tutorial)
- [Property Testing with QuickCheck](https://www.fpcomplete.com/haskell/library/quickcheck/)
- [Haddock Documentation Guide](https://haskell-haddock.readthedocs.io/)
- [GHC Optimization Guide](https://wiki.haskell.org/Performance)

## 📜 License and Credits

This coding standard incorporates best practices from:

- The Elm compiler team
- Haskell community style guides
- Industrial Haskell practices
- Modern compiler construction techniques

---

**Remember**: These standards exist to help us build a robust, maintainable, and high-performance compiler. When in doubt, prioritize code clarity and correctness over cleverness.

For questions or suggestions, please open an issue in the project repository.

- Do not add comments like this