# New Query-Based Compiler - Usage Guide

**Version:** 0.19.1
**Last Updated:** 2025-09-30

## Overview

The new query-based compiler provides a modern, STM-free architecture with:
- Pure functional query system
- Comprehensive debug logging
- Parallel module compilation
- Content-hash based caching
- Complete backwards compatibility

## Quick Start

### Enabling the New Compiler

```bash
# Use new compiler for single command
CANOPY_NEW_COMPILER=1 canopy make src/Main.can

# Enable for entire session
export CANOPY_NEW_COMPILER=1
canopy make src/Main.can

# Use old compiler (default)
canopy make src/Main.can
```

### Debug Logging

```bash
# Enable all debug categories
CANOPY_DEBUG=1 canopy make src/Main.can

# Enable specific categories
CANOPY_DEBUG=PARSE,TYPE canopy make src/Main.can

# Debug compiler pipeline
CANOPY_DEBUG=COMPILE_DEBUG canopy make src/Main.can

# Debug parallel compilation
CANOPY_DEBUG=WORKER_DEBUG canopy make src/Main.can
```

## Debug Categories

The compiler provides strongly-typed debug categories:

| Category | Purpose | Example Output |
|----------|---------|----------------|
| `PARSE` | Parsing operations | File parsing, syntax analysis |
| `TYPE` | Type checking | Type inference, constraint solving |
| `CODEGEN` | Code generation | JavaScript output |
| `BUILD` | Build system | Module dependencies |
| `COMPILE_DEBUG` | General compilation | Pipeline stages |
| `DEPS_SOLVER` | Dependency resolution | Package dependencies |
| `CACHE_DEBUG` | Cache operations | Hit/miss rates, invalidation |
| `QUERY_DEBUG` | Query execution | Query lifecycle |
| `WORKER_DEBUG` | Worker pool | Parallel compilation |
| `KERNEL_DEBUG` | Kernel modules | Built-in module handling |
| `FFI_DEBUG` | FFI processing | Foreign function analysis |
| `PERMISSIONS_DEBUG` | Permission validation | Security checks |

### Examples

```bash
# Parse debug
$ CANOPY_DEBUG=PARSE canopy make src/Main.can
[PARSE] Parsing module: src/Main.can
[PARSE] File content length: 1234 bytes
[PARSE] Parse success: module Main

# Type check debug
$ CANOPY_DEBUG=TYPE canopy make src/Main.can
[TYPE] Type checking module: Main
[TYPE] Constraint generation complete
[TYPE] Solving constraints...
[TYPE] Type inference succeeded

# Compilation pipeline
$ CANOPY_DEBUG=COMPILE_DEBUG canopy make src/Main.can
[COMPILE_DEBUG] Compiling module: src/Main.can
[COMPILE_DEBUG] Package: user/app
[COMPILE_DEBUG] Phase 1: Parsing
[COMPILE_DEBUG] Phase 2: Canonicalization
[COMPILE_DEBUG] Phase 3: Type Checking
[COMPILE_DEBUG] Compilation complete

# Cache statistics
$ CANOPY_DEBUG=CACHE_DEBUG canopy make src/Main.can
[CACHE_DEBUG] Cache size: 42
[CACHE_DEBUG] Cache hits: 156
[CACHE_DEBUG] Cache misses: 23
[CACHE_DEBUG] Hit rate: 87.2%
```

## Programmatic Usage

### Single Module Compilation

```haskell
import qualified New.Compiler.Driver as Driver
import qualified Canopy.Package as Pkg
import qualified Parse.Module as Parse

-- Compile a single module
compileFile :: FilePath -> IO (Either QueryError CompileResult)
compileFile path = do
  let pkg = Pkg.dummyName  -- Or actual package name
      ifaces = Map.empty    -- Dependency interfaces
      projectType = Parse.Application

  Driver.compileModule pkg ifaces path projectType
```

### Parallel Module Compilation

```haskell
import qualified New.Compiler.Driver as Driver
import qualified New.Compiler.Worker.Pool as Pool

-- Configure worker pool
let config = Pool.PoolConfig
      { poolConfigWorkers = 8        -- 8 workers
      , poolConfigQueueSize = 100    -- Task queue size
      }

-- List of modules to compile
let modules =
      [ ("src/Main.can", Parse.Application)
      , ("src/Utils.can", Parse.Application)
      , ("src/Types.can", Parse.Application)
      ]

-- Compile in parallel
results <- Driver.compileModulesParallel config pkg ifaces modules
```

### Progress Tracking

```haskell
import qualified New.Compiler.Driver as Driver
import qualified New.Compiler.Worker.Pool as Pool

-- Progress callback
let progressFn :: Pool.Progress -> IO ()
    progressFn progress = do
      let completed = Pool.progressCompleted progress
          total = Pool.progressTotal progress
          failed = Pool.progressFailed progress
      putStrLn ("Progress: " ++ show completed ++ "/" ++ show total ++ " (failed: " ++ show failed ++ ")")

-- Compile with progress
results <- Driver.compileModulesWithProgress config pkg ifaces modules progressFn
```

