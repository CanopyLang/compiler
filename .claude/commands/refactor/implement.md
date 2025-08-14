# Refactor Implementation — CLAUDE.md Systematic Transformation

**Task:**
Execute systematic refactoring implementation based on analysis output: `$ARGUMENTS`.

- **Input**: Analysis results from `refactor/analyze.md` execution
- **Foundation**: Apply all violations and recommendations from analysis
- **Standards**: Enforce all CLAUDE.md guidelines systematically
- **Process**: Step-by-step transformation addressing each identified issue
- **Quality**: Achieve gold standard compliance

**Expected Input Format:**
```
Analysis Results for Module: [ModuleName]
Compliance Score: [X]/100

Critical Violations:
- Function size violations: [list]
- Import pattern issues: [list]
- Record access violations: [list]
- Missing documentation: [list]

Architectural Improvements:
- Modularization opportunities: [list]
- Performance optimizations: [list]
- Error handling enhancements: [list]
```

---

## 1. Parse Analysis Results and Setup

### Extract Analysis Information

**Parse Input Analysis:**

```bash
# Parse the analysis results from $ARGUMENTS
ANALYSIS_FILE="$ARGUMENTS"
MODULE_NAME=$(grep "Analysis Results for Module:" "$ANALYSIS_FILE" | cut -d: -f2 | xargs)
COMPLIANCE_SCORE=$(grep "Compliance Score:" "$ANALYSIS_FILE" | cut -d: -f2 | cut -d/ -f1 | xargs)

echo "Processing refactoring for module: $MODULE_NAME"
echo "Current compliance score: $COMPLIANCE_SCORE/100"

# Extract violation lists
FUNCTION_VIOLATIONS=$(sed -n '/Function size violations:/,/^- [A-Z]/p' "$ANALYSIS_FILE" | grep -v "^- [A-Z]" | tail -n +2)
IMPORT_VIOLATIONS=$(sed -n '/Import pattern issues:/,/^- [A-Z]/p' "$ANALYSIS_FILE" | grep -v "^- [A-Z]" | tail -n +2)
RECORD_VIOLATIONS=$(sed -n '/Record access violations:/,/^- [A-Z]/p' "$ANALYSIS_FILE" | grep -v "^- [A-Z]" | tail -n +2)
DOC_VIOLATIONS=$(sed -n '/Missing documentation:/,/^- [A-Z]/p' "$ANALYSIS_FILE" | grep -v "^- [A-Z]" | tail -n +2)

# Extract improvement opportunities
MODULARIZATION=$(sed -n '/Modularization opportunities:/,/^- [A-Z]/p' "$ANALYSIS_FILE" | grep -v "^- [A-Z]" | tail -n +2)
PERFORMANCE=$(sed -n '/Performance optimizations:/,/^- [A-Z]/p' "$ANALYSIS_FILE" | grep -v "^- [A-Z]" | tail -n +2)
ERROR_HANDLING=$(sed -n '/Error handling enhancements:/,/^- [A-Z]/p' "$ANALYSIS_FILE" | grep -v "^- [A-Z]" | tail -n +2)
```

### Environment Preparation

**Backup & Branching:**

```bash
# Create refactor branch with specific module name
git checkout -b refactor/$MODULE_NAME-claude-compliance

# Backup current state
cp "$MODULE_NAME.hs" "$MODULE_NAME.hs.backup"
[ -d "$MODULE_NAME" ] && cp -r "$MODULE_NAME" "$MODULE_NAME.backup"

# Verify clean working state
git status
make build
make test
```

**Analysis Integration:**

- Parse specific violations from analysis results
- Prioritize critical violations by severity
- Plan modularization based on identified opportunities
- Prepare test framework for new architecture

---

## 2. Address Import Pattern Violations

### Fix Specific Import Issues from Analysis

**Step 1: Apply Import Violations from Analysis**

```bash
# Process each import violation identified in analysis
echo "$IMPORT_VIOLATIONS" | while IFS= read -r violation; do
  if [[ -n "$violation" ]]; then
    echo "Fixing import violation: $violation"
    
    # Extract line number and violation type
    line_num=$(echo "$violation" | grep -o "line [0-9]*" | cut -d' ' -f2)
    violation_type=$(echo "$violation" | cut -d: -f2)
    
    # Apply specific fix based on violation type
    case "$violation_type" in
      *"unqualified function import"*)
        # Convert to qualified import
        sed -i "${line_num}s/import \([^(]*\)$/import qualified \1 as \1/" "$MODULE_NAME.hs"
        ;;
      *"abbreviated alias"*)
        # Expand abbreviated alias
        old_alias=$(echo "$violation" | grep -o "as [A-Z]*" | cut -d' ' -f2)
        full_name=$(echo "$violation" | grep -o "import.*qualified.*" | cut -d' ' -f3)
        sed -i "s/as $old_alias/as $full_name/g" "$MODULE_NAME.hs"
        ;;
      *"mixed qualification"*)
        # Standardize to types unqualified, functions qualified
        line_content=$(sed -n "${line_num}p" "$MODULE_NAME.hs")
        # Apply transformation based on analysis recommendation
        ;;
    esac
  fi
done
```

**Step 2: Apply Standard Pattern**

```haskell
-- BEFORE (Violations)
import Data.Map as M
import qualified Control.Monad.State as S  
import System.Exit
import qualified Data.Text

-- AFTER (CLAUDE.md Compliant)
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

-- Standard library with types unqualified + qualified functions
import Control.Lens ((&), (.~), (^.), makeLenses)
import qualified Control.Monad.State.Strict as State
import System.Exit (ExitCode)
import qualified System.Exit as Exit
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

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

**Step 3: Update Usage Throughout Module**

```haskell
-- BEFORE: Mixed patterns
result = M.lookup key inputMap
status = exitSuccess
text = T.pack "hello"

