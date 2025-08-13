# Refactor Prompt — Canopy Compiler Coding Guidelines (Non-Negotiable)

**Task:**
Please refactor the module and all related sub-modules: `$ARGUMENTS`.

- **Target**: Primary module and all sub-modules (e.g., `Make.hs` + `Make/*.hs`)
- **Standards**: Follow **CLAUDE.md guidelines** exactly - all rules are **non-negotiable**
- **Quality**: Code must achieve gold standard compliance with comprehensive documentation
- **Architecture**: Apply modular design patterns from exemplar modules

---

## Refactoring Strategy & Architecture

### Modular Design Patterns

**Primary Module Structure:**

```haskell
-- Main orchestration module (e.g., Make.hs, Publish.hs)
module ModuleName
  ( -- * Core Types (re-exported from Types module)
    MainType (..),
    ConfigType (..),

    -- * Main Interface
    run,

    -- * Sub-functionality (re-exported from specialized modules)
    parseConfig,
    validateInput,
    processData,
  ) where
```

**Sub-Module Architecture:**

```
ModuleName/
├── Types.hs          -- Core types, lenses, data structures
├── Environment.hs    -- Environment setup and validation
├── Parser.hs         -- Input parsing and validation
├── Validation.hs     -- Business logic validation
├── Processing.hs     -- Core processing logic
└── Output.hs         -- Output generation and formatting
```

---

## Systematic Refactoring Process

### 1. **Architectural Analysis**

**Module Scope Assessment:**

- Map public API surface and dependencies
- Identify single vs. multiple responsibilities
- Document current import patterns and lens usage
- Analyze function complexity and size distribution

**Modularization Strategy:**

- Extract specialized concerns into focused sub-modules
- Create `Types.hs` for data structures and lenses
- Separate pure and effectful operations
- Design clear interfaces between modules

### 2. **CLAUDE.md Compliance Audit**

**Non-Negotiable Violations (Must Fix):**

❌ **Function Constraints**:

- Functions >15 lines (extract helpers)
- Functions >4 parameters (use records/newtypes)
- Branching complexity >4 (factor conditions)

❌ **Import Violations**:

- Unqualified function imports
- Abbreviated aliases (`as M`, `as DD`)
- Wrong qualification patterns

❌ **Record Access**:

- Record-dot syntax usage (`record.field`)
- Missing lens definitions and usage
- Direct record updates (`record { field = value }`)

❌ **Documentation**:

- Missing module-level Haddock docs
- Undocumented public functions
- Missing examples and `@since` tags

❌ **Code Quality**:

- Logic duplication (DRY violations)
- Multiple responsibilities per module
- Inadequate error handling

### 3. **Systematic Code Transformation**

**Import Standardization:**

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- | Module purpose and functionality description.
--
-- Comprehensive module overview with:
-- - Key responsibilities and features
-- - Architecture and sub-module organization
-- - Usage examples and common patterns
-- - Integration points and dependencies
--
-- @since 0.19.1
module ModuleName
  ( -- * Types
    TypeName (..),
    ConfigType (..),

    -- * Main Interface
    run,
    process,

    -- * Lenses (re-exported from Types)
    fieldLens,
    configLens,
  ) where

-- MANDATORY: Types unqualified, functions qualified (DO NOT INCLUDE COMMENTS LIKE THIS)
import Control.Lens ((&), (.~), (^.), makeLenses)
import qualified Control.Monad.IO.Class as IO
import qualified Data.Text as Text
import Data.Time (UTCTime)
import qualified Data.Time as Time

-- Local modules with selective type imports
import ModuleName.Types
  ( TypeName (..),
    ConfigType (..),
    fieldLens,
    configLens
  )
import qualified ModuleName.Environment as Environment
import qualified ModuleName.Processing as Processing
```

**Function Size Management:**

```haskell
-- BEFORE: Violates size limit
processLargeFunction :: Config -> Input -> IO (Either Error Result)
processLargeFunction config input = do
  -- 20+ lines of mixed concerns
  validation <- validateInput input
  -- complex processing logic
  -- error handling
  -- output generation

