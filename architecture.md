# Canopy Compiler Architecture Plan

## 🎯 Goals

- **Maintainability**: Clear module boundaries and dependency separation following CLAUDE.md standards
- **Compile Speed**: Minimize dependencies and enable parallel compilation through multi-package structure
- **Modularity**: Independent libraries that can be developed and tested separately
- **Testing**: Comprehensive coverage with clear test organization per package
- **Performance**: Optimized hot paths while maintaining code clarity

## 🏗️ Proposed Multi-Package Architecture

### Overview

The monolithic library will be split into focused packages with clear dependency layers:

```
canopy/
├── libs/                           # Core libraries (bottom-up dependencies)
│   ├── canopy-core/                # Foundation: types, names, utilities
│   ├── canopy-ast/                 # AST definitions and interfaces
│   ├── canopy-parser/              # Parser components and JSON
│   ├── canopy-types/               # Type system and canonicalization
│   ├── canopy-optimize/            # Optimization passes
│   ├── canopy-codegen/             # Code generation
│   └── canopy-reporting/           # Error reporting and diagnostics
├── builder/                        # Build system (separate package)
├── terminal/                       # CLI interface (separate package)
├── app/                           # Main executable
└── test/                          # Comprehensive test suites
```

### Dependency Graph (Bottom-Up)

1. **canopy-core** → foundational types (no internal dependencies)
2. **canopy-ast** → depends on canopy-core
3. **canopy-parser** → depends on canopy-ast, canopy-core
4. **canopy-types** → depends on canopy-ast, canopy-core
5. **canopy-optimize** → depends on canopy-ast, canopy-types, canopy-core
6. **canopy-codegen** → depends on canopy-optimize, canopy-ast, canopy-core
7. **canopy-reporting** → depends on all others for comprehensive error reporting
8. **builder** → depends on all libs for build coordination
9. **terminal** → depends on builder for CLI functionality

## 📁 Detailed File Structure with Module Mappings

### libs/canopy-core/

**Purpose**: Foundational types, utilities, and core data structures
**Current Size**: ~15 modules
**Compile Impact**: Lowest level, changes rarely affect other packages

```
libs/canopy-core/
├── canopy-core.cabal
├── src/
│   └── Canopy/
│       ├── Core/
│       │   ├── ModuleName.hs          # From: compiler/src/Canopy/ModuleName.hs
│       │   │                          # Core module naming and validation
│       │   ├── Package.hs             # From: compiler/src/Canopy/Package.hs  
│       │   │                          # Package names and metadata
│       │   ├── Version.hs             # From: compiler/src/Canopy/Version.hs
│       │   │                          # Semantic versioning
│       │   ├── Name.hs                # From: compiler/src/Data/Name.hs
│       │   │                          # Internal name representation
│       │   └── String.hs              # From: compiler/src/Canopy/String.hs
│       │                              # String utilities and constants
│       ├── Data/
│       │   ├── Bag.hs                 # From: compiler/src/Data/Bag.hs
│       │   │                          # Efficient bag/multiset data structure
│       │   ├── Index.hs               # From: compiler/src/Data/Index.hs
│       │   │                          # Index types for arrays/maps
│       │   ├── NonEmptyList.hs        # From: compiler/src/Data/NonEmptyList.hs
│       │   │                          # Non-empty list utilities
│       │   ├── OneOrMore.hs           # From: compiler/src/Data/OneOrMore.hs
│       │   │                          # OneOrMore data type for collections
│       │   ├── Utf8.hs                # From: compiler/src/Data/Utf8.hs
│       │   │                          # UTF-8 string handling
│       │   └── Utils.hs               # From: compiler/src/Data/Map/Utils.hs
│       │                              # Map utilities and helper functions
│       └── Utils/
│           ├── Float.hs               # From: compiler/src/Canopy/Float.hs
│           │                          # Float constants and utilities
│           ├── Magnitude.hs           # From: compiler/src/Canopy/Magnitude.hs
│           │                          # Number magnitude calculations
│           └── Constraint.hs          # From: compiler/src/Canopy/Constraint.hs
│                                      # Core constraint types
└── test/
    └── Unit/
        ├── Core/
        ├── Data/
        └── Utils/
```

### libs/canopy-ast/

**Purpose**: AST definitions, interfaces, and documentation
**Current Size**: ~8 modules
**Compile Impact**: Medium - changes affect parser, types, and codegen