-- AFTER: Consistent qualification
result = Map.lookup key inputMap  
status = Exit.exitSuccess
text = Text.pack "hello"
```

---

## 3. Fix Function Size & Complexity Violations

### Address Specific Function Issues from Analysis

**Step 1: Process Function Violations from Analysis**

```bash
# Process each function violation identified in analysis
echo "$FUNCTION_VIOLATIONS" | while IFS= read -r violation; do
  if [[ -n "$violation" ]]; then
    echo "Fixing function violation: $violation"
    
    # Extract function name and line number from violation
    func_name=$(echo "$violation" | grep -o "Function [a-zA-Z]*" | cut -d' ' -f2)
    line_num=$(echo "$violation" | grep -o "line [0-9]*" | cut -d' ' -f2)
    violation_details=$(echo "$violation" | cut -d: -f2-)
    
    echo "Refactoring function: $func_name at line $line_num"
    echo "Issue: $violation_details"
    
    # Mark function for extraction based on violation type
    case "$violation_details" in
      *"exceeds 15 lines"*)
        echo "# TODO: Extract helper functions for $func_name (size violation)" >> refactor_tasks.txt
        ;;
      *"too many parameters"*)
        echo "# TODO: Create config record for $func_name parameters" >> refactor_tasks.txt
        ;;
      *"branching complexity"*)
        echo "# TODO: Factor out conditions for $func_name" >> refactor_tasks.txt
        ;;
    esac
  fi
done
```

**Step 2: Extract Helper Functions**

```haskell
-- BEFORE: Monolithic function (20+ lines)
processLargeFunction :: Config -> Input -> IO (Either Error Result)
processLargeFunction config input = do
  -- validation logic (5 lines)
  validation <- validateInput input
  case validation of
    Left err -> pure (Left err)
    Right validInput -> do
      -- processing logic (8 lines)
      processed <- runComplexProcessing config validInput
      case processed of
        Left procErr -> pure (Left procErr)
        Right procResult -> do
          -- output generation (7 lines)
          output <- generateOutput procResult
          case output of
            Left outErr -> pure (Left outErr)
            Right final -> pure (Right final)

-- AFTER: Decomposed functions (≤15 lines each)
processInput :: Config -> Input -> IO (Either Error Result)
processInput config input =
  validateInput input
    >>= processValidatedInput config
    >>= generateOutput

validateInput :: Input -> IO (Either Error ValidatedInput)
validateInput input
  | Text.null (input ^. inputData) = pure (Left EmptyInputError)
  | Text.length (input ^. inputData) > maxLength = pure (Left TooLargeError)
  | not (isValidFormat input) = pure (Left FormatError)
  | otherwise = pure (Right (ValidatedInput input))
  where
    maxLength = 10000

processValidatedInput :: Config -> ValidatedInput -> IO (Either Error ProcessedData)
processValidatedInput config validInput = do
  let settings = config ^. configSettings
  result <- runProcessing settings (validInput ^. validInputData)
  case result of
    Left err -> pure (Left (ProcessingError err))
    Right processed -> pure (Right (ProcessedData processed))

generateOutput :: ProcessedData -> IO (Either Error Result)
generateOutput processed = do
  let formatted = formatResult (processed ^. processedValue)
  case writeOutput formatted of
    Left err -> pure (Left (OutputError err))
    Right output -> pure (Right (Result output))
```

**Step 3: Parameter Reduction**

```haskell
-- BEFORE: Too many parameters (>4)
compile :: FilePath -> BuildMode -> OptLevel -> Bool -> [String] -> IO Result

-- AFTER: Use configuration record
data CompileConfig = CompileConfig
  { _ccFilePath :: !FilePath
  , _ccMode :: !BuildMode
  , _ccOptLevel :: !OptLevel
  , _ccDebug :: !Bool
  , _ccFlags :: ![String]
  }
makeLenses ''CompileConfig

compile :: CompileConfig -> IO Result
```

---

## 4. Fix Record Access Violations

### Address Lens Infrastructure Issues from Analysis

**Step 1: Process Record Access Violations**

```bash
# Process each record violation identified in analysis
echo "$RECORD_VIOLATIONS" | while IFS= read -r violation; do
  if [[ -n "$violation" ]]; then
    echo "Fixing record violation: $violation"
    
    # Extract line number and violation type
    line_num=$(echo "$violation" | grep -o "line [0-9]*" | cut -d' ' -f2)
    violation_type=$(echo "$violation" | cut -d: -f2)
    
    case "$violation_type" in
      *"record-dot syntax"*)
        # Replace record.field with record ^. fieldLens
        field_access=$(sed -n "${line_num}p" "$MODULE_NAME.hs" | grep -o "[a-zA-Z]*\.[a-zA-Z]*")
        if [[ -n "$field_access" ]]; then
          record_var=$(echo "$field_access" | cut -d. -f1)
          field_name=$(echo "$field_access" | cut -d. -f2)
          lens_name="${field_name}Lens"
          sed -i "${line_num}s/${field_access}/${record_var} ^. ${lens_name}/g" "$MODULE_NAME.hs"
        fi
        ;;
      *"direct record update"*)
        # Replace record { field = value } with record & fieldLens .~ value
        echo "# TODO: Replace record update at line $line_num with lens" >> refactor_tasks.txt
        ;;
      *"missing lens definitions"*)
        # Add makeLenses directive for identified types
        type_name=$(echo "$violation" | grep -o "type [a-zA-Z]*" | cut -d' ' -f2)
        echo "makeLenses ''$type_name" >> lens_additions.txt
        ;;
    esac
  fi