-- AFTER: Properly decomposed
processInput :: Config -> Input -> IO (Either Error Result)
processInput config input =
  validateInput input
    >>= processValidatedInput config
    >>= generateOutput

validateInput :: Input -> IO (Either Error ValidatedInput)
processValidatedInput :: Config -> ValidatedInput -> IO (Either Error ProcessedData)
generateOutput :: ProcessedData -> IO (Either Error Result)
```

**Lens Integration:**

```haskell
-- Types.hs
data BuildContext = BuildContext
  { _bcStyle :: !Style
  , _bcRoot :: !FilePath
  , _bcDetails :: !Details
  , _bcMode :: !BuildMode
  }
makeLenses ''BuildContext

-- Usage (MANDATORY pattern)
updateContext :: BuildContext -> Details -> BuildContext
updateContext ctx details = ctx & bcDetails .~ details

getContextRoot :: BuildContext -> FilePath
getContextRoot ctx = ctx ^. bcRoot
```

### 4. **Documentation Excellence**

**Module Documentation Template:**

```haskell
-- | [Module Name] - [Brief Purpose]
--
-- [Detailed description of module functionality, architecture, and design decisions]
--
-- == Key Features
--
-- * Feature 1 - Description and benefits
-- * Feature 2 - Implementation approach
-- * Feature 3 - Integration patterns
--
-- == Architecture
--
-- This module follows the modular design pattern:
--
-- * 'Types' - Core data structures and lenses
-- * 'Environment' - Setup and configuration
-- * 'Processing' - Business logic implementation
-- * 'Output' - Result generation and formatting
--
-- == Usage Examples
--
-- @
-- config <- Environment.setup defaultFlags
-- result <- run config ["input.txt"]
-- case result of
--   Right output -> putStrLn "Success"
--   Left err -> reportError err
-- @
--
-- == Error Handling
--
-- All functions use rich error types:
--
-- * 'ValidationError' - Input validation failures
-- * 'ProcessingError' - Business logic errors
-- * 'OutputError' - Generation and formatting errors
--
-- @since 0.19.1
module ModuleName
```

**Function Documentation Pattern:**

```haskell
-- | Process input data through the complete pipeline.
--
-- Performs validation, processing, and output generation in sequence.
-- Each step can fail independently with appropriate error types.
--
-- The processing pipeline:
--
-- 1. 'validateInput' - Check input format and constraints
-- 2. 'processValidatedInput' - Apply business logic
-- 3. 'generateOutput' - Create final result
--
-- ==== Examples
--
-- >>> config <- Environment.defaultConfig
-- >>> processInput config (InputData "test")
-- Right (OutputData "processed: test")
--
-- >>> processInput config (InvalidInput)
-- Left (ValidationError "Invalid input format")
--
-- ==== Error Conditions
--
-- Returns 'Left' for:
--   * Input validation failures
--   * Processing logic errors
--   * Output generation issues
--
-- @since 0.19.1
processInput
  :: Config
  -- ^ Processing configuration
  -> Input
  -- ^ Input data to process
  -> IO (Either Error Result)
  -- ^ Processed result or error
```

### 5. **Comprehensive Testing Integration**

**Test Creation Strategy:**

```bash
# Generate tests for all refactored modules
/test ModuleName.hs         # Unit tests
/test ModuleName/Types.hs   # Type and lens tests
/test ModuleName/Parser.hs  # Parser validation tests

# Ensure comprehensive coverage
make test-coverage          # Target ≥80% coverage
make test-match PATTERN="ModuleName"  # Run specific tests
```

**Testing Requirements:**

- Unit tests for all public functions
- Property tests for laws and invariants
- Integration tests for module interactions
- Golden tests for deterministic outputs
- Error condition coverage for all failure paths

### 6. **Quality Validation Pipeline**

**Sequential Validation Steps:**

```bash
# 1. Code Quality
make lint                   # HLint compliance check
make format                 # Ormolu formatting
hlint -h .hlint.yaml ModuleName.hs  # Module-specific check

# 2. Build Verification
make build                  # Compilation success
stack ghci ModuleName       # Module loading test

# 3. Test Validation
make test                   # Full test suite
make test-coverage          # Coverage analysis (≥80%)
make test-match PATTERN="ModuleName"  # Module-specific tests