```
libs/canopy-ast/
├── canopy-ast.cabal
├── src/
│   └── AST/
│       ├── Source.hs                  # From: compiler/src/AST/Source.hs
│       │                              # Source AST after parsing
│       ├── Canonical.hs               # From: compiler/src/AST/Canonical.hs
│       │                              # Canonical AST after name resolution
│       ├── Optimized.hs               # From: compiler/src/AST/Optimized.hs
│       │                              # Optimized AST ready for codegen
│       ├── Utils/
│       │   ├── Binop.hs               # From: compiler/src/AST/Utils/Binop.hs
│       │   │                          # Binary operator utilities
│       │   ├── Shader.hs              # From: compiler/src/AST/Utils/Shader.hs
│       │   │                          # GLSL shader AST utilities
│       │   └── Type.hs                # From: compiler/src/AST/Utils/Type.hs
│       │                              # Type AST utilities
│       └── Interface/
│           ├── Interface.hs           # From: compiler/src/Canopy/Interface.hs
│           │                          # Module interface definitions
│           ├── Kernel.hs              # From: compiler/src/Canopy/Kernel.hs
│           │                          # Kernel module interfaces
│           └── Docs.hs                # From: compiler/src/Canopy/Docs.hs
│                                      # Documentation generation
└── test/
    └── Unit/
        ├── AST/
        └── Interface/
```

### libs/canopy-parser/

**Purpose**: Parser components and JSON handling
**Current Size**: ~15 modules
**Compile Impact**: Medium - changes mainly affect build phase, not runtime

```
libs/canopy-parser/
├── canopy-parser.cabal
├── src/
│   └── Parse/
│       ├── Module.hs                  # From: compiler/src/Parse/Module.hs
│       │                              # Top-level module parser
│       ├── Expression.hs              # From: compiler/src/Parse/Expression.hs
│       │                              # Expression parsing
│       ├── Pattern.hs                 # From: compiler/src/Parse/Pattern.hs
│       │                              # Pattern matching parser
│       ├── Type.hs                    # From: compiler/src/Parse/Type.hs
│       │                              # Type annotation parser
│       ├── Declaration.hs             # From: compiler/src/Parse/Declaration.hs
│       │                              # Top-level declaration parser
│       ├── Primitives.hs              # From: compiler/src/Parse/Primitives.hs
│       │                              # Parser combinator primitives
│       ├── Support/
│       │   ├── Keyword.hs             # From: compiler/src/Parse/Keyword.hs
│       │   │                          # Keyword recognition
│       │   ├── Number.hs              # From: compiler/src/Parse/Number.hs
│       │   │                          # Number literal parsing
│       │   ├── String.hs              # From: compiler/src/Parse/String.hs
│       │   │                          # String literal parsing
│       │   ├── Symbol.hs              # From: compiler/src/Parse/Symbol.hs
│       │   │                          # Symbol and operator parsing
│       │   ├── Variable.hs            # From: compiler/src/Parse/Variable.hs
│       │   │                          # Variable name parsing
│       │   ├── Space.hs               # From: compiler/src/Parse/Space.hs
│       │   │                          # Whitespace and comment handling
│       │   └── Shader.hs              # From: compiler/src/Parse/Shader.hs
│       │                              # GLSL shader parsing
│       └── Json/
│           ├── Decode.hs              # From: compiler/src/Json/Decode.hs
│           │                          # JSON decoder
│           ├── Encode.hs              # From: compiler/src/Json/Encode.hs
│           │                          # JSON encoder
│           └── String.hs              # From: compiler/src/Json/String.hs
│                                      # JSON string utilities
└── test/
    └── Unit/
        ├── Parse/
        └── Json/
```

### libs/canopy-types/

**Purpose**: Type system, constraint solving, and canonicalization
**Current Size**: ~25 modules
**Compile Impact**: High - core to compilation, changes affect optimization and codegen

```
libs/canopy-types/
├── canopy-types.cabal
├── src/
│   ├── Type/
│   │   ├── Type.hs                    # From: compiler/src/Type/Type.hs
│   │   │                              # Core type representation
│   │   ├── Solve.hs                   # From: compiler/src/Type/Solve.hs
│   │   │                              # Constraint solving algorithm
│   │   ├── Unify.hs                   # From: compiler/src/Type/Unify.hs
│   │   │                              # Type unification
│   │   ├── Occurs.hs                  # From: compiler/src/Type/Occurs.hs
│   │   │                              # Occurs check for infinite types
│   │   ├── UnionFind.hs               # From: compiler/src/Type/UnionFind.hs
│   │   │                              # Union-find for type variables
│   │   ├── Error.hs                   # From: compiler/src/Type/Error.hs
│   │   │                              # Type error representation
│   │   ├── Instantiate.hs             # From: compiler/src/Type/Instantiate.hs
│   │   │                              # Type instantiation
│   │   └── Constrain/
│   │       ├── Expression.hs          # From: compiler/src/Type/Constrain/Expression.hs
│   │       │                          # Expression constraint generation
│   │       ├── Pattern.hs             # From: compiler/src/Type/Constrain/Pattern.hs
│   │       │                          # Pattern constraint generation
│   │       └── Module.hs              # From: compiler/src/Type/Constrain/Module.hs
│   │                                  # Module-level constraint generation
│   ├── Canonicalize/
│   │   ├── Module.hs                  # From: compiler/src/Canonicalize/Module.hs
│   │   │                              # Module canonicalization
│   │   ├── Expression.hs              # From: compiler/src/Canonicalize/Expression.hs
│   │   │                              # Expression canonicalization
│   │   ├── Pattern.hs                 # From: compiler/src/Canonicalize/Pattern.hs
│   │   │                              # Pattern canonicalization
│   │   ├── Type.hs                    # From: compiler/src/Canonicalize/Type.hs
│   │   │                              # Type annotation canonicalization
│   │   ├── Effects.hs                 # From: compiler/src/Canonicalize/Effects.hs
│   │   │                              # Effect system canonicalization
│   │   └── Environment/
│   │       ├── Environment.hs         # From: compiler/src/Canonicalize/Environment.hs
│   │       │                          # Canonicalization environment
│   │       ├── Dups.hs                # From: compiler/src/Canonicalize/Environment/Dups.hs
│   │       │                          # Duplicate name detection
│   │       ├── Foreign.hs             # From: compiler/src/Canonicalize/Environment/Foreign.hs
│   │       │                          # Foreign import handling
│   │       └── Local.hs               # From: compiler/src/Canonicalize/Environment/Local.hs
│   │                                  # Local scope handling
│   └── Compiler/
│       ├── Imports.hs                 # From: compiler/src/Canopy/Compiler/Imports.hs
│       │                              # Import resolution
│       ├── Type.hs                    # From: compiler/src/Canopy/Compiler/Type.hs
│       │                              # Compiler type utilities
│       └── Extract.hs                 # From: compiler/src/Canopy/Compiler/Type/Extract.hs
│                                      # Type extraction utilities
└── test/
    └── Unit/
        ├── Type/
        ├── Canonicalize/
        └── Compiler/
```