## Query System

### Query Engine

The query engine manages caching and execution:

```haskell
import qualified New.Compiler.Query.Engine as Engine

-- Create engine
engine <- Engine.initEngine

-- Compile with existing engine (for batch compilation)
result <- Driver.compileModuleFull engine pkg ifaces path projectType

-- Get cache statistics
cacheSize <- Engine.getCacheSize engine
hits <- Engine.getCacheHits engine
misses <- Engine.getCacheMisses engine
```

### Query Types

```haskell
-- Parse query
result <- ParseQuery.parseModuleQuery projectType filePath

-- Canonicalize query
result <- CanonQuery.canonicalizeModuleQuery pkg ifaces ffiContent sourceModule

-- Type check query
result <- TypeQuery.typeCheckModuleQuery canonModule

-- FFI query
result <- ForeignQuery.foreignFileQuery javascriptFile

-- Kernel query
result <- KernelQuery.kernelFileQuery pkg foreigns kernelFile
```

## Worker Pool

### Configuration

```haskell
-- Default configuration (CPU cores)
pool <- Pool.createPoolDefault compileFn

-- Custom configuration
let config = Pool.PoolConfig
      { poolConfigWorkers = 16       -- 16 worker threads
      , poolConfigQueueSize = 200    -- Queue up to 200 tasks
      }
pool <- Pool.createPool config compileFn
```

### Compilation Function

The worker pool requires a compilation function:

```haskell
-- Define how to compile a task
compileFn :: Engine.QueryEngine -> Pool.CompileTask -> IO (Either QueryError result)
compileFn engine task = do
  Driver.compileModuleFull
    engine
    (Pool.taskPackage task)
    (Pool.taskInterfaces task)
    (Pool.taskFilePath task)
    (Pool.taskProjectType task)
```

### Managing Workers

```haskell
-- Create pool
pool <- Pool.createPool config compileFn

-- Submit tasks
results <- Pool.compileModules pool tasks

-- Track progress
progress <- Pool.getProgress pool

-- Shutdown when done
Pool.shutdownPool pool
```

## FFI Query System

```haskell
import qualified New.Compiler.Queries.Foreign as ForeignQuery

-- Analyze JavaScript file
result <- ForeignQuery.foreignFileQuery "src/dom.js"

case result of
  Left err -> putStrLn ("FFI error: " ++ show err)
  Right functions -> do
    putStrLn ("Found " ++ show (length functions) ++ " FFI functions")
    mapM_ printFunction functions

-- Process multiple foreign imports
imports <- buildImportList
result <- ForeignQuery.foreignImportsQuery imports
```

## Kernel Query System

```haskell
import qualified New.Compiler.Queries.Kernel as KernelQuery
import qualified Canopy.Package as Pkg

-- Analyze kernel module
let pkg = Pkg.core
    foreigns = Map.empty
result <- KernelQuery.kernelFileQuery pkg foreigns "src/Basics.js"

case result of
  Left err -> putStrLn ("Kernel error: " ++ show err)
  Right content -> do
    putStrLn "Kernel module parsed successfully"
```

## Performance Tips

### Caching

The query engine automatically caches results:

```haskell
-- First compilation - cache miss
result1 <- Driver.compileModule pkg ifaces path projectType

-- Second compilation - cache hit (if file unchanged)
result2 <- Driver.compileModule pkg ifaces path projectType
```

### Parallel Compilation

Use parallel compilation for large projects:

```haskell
-- Single-threaded (slow)
results <- mapM (Driver.compileModule pkg ifaces) paths

-- Parallel (fast)
results <- Driver.compileModulesParallel config pkg ifaces paths
```

### Worker Count

Choose worker count based on your hardware:

```bash
# Query CPU cores
$ nproc
8

# Use 75% of cores (leave some for system)
$ export WORKER_COUNT=6
```

```haskell
let config = Pool.PoolConfig
      { poolConfigWorkers = 6  -- Based on your hardware
      , poolConfigQueueSize = 100
      }
```

## Troubleshooting

### Compiler Not Switching

If `CANOPY_NEW_COMPILER=1` doesn't work:

```bash
# Check environment variable
$ echo $CANOPY_NEW_COMPILER
1

# Check Bridge integration
$ CANOPY_DEBUG=COMPILE_DEBUG canopy make src/Main.can | grep "Bridge"
[COMPILE_DEBUG] Bridge: Using new compiler
```

### Debug Logging Not Working

If `CANOPY_DEBUG` doesn't show output:

```bash
# Check environment variable
$ echo $CANOPY_DEBUG
PARSE,TYPE

# Try enabling all categories
$ CANOPY_DEBUG=1 canopy make src/Main.can
```