done
```

### Data Structure Transformation

**Step 2: Extract Types to Separate Module (if recommended by analysis)**

```haskell
-- Create ModuleName/Types.hs
{-# LANGUAGE TemplateHaskell #-}
module ModuleName.Types
  ( -- * Core Types
    ModuleConfig (..),
    ProcessingState (..),
    OutputResult (..),
    
    -- * Lenses
    mcFilePath,
    mcSettings,
    psCurrentStep,
    psErrors,
    orData,
    orMetadata
  ) where

import Control.Lens (makeLenses)
import Data.Text (Text)
import Data.Time (UTCTime)

-- | Module configuration settings.
--
-- Contains all parameters needed for module operation including
-- file paths, processing settings, and behavioral flags.
--
-- @since 0.19.1
data ModuleConfig = ModuleConfig
  { _mcFilePath :: !FilePath
  , _mcSettings :: !Settings
  , _mcDebugMode :: !Bool
  , _mcCreatedAt :: !UTCTime
  } deriving (Eq, Show)

-- | Processing state during module execution.
--
-- Tracks current step, accumulated errors, and processing metadata
-- throughout the execution pipeline.
--
-- @since 0.19.1  
data ProcessingState = ProcessingState
  { _psCurrentStep :: !ProcessingStep
  , _psErrors :: ![ProcessingError]
  , _psWarnings :: ![Warning]
  , _psStartTime :: !UTCTime
  } deriving (Eq, Show)

-- Generate lenses for all types
makeLenses ''ModuleConfig
makeLenses ''ProcessingState
```

**Step 2: Replace Record Access**

```haskell
-- BEFORE: Record-dot syntax violations
config = moduleConfig { filePath = newPath }
currentPath = moduleConfig.filePath
state = processingState { errors = newErrors }

-- AFTER: Lens-based operations
config = moduleConfig & mcFilePath .~ newPath
currentPath = moduleConfig ^. mcFilePath  
state = processingState & psErrors .~ newErrors

-- Complex updates with lens composition
updateConfig :: FilePath -> Settings -> ModuleConfig -> ModuleConfig
updateConfig path settings config = config
  & mcFilePath .~ path
  & mcSettings .~ settings
  & mcDebugMode .~ False

-- Nested access and modification
getCurrentErrors :: ProcessingState -> [ProcessingError]
getCurrentErrors state = state ^. psErrors

addError :: ProcessingError -> ProcessingState -> ProcessingState
addError err state = state & psErrors %~ (err :)

-- Conditional updates
enableDebugIfDev :: Environment -> ModuleConfig -> ModuleConfig
enableDebugIfDev env config = config
  & mcDebugMode .~ (env == Development)
```

---

## 5. Implement Modularization from Analysis

### Create Sub-Modules Based on Analysis Recommendations

**Step 1: Process Modularization Opportunities**

```bash
# Process each modularization opportunity from analysis
echo "$MODULARIZATION" | while IFS= read -r opportunity; do
  if [[ -n "$opportunity" ]]; then
    echo "Creating sub-module for: $opportunity"
    
    # Extract module type and responsibility
    module_type=$(echo "$opportunity" | cut -d: -f1 | xargs)
    responsibility=$(echo "$opportunity" | cut -d: -f2- | xargs)
    
    case "$module_type" in
      *"Types"*)
        echo "Creating $MODULE_NAME/Types.hs for data structures"
        mkdir -p "$MODULE_NAME"
        # Extract type definitions from analysis
        ;;
      *"Environment"*)
        echo "Creating $MODULE_NAME/Environment.hs for setup logic"
        # Extract environment-related functions
        ;;
      *"Parser"*)
        echo "Creating $MODULE_NAME/Parser.hs for input processing"
        # Extract parsing functions
        ;;
      *"Processing"*)
        echo "Creating $MODULE_NAME/Processing.hs for business logic"
        # Extract core processing functions
        ;;
      *"Output"*)
        echo "Creating $MODULE_NAME/Output.hs for result generation"
        # Extract output formatting functions
        ;;
    esac
  fi
done
```

**Step 2: Create Specialized Sub-Modules Based on Analysis**

```haskell
-- ModuleName/Environment.hs
module ModuleName.Environment
  ( setupEnvironment,
    validateEnvironment,
    defaultConfig
  ) where

-- | Set up the execution environment.
--
-- Initializes configuration, validates system requirements,
-- and prepares the runtime environment for module execution.
--
-- ==== Examples
--
-- >>> config <- setupEnvironment defaultFlags
-- >>> case config of
-- >>>   Right env -> putStrLn "Environment ready"
-- >>>   Left err -> reportError err
--
-- @since 0.19.1
setupEnvironment :: [Flag] -> IO (Either EnvironmentError ModuleConfig)
setupEnvironment flags = do
  currentTime <- Time.getCurrentTime
  either (pure . Left) (setupWithTime currentTime) (validateFlags flags)
  where
    setupWithTime time validFlags = do
      settings <- loadSettings validFlags
      pure (Right (ModuleConfig defaultPath settings False time))

-- ModuleName/Parser.hs  
module ModuleName.Parser
  ( parseInput,
    validateSyntax,
    ParseError (..)
  ) where

-- | Parse module input from text.
--
-- Performs lexical analysis and syntax parsing with comprehensive
-- error reporting and recovery. Handles both .can and .canopy formats.
--
-- @since 0.19.1
parseInput :: Text -> Either ParseError ParsedInput
parseInput input
  | Text.null input = Left EmptyInputError
  | not (isValidSyntax input) = Left (SyntaxError details)
  | otherwise = runParser moduleParser input
  where
    details = analyzeSyntaxErrors input

-- ModuleName/Processing.hs
module ModuleName.Processing
  ( processData,
    transformInput,
    ProcessingError (..)
  ) where

-- | Process validated input through transformation pipeline.
--
-- Applies business logic transformations, optimizations, and
-- validation steps. Each transformation can fail independently.
--
-- @since 0.19.1
processData :: ModuleConfig -> ParsedInput -> IO (Either ProcessingError ProcessedData)
processData config input = do
  let pipeline = validateInput >=> transformInput config >=> optimizeResult
  runProcessingPipeline pipeline input

-- ModuleName/Output.hs
module ModuleName.Output  
  ( generateOutput,
    formatResult,
    writeResult
  ) where

-- | Generate final output from processed data.
--
-- Creates formatted output, applies final transformations,
-- and handles multiple output formats and destinations.
--
-- @since 0.19.1
generateOutput :: ProcessedData -> IO (Either OutputError Result)
generateOutput processed = do
  formatted <- formatResult processed
  case formatted of
    Left err -> pure (Left err)
    Right output -> writeResult output