### libs/canopy-optimize/

**Purpose**: Optimization passes and analysis
**Current Size**: ~8 modules
**Compile Impact**: Medium - affects final code quality but not core compilation

```
libs/canopy-optimize/
├── canopy-optimize.cabal
├── src/
│   └── Optimize/
│       ├── Module.hs                  # From: compiler/src/Optimize/Module.hs
│       │                              # Module-level optimizations
│       ├── Expression.hs              # From: compiler/src/Optimize/Expression.hs
│       │                              # Expression optimizations
│       ├── Names.hs                   # From: compiler/src/Optimize/Names.hs
│       │                              # Name optimization and mangling
│       ├── Port.hs                    # From: compiler/src/Optimize/Port.hs
│       │                              # Port/effect optimization
│       ├── Case.hs                    # From: compiler/src/Optimize/Case.hs
│       │                              # Case expression optimization
│       ├── DecisionTree.hs            # From: compiler/src/Optimize/DecisionTree.hs
│       │                              # Decision tree optimization
│       └── Nitpick/
│           ├── Debug.hs               # From: compiler/src/Nitpick/Debug.hs
│           │                          # Debug statement analysis
│           └── PatternMatches.hs      # From: compiler/src/Nitpick/PatternMatches.hs
│                                      # Pattern match exhaustiveness
└── test/
    └── Unit/
        └── Optimize/
```

### libs/canopy-codegen/

**Purpose**: Code generation for various targets
**Current Size**: ~6 modules
**Compile Impact**: Low - final stage, doesn't affect other compilation phases

```
libs/canopy-codegen/
├── canopy-codegen.cabal
├── src/
│   └── Generate/
│       ├── Html.hs                    # From: compiler/src/Generate/Html.hs
│       │                              # HTML page generation
│       ├── Mode.hs                    # From: compiler/src/Generate/Mode.hs
│       │                              # Generation mode configuration
│       ├── JavaScript.hs              # From: compiler/src/Generate/JavaScript.hs
│       │                              # Main JavaScript codegen
│       └── JavaScript/
│           ├── Builder.hs             # From: compiler/src/Generate/JavaScript/Builder.hs
│           │                          # JavaScript AST builder
│           ├── Expression.hs          # From: compiler/src/Generate/JavaScript/Expression.hs
│           │                          # JavaScript expression generation
│           ├── Functions.hs           # From: compiler/src/Generate/JavaScript/Functions.hs
│           │                          # JavaScript function generation
│           └── Name.hs                # From: compiler/src/Generate/JavaScript/Name.hs
│                                      # JavaScript name mangling
└── test/
    └── Unit/
        └── Generate/
```

### libs/canopy-reporting/

**Purpose**: Error reporting, diagnostics, and pretty printing
**Current Size**: ~20 modules
**Compile Impact**: Low - used for user feedback, doesn't affect compilation correctness

