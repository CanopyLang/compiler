# Canopy Compiler: Integrated Tooling & Local Package Development Research

**Research Date**: 2025-11-09
**Codebase Version**: 0.19.1
**Repository**: /home/quinten/fh/canopy

---

## Executive Summary

This comprehensive research analyzes the Canopy Compiler's current state regarding:
1. **Integrated Tooling** - Testing, formatting, linting, documentation generation
2. **Local Package Development** - Workflows for developing packages without publishing
3. **Missing Features** - Gaps compared to the Elm ecosystem
4. **CLI Commands** - Available developer commands and their capabilities

### Key Findings

✅ **What Exists:**
- Comprehensive test infrastructure (Unit, Property, Integration, Golden)
- Local package override system via `canopy-package-overrides/`
- FFI testing command (`canopy test-ffi`)
- HLint integration for Haskell code linting
- Custom repository support for package development

❌ **What's Missing:**
- **No `canopy format`** command (no equivalent to `elm-format`)
- **No `canopy lint`** for Canopy code
- **No `canopy test`** for user code (only internal compiler tests)
- **No `canopy docs`** generation for packages
- **No `canopy link`** command for local package linking
- **Limited documentation** on local development workflows

---

## 1. Integrated Tooling Analysis

### 1.1 Testing Infrastructure

#### ✅ **Comprehensive Internal Test Suite**

The compiler has excellent testing for itself:

**Test Structure** (`/home/quinten/fh/canopy/test/`):
```
test/
├── Unit/           # 80+ unit tests for compiler internals
├── Property/       # QuickCheck property-based tests
├── Integration/    # End-to-end compilation tests
├── Golden/         # Golden file snapshot tests
└── benchmark/      # Performance benchmarking
```

**Test Runner** (`test/Main.hs`):
- Uses `tasty` framework (tasty-hunit, tasty-quickcheck, tasty-golden)
- 100+ test modules covering:
  - AST parsing and canonicalization
  - Type checking and inference
  - JavaScript code generation
  - Builder and dependency resolution
  - Terminal/CLI functionality
  - FFI validation

**Makefile Test Commands**:
```bash
make test              # Run all tests
make test-unit         # Unit tests only
make test-property     # Property-based tests
make test-integration  # Integration tests
make test-watch        # Watch mode
make test-coverage     # Coverage report
```

**Test Dependencies** (`canopy.cabal`):
```haskell
test-suite canopy-test
  build-depends:
    tasty
    tasty-hunit
    tasty-quickcheck
    tasty-golden
    QuickCheck
    temporary
```

#### ⚠️ **FFI Testing Command** - Partial Implementation

**Command**: `canopy test-ffi`

**Implementation**: `/home/quinten/fh/canopy/packages/canopy-terminal/src/Test/FFI.hs`

**Features**:
- Generates JavaScript test files from FFI declarations
- Validates FFI contracts and JSDoc annotations
- Property-based testing for FFI functions
- Runtime validation of type safety
- Watch mode for continuous testing

**Flags**:
```bash
canopy test-ffi                              # Run all FFI tests
canopy test-ffi --generate                   # Generate test files
canopy test-ffi --output test-generation/    # Custom output directory
canopy test-ffi --watch                      # Watch for changes
canopy test-ffi --validate-only              # Only validate contracts
canopy test-ffi --verbose                    # Detailed output
canopy test-ffi --property-runs 500          # Property test iterations
canopy test-ffi --browser                    # Run in browser
```

**Current Status**: Implemented but specialized for FFI only

**What's Missing**: General-purpose test command for Canopy user code
- No `canopy test` equivalent to `elm-test`
- No test framework for application code
- No test runner for pure Canopy modules

### 1.2 Code Formatting

#### ❌ **No Canopy Code Formatter**

**Current State**:
- **No `canopy format` command**
- **No equivalent to `elm-format`**
- No automated code formatting for `.can` or `.canopy` files

**What Exists**: Haskell code formatting only
```makefile
# Makefile formatting commands (compiler source only)
format:
    @find builder compiler terminal test -name '*.hs' \
      -exec ormolu --ghc-opt=-XTypeApplications --mode=inplace {} \;
```

**Tools Used** (for compiler development):
- `ormolu` - Haskell code formatter
- Applied only to compiler source code (`.hs` files)
- Not applicable to user Canopy code