# 4. Documentation Build
stack haddock               # Documentation generation
```

### 7. **Agent-Driven Compliance Validation**

**Multi-Stage Agent Verification:**

**Stage 1: Code Structure Analysis**

- Function size and complexity verification
- Import pattern compliance checking
- Lens usage validation
- Documentation completeness audit

**Stage 2: Architecture Assessment**

- Single responsibility principle adherence
- Module boundaries and interfaces
- Error handling patterns
- Type safety and robustness

**Stage 3: Integration Validation**

- Sub-module coordination
- Test coverage and quality
- Build system integration
- Performance implications

### 8. **Version Control Integration**

**Conventional Commit Structure:**

```bash
refactor(module): apply CLAUDE.md guidelines and modularize [system]

- Extract [N] specialized sub-modules for focused responsibilities
- Apply mandatory import qualification patterns throughout
- Replace record-dot syntax with lens operations
- Reduce [N] functions to meet size/complexity limits
- Add comprehensive Haddock documentation with examples
- Achieve [X]% test coverage with unit/property/integration tests
- Validate full CLAUDE.md compliance via agent analysis

BREAKING CHANGE: Module interface updated with new sub-module architecture
```

---

## Quality Benchmarks & Compliance

### **Gold Standard Requirements:**

1. **Function Design**: All functions ≤15 lines, ≤4 parameters, ≤4 branches
2. **Import Standards**: Mandatory qualification patterns applied consistently
3. **Lens Integration**: Zero record-dot syntax, comprehensive lens usage
4. **Documentation**: Complete Haddock docs with examples and error conditions
5. **Modularity**: Clear single responsibility with specialized sub-modules
6. **Testing**: ≥80% coverage with unit/property/integration/golden tests
7. **Error Handling**: Rich error types with comprehensive validation
8. **Performance**: Efficient implementation without optimization sacrificing clarity

### **Reference Excellence Examples:**

**Modular Architecture Exemplars:**

- `terminal/src/Make.hs` + `terminal/src/Make/*.hs` - Build system modularization
- `terminal/src/Publish.hs` + `terminal/src/Publish/*.hs` - Publishing workflow
- `terminal/src/Repl.hs` + `terminal/src/Repl/*.hs` - REPL implementation

**Documentation & Standards:**

- `terminal/src/Make/Types.hs` - Comprehensive type documentation
- `terminal/src/Publish/Environment.hs` - Environment setup patterns
- `terminal/src/Make/Parser.hs` - Input parsing and validation

**Testing Patterns:**

- `test/Unit/Parse/PatternTest.hs` - Unit test excellence
- `test/Property/Data/NameProps.hs` - Property test patterns
- `test/Golden/JsGenGolden.hs` - Golden test architecture

---

## Progressive Refactoring Checklist

### **Pre-Refactoring Analysis:**

- [ ] Module scope and responsibility analysis complete
- [ ] Current violation inventory documented
- [ ] Modularization strategy designed
- [ ] Test strategy planned

### **Code Transformation:**

- [ ] Import patterns standardized (types unqualified, functions qualified)
- [ ] Function size/complexity limits enforced (≤15 lines, ≤4 params, ≤4 branches)
- [ ] Record-dot syntax eliminated, lenses implemented
- [ ] Logic duplication removed, DRY principle applied
- [ ] Single responsibility principle enforced per module

### **Documentation Excellence:**

- [ ] Comprehensive module-level Haddock documentation
- [ ] All public functions documented with examples and error conditions
- [ ] `@since` tags applied consistently
- [ ] Architecture and design decisions explained

### **Testing & Quality:**

- [ ] Unit tests created/updated for all public functions
- [ ] Property tests implemented for laws and invariants
- [ ] Integration tests covering module interactions
- [ ] Test coverage ≥80% verified
- [ ] All build commands pass (lint, format, test-coverage)

### **Validation & Integration:**

- [ ] Agent validation confirms full CLAUDE.md compliance
- [ ] Sub-modules properly coordinated and tested
- [ ] Documentation builds successfully
- [ ] Performance implications assessed
- [ ] Conventional commit message prepared