```
libs/canopy-reporting/
├── canopy-reporting.cabal
├── src/
│   └── Reporting/
│       ├── Annotation.hs              # From: compiler/src/Reporting/Annotation.hs
│       │                              # Source location annotations
│       ├── Doc.hs                     # From: compiler/src/Reporting/Doc.hs
│       │                              # Pretty-printing document type
│       ├── Error.hs                   # From: compiler/src/Reporting/Error.hs
│       │                              # Main error type and handling
│       ├── Report.hs                  # From: compiler/src/Reporting/Report.hs
│       │                              # Error report generation
│       ├── Result.hs                  # From: compiler/src/Reporting/Result.hs
│       │                              # Result type for error handling
│       ├── Suggest.hs                 # From: compiler/src/Reporting/Suggest.hs
│       │                              # Error suggestions and fixes
│       ├── Warning.hs                 # From: compiler/src/Reporting/Warning.hs
│       │                              # Warning types and handling
│       ├── Error/
│       │   ├── Canonicalize.hs        # From: compiler/src/Reporting/Error/Canonicalize.hs
│       │   │                          # Canonicalization error reporting
│       │   ├── Docs.hs                # From: compiler/src/Reporting/Error/Docs.hs
│       │   │                          # Documentation error reporting
│       │   ├── Import.hs              # From: compiler/src/Reporting/Error/Import.hs
│       │   │                          # Import error reporting
│       │   ├── Json.hs                # From: compiler/src/Reporting/Error/Json.hs
│       │   │                          # JSON parsing error reporting
│       │   ├── Main.hs                # From: compiler/src/Reporting/Error/Main.hs
│       │   │                          # Main function error reporting
│       │   ├── Pattern.hs             # From: compiler/src/Reporting/Error/Pattern.hs
│       │   │                          # Pattern matching error reporting
│       │   ├── Syntax.hs              # From: compiler/src/Reporting/Error/Syntax.hs
│       │   │                          # Syntax error reporting
│       │   └── Type.hs                # From: compiler/src/Reporting/Error/Type.hs
│       │                              # Type error reporting
│       └── Render/
│           ├── Code.hs                # From: compiler/src/Reporting/Render/Code.hs
│           │                          # Source code rendering
│           ├── Type.hs                # From: compiler/src/Reporting/Render/Type.hs
│           │                          # Type rendering for errors
│           └── Localizer.hs           # From: compiler/src/Reporting/Render/Type/Localizer.hs
│                                      # Type name localization
└── test/
    └── Unit/
        └── Reporting/
```

### builder/

**Purpose**: Build system, dependency resolution, and project coordination
**Current Size**: ~25 modules
**Compile Impact**: High for build times, but isolated from core compiler changes

```
builder/
├── builder.cabal
├── src/
│   ├── Build.hs                       # From: builder/src/Build.hs
│   │                                  # Main build coordination
│   ├── Compile.hs                     # From: compiler/src/Compile.hs (moved here)
│   │                                  # High-level compilation orchestration
│   ├── BackgroundWriter.hs            # From: builder/src/BackgroundWriter.hs
│   │                                  # Async file writing
│   ├── Generate.hs                    # From: builder/src/Generate.hs
│   │                                  # Build artifact generation
│   ├── File.hs                        # From: builder/src/File.hs
│   │                                  # File system utilities
│   ├── Http.hs                        # From: builder/src/Http.hs
│   │                                  # HTTP client for package downloads
│   ├── Stuff.hs                       # From: builder/src/Stuff.hs
│   │                                  # Path and directory utilities
│   ├── Canopy/
│   │   ├── Details.hs                 # From: builder/src/Canopy/Details.hs
│   │   │                              # Project details and cache
│   │   ├── Outline.hs                 # From: builder/src/Canopy/Outline.hs
│   │   │                              # canopy.json structure
│   │   ├── CustomRepositoryData.hs    # From: builder/src/Canopy/CustomRepositoryData.hs
│   │   │                              # Custom package repository data
│   │   ├── PackageOverrideData.hs     # From: builder/src/Canopy/PackageOverrideData.hs
│   │   │                              # Package override configuration
│   │   └── Licenses.hs                # From: compiler/src/Canopy/Licenses.hs
│   │                                  # License validation and tracking
│   ├── Deps/
│   │   ├── Bump.hs                    # From: builder/src/Deps/Bump.hs
│   │   │                              # Version bumping logic
│   │   ├── Diff.hs                    # From: builder/src/Deps/Diff.hs
│   │   │                              # Dependency difference calculation
│   │   ├── Registry.hs                # From: builder/src/Deps/Registry.hs
│   │   │                              # Package registry interaction
│   │   ├── Solver.hs                  # From: builder/src/Deps/Solver.hs
│   │   │                              # Dependency resolution algorithm
│   │   ├── Website.hs                 # From: builder/src/Deps/Website.hs
│   │   │                              # Package website scraping
│   │   └── CustomRepositoryDataIO.hs  # From: builder/src/Deps/CustomRepositoryDataIO.hs
│   │                                  # Custom repository I/O
│   ├── Logging/
│   │   └── Logger.hs                  # From: builder/src/Logging/Logger.hs
│   │                                  # Build logging utilities
│   └── Reporting/
│       ├── Reporting.hs               # From: builder/src/Reporting.hs
│       │                              # Build progress reporting
│       ├── Exit.hs                    # From: builder/src/Reporting/Exit.hs
│       │                              # Exit codes and build results
│       ├── Task.hs                    # From: builder/src/Reporting/Task.hs
│       │                              # Task monad for build operations
│       └── Help.hs                    # From: builder/src/Reporting/Exit/Help.hs
│                                      # Help text generation
└── test/
    └── Unit/
        ├── Build/
        ├── Deps/
        └── Reporting/
```

### terminal/