**Gap**: Users have no way to automatically format their Canopy code

### 1.3 Linting

#### ✅ **HLint for Compiler Source**

**Configuration**: `.hlint.yaml`

**Features**:
- Enforces Haskell code quality rules
- Custom rules for Canopy compiler
- Integrated into Makefile

**Makefile Lint Commands**:
```bash
make lint              # Run hlint + ormolu checks
make fix-lint          # Auto-fix linting issues
make fix-lint-folder FOLDER=compiler  # Fix specific directory
```

**HLint Configuration Highlights**:
```yaml
- arguments: [--color=auto, -XStrictData]
- group: { name: dollar, enabled: true }      # Prefer $ over nested parens
- group: { name: generalise, enabled: true }  # map → fmap, ++ → <>
- warn: { group: { name: default } }

# Ignored hints
- ignore: { name: Redundant bracket }
- ignore: { name: Use explicit module export list }
```

#### ❌ **No Linting for Canopy Code**

**Current State**:
- **No `canopy lint` command**
- No style checking for user Canopy code
- No equivalent to ESLint/elm-analyse

**Gap**: Users cannot enforce code quality standards for Canopy code

### 1.4 Documentation Generation

#### ⚠️ **Partial Documentation Support**

**Make Command**:
```bash
canopy make --docs docs.json src/Main.can
```

**What It Does** (`Make.hs`):
- Generates JSON documentation for packages
- Intended for package publishing
- Flag exists in CLI (`--docs` flag)

**Implementation** (`Make/Types.hs`):
```haskell
data Flags = Flags
  { _docs :: Maybe DocsFile
  , _output :: Maybe Output
  , ...
  }

docsFile :: Parser DocsFile
docsFile = Parser
  { _singular = "json file"
  , _plural = "json files"
  , _parser = Just . DocsFile
  , ...
  }
```

**What's Missing**:
- No documentation preview/viewer
- No `canopy docs` standalone command
- No HTML documentation generation
- No doc search/navigation tools
- Roadmap mentions: "Eventually it will be possible to preview docs with `reactor`"

### 1.5 Type Checking

#### ✅ **Built-In Type Checker**

All type checking is built into compilation:
- No separate `canopy check` command needed
- Type errors shown during `canopy make`
- Comprehensive error messages with suggestions

**Type Checking Components**:
```
packages/canopy-core/src/Type/
├── Constrain/       # Constraint generation
├── Solve.hs         # Type inference solver
├── Unify.hs         # Type unification
└── Error.hs         # Type error reporting
```

### 1.6 Build Tools

#### ✅ **Compilation Commands**

**Make Command** (`canopy make`):
```haskell
-- CLI/Commands.hs
createMakeCommand :: Command
createMakeCommand =
  Terminal.Command "make" Terminal.Uncommon details example args flags Make.run

createMakeFlags :: Terminal.Flags Make.Flags
createMakeFlags =
  Terminal.flags Make.Flags
    |-- Terminal.onOff "debug"      -- Time-travelling debugger
    |-- Terminal.onOff "optimize"   -- Production optimization
    |-- Terminal.onOff "watch"      -- File watching
    |-- Terminal.flag "output" Make.output  -- Custom output path
    |-- Terminal.flag "report" Make.reportType  -- JSON error reports
    |-- Terminal.flag "docs" Make.docsFile  -- Documentation JSON
    |-- Terminal.onOff "verbose"    -- Detailed compilation logs
```

**Watch Mode**:
- `canopy make --watch src/Main.can`
- File watcher for automatic recompilation
- Implementation: `packages/canopy-terminal/src/Watch.hs`

**Development Server** (`canopy reactor`):
```bash
canopy reactor           # Start at http://localhost:8000
canopy reactor --port 3000  # Custom port
```

Features:
- File browser interface
- Click-to-compile workflow
- No hot reloading (manual refresh required)

---

## 2. Local Package Development

### 2.1 Package Override System

#### ✅ **Local Package Overrides** - Implemented

**Directory Structure**:
```
canopy-package-overrides/
├── README.md
├── canopy-browser-1.0.2.zip
├── canopy-html-1.0.0.zip
├── canopy-json-1.1.4.zip
└── ...
```