```

**Step 2: Update Main Module Interface**

```haskell
-- Main ModuleName.hs
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | [Module Name] - [Brief Purpose Description]
--
-- [Detailed module description with architecture explanation]
--
-- == Key Features
--
-- * Feature 1 - Environment setup and validation
-- * Feature 2 - Input parsing and syntax analysis  
-- * Feature 3 - Data processing and transformation
-- * Feature 4 - Output generation and formatting
--
-- == Architecture  
--
-- This module follows the modular design pattern with specialized sub-modules:
--
-- * 'Types' - Core data structures with lens support
-- * 'Environment' - Runtime environment setup and validation
-- * 'Parser' - Input parsing and syntax analysis
-- * 'Processing' - Business logic and data transformation
-- * 'Output' - Result formatting and output generation
--
-- == Usage Examples
--
-- @
-- config <- Environment.setupEnvironment defaultFlags
-- input <- readFile "input.can"
-- parsed <- Parser.parseInput input
-- result <- Processing.processData config parsed
-- Output.writeResult result
-- @
--
-- @since 0.19.1
module ModuleName
  ( -- * Core Types (re-exported from Types)
    ModuleConfig (..),
    ProcessingState (..),
    
    -- * Main Interface
    run,
    runWithConfig,
    
    -- * Configuration (re-exported from Environment)
    setupEnvironment,
    defaultConfig,
    
    -- * Lenses (re-exported from Types)
    mcFilePath,
    mcSettings,
    psCurrentStep,
    psErrors
  ) where

-- Standard imports with CLAUDE.md patterns
import Control.Lens ((&), (.~), (^.))
import qualified Control.Monad.IO.Class as IO
import Data.Text (Text)
import qualified Data.Text as Text

-- Local module imports with selective type re-exports
import ModuleName.Types
  ( ModuleConfig (..),
    ProcessingState (..),
    mcFilePath,
    mcSettings,
    psCurrentStep,  
    psErrors
  )
import qualified ModuleName.Environment as Environment
import qualified ModuleName.Parser as Parser
import qualified ModuleName.Processing as Processing
import qualified ModuleName.Output as Output

-- | Main entry point for module execution.
--
-- Sets up environment, processes input, and generates output using
-- the complete processing pipeline with comprehensive error handling.
--
-- @since 0.19.1
run :: [String] -> IO (Either Error Result)
run args = do
  config <- Environment.setupEnvironment (parseFlags args)
  case config of
    Left envErr -> pure (Left (EnvironmentError envErr))
    Right validConfig -> runWithConfig validConfig args

-- | Execute with pre-configured environment.
--
-- Processes arguments through the complete pipeline using provided
-- configuration. Suitable for integration and testing scenarios.
--
-- @since 0.19.1
runWithConfig :: ModuleConfig -> [String] -> IO (Either Error Result)
runWithConfig config args =
  processArguments args
    >>= Parser.parseInput
    >>= Processing.processData config  
    >>= Output.generateOutput
  where
    processArguments = pure . Text.unlines . map Text.pack
```

---

## 6. Address Documentation Violations

### Fix Missing Documentation from Analysis

**Step 1: Process Documentation Violations**

```bash
# Process each documentation violation identified in analysis
echo "$DOC_VIOLATIONS" | while IFS= read -r violation; do
  if [[ -n "$violation" ]]; then
    echo "Fixing documentation violation: $violation"
    
    # Extract function name and line number
    func_name=$(echo "$violation" | grep -o "Function [a-zA-Z]*" | cut -d' ' -f2)
    line_num=$(echo "$violation" | grep -o "line [0-9]*" | cut -d' ' -f2)
    violation_type=$(echo "$violation" | cut -d: -f2)
    
    case "$violation_type" in
      *"missing module documentation"*)
        echo "Adding module-level Haddock documentation"
        # Insert comprehensive module doc at top
        ;;
      *"undocumented function"*)
        echo "Adding documentation for function: $func_name at line $line_num"
        # Insert function documentation before type signature
        prev_line=$((line_num - 1))
        sed -i "${prev_line}a\\-- | [Function description needed for $func_name]" "$MODULE_NAME.hs"
        ;;
      *"missing examples"*)
        echo "Adding examples for function: $func_name"
        # Add example documentation
        ;;
      *"missing @since tags"*)
        echo "Adding version tags for function: $func_name"
        # Add @since tags
        ;;
    esac
  fi
done
```

### Comprehensive Documentation Implementation

**Step 2: Module-Level Documentation Based on Analysis**

```haskell
-- | [Module Name] - [Concise Purpose Statement]
--
-- [2-3 sentence overview of module functionality and role in system]
--
-- [Detailed description explaining:]
-- * Core responsibilities and capabilities
-- * Key algorithms and approaches used
-- * Integration patterns and dependencies
-- * Performance characteristics and considerations
--
-- == Key Features
--
-- * Feature 1 - [Description with benefits and use cases]
-- * Feature 2 - [Implementation approach and design decisions]  
-- * Feature 3 - [Integration patterns and compatibility]
-- * Feature 4 - [Performance characteristics and limitations]
--
-- == Architecture
--
-- This module implements [architectural pattern] with the following structure:
--
-- * 'Types' - Core data structures with comprehensive lens support
-- * 'Environment' - Runtime setup, validation, and configuration management
-- * 'Parser' - Input processing with robust error handling and recovery
-- * 'Processing' - Business logic implementation with pipeline architecture
-- * 'Output' - Result generation with multiple format and destination support
--
-- The design emphasizes [key design principles: modularity, type safety, performance].
--
-- == Usage Examples
--
-- === Basic Usage
--
-- @
-- -- Set up environment and process single input
-- config <- Environment.setupEnvironment defaultFlags
-- result <- runWithConfig config ["input.can"]
-- case result of
--   Right output -> putStrLn "Processing successful"
--   Left err -> reportError err
-- @
--
-- === Advanced Configuration
--
-- @
-- -- Custom configuration with specific settings
-- let customConfig = defaultConfig
--       & mcFilePath .~ "custom/path"
--       & mcSettings . settingsOptLevel .~ O2
-- result <- runWithConfig customConfig inputs
-- @
--
-- === Batch Processing
--
-- @
-- -- Process multiple inputs with shared configuration
-- config <- Environment.setupEnvironment [BatchMode, OptimizeOn]
-- results <- mapM (runWithConfig config) inputBatches
-- let (errors, outputs) = partitionEithers results
-- @
--
-- == Error Handling
--
-- All functions use structured error types for comprehensive error reporting:
--
-- * 'EnvironmentError' - Setup and configuration failures
-- * 'ParseError' - Input parsing and syntax validation errors
-- * 'ProcessingError' - Business logic and transformation failures
-- * 'OutputError' - Result generation and formatting issues
--
-- Error messages include detailed context, suggestions for resolution,
-- and structured information for programmatic handling.
--
-- == Performance Considerations
--
-- * Input processing is lazy and streaming-capable for large files
-- * Memory usage is bounded through strict evaluation in critical paths
-- * Optimization levels can be configured for different use cases
-- * Parallel processing is available for batch operations
--
-- == Thread Safety
--
-- This module is thread-safe for concurrent read operations. Write operations
-- require external synchronization. Configuration objects are immutable after
-- creation.
--
-- @since 0.19.1
module ModuleName
```

**Step 2: Function Documentation Standards**

```haskell
-- | Process input data through the complete transformation pipeline.
--
-- Performs validation, transformation, optimization, and output generation
-- in a structured pipeline with comprehensive error handling at each stage.
-- Each processing step can fail independently with detailed error information.
--
-- The processing pipeline consists of:
--
-- 1. 'validateInput' - Input format and constraint validation
-- 2. 'transformInput' - Core business logic application  
-- 3. 'optimizeResult' - Performance and size optimization
-- 4. 'generateOutput' - Final result formatting and preparation
--
-- ==== Examples
--
-- >>> config <- Environment.defaultConfig
-- >>> processInput config (InputData "test content")
-- Right (ProcessedData {_pdValue = "processed: test content", ...})
--
-- >>> processInput config (InputData "")
-- Left (ValidationError "Input cannot be empty")
--
-- >>> processInput config (MalformedInput)  
-- Left (ParseError "Invalid input format at line 1, column 5")
--
-- ==== Error Conditions
--
-- Returns 'Left' with specific error types for:
--
-- * 'ValidationError' - Input validation failures (empty, too large, invalid format)
-- * 'TransformError' - Business logic errors (unsupported operations, constraint violations)
-- * 'OptimizationError' - Optimization failures (resource limits, complexity bounds)
-- * 'OutputError' - Generation failures (format issues, write permissions)
--
-- Each error includes detailed context, suggested fixes, and structured
-- information for programmatic error handling and user reporting.
--
-- ==== Performance
--
-- * Time complexity: O(n) where n is input size
-- * Space complexity: O(1) with streaming for large inputs
-- * Memory usage: Bounded by configuration limits (default 100MB)
-- * Parallelization: Available for batch processing via 'processBatch'
--
-- ==== Thread Safety
--
-- This function is thread-safe for concurrent execution with different
-- configurations. Shared configuration objects are immutable.
--
-- @since 0.19.1
processInput
  :: ModuleConfig
  -- ^ Processing configuration with optimization settings
  -> InputData
  -- ^ Input data to process (validated format required)
  -> IO (Either ProcessingError ProcessedData)
  -- ^ Processed result or detailed error information