**Purpose**: CLI interface, commands, and user interaction
**Current Size**: ~60 modules
**Compile Impact**: Low - isolated from core compiler, mainly I/O and user interface

```
terminal/
├── terminal.cabal
├── src/
│   ├── Commands/
│   │   ├── Make.hs                    # From: terminal/src/Make.hs
│   │   │                              # canopy make command
│   │   ├── Install.hs                 # From: terminal/src/Install.hs
│   │   │                              # canopy install command
│   │   ├── Repl.hs                    # From: terminal/src/Repl.hs
│   │   │                              # canopy repl command
│   │   ├── Develop.hs                 # From: terminal/src/Develop.hs
│   │   │                              # canopy develop command
│   │   ├── Diff.hs                    # From: terminal/src/Diff.hs
│   │   │                              # canopy diff command
│   │   ├── Init.hs                    # From: terminal/src/Init.hs
│   │   │                              # canopy init command
│   │   ├── Publish.hs                 # From: terminal/src/Publish.hs
│   │   │                              # canopy publish command
│   │   ├── Bump.hs                    # From: terminal/src/Bump.hs
│   │   │                              # canopy bump command
│   │   └── Watch.hs                   # From: terminal/src/Watch.hs
│   │                                  # canopy watch command
│   ├── Make/
│   │   ├── Builder.hs                 # From: terminal/src/Make/Builder.hs
│   │   ├── Environment.hs             # From: terminal/src/Make/Environment.hs
│   │   ├── Generation.hs              # From: terminal/src/Make/Generation.hs
│   │   ├── Output.hs                  # From: terminal/src/Make/Output.hs
│   │   ├── Parser.hs                  # From: terminal/src/Make/Parser.hs
│   │   └── Types.hs                   # From: terminal/src/Make/Types.hs
│   ├── Install/
│   │   ├── AppPlan.hs                 # From: terminal/src/Install/AppPlan.hs
│   │   ├── Arguments.hs               # From: terminal/src/Install/Arguments.hs
│   │   ├── Changes.hs                 # From: terminal/src/Install/Changes.hs
│   │   ├── Display.hs                 # From: terminal/src/Install/Display.hs
│   │   ├── Execution.hs               # From: terminal/src/Install/Execution.hs
│   │   ├── PkgPlan.hs                 # From: terminal/src/Install/PkgPlan.hs
│   │   └── Types.hs                   # From: terminal/src/Install/Types.hs
│   ├── Repl/
│   │   ├── Commands.hs                # From: terminal/src/Repl/Commands.hs
│   │   ├── Eval.hs                    # From: terminal/src/Repl/Eval.hs
│   │   ├── State.hs                   # From: terminal/src/Repl/State.hs
│   │   └── Types.hs                   # From: terminal/src/Repl/Types.hs
│   ├── Develop/
│   │   ├── Compilation.hs             # From: terminal/src/Develop/Compilation.hs
│   │   ├── Environment.hs             # From: terminal/src/Develop/Environment.hs
│   │   ├── MimeTypes.hs               # From: terminal/src/Develop/MimeTypes.hs
│   │   ├── Server.hs                  # From: terminal/src/Develop/Server.hs
│   │   ├── Socket.hs                  # From: terminal/src/Develop/Socket.hs
│   │   ├── StaticFiles.hs             # From: terminal/src/Develop/StaticFiles.hs
│   │   ├── Types.hs                   # From: terminal/src/Develop/Types.hs
│   │   ├── Generate/
│   │   │   ├── Help.hs                # From: terminal/src/Develop/Generate/Help.hs
│   │   │   └── Index.hs               # From: terminal/src/Develop/Generate/Index.hs
│   │   └── StaticFiles/
│   │       └── Build.hs               # From: terminal/src/Develop/StaticFiles/Build.hs
│   ├── Diff/
│   │   ├── Documentation.hs           # From: terminal/src/Diff/Documentation.hs
│   │   ├── Environment.hs             # From: terminal/src/Diff/Environment.hs
│   │   ├── Execution.hs               # From: terminal/src/Diff/Execution.hs
│   │   ├── Outline.hs                 # From: terminal/src/Diff/Outline.hs
│   │   ├── Output.hs                  # From: terminal/src/Diff/Output.hs
│   │   └── Types.hs                   # From: terminal/src/Diff/Types.hs
│   ├── Init/
│   │   ├── Display.hs                 # From: terminal/src/Init/Display.hs
│   │   ├── Environment.hs             # From: terminal/src/Init/Environment.hs
│   │   ├── Project.hs                 # From: terminal/src/Init/Project.hs
│   │   ├── Types.hs                   # From: terminal/src/Init/Types.hs
│   │   └── Validation.hs              # From: terminal/src/Init/Validation.hs
│   ├── Publish/
│   │   ├── Environment.hs             # From: terminal/src/Publish/Environment.hs
│   │   ├── Git.hs                     # From: terminal/src/Publish/Git.hs
│   │   ├── Progress.hs                # From: terminal/src/Publish/Progress.hs
│   │   ├── Registry.hs                # From: terminal/src/Publish/Registry.hs
│   │   ├── Types.hs                   # From: terminal/src/Publish/Types.hs
│   │   └── Validation.hs              # From: terminal/src/Publish/Validation.hs
│   ├── Bump/
│   │   ├── Analysis.hs                # From: terminal/src/Bump/Analysis.hs
│   │   ├── Environment.hs             # From: terminal/src/Bump/Environment.hs
│   │   ├── Operations.hs              # From: terminal/src/Bump/Operations.hs
│   │   ├── Types.hs                   # From: terminal/src/Bump/Types.hs
│   │   └── Validation.hs              # From: terminal/src/Bump/Validation.hs
│   └── CLI/
│       ├── Commands.hs                # From: terminal/src/CLI/Commands.hs
│       ├── Documentation.hs           # From: terminal/src/CLI/Documentation.hs  
│       ├── Parsers.hs                 # From: terminal/src/CLI/Parsers.hs
│       └── Types.hs                   # From: terminal/src/CLI/Types.hs
├── impl/                              # Terminal implementation (unchanged)
│   ├── Terminal.hs                    # From: terminal/impl/Terminal.hs
│   └── Terminal/
│       ├── Application.hs             # From: terminal/impl/Terminal/Application.hs
│       ├── Chomp.hs                   # From: terminal/impl/Terminal/Chomp.hs
│       ├── Command.hs                 # From: terminal/impl/Terminal/Command.hs
│       ├── Completion.hs              # From: terminal/impl/Terminal/Completion.hs
│       ├── Error.hs                   # From: terminal/impl/Terminal/Error.hs
│       ├── Helpers.hs                 # From: terminal/impl/Terminal/Helpers.hs
│       ├── Internal.hs                # From: terminal/impl/Terminal/Internal.hs
│       ├── Parser.hs                  # From: terminal/impl/Terminal/Parser.hs
│       ├── Types.hs                   # From: terminal/impl/Terminal/Types.hs
│       ├── Chomp/
│       │   ├── Arguments.hs           # From: terminal/impl/Terminal/Chomp/Arguments.hs
│       │   ├── Flags.hs               # From: terminal/impl/Terminal/Chomp/Flags.hs
│       │   ├── Parser.hs              # From: terminal/impl/Terminal/Chomp/Parser.hs
│       │   ├── Processing.hs          # From: terminal/impl/Terminal/Chomp/Processing.hs
│       │   ├── Suggestion.hs          # From: terminal/impl/Terminal/Chomp/Suggestion.hs
│       │   └── Types.hs               # From: terminal/impl/Terminal/Chomp/Types.hs
│       └── Error/
│           ├── Display.hs             # From: terminal/impl/Terminal/Error/Display.hs
│           ├── Formatting.hs          # From: terminal/impl/Terminal/Error/Formatting.hs
│           ├── Help.hs                # From: terminal/impl/Terminal/Error/Help.hs
│           ├── Suggestions.hs         # From: terminal/impl/Terminal/Error/Suggestions.hs
│           └── Types.hs               # From: terminal/impl/Terminal/Error/Types.hs
└── test/
    └── Unit/
        ├── Commands/
        ├── CLI/
        └── Terminal/
```