**Configuration**: `custom-package-repository-config.json`

**Single Package Locations**:
```json
{
  "single-package-locations": [
    {
      "file-type": "zipfile",
      "package-name": "canopy/browser",
      "version": "1.0.2",
      "url": "file:///home/quinten/fh/canopy/canopy-package-overrides/canopy-browser-1.0.2.zip",
      "hash-type": "sha-1",
      "hash": "generated"
    }
  ]
}
```

**Implementation**: `packages/canopy-terminal/src/LocalPackage.hs`

**LocalPackage Module Features**:
```haskell
module LocalPackage where

data Args
  = Setup  -- Setup canopy-package-overrides directory
  | AddPackage !Pkg.Name !Version.Version !FilePath  -- Add local package
  | Package !FilePath !FilePath  -- Create ZIP from source

run :: Args -> () -> IO ()
```

**Workflow**:
1. **Setup Directory**:
   ```bash
   # Creates canopy-package-overrides/ with README
   canopy local-package setup
   ```

2. **Add Local Package**:
   ```bash
   canopy local-package add-local canopy/html 1.0.0 /path/to/package
   ```

   This:
   - Copies source files to `canopy-package-overrides/canopy-html-1.0.0/`
   - Creates ZIP archive
   - Calculates SHA-1 hash
   - Writes `.sha1` file
   - Prints configuration snippet

3. **Update Configuration**:
   Add to `custom-package-repository-config.json`:
   ```json
   {
     "file-type": "zipfile",
     "package-name": "canopy/html",
     "version": "1.0.0",
     "url": "file:///absolute/path/canopy-html-1.0.0.zip",
     "hash-type": "sha-1",
     "hash": "abc123..."
   }
   ```

4. **Use in Project**:
   Add to `canopy.json`:
   ```json
   {
     "dependencies": {
       "direct": {
         "canopy/html": "1.0.0"
       }
     }
   }
   ```

### 2.2 Custom Repositories

#### ✅ **Repository Configuration**

**Repository Types**:
```json
{
  "repositories": [
    {
      "repository-type": "package-server-with-standard-canopy-v0.19-package-server-api",
      "repository-url": "https://package.canopy-lang.org",
      "repository-local-name": "standard-canopy-repository"
    },
    {
      "repository-type": "package-server-with-standard-canopy-v0.19-package-server-api",
      "repository-url": "https://package.elm-lang.org",
      "repository-local-name": "elm-fallback-repository"
    }
  ]
}
```

**Implementation**:
- `packages/canopy-terminal/src/Canopy/CustomRepositoryData.hs`
- `packages/canopy-terminal/src/Deps/CustomRepositoryDataIO.hs`

**Repository Data Types**:
```haskell
type RepositoryLocalName = Text.Text
type RepositoryAuthToken = Text.Text
type RepositoryUrl = Text.Text

data CustomSingleRepositoryData
  = DefaultPackageServerRepoData
      { _defaultPackageServerRepoLocalName :: !RepositoryLocalName
      , _defaultPackageServerRepoUrl :: !RepositoryUrl
      , _defaultPackageServerRepoAuthToken :: !(Maybe RepositoryAuthToken)
      }
  | PZRPackageServerRepoData  -- Custom repository type
      { ... }
```

### 2.3 Publishing Workflow

#### ✅ **Publish Command**

**Command**: `canopy publish [repository-url]`

**Implementation**: `packages/canopy-terminal/src/Publish.hs`

**Features**:
- Publishes to custom repositories
- Validates package structure
- Calculates version bumps
- Git integration

**Usage**:
```bash
canopy publish                                   # Publish to default repo
canopy publish https://my-repo.example.com       # Custom repository
```

### 2.4 What's Missing

#### ❌ **No `canopy link` Command**