processInput config input = do
  validatedInput <- validateInput input
  case validatedInput of
    Left err -> pure (Left (ValidationError err))
    Right valid -> transformAndOptimize config valid
  where
    transformAndOptimize cfg validInput =
      transformInput cfg validInput
        >>= optimizeResult (cfg ^. mcOptLevel)
        >>= prepareOutput
```

---

## 7. Implement Performance and Error Handling Improvements

### Address Performance Optimizations from Analysis

**Step 1: Process Performance Improvements**

```bash
# Process each performance optimization from analysis
echo "$PERFORMANCE" | while IFS= read -r optimization; do
  if [[ -n "$optimization" ]]; then
    echo "Implementing performance optimization: $optimization"
    
    # Extract optimization type and location
    opt_type=$(echo "$optimization" | cut -d: -f1 | xargs)
    location=$(echo "$optimization" | grep -o "line [0-9]*" | cut -d' ' -f2)
    
    case "$opt_type" in
      *"String to Text"*)
        echo "Converting String usage to Text at line $location"
        # Replace String with Text imports and usage
        ;;
      *"lazy evaluation"*)
        echo "Adding strict evaluation at line $location"
        # Add BangPatterns or strict fields
        ;;
      *"inefficient concatenation"*)
        echo "Replacing ++ with efficient concatenation at line $location"
        # Replace ++ with Builder or efficient alternatives
        ;;
      *"memory leak"*)
        echo "Fixing memory leak at line $location"
        # Add strict evaluation or clear references
        ;;
    esac
  fi
done
```

### Address Error Handling Improvements

**Step 2: Process Error Handling Enhancements**

```bash
# Process each error handling improvement from analysis
echo "$ERROR_HANDLING" | while IFS= read -r improvement; do
  if [[ -n "$improvement" ]]; then
    echo "Implementing error handling improvement: $improvement"
    
    # Extract improvement type and details
    error_type=$(echo "$improvement" | cut -d: -f1 | xargs)
    details=$(echo "$improvement" | cut -d: -f2- | xargs)
    
    case "$error_type" in
      *"missing error types"*)
        echo "Adding rich error types: $details"
        # Create comprehensive error type definitions
        ;;
      *"inadequate validation"*)
        echo "Adding input validation: $details"
        # Add validation functions
        ;;
      *"poor error messages"*)
        echo "Improving error messages: $details"
        # Enhance error message content
        ;;
    esac
  fi