### test/

**Purpose**: Comprehensive testing organization per package
**Current Size**: ~50 test modules
**Benefits**: Parallel test execution, clear test boundaries, isolated failures

```
test/
├── Unit/                              # Unit tests per package
│   ├── Core/                          # Tests for canopy-core
│   │   ├── ModuleNameTest.hs          # From: test/Unit/Canopy/VersionTest.hs (expanded)
│   │   ├── PackageTest.hs             # New comprehensive package tests
│   │   ├── VersionTest.hs             # From: test/Unit/Canopy/VersionTest.hs
│   │   └── NameTest.hs                # From: test/Unit/Data/NameTest.hs
│   ├── AST/                           # Tests for canopy-ast
│   │   ├── SourceTest.hs              # From: test/Unit/AST/SourceTest.hs
│   │   ├── CanonicalTest.hs           # From: test/Unit/AST/CanonicalTypeTest.hs (expanded)
│   │   ├── OptimizedTest.hs           # From: test/Unit/AST/OptimizedTest.hs
│   │   └── InterfaceTest.hs           # New interface tests
│   ├── Parser/                        # Tests for canopy-parser
│   │   ├── ExpressionTest.hs          # From: test/Unit/Parse/ExpressionTest.hs
│   │   ├── ModuleTest.hs              # From: test/Unit/Parse/ModuleTest.hs
│   │   ├── PatternTest.hs             # From: test/Unit/Parse/PatternTest.hs
│   │   ├── TypeTest.hs                # From: test/Unit/Parse/TypeTest.hs
│   │   └── JsonTest.hs                # From: test/Unit/Json/DecodeTest.hs (expanded)
│   ├── Types/                         # Tests for canopy-types
│   │   ├── TypeTest.hs                # New comprehensive type system tests
│   │   ├── SolveTest.hs               # New constraint solving tests
│   │   ├── UnifyTest.hs               # New unification tests
│   │   └── CanonicalizeTest.hs        # New canonicalization tests
│   ├── Optimize/                      # Tests for canopy-optimize
│   │   ├── ExpressionTest.hs          # New expression optimization tests
│   │   ├── CaseTest.hs                # New case optimization tests
│   │   └── DecisionTreeTest.hs        # New decision tree tests
│   ├── Codegen/                       # Tests for canopy-codegen
│   │   ├── JavaScriptTest.hs          # New JavaScript generation tests
│   │   └── HtmlTest.hs                # New HTML generation tests
│   ├── Reporting/                     # Tests for canopy-reporting
│   │   ├── ErrorTest.hs               # New comprehensive error tests
│   │   └── RenderTest.hs              # New rendering tests
│   └── Integration/                   # Cross-package integration tests
│       ├── CompilerTest.hs            # From: test/Integration/CompilerTest.hs
│       ├── CanExtensionTest.hs        # From: test/Integration/CanExtensionTest.hs
│       ├── JsGenTest.hs               # From: test/Integration/JsGenTest.hs
│       └── EndToEndTest.hs            # New full compilation pipeline tests
├── Property/                          # Property-based tests per package
│   ├── Core/
│   │   └── VersionProps.hs            # From: test/Property/Canopy/VersionProps.hs
│   ├── AST/
│   │   ├── CanonicalProps.hs          # From: test/Property/AST/CanonicalProps.hs
│   │   ├── OptimizedProps.hs          # From: test/Property/AST/OptimizedProps.hs
│   │   └── OptimizedBinaryProps.hs    # From: test/Property/AST/OptimizedBinaryProps.hs
│   ├── Parser/
│   │   └── RoundtripProps.hs          # New parser roundtrip properties
│   ├── Types/
│   │   └── UnificationProps.hs        # New type system properties
│   └── Terminal/
│       ├── ChompProps.hs              # From: test/Property/Terminal/ChompProps.hs
│       ├── TerminalProps.hs           # From: test/Property/TerminalProps.hs
│       └── CommandProps.hs            # New command parsing properties
├── Golden/                            # Golden file tests
│   ├── JsGenGolden.hs                 # From: test/Golden/JsGenGolden.hs
│   ├── ParseAliasGolden.hs            # From: test/Golden/ParseAliasGolden.hs
│   ├── ParseExprGolden.hs             # From: test/Golden/ParseExprGolden.hs
│   ├── ParseModuleGolden.hs           # From: test/Golden/ParseModuleGolden.hs
│   ├── ParseTypeGolden.hs             # From: test/Golden/ParseTypeGolden.hs
│   └── expected/                      # Golden files
│       ├── Alias.golden               # From: test/Golden/expected/Alias.golden
│       ├── Expr_LambdaTupleMap.golden # From: test/Golden/expected/Expr_LambdaTupleMap.golden
│       ├── Expr_RecordUpdate.golden   # From: test/Golden/expected/Expr_RecordUpdate.golden
│       ├── JsDevMulti.js              # From: test/Golden/expected/JsDevMulti.js
│       ├── Ops.golden                 # From: test/Golden/expected/Ops.golden
│       ├── Shapes.golden              # From: test/Golden/expected/Shapes.golden
│       ├── Type_NestedRecordFunc.golden # From: test/Golden/expected/Type_NestedRecordFunc.golden
│       └── Utils.golden               # From: test/Golden/expected/Utils.golden
└── Benchmarks/                        # Performance benchmarks
    ├── ParserBench.hs                 # New parser performance tests
    ├── TypecheckBench.hs              # New typechecker performance tests
    ├── OptimizeBench.hs               # New optimizer performance tests
    └── CodegenBench.hs                # New codegen performance tests
```