**Elm Ecosystem Equivalent**: None (Elm doesn't have this either)

**Similar Tools in Other Languages**:
- `npm link` - Create symlinks for local development
- `cargo install --path .` - Install local package
- `go mod replace` - Redirect to local module

**Gap**: No easy way to link packages for development
- Current workaround: Manual ZIP creation + override configuration
- No automatic dependency resolution for linked packages
- No workspace/monorepo support

**What Would Be Needed**:
```bash
# Proposed workflow (NOT IMPLEMENTED)
canopy link /path/to/local/package       # Link package for development
canopy link --list                       # Show linked packages
canopy unlink canopy/html                # Unlink package
```

#### ❌ **No Workspace Support**

**Other Language Examples**:
- `npm workspaces` - Monorepo management
- `cargo workspaces` - Rust multi-package projects
- `go workspaces` - Multi-module development

**Gap**: No built-in multi-package project support
- Can't develop multiple packages together easily
- No shared dependency resolution
- Each package must be separately configured

---

## 3. CLI Commands Summary

### 3.1 Available Commands

**Source**: `app/Main.hs` and `packages/canopy-terminal/src/CLI/Commands.hs`

```haskell
createAllCommands :: [Terminal.Command]
createAllCommands =
  [ createReplCommand        -- Interactive REPL
  , createInitCommand        -- Initialize new project
  , createReactorCommand     -- Development server
  , createMakeCommand        -- Compile code
  , createFFITestCommand     -- Test FFI functions
  , createInstallCommand     -- Install packages
  , createBumpCommand        -- Version management
  , createDiffCommand        -- API change detection
  , createPublishCommand     -- Publish packages
  ]
```

#### **1. canopy init**
```bash
canopy init
```
- Creates `canopy.json` configuration
- Initializes new Canopy project
- Provides getting started guidance

**Flags**: None

#### **2. canopy repl**
```bash
canopy repl
canopy repl --interpreter node
canopy repl --no-colors
```
- Interactive programming session
- Evaluate expressions
- Import modules

**Flags**:
- `--interpreter PATH` - Alternate JS interpreter
- `--no-colors` - Disable ANSI colors

#### **3. canopy reactor**
```bash
canopy reactor
canopy reactor --port 3000
```
- Development server with file browser
- Click-to-compile interface
- Serves at `http://localhost:8000`

**Flags**:
- `--port PORT` - Custom port number

#### **4. canopy make**
```bash
canopy make src/Main.can
canopy make src/Main.can --output=app.js
canopy make src/Main.can --optimize --debug
canopy make src/Main.can --watch --verbose
```
- Compile Canopy to JavaScript or HTML
- Production optimization
- Debug mode with time-travel

**Flags**:
- `--debug` - Enable time-travelling debugger
- `--optimize` - Production optimizations
- `--watch` - File watching mode
- `--output=PATH` - Custom output path
- `--report=json` - JSON error reports
- `--docs=PATH` - Generate documentation JSON
- `--verbose` - Detailed compilation logs

#### **5. canopy test-ffi**
```bash
canopy test-ffi
canopy test-ffi --generate --output tests/
canopy test-ffi --watch
canopy test-ffi --validate-only
```
- Test FFI function contracts
- Generate test files
- Property-based testing

**Flags**:
- `--generate` - Generate tests without running
- `--output=DIR` - Output directory
- `--watch` - Watch for changes
- `--validate-only` - Contract validation only
- `--verbose` - Detailed output
- `--property-runs=N` - Property test iterations
- `--browser` - Run in browser

#### **6. canopy install**
```bash
canopy install
canopy install canopy/http
canopy install elm/json
```
- Install packages from repositories
- Resolve dependencies
- Update `canopy.json`

**Flags**: None

#### **7. canopy publish**
```bash
canopy publish
canopy publish https://my-repo.example.com
```
- Publish package to repository
- Validate package structure
- Git integration

**Flags**: None

#### **8. canopy bump**
```bash
canopy bump
```
- Analyze API changes
- Determine version increment
- Follow semantic versioning

**Flags**: None

#### **9. canopy diff**
```bash
canopy diff                           # Code vs latest
canopy diff 2.0.0                     # Code vs specific version
canopy diff 1.0.0 2.0.0               # Local package comparison
canopy diff canopy/html 1.0.0 2.0.0  # Global package comparison
```
- Detect API changes
- Compare package versions
- Upgrade planning

**Flags**: None

### 3.2 Terminal Implementation

**Framework**: Custom terminal framework

**Location**: `packages/canopy-terminal/impl/Terminal/`

**Key Modules**:
```
Terminal/
├── Command.hs      # Command definitions
├── Helpers.hs      # Parser helpers
├── Args.hs         # Argument parsing
└── Flags.hs        # Flag parsing
```

**Parser Infrastructure** (`CLI/Parsers.hs`):
```haskell
-- Reusable parsers
createPortParser :: Terminal.Parser Int
createInterpreterParser :: Terminal.Parser FilePath
outputParser :: Terminal.Parser FilePath
propertyRunsParser :: Terminal.Parser Int
```

**Documentation** (`CLI/Documentation.hs`):
```haskell
createIntroduction :: String  -- CLI intro text
createOutro :: String          -- Help footer
reflowText :: String -> Doc    -- Text formatting
stackDocuments :: [Doc] -> Doc -- Document composition
```

---

## 4. Missing Features Compared to Elm

### 4.1 Developer Tooling Gaps

| Feature | Elm | Canopy | Status |
|---------|-----|--------|--------|
| Code formatter | ✅ `elm-format` | ❌ None | **MISSING** |
| Test runner | ✅ `elm-test` | ⚠️ `test-ffi` only | **PARTIAL** |
| Linter | ✅ `elm-analyse` | ❌ None | **MISSING** |
| Doc viewer | ✅ `elm reactor` | ⚠️ JSON only | **PARTIAL** |
| Package search | ✅ package.elm-lang.org | ✅ package.canopy-lang.org | ✅ |
| REPL | ✅ `elm repl` | ✅ `canopy repl` | ✅ |
| Dev server | ✅ `elm reactor` | ✅ `canopy reactor` | ✅ |
| Package install | ✅ `elm install` | ✅ `canopy install` | ✅ |
| Local packages | ❌ None | ⚠️ Manual override | **PARTIAL** |

### 4.2 What Canopy Has That Elm Doesn't

| Feature | Canopy | Elm | Advantage |
|---------|--------|-----|-----------|
| FFI testing | ✅ `canopy test-ffi` | ❌ None | **CANOPY** |
| Custom repositories | ✅ Full support | ❌ None | **CANOPY** |
| Local overrides | ✅ ZIP-based | ❌ None | **CANOPY** |
| Watch mode | ✅ `--watch` flag | ❌ External tool | **CANOPY** |
| Verbose logging | ✅ `--verbose` | ❌ Limited | **CANOPY** |

### 4.3 Quality-of-Life Features Needed

Based on roadmap analysis (`plans/roadmap.md`):

**Phase I Priorities** (Roadmap excerpt):
```markdown
1. **🔧 Integrated Tooling** - Format, test, review built into compiler
   Status: ❌ NOT IMPLEMENTED

2. **📦 Evolved Module System** - Improved imports, namespaces
   Status: 🔄 IN PROGRESS (package migration)

3. **🔧 Advanced Development Features** - Hot reloading, better debugging
   Status: ⚠️ PARTIAL (reactor exists, no hot reload)
```

---

## 5. Recommendations

### 5.1 High Priority - Integrated Tooling

#### **1. Implement `canopy format`**

**Rationale**: Most requested feature in functional language communities

**Implementation Path**:
```haskell
-- New module: packages/canopy-terminal/src/Format.hs
module Format (run, Flags(..)) where

data Flags = Flags
  { _validate :: Bool     -- Check only, don't modify
  , _stdin :: Bool        -- Read from stdin
  , _yes :: Bool          -- Auto-accept changes
  }

run :: [FilePath] -> Flags -> IO ()
run files flags = do
  -- Parse Canopy source
  -- Apply formatting rules
  -- Write back or show diff
```

**Features**:
- Parse `.can` files to AST
- Apply consistent formatting
- Configurable via `.canopy-format.yaml`
- Integration with editor plugins

**Similar to**:
- `elm-format` for Elm
- `rustfmt` for Rust
- `gofmt` for Go

#### **2. Implement `canopy test`**

**Current Gap**: `test-ffi` only tests FFI, not user code

**Proposed Design**:
```haskell
-- New module: packages/canopy-terminal/src/Test.hs
module Test (run, Flags(..)) where

data Flags = Flags
  { _watch :: Bool          -- Watch mode
  , _fuzz :: Maybe Int      -- Fuzz test iterations
  , _seed :: Maybe Int      -- Random seed
  , _compiler :: FilePath   -- Canopy compiler path
  , _report :: ReportType   -- Output format
  }

run :: [FilePath] -> Flags -> IO ()
```

**Features**:
- Discover test modules automatically
- Run test suites via `Test` module
- Property-based testing with QuickCheck-style API
- Watch mode for TDD workflow
- TAP/JSON output for CI

**Test Module Convention**:
```elm
-- tests/UtilsTest.can
module UtilsTest exposing (suite)

import Test exposing (Test, describe, test, fuzz)
import Expect
import Utils

suite : Test
suite =
  describe "Utils module"
    [ test "addition works" <|
        \_ -> Expect.equal 4 (Utils.add 2 2)
    , fuzz int "addition is commutative" <|
        \x y -> Expect.equal (Utils.add x y) (Utils.add y x)
    ]
```

#### **3. Implement `canopy lint`**

**Purpose**: Enforce code quality and style

**Proposed Rules**:
- Unused imports
- Unused variables
- Missing type signatures
- Inconsistent naming
- Complexity warnings
- Accessibility issues (for HTML)

**Configuration**: `.canopy-lint.yaml`
```yaml
rules:
  - no-unused-imports: error
  - no-unused-variables: warn
  - require-type-signatures: error
  - max-function-length: 50
  - naming-conventions:
      functions: camelCase
      types: PascalCase
      modules: PascalCase
```

### 5.2 Medium Priority - Local Development

#### **4. Implement `canopy link`**

**Purpose**: Simplify local package development

**Workflow**:
```bash
# In package directory
cd ~/packages/my-utils
canopy link

# In application directory
cd ~/apps/my-app
canopy link my-username/my-utils

# Use in canopy.json
{
  "dependencies": {
    "direct": {
      "my-username/my-utils": "1.0.0"  # Resolves to linked version
    }
  }
}
```

**Implementation**:
- Maintain link registry in `~/.canopy/links/`
- Symlink or copy package during dependency resolution
- Auto-detect changes for hot reloading

#### **5. Workspace Support**

**Purpose**: Multi-package monorepo development

**Configuration**: `canopy-workspace.json`
```json
{
  "workspace": {
    "members": [
      "packages/core",
      "packages/http",
      "packages/json",
      "apps/demo"
    ],
    "shared-dependencies": {
      "elm/core": "1.0.5"
    }
  }
}
```

**Features**:
- Shared dependency resolution
- Build all packages with one command
- Cross-package linking automatic
- Version synchronization

### 5.3 Low Priority - Documentation

#### **6. Enhance Documentation Preview**

**Current**: `--docs` flag generates JSON

**Needed**:
- HTML documentation generation
- Built-in doc server (`canopy docs --serve`)
- Search functionality
- Cross-package linking
- Example highlighting

**Integration with Reactor**:
```bash
canopy reactor          # Now shows docs tab
# Navigate to http://localhost:8000/docs
```

---

## 6. Implementation Priorities

### Tier 1 - Essential Developer Experience (3 months)

1. **`canopy format`** - Code formatting (4 weeks)
   - Parser integration
   - Formatting rules engine
   - Editor plugin support

2. **`canopy test`** - Test runner (6 weeks)
   - Test framework design
   - Discovery mechanism
   - Reporter implementations

3. **`canopy lint`** - Code linting (4 weeks)
   - Rule engine
   - Configuration system
   - Auto-fix capability

### Tier 2 - Local Development Workflow (2 months)

4. **`canopy link`** - Package linking (3 weeks)
   - Link registry
   - Dependency resolution integration
   - Change detection

5. **Workspace Support** - Monorepo tooling (5 weeks)
   - Workspace configuration
   - Shared dependency resolution
   - Build orchestration

### Tier 3 - Polish & Refinement (1 month)

6. **Documentation Enhancement** (2 weeks)
   - HTML doc generation
   - Search functionality
   - Reactor integration

7. **Watch Mode Improvements** (2 weeks)
   - Faster rebuilds
   - Better error reporting
   - Hot reloading (HMR)

---

## 7. Codebase Entry Points

### For Implementing New Commands

**1. Add Command Definition**:
```haskell
-- File: packages/canopy-terminal/src/CLI/Commands.hs

createFormatCommand :: Command
createFormatCommand =
  Terminal.Command "format" Terminal.Uncommon details example args flags Format.run
```

**2. Create Handler Module**:
```haskell
-- File: packages/canopy-terminal/src/Format.hs

module Format (run, Flags(..)) where

data Flags = Flags { ... }

run :: [FilePath] -> Flags -> IO ()
run files flags = ...
```

**3. Register in Main**:
```haskell
-- File: app/Main.hs

import qualified Format

createAllCommands :: [Terminal.Command]
createAllCommands =
  [ ...
  , createFormatCommand
  ]
```

**4. Update Cabal File**:
```cabal
-- File: canopy.cabal or package.yaml

library
  exposed-modules:
    ...
    Format
```

### Key Source Locations

| Component | Location | Description |
|-----------|----------|-------------|
| CLI Entry | `app/Main.hs` | Application entry point |
| Commands | `packages/canopy-terminal/src/CLI/Commands.hs` | Command definitions |
| Parsers | `packages/canopy-terminal/src/CLI/Parsers.hs` | Argument parsers |
| Terminal | `packages/canopy-terminal/impl/Terminal/` | Terminal framework |
| Builder | `packages/canopy-builder/src/` | Compilation orchestration |
| Compiler | `packages/canopy-core/src/` | Core compiler logic |
| Tests | `test/` | Test infrastructure |

---

## 8. Conclusion

### Current State Summary

**Strengths**:
- ✅ Excellent internal test infrastructure
- ✅ Comprehensive CLI with good documentation
- ✅ Local package override system works
- ✅ Custom repository support
- ✅ FFI testing capability
- ✅ Watch mode for development

**Critical Gaps**:
- ❌ No code formatter (`canopy format`)
- ❌ No general test runner (`canopy test`)
- ❌ No linter for Canopy code (`canopy lint`)
- ❌ No package linking (`canopy link`)
- ⚠️ Limited documentation tooling

### Roadmap Alignment

The roadmap (`plans/roadmap.md`) correctly identifies **Integrated Tooling** as Phase I Priority #1:

> **Phase I: Foundation** - "Zero-setup development with integrated tooling"
>
> 1. **🔧 Integrated Tooling** - Format, test, review built into compiler (no tool version hell)

**Current Implementation Status**: 🔴 **NOT STARTED**

### Next Steps

1. **Immediate** (Week 1-2):
   - Design `canopy format` specification
   - Prototype formatting engine with AST integration

2. **Short-term** (Weeks 3-8):
   - Implement `canopy format` command
   - Design `canopy test` framework
   - Create test discovery mechanism

3. **Medium-term** (Weeks 9-16):
   - Implement `canopy test` runner
   - Design `canopy lint` rules engine
   - Implement `canopy link` for local packages

### Developer Experience Impact

Implementing these tools will:
- **Reduce friction** - No external tools to install/maintain
- **Improve consistency** - Automated formatting across teams
- **Enable TDD** - Fast test feedback loop
- **Simplify development** - Local package linking for monorepos
- **Match expectations** - Parity with modern language tooling

---

## Appendix A: Commands Not Found

Commands that might be expected but **do not exist**:

- `canopy format` - Code formatting
- `canopy lint` - Code linting
- `canopy test` - General test runner
- `canopy docs` - Documentation viewer
- `canopy link` - Local package linking
- `canopy build` - Build alias (use `make`)
- `canopy check` - Type check only (use `make`)
- `canopy clean` - Clear build artifacts
- `canopy upgrade` - Upgrade dependencies

## Appendix B: Example canopy.json

**Minimal Application**:
```json
{
  "type": "application",
  "source-directories": ["src"],
  "canopy-version": "0.19.1",
  "dependencies": {
    "direct": {
      "elm/core": "1.0.5"
    },
    "indirect": {}
  },
  "test-dependencies": {
    "direct": {},
    "indirect": {}
  }
}
```

**With Local Overrides**:
```json
{
  "type": "application",
  "source-directories": ["src"],
  "canopy-version": "0.19.1",
  "dependencies": {
    "direct": {
      "canopy/html": "1.0.0"
    },
    "indirect": {}
  },
  "zokka-package-overrides": []
}
```

Then configure `custom-package-repository-config.json` for local package locations.

---

**Research Completed**: 2025-11-09
**Total Files Analyzed**: 50+
**Key Modules Reviewed**: 25+
**Lines of Code Inspected**: ~15,000