done
```

## 8. Test Infrastructure Creation

### Comprehensive Test Suite Implementation

**Step 1: Unit Test Framework for Refactored Module**

```haskell
-- test/Unit/ModuleNameTest.hs
{-# LANGUAGE OverloadedStrings #-}
module Test.Unit.ModuleNameTest where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import qualified ModuleName as Module
import qualified ModuleName.Types as Types
import qualified ModuleName.Environment as Environment

tests :: TestTree
tests = testGroup "ModuleName Tests"
  [ testGroup "Core Functionality"
      [ testCase "processes valid input successfully" $
          testValidInputProcessing
      , testCase "handles empty input gracefully" $
          testEmptyInputHandling
      , testCase "reports parsing errors with context" $
          testParsingErrorReporting
      ]
  , testGroup "Configuration Management"
      [ testCase "creates default configuration" $
          testDefaultConfiguration
      , testCase "validates configuration parameters" $
          testConfigurationValidation
      , testCase "handles invalid configuration gracefully" $
          testInvalidConfigurationHandling
      ]
  , testGroup "Error Handling"
      [ testCase "provides detailed error messages" $
          testDetailedErrorMessages
      , testCase "maintains error context through pipeline" $
          testErrorContextPropagation
      ]
  ]

-- Concrete test implementations
testValidInputProcessing :: Assertion
testValidInputProcessing = do
  config <- Environment.defaultConfig
  result <- Module.processInput config (Types.InputData "test content")
  case result of
    Right processed -> do
      Types._pdValue processed @?= "processed: test content"
      length (Types._pdMetadata processed) @?= 1
    Left err -> assertFailure ("Unexpected error: " ++ show err)

testEmptyInputHandling :: Assertion  
testEmptyInputHandling = do
  config <- Environment.defaultConfig
  result <- Module.processInput config (Types.InputData "")
  case result of
    Left (Types.ValidationError msg) -> 
      assertBool "Error message mentions empty input" ("empty" `isInfixOf` msg)
    _ -> assertFailure "Expected ValidationError for empty input"
```

**Step 2: Property-Based Testing**

```haskell
-- test/Property/ModuleNameProps.hs
module Test.Property.ModuleNameProps where

import Test.Tasty
import Test.Tasty.QuickCheck
import qualified ModuleName as Module
import qualified ModuleName.Types as Types

properties :: TestTree
properties = testGroup "ModuleName Properties"
  [ testProperty "processing is deterministic" $
      processingDeterminismProperty
  , testProperty "roundtrip property for serialization" $
      serializationRoundtripProperty
  , testProperty "error handling is total" $
      errorHandlingTotalityProperty
  ]

-- Property implementations
processingDeterminismProperty :: Types.InputData -> Property
processingDeterminismProperty input = monadicIO $ do
  config <- run Environment.defaultConfig
  result1 <- run (Module.processInput config input)
  result2 <- run (Module.processInput config input)
  assert (result1 == result2)

serializationRoundtripProperty :: Types.ProcessedData -> Bool
serializationRoundtripProperty processed =
  case Types.fromSerialized (Types.toSerialized processed) of
    Right restored -> restored == processed
    Left _ -> False

errorHandlingTotalityProperty :: Types.InputData -> Property
errorHandlingTotalityProperty input = monadicIO $ do
  config <- run Environment.defaultConfig
  result <- run (Module.processInput config input)
  assert (isValidResult result)
  where
    isValidResult (Right _) = True
    isValidResult (Left _) = True
```

**Step 3: Integration Testing**

```haskell
-- test/Integration/ModuleNameIntegration.hs
module Test.Integration.ModuleNameIntegration where

import Test.Tasty
import Test.Tasty.HUnit
import qualified ModuleName as Module
import qualified System.IO.Temp as Temp
import qualified Data.Text.IO as Text

integrationTests :: TestTree
integrationTests = testGroup "ModuleName Integration"
  [ testCase "end-to-end file processing" $
      testEndToEndProcessing
  , testCase "batch processing with shared configuration" $
      testBatchProcessing
  , testCase "error recovery and continuation" $
      testErrorRecoveryFlow
  ]

testEndToEndProcessing :: Assertion
testEndToEndProcessing =
  Temp.withTempDirectory "." "module-test" $ \tmpDir -> do
    let inputFile = tmpDir </> "input.can"
        outputFile = tmpDir </> "output.result"
    
    Text.writeFile inputFile "module Test exposing (..)\n\nvalue = 42"
    result <- Module.run [inputFile, "--output", outputFile]
    
    case result of
      Right _ -> do
        outputExists <- doesFileExist outputFile
        assertBool "Output file should be created" outputExists
      Left err -> assertFailure ("Processing failed: " ++ show err)
```

---

## 9. Quality Validation Pipeline

### Validate Fixes Against Analysis Results

**Step 1: Re-run Analysis to Verify Improvements**

```bash
#!/bin/bash
# validate-fixes.sh

echo "=== Validating Refactoring Against Analysis Results ==="

# Re-run analysis on refactored module
NEW_ANALYSIS="/tmp/${MODULE_NAME}_post_refactor_analysis.txt"
/refactor/analyze "$MODULE_NAME.hs" > "$NEW_ANALYSIS"

# Compare compliance scores
OLD_SCORE=$(grep "Compliance Score:" "$ANALYSIS_FILE" | cut -d: -f2 | cut -d/ -f1 | xargs)
NEW_SCORE=$(grep "Compliance Score:" "$NEW_ANALYSIS" | cut -d: -f2 | cut -d/ -f1 | xargs)

echo "Compliance Score Improvement: $OLD_SCORE/100 → $NEW_SCORE/100"

if [ "$NEW_SCORE" -gt "$OLD_SCORE" ]; then
  echo "✅ Compliance score improved by $((NEW_SCORE - OLD_SCORE)) points"
else
  echo "❌ Compliance score did not improve"
  exit 1
fi

# Check if critical violations were addressed
REMAINING_VIOLATIONS=$(grep -c "VIOLATION\|❌" "$NEW_ANALYSIS")
if [ "$REMAINING_VIOLATIONS" -eq 0 ]; then
  echo "✅ All critical violations resolved"
else
  echo "⚠️  $REMAINING_VIOLATIONS violations remain"
fi
```

**Step 2: CLAUDE.md Compliance Verification**

```bash
#!/bin/bash
# validate-compliance.sh

echo "=== CLAUDE.md Compliance Validation ==="

# Function size validation  
echo "Checking function size limits..."
violations=$(grep -n "^[a-zA-Z].*::" "$MODULE_NAME.hs" | while read line; do
  func_line=$(echo "$line" | cut -d: -f1)
  next_func=$(tail -n +$((func_line + 1)) "$MODULE_NAME.hs" | grep -n "^[a-zA-Z].*::" | head -1 | cut -d: -f1)
  if [ -z "$next_func" ]; then
    length=$(wc -l < "$MODULE_NAME.hs")
    length=$((length - func_line))
  else
    length=$((next_func - 1))
  fi
  if [ "$length" -gt 15 ]; then
    echo "VIOLATION: Function at line $func_line exceeds 15 lines ($length lines)"
  fi
done)

if [ -n "$violations" ]; then
  echo "❌ Function size violations found:"
  echo "$violations"
  exit 1
else
  echo "✅ All functions within size limits"
fi

# Import pattern validation
echo "Checking import qualification patterns..."
unqualified_imports=$(grep "^import [^(]*$" "$MODULE_NAME.hs" | grep -v "qualified" | wc -l)
abbreviated_aliases=$(grep "qualified.*as [A-Z]$\|qualified.*as [A-Z][A-Z]$" "$MODULE_NAME.hs" | wc -l)

if [ "$unqualified_imports" -gt 0 ] || [ "$abbreviated_aliases" -gt 0 ]; then
  echo "❌ Import pattern violations found"
  grep "^import [^(]*$" "$MODULE_NAME.hs" | grep -v "qualified"
  grep "qualified.*as [A-Z]$\|qualified.*as [A-Z][A-Z]$" "$MODULE_NAME.hs"
  exit 1
else
  echo "✅ All import patterns compliant"
fi

# Lens usage validation
echo "Checking lens usage patterns..."
record_dot_usage=$(grep -n "\._\|\..*=" "$MODULE_NAME.hs" | wc -l)
direct_updates=$(grep -n "{\s*.*=" "$MODULE_NAME.hs" | wc -l)

if [ "$record_dot_usage" -gt 0 ] || [ "$direct_updates" -gt 0 ]; then
  echo "❌ Record access violations found"
  grep -n "\._\|\..*=" "$MODULE_NAME.hs"
  grep -n "{\s*.*=" "$MODULE_NAME.hs"
  exit 1
else
  echo "✅ All record access uses lenses"
fi

# Documentation validation
echo "Checking documentation completeness..."
public_functions=$(grep -c "^[a-zA-Z].*::" "$MODULE_NAME.hs")
documented_functions=$(grep -B1 "^[a-zA-Z].*::" "$MODULE_NAME.hs" | grep -c "-- |")

if [ "$documented_functions" -lt "$public_functions" ]; then
  echo "❌ Documentation incomplete: $documented_functions/$public_functions functions documented"
  exit 1
else
  echo "✅ All public functions documented"
fi

echo "🎉 All CLAUDE.md compliance checks passed!"
```

**Step 2: Build and Test Validation**

```bash
# Sequential validation pipeline
make format           # Apply standard formatting
make lint            # Check code quality  
make build           # Verify compilation
make test            # Run test suite
make test-coverage   # Check coverage ≥80%
make bench           # Performance regression check
stack haddock        # Documentation build
```

**Step 3: Test Coverage Analysis**

```bash
# Generate detailed coverage report
make test-coverage

# Validate minimum coverage
coverage_percentage=$(make test-coverage | grep "expressions used" | awk '{print $1}' | sed 's/%//')
if [ "$coverage_percentage" -lt 80 ]; then
  echo "❌ Test coverage below 80%: ${coverage_percentage}%"
  exit 1
else
  echo "✅ Test coverage meets requirement: ${coverage_percentage}%"
fi

# Check for untested modules
uncovered_modules=$(make test-coverage | grep "  0%" | wc -l)
if [ "$uncovered_modules" -gt 0 ]; then
  echo "❌ Modules with 0% coverage found"
  make test-coverage | grep "  0%"
  exit 1
fi
```

---

## 9. Documentation and Examples

### Complete Documentation Generation

**Step 1: Generate Module Documentation**

```bash
# Build comprehensive documentation
stack haddock --haddock-all --haddock-hyperlink-source

# Generate usage examples
stack ghci --ghci-script examples.ghci < /dev/null > examples-output.txt

# Validate documentation links
stack haddock --haddock-all 2>&1 | grep -i "warning\|error" || echo "✅ Clean documentation build"
```

**Step 2: Create Usage Examples**

```haskell
-- examples/ModuleNameExamples.hs
{-# LANGUAGE OverloadedStrings #-}
module Examples.ModuleNameExamples where

import qualified ModuleName as Module
import qualified ModuleName.Environment as Environment
import qualified ModuleName.Types as Types

-- | Basic usage example demonstrating standard workflow.
basicUsageExample :: IO ()
basicUsageExample = do
  putStrLn "=== Basic Usage Example ==="
  
  -- Setup environment with default configuration
  config <- Environment.setupEnvironment []
  case config of
    Left envErr -> putStrLn ("Environment setup failed: " ++ show envErr)
    Right validConfig -> do
      -- Process single input
      result <- Module.processInput validConfig (Types.InputData "hello world")
      case result of
        Right processed -> do
          putStrLn ("Processed: " ++ show (Types._pdValue processed))
          putStrLn ("Metadata: " ++ show (Types._pdMetadata processed))
        Left err -> putStrLn ("Processing failed: " ++ show err)

-- | Advanced configuration example with custom settings.
advancedConfigExample :: IO ()
advancedConfigExample = do
  putStrLn "=== Advanced Configuration Example ==="
  
  -- Create custom configuration using lenses
  baseConfig <- Environment.defaultConfig
  let customConfig = baseConfig
        & Types.mcOptLevel .~ Types.O2
        & Types.mcDebugMode .~ True
        & Types.mcTimeout .~ 30
  
  -- Process with optimization
  result <- Module.processInput customConfig (Types.InputData "complex input")
  case result of
    Right processed -> putStrLn ("Optimized result: " ++ show processed)
    Left err -> putStrLn ("Error: " ++ show err)

-- | Batch processing example with error handling.
batchProcessingExample :: IO ()
batchProcessingExample = do
  putStrLn "=== Batch Processing Example ==="
  
  config <- Environment.setupEnvironment [Types.BatchMode]
  let inputs = map Types.InputData ["input1", "input2", "input3"]
  
  results <- mapM (Module.processInput config) inputs
  let (errors, successes) = partitionEithers results
  
  putStrLn ("Successful: " ++ show (length successes))
  putStrLn ("Failed: " ++ show (length errors))
  mapM_ (putStrLn . ("Error: " ++) . show) errors
```

---

## 10. Final Integration and Validation

### Complete System Validation

**Step 1: Integration Testing**

```bash
# Run complete validation suite
./validate-compliance.sh $ARGUMENTS
make build
make test
make test-coverage
make bench

# Test integration with other modules
make test-integration

# Validate performance benchmarks
make bench | grep -E "(faster|slower)" || echo "✅ No performance regressions"
```

**Step 2: Documentation Verification**

```bash
# Verify all documentation builds
stack haddock --haddock-all

# Check documentation coverage
stack haddock --haddock-all 2>&1 | grep "100%" && echo "✅ Complete documentation coverage"

# Validate examples run correctly
cd examples && stack runghc ModuleNameExamples.hs
```

**Step 3: Agent Validation**

Use specialized agents to verify compliance:

```bash
# Run comprehensive analysis agent
/refactor/analyze $ARGUMENTS

# Verify all violations addressed
grep -E "VIOLATION|❌|FAILED" analysis-output.txt | wc -l | grep "^0$" && echo "✅ All violations resolved"
```

---

## 11. Commit and Documentation

### Version Control Integration

**Step 1: Prepare Conventional Commit Based on Analysis**

```bash
# Stage all changes
git add "$MODULE_NAME.hs" "$MODULE_NAME"/

# Calculate actual improvements
VIOLATIONS_FIXED=$(echo "$FUNCTION_VIOLATIONS$IMPORT_VIOLATIONS$RECORD_VIOLATIONS$DOC_VIOLATIONS" | wc -l)
MODULES_CREATED=$(echo "$MODULARIZATION" | wc -l)
SCORE_IMPROVEMENT=$((NEW_SCORE - OLD_SCORE))

# Generate commit message following conventional commits
git commit -m "$(cat <<EOF
refactor($MODULE_NAME): apply CLAUDE.md guidelines and modularize

Analysis-driven refactoring with compliance improvement: $OLD_SCORE/100 → $NEW_SCORE/100

Violations addressed:
- Fixed $VIOLATIONS_FIXED critical CLAUDE.md violations
- Applied mandatory import qualification patterns throughout
- Replaced record-dot syntax with comprehensive lens operations  
- Reduced oversized functions to meet size/complexity limits (≤15 lines, ≤4 params)
- Added comprehensive Haddock documentation with examples and error handling

Architectural improvements:
- Extracted $MODULES_CREATED specialized sub-modules for focused responsibilities
- Implemented performance optimizations from analysis
- Enhanced error handling with rich error types
- Achieved target test coverage with unit/property/integration tests

Sub-modules created based on analysis:
$(echo "$MODULARIZATION" | sed 's/^/- /')

BREAKING CHANGE: Module interface updated with new sub-module architecture.
Public API remains compatible but internal structure completely refactored.

Compliance Score Improvement: +$SCORE_IMPROVEMENT points
EOF
)"
```

**Step 2: Update Project Documentation Based on Analysis Results**

```bash
# Update CHANGELOG.md with specific improvements
echo "## [0.19.1] - $(date +%Y-%m-%d)" >> CHANGELOG.md
echo "### Changed" >> CHANGELOG.md
echo "- Refactored $MODULE_NAME module to follow CLAUDE.md guidelines (compliance: $OLD_SCORE/100 → $NEW_SCORE/100)" >> CHANGELOG.md
echo "- Fixed $VIOLATIONS_FIXED critical violations identified in architectural analysis" >> CHANGELOG.md
echo "- Extracted $MODULES_CREATED specialized sub-modules for improved maintainability" >> CHANGELOG.md
echo "- Implemented performance optimizations and enhanced error handling" >> CHANGELOG.md

# Update module documentation index with analysis summary
echo "- [$MODULE_NAME](docs/$MODULE_NAME.md) - Analysis-driven refactoring with $SCORE_IMPROVEMENT point compliance improvement" >> docs/INDEX.md
```

**Step 3: Final Validation**

```bash
# Run final comprehensive check
make validate-release

# Verify no regressions
make test-all
make bench-regression

# Check documentation build
make docs

echo "🎉 Analysis-driven refactoring complete!"
echo "Module $MODULE_NAME compliance improved from $OLD_SCORE/100 to $NEW_SCORE/100"
echo "All $VIOLATIONS_FIXED identified violations have been addressed"
```

---

## 12. Success Criteria Checklist

### Technical Compliance ✅

- [ ] All functions ≤15 lines, ≤4 parameters, ≤4 branches
- [ ] Import qualification patterns applied consistently
- [ ] Zero record-dot syntax, comprehensive lens integration  
- [ ] Complete Haddock documentation with examples and error handling

### Architectural Quality ✅

- [ ] Clear single responsibility per module
- [ ] Specialized sub-modules with focused concerns
- [ ] Rich error types with comprehensive validation
- [ ] Clean interfaces with minimal coupling

### Testing Excellence ✅

- [ ] ≥80% test coverage across all modules
- [ ] Unit/property/integration/golden test coverage
- [ ] All error conditions tested thoroughly
- [ ] Build system integration validated

### Documentation Standard ✅

- [ ] Comprehensive module-level documentation
- [ ] All public functions documented with examples
- [ ] Architecture and design decisions explained
- [ ] Error handling patterns documented

### Process Validation ✅

- [ ] Agent compliance verification completed
- [ ] Build pipeline passes completely
- [ ] Performance benchmarks stable
- [ ] Conventional commit prepared

---

## 12. Analysis-Driven Success Verification

### Compliance Improvement Summary

**Quantified Results:**
- **Module:** $MODULE_NAME  
- **Compliance Score:** $OLD_SCORE/100 → $NEW_SCORE/100 (+$SCORE_IMPROVEMENT points)
- **Violations Fixed:** $VIOLATIONS_FIXED critical issues addressed
- **Sub-modules Created:** $MODULES_CREATED specialized modules
- **Architecture:** Fully modularized following analysis recommendations

**Critical Violations Resolved:**
- [ ] Function size/complexity violations: All oversized functions decomposed
- [ ] Import pattern issues: Mandatory qualification applied systematically  
- [ ] Record access violations: Comprehensive lens integration implemented
- [ ] Missing documentation: Complete Haddock docs with examples added

**Architectural Improvements Implemented:**
- [ ] Modularization opportunities: Specialized sub-modules created per analysis
- [ ] Performance optimizations: String→Text, strict evaluation, efficient patterns
- [ ] Error handling enhancements: Rich error types and comprehensive validation

**Quality Validation Confirmed:**
- [ ] Re-analysis shows compliance improvement
- [ ] All build commands pass (lint, format, test-coverage)
- [ ] Documentation builds successfully  
- [ ] Performance benchmarks stable or improved

**Process Validation:**
- [ ] Analysis input parsed correctly
- [ ] All identified violations systematically addressed
- [ ] Improvements quantified and verified
- [ ] Conventional commit reflects actual changes

---

**Status:** Analysis-driven implementation complete with verified CLAUDE.md compliance improvement.