## 🚀 Compile Time Optimization Strategies

### 1. Parallel Compilation
- **Independent Packages**: Each lib can compile in parallel since dependencies are explicit
- **Incremental Builds**: Changes in `canopy-core` won't rebuild `canopy-codegen` unnecessarily
- **Layer Isolation**: Bottom-up dependencies prevent circular rebuilds

### 2. Dependency Minimization
- **Focused Dependencies**: Each package only depends on what it needs
- **External Dependencies**: Kept minimal and specific to package purpose
- **Template Haskell Isolation**: TH usage confined to specific packages

### 3. Interface Stability
- **Clear APIs**: Well-defined interfaces between packages
- **Version Boundaries**: Explicit versioning prevents cascading rebuilds
- **Abstract Types**: Hide implementation details to reduce recompilation

### 4. Build System Optimizations
```yaml
# Example cabal.project for parallel builds
packages: 
  libs/canopy-core
  libs/canopy-ast  
  libs/canopy-parser
  libs/canopy-types
  libs/canopy-optimize
  libs/canopy-codegen
  libs/canopy-reporting
  builder
  terminal

-- Enable parallel builds
jobs: $ncpus

-- Optimize compilation flags per package
package canopy-core
  optimization: 2
  
package canopy-parser  
  optimization: 1  -- Parser doesn't need heavy optimization

package canopy-types
  optimization: 2  -- Critical path needs optimization
```