### Worker Pool Issues

If parallel compilation fails:

```haskell
-- Enable worker debug logging
-- CANOPY_DEBUG=WORKER_DEBUG canopy make

-- Check for exceptions in logs
[WORKER_DEBUG] Worker 1 exception: ...

-- Try reducing worker count
let config = Pool.PoolConfig
      { poolConfigWorkers = 2  -- Reduce to 2
      , poolConfigQueueSize = 100
      }
```

## Integration with Build System

### Make.Builder Integration

The new compiler integrates via `New.Compiler.Bridge`:

```haskell
-- In terminal/src/Make/Builder.hs
useNew <- Task.io Bridge.shouldUseNewCompiler

if useNew
  then buildWithNewCompiler style root details paths
  else buildWithOldCompiler style root details paths
```

### Backwards Compatibility

The Bridge ensures compatibility:

```haskell
-- Bridge function matches old API
compileFromPaths ::
  Reporting.Style ->
  FilePath ->
  Details.Details ->
  List FilePath ->
  IO (Either Exit.BuildProblem Build.Artifacts)
```

## Migration Path

### Phase 1: Validation (Current)

```bash
# Test with new compiler
CANOPY_NEW_COMPILER=1 canopy make src/Main.can

# Validate output matches old compiler
diff old-output.js new-output.js
```

### Phase 2: Gradual Rollout

```bash
# Enable for specific projects
export CANOPY_NEW_COMPILER=1
cd my-project
canopy make src/Main.can

# Monitor for issues
CANOPY_DEBUG=COMPILE_DEBUG canopy make src/Main.can
```

### Phase 3: Default Switch

```bash
# Eventually make new compiler default
# Old compiler available via CANOPY_OLD_COMPILER=1
```

## API Reference

### Driver Module

```haskell
module New.Compiler.Driver
  ( CompileResult(..)
  , compileModule              -- Single module
  , compileModuleFull          -- With existing engine
  , compileModulesParallel     -- Parallel compilation
  , compileModulesWithProgress -- With progress callback
  )
```

### Worker Pool Module

```haskell
module New.Compiler.Worker.Pool
  ( WorkerPool
  , PoolConfig(..)
  , CompileTask(..)
  , Progress(..)
  , createPool
  , createPoolDefault
  , shutdownPool
  , compileModules
  , compileModulesWithProgress
  , getProgress
  )
```

### Query Engine Module

```haskell
module New.Compiler.Query.Engine
  ( QueryEngine
  , initEngine
  , getCacheSize
  , getCacheHits
  , getCacheMisses
  )
```

## Examples

### Complete Compilation Pipeline

```haskell
import qualified New.Compiler.Driver as Driver
import qualified Canopy.Package as Pkg

main :: IO ()
main = do
  let pkg = Pkg.dummyName
      ifaces = Map.empty
      path = "src/Main.can"
      projectType = Parse.Application

  result <- Driver.compileModule pkg ifaces path projectType

  case result of
    Left err -> putStrLn ("Compilation failed: " ++ show err)
    Right compileResult -> do
      putStrLn "Compilation succeeded!"
      let canonModule = Driver.compileResultModule compileResult
          types = Driver.compileResultTypes compileResult
      putStrLn ("Module: " ++ show canonModule)
      putStrLn ("Types: " ++ show (Map.size types))
```

### Parallel Compilation with Progress

```haskell
import qualified New.Compiler.Driver as Driver
import qualified New.Compiler.Worker.Pool as Pool

main :: IO ()
main = do
  let config = Pool.PoolConfig 8 100
      pkg = Pkg.dummyName
      ifaces = Map.empty
      modules =
        [ ("src/Main.can", Parse.Application)
        , ("src/Utils.can", Parse.Application)
        , ("src/Types.can", Parse.Application)
        ]

  let progressFn progress = do
        let completed = Pool.progressCompleted progress
            total = Pool.progressTotal progress
            percent = (fromIntegral completed / fromIntegral total * 100 :: Double)
        putStrLn (printf "Progress: %.1f%% (%d/%d)" percent completed total)

  results <- Driver.compileModulesWithProgress config pkg ifaces modules progressFn

  let successes = length [r | Right r <- results]
      failures = length [r | Left r <- results]
  putStrLn (printf "Compilation complete: %d succeeded, %d failed" successes failures)
```

## Further Reading

- [Implementation Status](NEW_COMPILER_IMPLEMENTATION_STATUS.md) - Current status and completed features
- [Architecture Plan](CANOPY_QUERY_COMPILER_IMPLEMENTATION_PLAN.md) - Original design document
- [CLAUDE.md](../CLAUDE.md) - Coding standards and conventions

## Support

For issues or questions:
1. Enable debug logging: `CANOPY_DEBUG=1`
2. Check logs for errors
3. Report issues with full debug output
4. Fall back to old compiler if needed: unset `CANOPY_NEW_COMPILER`