### 5. Module Organization
- **Smaller Modules**: Following CLAUDE.md 15-line function limit
- **Clear Exports**: Only export necessary functions to reduce interface surface
- **Strategic Re-exports**: Central modules re-export commonly used functions

## 📋 Implementation Phases

### Phase 1: Foundation Setup (Week 1)
- Create multi-package structure with cabal files
- Move `canopy-core` modules and establish basic build
- Update import statements to use new structure
- Verify basic compilation works

### Phase 2: AST and Parser Separation (Week 2)  
- Extract `canopy-ast` package with AST definitions
- Extract `canopy-parser` package with parsing logic
- Update all import statements throughout codebase
- Ensure parser tests pass

### Phase 3: Type System Extraction (Week 2-3)
- Create `canopy-types` with type system and canonicalization
- This is the largest migration - requires careful import management
- Update builder and terminal to use new type system interface
- Verify type system tests pass

### Phase 4: Optimization and Codegen (Week 3)
- Extract `canopy-optimize` and `canopy-codegen` packages
- These have fewer interdependencies, should be straightforward
- Update golden tests for JavaScript generation
- Verify optimization passes work correctly

### Phase 5: Reporting System (Week 4)
- Extract `canopy-reporting` package
- Update all error handling throughout system  
- Ensure error messages still format correctly
- Test comprehensive error reporting

### Phase 6: Builder and Terminal Updates (Week 4-5)
- Update `builder` package to use new library structure
- Update `terminal` package imports and dependencies  
- Verify all CLI commands work correctly
- Update integration tests

### Phase 7: Testing and CI (Week 5)
- Reorganize test suites per package
- Update CI configuration for multi-package builds
- Add package-level benchmarks
- Verify parallel compilation works correctly

### Phase 8: Documentation and Polish (Week 6)
- Update CLAUDE.md with new architecture guidelines
- Create package-level documentation  
- Add migration guide for contributors
- Performance validation and optimization

## 🔧 Build Configuration

### Root cabal.project
```yaml
packages: 
  libs/canopy-core
  libs/canopy-ast  
  libs/canopy-parser
  libs/canopy-types
  libs/canopy-optimize
  libs/canopy-codegen
  libs/canopy-reporting
  builder
  terminal
  app

-- Parallel builds
jobs: $ncpus

-- Global optimization settings
optimization: True
documentation: True
tests: True
benchmarks: True

-- Package-specific optimizations
package canopy-core
  optimization: 2
  ghc-options: -O2 -funbox-strict-fields

package canopy-types  
  optimization: 2
  ghc-options: -O2 -funbox-strict-fields -fspecialise-aggressively

package canopy-parser
  optimization: 1
  ghc-options: -O1

-- Development settings
if impl(ghc >= 9.2)
  package *
    ghc-options: -Wno-unused-packages
```

### Example Package cabal File
```yaml
# libs/canopy-core/canopy-core.cabal
cabal-version: 2.2
name: canopy-core
version: 0.19.1
synopsis: Core types and utilities for Canopy compiler
description: Foundational types, names, and data structures used throughout the Canopy compiler

library
  exposed-modules:
    Canopy.Core.ModuleName
    Canopy.Core.Package  
    Canopy.Core.Version
    Canopy.Core.Name
    Canopy.Core.String
    Canopy.Data.Bag
    Canopy.Data.Index
    Canopy.Data.NonEmptyList
    Canopy.Data.OneOrMore
    Canopy.Data.Utf8
    Canopy.Data.Utils
    Canopy.Utils.Float
    Canopy.Utils.Magnitude
    Canopy.Utils.Constraint

  hs-source-dirs: src
  default-language: Haskell2010
  
  build-depends:
    base >= 4.12 && < 5,
    containers >= 0.6,
    bytestring >= 0.10,
    text >= 1.2,
    binary >= 0.8

  ghc-options: 
    -Wall 
    -Wno-name-shadowing
    -O2
    -funbox-strict-fields
```

## 📊 Expected Benefits

### Compile Time Improvements
- **Parallel Compilation**: 3-4x faster on multi-core systems
- **Incremental Builds**: 5-10x faster for typical changes
- **Reduced Rebuilds**: Changes isolated to relevant packages only
- **Smaller Interface Surface**: Less recompilation due to internal changes

### Development Benefits  
- **Clear Ownership**: Each package has focused responsibility
- **Independent Testing**: Test suites can run in parallel per package
- **Easier Onboarding**: New contributors can focus on specific packages
- **Better IDE Support**: Smaller compilation units improve IDE responsiveness

### Maintenance Benefits
- **Isolated Changes**: Bug fixes confined to relevant packages
- **Clear Dependencies**: No hidden coupling between components
- **Version Management**: Can version and release packages independently
- **Code Quality**: Easier to enforce standards per package

This architecture transforms the Canopy compiler from a monolithic library into a well-structured, maintainable, and fast-compiling multi-package system while preserving all existing functionality and following CLAUDE.md standards.