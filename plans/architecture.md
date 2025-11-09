# Canopy Compiler Architecture Plan

## 🎯 Goals

- **Maintainability**: Clear module boundaries and dependency separation following CLAUDE.md standards
- **Compile Speed**: Minimize dependencies and enable parallel compilation through multi-package structure
- **Modularity**: Independent libraries that can be developed and tested separately
- **Testing**: Comprehensive coverage with clear test organization per package
- **Performance**: Optimized hot paths while maintaining code clarity
- **Semantic Clarity**: Module names immediately convey their purpose and responsibilities
- **Backward Compatibility**: Terminal commands remain unchanged; internal modules can be reorganized freely

## 🏗️ Proposed Multi-Package Architecture

### Overview

The monolithic library will be split into focused packages with clear dependency layers:

```
canopy/
├── libs/                                    # Core libraries (bottom-up dependencies)
│   ├── canopy-foundation/                   # Foundation: types, names, utilities, shared patterns
│   ├── canopy-syntax-tree/                  # Abstract syntax tree definitions and interfaces
│   ├── canopy-language-parser/              # Parser components and basic JSON utilities
│   ├── canopy-type-system/                  # Type inference, checking, and canonicalization
│   ├── canopy-analyzer/                     # Code analysis, optimization, and pattern matching
│   ├── canopy-code-generator/               # Code generation for multiple targets
│   ├── canopy-diagnostics/                  # Error reporting, warnings, and user feedback
│   └── canopy-project-management/           # Project configuration, JSON handling, licenses
├── compiler-orchestrator/                   # High-level compilation pipeline coordination
├── builder/                                 # Build system and dependency resolution
├── terminal/                                # CLI interface and user commands
├── app/                                    # Main executable and entry points
└── test/                                   # Comprehensive test suites per package
```

### Dependency Graph (Bottom-Up)

1. **canopy-foundation** → foundational types, shared patterns (no internal dependencies)
2. **canopy-syntax-tree** → depends on canopy-foundation
3. **canopy-language-parser** → depends on canopy-syntax-tree, canopy-foundation
4. **canopy-type-system** → depends on canopy-syntax-tree, canopy-foundation
5. **canopy-analyzer** → depends on canopy-syntax-tree, canopy-type-system, canopy-foundation
6. **canopy-code-generator** → depends on canopy-analyzer, canopy-syntax-tree, canopy-foundation
7. **canopy-diagnostics** → depends on all core libs for comprehensive error reporting
8. **canopy-project-management** → depends on canopy-foundation, canopy-diagnostics
9. **compiler-orchestrator** → depends on all libs for compilation pipeline
10. **builder** → depends on compiler-orchestrator, canopy-project-management
11. **terminal** → depends on builder for CLI functionality

### Key Naming Improvements

- **Foundation** (was `core`) - More descriptive, now includes shared patterns
- **Syntax Tree** (was `ast`) - Clearer purpose than abbreviation 
- **Language Parser** (was `parser`) - Specifies it's parsing the Canopy language
- **Type System** (was `types`) - More comprehensive than just "types"
- **Analyzer** (was `optimizer`) - Better separation of analysis from transformation
- **Code Generator** (was `codegen`) - Full name instead of abbreviation
- **Diagnostics** (was `reporting`) - More specific about error handling and user feedback
- **Project Management** (NEW) - Dedicated package for project configuration and metadata
- **Compiler Orchestrator** (NEW) - High-level compilation pipeline extracted from compiler

### Critical Terminal Interface Improvements

The most problematic names were in the terminal interface:

- **ArgumentParser** (was `Chomp`) - "Chomp" was completely unclear; ArgumentParser immediately conveys its purpose
- **ArgumentParser/Suggestions** (was `Chomp/Suggestion`) - Clearer naming for help and suggestions
- **Lexical/** (was `Support/`) - More semantic grouping for parser lexical elements  
- **Collections/** (was `Data/`) - Better organization of data structure modules
- **Numeric/** - New grouping for numeric utilities and constraints

These changes maintain 100% backward compatibility for all terminal commands while dramatically improving code readability.

## 🔍 Deep Analysis Results

### Architectural Strengths Found
After comprehensive analysis of all 200+ modules, the Canopy compiler demonstrates **exceptional architectural discipline**:
- Clean AST pipeline separation (`Source → Canonical → Optimized`)
- Proper error handling hierarchies by compiler phase
- Excellent type system design with UTF-8 optimized operations
- No significant circular dependencies or problematic overlaps

### Identified Optimization Opportunities

#### 1. **Environment Pattern Duplication** ⚠️
Found multiple `Environment` modules with similar setup patterns:
- `Make/Environment.hs`, `Develop/Environment.hs`, `Diff/Environment.hs`, `Init/Environment.hs`, `Publish/Environment.hs`
- **Solution**: Extract common environment patterns into shared utilities

#### 2. **Module Misplacement** ⚠️ 
- `Canopy.Licenses` currently in compiler package but only used in builder for package metadata
- **Solution**: Move to appropriate package location

#### 3. **Compilation Orchestration** 💡
- `Compile.hs` orchestrates entire pipeline but sits within compiler package
- **Solution**: Extract as separate high-level orchestration package

#### 4. **JSON Configuration Handling** 💡
- Project configuration JSON scattered between builder and compiler
- **Solution**: Consolidate into dedicated project management package

## 🔄 Backward Compatibility Strategy

### Terminal Command Interface (PROTECTED)

All existing terminal commands are **GUARANTEED** to work exactly as before:

```bash
# All of these commands remain IDENTICAL in behavior and flags
canopy make                 # Build project  
canopy install              # Install packages
canopy repl                 # Interactive REPL
canopy init                 # Initialize new project  
canopy develop              # Development server
canopy diff                 # Show API differences
canopy publish              # Publish to registry
canopy bump                 # Bump version number
canopy watch               # File watcher mode
```

**Command Flags and Arguments**: All existing flags, options, and argument parsing remain unchanged.
**Exit Codes**: All exit codes and error behaviors remain identical.
**Output Format**: All output formatting and logging remains unchanged.

### Internal Module Changes (ALLOWED)

The following internal changes are freely allowed as they don't affect the public terminal interface:

- **Module Names**: `Terminal.Chomp` → `Terminal.ArgumentParser` (internal only)
- **File Organization**: Moving modules between packages (e.g., `compiler/src/` → `libs/canopy-*/src/`)
- **Import Statements**: Updating qualified import paths to match new package structure
- **Function Names**: Internal function renaming for clarity (non-public functions only)
- **Type Names**: Internal type renaming that doesn't affect command behavior

### Migration Philosophy

1. **User-Facing = Immutable**: Anything users interact with directly cannot change
2. **Internal = Flexible**: Internal organization can be completely reorganized
3. **Build Interface = Preserved**: `cabal build`, `stack build` continue to work
4. **Library APIs = Versioned**: If internal libraries need breaking changes, they use proper semantic versioning

## 📁 Detailed File Structure with Module Mappings

### libs/canopy-foundation/

**Purpose**: Foundational types, utilities, and shared patterns that form the base of all other packages
**Key Responsibilities**:
- Core naming and versioning systems
- Fundamental data structures (bags, indices, non-empty lists)
- UTF-8 string handling and text processing
- Basic numeric utilities and constraints
- **NEW**: Shared environment setup patterns used across terminal commands
- **NEW**: Common project detection and configuration utilities

**Current Size**: ~18 modules (expanded with shared patterns)
**Compile Impact**: Lowest level, changes rarely affect other packages

```
libs/canopy-foundation/
├── canopy-foundation.cabal
├── src/
│   └── Canopy/
│       ├── Foundation/
│       │   ├── ModuleName.hs          # From: compiler/src/Canopy/ModuleName.hs
│       │   │                          # Core module naming and validation
│       │   ├── Package.hs             # From: compiler/src/Canopy/Package.hs  
│       │   │                          # Package names and metadata
│       │   ├── Version.hs             # From: compiler/src/Canopy/Version.hs
│       │   │                          # Semantic versioning
│       │   ├── Name.hs                # From: compiler/src/Data/Name.hs
│       │   │                          # Internal name representation
│       │   └── Text.hs                # From: compiler/src/Canopy/String.hs
│       │                              # Text utilities and string constants
│       ├── Collections/
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
│       │   └── MapUtilities.hs        # From: compiler/src/Data/Map/Utils.hs
│       │                              # Map utilities and helper functions
│       ├── Numeric/
│       │   ├── Float.hs               # From: compiler/src/Canopy/Float.hs
│       │   │                          # Float constants and utilities
│       │   ├── Magnitude.hs           # From: compiler/src/Canopy/Magnitude.hs
│       │   │                          # Number magnitude calculations
│       │   └── Constraint.hs          # From: compiler/src/Canopy/Constraint.hs
│       │                              # Core constraint types
│       └── Environment/               # NEW: Shared environment patterns
│           ├── Common.hs              # Common environment setup utilities
│           ├── ProjectDetection.hs    # Project root discovery patterns
│           └── Configuration.hs       # Configuration management utilities
└── test/
    └── Unit/
        ├── Foundation/
        ├── Collections/
        ├── Numeric/
        └── Environment/
```

### libs/canopy-syntax-tree/

**Purpose**: Abstract syntax tree definitions, module interfaces, and AST transformations
**Key Responsibilities**:
- Define all AST node types for different compilation phases
- Module interface specifications and kernel definitions
- AST utility functions and binary operator handling
- Documentation AST structures

**Current Size**: ~8 modules
**Compile Impact**: Medium - changes affect parser, types, and codegen

```
libs/canopy-syntax-tree/
├── canopy-syntax-tree.cabal
├── src/
│   └── Canopy/
│       ├── SyntaxTree/
│       │   ├── Source.hs              # From: compiler/src/AST/Source.hs
│       │   │                          # Source AST after parsing
│       │   ├── Canonical.hs           # From: compiler/src/AST/Canonical.hs
│       │   │                          # Canonical AST after name resolution
│       │   ├── Optimized.hs           # From: compiler/src/AST/Optimized.hs
│       │   │                          # Optimized AST ready for codegen
│       │   └── Utilities/
│       │       ├── BinaryOperators.hs # From: compiler/src/AST/Utils/Binop.hs
│       │       │                      # Binary operator utilities
│       │       ├── ShaderAST.hs       # From: compiler/src/AST/Utils/Shader.hs
│       │       │                      # GLSL shader AST utilities
│       │       └── TypeAST.hs         # From: compiler/src/AST/Utils/Type.hs
│       │                              # Type AST utilities
│       └── ModuleInterface/
│           ├── Interface.hs           # From: compiler/src/Canopy/Interface.hs
│           │                          # Module interface definitions
│           ├── Kernel.hs              # From: compiler/src/Canopy/Kernel.hs
│           │                          # Kernel module interfaces
│           └── Documentation.hs       # From: compiler/src/Canopy/Docs.hs
│                                      # Documentation generation
└── test/
    └── Unit/
        ├── SyntaxTree/
        └── ModuleInterface/
```

### libs/canopy-language-parser/

**Purpose**: Parsing Canopy language source code and JSON configuration files
**Key Responsibilities**:
- Parse all Canopy language constructs (modules, expressions, patterns, types, declarations)
- Handle JSON encoding/decoding for configuration files
- Provide parser combinators and primitives for language parsing
- Support GLSL shader parsing within Canopy code
- Handle all lexical elements (keywords, numbers, strings, symbols, variables)

**Current Size**: ~15 modules
**Compile Impact**: Medium - changes mainly affect build phase, not runtime

```
libs/canopy-language-parser/
├── canopy-language-parser.cabal
├── src/
│   └── Canopy/
│       ├── LanguageParser/
│       │   ├── Module.hs              # From: compiler/src/Parse/Module.hs
│       │   │                          # Top-level module parser
│       │   ├── Expression.hs          # From: compiler/src/Parse/Expression.hs
│       │   │                          # Expression parsing
│       │   ├── Pattern.hs             # From: compiler/src/Parse/Pattern.hs
│       │   │                          # Pattern matching parser
│       │   ├── TypeAnnotation.hs      # From: compiler/src/Parse/Type.hs
│       │   │                          # Type annotation parser
│       │   ├── Declaration.hs         # From: compiler/src/Parse/Declaration.hs
│       │   │                          # Top-level declaration parser
│       │   ├── Primitives.hs          # From: compiler/src/Parse/Primitives.hs
│       │   │                          # Parser combinator primitives
│       │   └── Lexical/
│       │       ├── Keywords.hs        # From: compiler/src/Parse/Keyword.hs
│       │       │                      # Keyword recognition
│       │       ├── Numbers.hs         # From: compiler/src/Parse/Number.hs
│       │       │                      # Number literal parsing
│       │       ├── Strings.hs         # From: compiler/src/Parse/String.hs
│       │       │                      # String literal parsing
│       │       ├── Symbols.hs         # From: compiler/src/Parse/Symbol.hs
│       │       │                      # Symbol and operator parsing
│       │       ├── Variables.hs       # From: compiler/src/Parse/Variable.hs
│       │       │                      # Variable name parsing
│       │       ├── Whitespace.hs      # From: compiler/src/Parse/Space.hs
│       │       │                      # Whitespace and comment handling
│       │       └── Shader.hs          # From: compiler/src/Parse/Shader.hs
│       │                              # GLSL shader parsing
│       └── JSON/
│           ├── Decoder.hs             # From: compiler/src/Json/Decode.hs
│           │                          # JSON decoder
│           ├── Encoder.hs             # From: compiler/src/Json/Encode.hs
│           │                          # JSON encoder
│           └── StringUtilities.hs     # From: compiler/src/Json/String.hs
│                                      # JSON string utilities
└── test/
    └── Unit/
        ├── LanguageParser/
        └── JSON/
```

### libs/canopy-type-system/

**Purpose**: Type inference, constraint solving, and name resolution (canonicalization)
**Key Responsibilities**:
- Core type representation and type checking algorithms
- Constraint generation and solving for type inference
- Type unification with occurs check for infinite types
- Name resolution and canonicalization of all language constructs  
- Environment management for scoping and duplicate detection
- Import resolution and foreign function interface handling

**Current Size**: ~25 modules
**Compile Impact**: High - core to compilation, changes affect optimization and codegen

```
libs/canopy-type-system/
├── canopy-type-system.cabal
├── src/
│   └── Canopy/
│       ├── TypeSystem/
│       │   ├── Types.hs               # From: compiler/src/Type/Type.hs
│       │   │                          # Core type representation
│       │   ├── ConstraintSolver.hs    # From: compiler/src/Type/Solve.hs
│       │   │                          # Constraint solving algorithm
│       │   ├── Unification.hs         # From: compiler/src/Type/Unify.hs
│       │   │                          # Type unification
│       │   ├── OccursCheck.hs         # From: compiler/src/Type/Occurs.hs
│       │   │                          # Occurs check for infinite types
│       │   ├── UnionFind.hs           # From: compiler/src/Type/UnionFind.hs
│       │   │                          # Union-find for type variables
│       │   ├── Errors.hs              # From: compiler/src/Type/Error.hs
│       │   │                          # Type error representation
│       │   ├── Instantiation.hs       # From: compiler/src/Type/Instantiate.hs
│       │   │                          # Type instantiation
│       │   └── Constraints/
│       │       ├── Expression.hs      # From: compiler/src/Type/Constrain/Expression.hs
│       │       │                      # Expression constraint generation
│       │       ├── Pattern.hs         # From: compiler/src/Type/Constrain/Pattern.hs
│       │       │                      # Pattern constraint generation
│       │       └── Module.hs          # From: compiler/src/Type/Constrain/Module.hs
│       │                              # Module-level constraint generation
│       ├── NameResolution/
│       │   ├── Module.hs              # From: compiler/src/Canonicalize/Module.hs
│       │   │                          # Module canonicalization
│       │   ├── Expression.hs          # From: compiler/src/Canonicalize/Expression.hs
│       │   │                          # Expression canonicalization
│       │   ├── Pattern.hs             # From: compiler/src/Canonicalize/Pattern.hs
│       │   │                          # Pattern canonicalization
│       │   ├── TypeAnnotation.hs      # From: compiler/src/Canonicalize/Type.hs
│       │   │                          # Type annotation canonicalization
│       │   ├── Effects.hs             # From: compiler/src/Canonicalize/Effects.hs
│       │   │                          # Effect system canonicalization
│       │   └── Environment/
│       │       ├── Scoping.hs         # From: compiler/src/Canonicalize/Environment.hs
│       │       │                      # Canonicalization environment
│       │       ├── DuplicateNames.hs  # From: compiler/src/Canonicalize/Environment/Dups.hs
│       │       │                      # Duplicate name detection
│       │       ├── ForeignImports.hs  # From: compiler/src/Canonicalize/Environment/Foreign.hs
│       │       │                      # Foreign import handling
│       │       └── LocalScopes.hs     # From: compiler/src/Canonicalize/Environment/Local.hs
│       │                              # Local scope handling
│       └── Compilation/
│           ├── ImportResolver.hs      # From: compiler/src/Canopy/Compiler/Imports.hs
│           │                          # Import resolution
│           ├── TypeUtilities.hs       # From: compiler/src/Canopy/Compiler/Type.hs
│           │                          # Compiler type utilities
│           └── TypeExtraction.hs      # From: compiler/src/Canopy/Compiler/Type/Extract.hs
│                                      # Type extraction utilities
└── test/
    └── Unit/
        ├── TypeSystem/
        ├── NameResolution/
        └── Compilation/
```

### libs/canopy-analyzer/

**Purpose**: Code analysis, optimization, and pattern matching analysis with clear separation between analysis and transformation
**Key Responsibilities**:
- Code analysis for debugging and pattern match exhaustiveness
- Dead code elimination and static analysis
- Pattern match optimization using decision trees
- Expression-level transformations and constant folding
- Name optimization and mangling for smaller output
- Port and effect system analysis and optimization

**Current Size**: ~8 modules
**Compile Impact**: Medium - affects final code quality but not core compilation

```
libs/canopy-analyzer/
├── canopy-analyzer.cabal
├── src/
│   └── Canopy/
│       ├── Analysis/
│       │   ├── Debug.hs               # From: compiler/src/Nitpick/Debug.hs
│       │   │                          # Debug statement analysis
│       │   ├── PatternMatching.hs     # From: compiler/src/Nitpick/PatternMatches.hs
│       │   │                          # Pattern match exhaustiveness
│       │   ├── DeadCode.hs            # NEW: Dead code detection and elimination
│       │   └── Effects.hs             # From: compiler/src/Optimize/Port.hs (analysis part)
│       │                              # Port/effect system analysis
│       └── Optimization/
│           ├── Module.hs              # From: compiler/src/Optimize/Module.hs
│           │                          # Module-level optimizations
│           ├── Expression.hs          # From: compiler/src/Optimize/Expression.hs
│           │                          # Expression transformations
│           ├── Names.hs               # From: compiler/src/Optimize/Names.hs
│           │                          # Name optimization and mangling
│           ├── CaseExpressions.hs     # From: compiler/src/Optimize/Case.hs
│           │                          # Case expression optimization
│           └── DecisionTree.hs        # From: compiler/src/Optimize/DecisionTree.hs
│                                      # Decision tree optimization
└── test/
    └── Unit/
        ├── Analysis/
        └── Optimization/
```

### libs/canopy-code-generator/

**Purpose**: Code generation for JavaScript and HTML targets
**Key Responsibilities**:
- JavaScript code generation from optimized AST
- HTML page generation and embedding
- JavaScript AST building and manipulation
- Function and expression code generation
- Name mangling for JavaScript output
- Generation mode configuration (development vs production)

**Current Size**: ~6 modules
**Compile Impact**: Low - final stage, doesn't affect other compilation phases

```
libs/canopy-code-generator/
├── canopy-code-generator.cabal
├── src/
│   └── Canopy/
│       ├── CodeGenerator/
│       │   ├── Html.hs                # From: compiler/src/Generate/Html.hs
│       │   │                          # HTML page generation
│       │   ├── Mode.hs                # From: compiler/src/Generate/Mode.hs
│       │   │                          # Generation mode configuration
│       │   ├── JavaScript.hs          # From: compiler/src/Generate/JavaScript.hs
│       │   │                          # Main JavaScript codegen
│       │   └── JavaScript/
│       │       ├── ASTBuilder.hs      # From: compiler/src/Generate/JavaScript/Builder.hs
│       │       │                      # JavaScript AST builder
│       │       ├── Expression.hs      # From: compiler/src/Generate/JavaScript/Expression.hs
│       │       │                      # JavaScript expression generation
│       │       ├── Functions.hs       # From: compiler/src/Generate/JavaScript/Functions.hs
│       │       │                      # JavaScript function generation
│       │       └── NameMangling.hs    # From: compiler/src/Generate/JavaScript/Name.hs
│       │                              # JavaScript name mangling
└── test/
    └── Unit/
        └── CodeGenerator/
```

### libs/canopy-diagnostics/

**Purpose**: Error reporting, diagnostics, warnings, and user feedback systems
**Key Responsibilities**:
- Comprehensive error reporting for all compilation phases
- Warning systems and diagnostic messages
- Pretty-printing and document formatting for error output
- Source code highlighting and annotation
- Error suggestions and helpful fix recommendations
- Result types and error handling utilities

**Current Size**: ~20 modules
**Compile Impact**: Low - used for user feedback, doesn't affect compilation correctness

```
libs/canopy-diagnostics/
├── canopy-diagnostics.cabal
├── src/
│   └── Canopy/
│       ├── Diagnostics/
│       │   ├── Annotation.hs          # From: compiler/src/Reporting/Annotation.hs
│       │   │                          # Source location annotations
│       │   ├── Document.hs            # From: compiler/src/Reporting/Doc.hs
│       │   │                          # Pretty-printing document type
│       │   ├── Errors.hs              # From: compiler/src/Reporting/Error.hs
│       │   │                          # Main error type and handling
│       │   ├── Reports.hs             # From: compiler/src/Reporting/Report.hs
│       │   │                          # Error report generation
│       │   ├── Result.hs              # From: compiler/src/Reporting/Result.hs
│       │   │                          # Result type for error handling
│       │   ├── Suggestions.hs         # From: compiler/src/Reporting/Suggest.hs
│       │   │                          # Error suggestions and fixes
│       │   └── Warnings.hs            # From: compiler/src/Reporting/Warning.hs
│       │                              # Warning types and handling
│       ├── ErrorReporting/
│       │   ├── NameResolution.hs      # From: compiler/src/Reporting/Error/Canonicalize.hs
│       │   │                          # Canonicalization error reporting
│       │   ├── Documentation.hs       # From: compiler/src/Reporting/Error/Docs.hs
│       │   │                          # Documentation error reporting
│       │   ├── Imports.hs             # From: compiler/src/Reporting/Error/Import.hs
│       │   │                          # Import error reporting
│       │   ├── JSON.hs                # From: compiler/src/Reporting/Error/Json.hs
│       │   │                          # JSON parsing error reporting
│       │   ├── MainFunction.hs        # From: compiler/src/Reporting/Error/Main.hs
│       │   │                          # Main function error reporting
│       │   ├── PatternMatching.hs     # From: compiler/src/Reporting/Error/Pattern.hs
│       │   │                          # Pattern matching error reporting
│       │   ├── Syntax.hs              # From: compiler/src/Reporting/Error/Syntax.hs
│       │   │                          # Syntax error reporting
│       │   └── Types.hs               # From: compiler/src/Reporting/Error/Type.hs
│       │                              # Type error reporting
│       └── Rendering/
│           ├── SourceCode.hs          # From: compiler/src/Reporting/Render/Code.hs
│           │                          # Source code rendering
│           ├── Types.hs               # From: compiler/src/Reporting/Render/Type.hs
│           │                          # Type rendering for errors
│           └── TypeLocalization.hs    # From: compiler/src/Reporting/Render/Type/Localizer.hs
│                                      # Type name localization
└── test/
    └── Unit/
        ├── Diagnostics/
        ├── ErrorReporting/
        └── Rendering/
```

### libs/canopy-project-management/

**Purpose**: Project configuration, JSON handling, license management, and package metadata
**Key Responsibilities**:
- Project configuration file handling (`canopy.json`, `elm.json`)
- Package metadata and license validation
- JSON encoding/decoding for project-specific data
- Package outline and dependency metadata structures
- Custom repository data and package override configuration

**Current Size**: ~6 modules (extracted from builder and compiler)
**Compile Impact**: Low - mainly data handling and configuration

```
libs/canopy-project-management/
├── canopy-project-management.cabal
├── src/
│   └── Canopy/
│       ├── ProjectManagement/
│       │   ├── Outline.hs             # From: builder/src/Canopy/Outline.hs
│       │   │                          # Project outline (canopy.json structure)
│       │   ├── Licenses.hs            # From: compiler/src/Canopy/Licenses.hs (MOVED)
│       │   │                          # License validation and metadata
│       │   ├── PackageOverrides.hs    # From: builder/src/Canopy/PackageOverrideData.hs
│       │   │                          # Package override configuration
│       │   └── CustomRepository.hs    # From: builder/src/Canopy/CustomRepositoryData.hs
│       │                              # Custom repository data
│       └── JSON/
│           ├── ProjectConfig.hs       # NEW: Project-specific JSON handling
│           ├── PackageMetadata.hs     # NEW: Package metadata JSON
│           └── Validation.hs          # NEW: JSON validation utilities
└── test/
    └── Unit/
        ├── ProjectManagement/
        └── JSON/
```

### compiler-orchestrator/

**Purpose**: High-level compilation pipeline coordination and orchestration
**Key Responsibilities**:
- Main compilation pipeline orchestration (extracted from compiler)
- Phase coordination (parsing → canonicalization → type checking → optimization → codegen)
- Compilation artifact management and result handling
- Clean compilation API for builder and terminal to use

**Current Size**: ~3 modules (extracted from compiler)
**Compile Impact**: High - coordinates entire compilation but isolated from implementation details

```
compiler-orchestrator/
├── compiler-orchestrator.cabal
├── src/
│   └── Canopy/
│       ├── CompilerOrchestrator/
│       │   ├── Pipeline.hs            # From: compiler/src/Compile.hs (MOVED)
│       │   │                          # Main compilation pipeline coordination
│       │   ├── Artifacts.hs           # NEW: Compilation artifact management
│       │   └── API.hs                 # NEW: Clean compilation API
└── test/
    └── Unit/
        └── CompilerOrchestrator/
```

### builder/

**Purpose**: Build system coordination, dependency resolution, and artifact generation (refined focus)
**Key Responsibilities**:
- Build process coordination and task management
- Dependency resolution algorithm and package solver
- Build artifact generation and output management
- HTTP client for package downloads and registry interaction
- Background writer and file system operations
- **REFINED**: Focuses on build orchestration, delegates compilation to compiler-orchestrator

**Current Size**: ~20 modules (reduced by extracting project management and compilation orchestration)
**Compile Impact**: High for build times, but isolated from core compiler changes

```
builder/
├── builder.cabal
├── src/
│   ├── Build.hs                       # From: builder/src/Build.hs
│   │                                  # Main build coordination
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
│   │   └── Details.hs                 # From: builder/src/Canopy/Details.hs
│   │                                  # Project details and cache
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

**Purpose**: CLI interface, user commands, and terminal interaction
**Key Responsibilities**:
- Command-line interface for all canopy commands (`make`, `install`, `repl`, etc.)
- Argument parsing and flag processing
- User interaction, help systems, and error messaging  
- Development server and file watching capabilities
- Package management operations (install, publish, bump)

**Current Size**: ~60 modules
**Compile Impact**: Low - isolated from core compiler, mainly I/O and user interface

**BACKWARD COMPATIBILITY GUARANTEE**: All terminal commands (`canopy make`, `canopy install`, `canopy repl`, etc.) maintain identical interfaces. Only internal module organization changes.

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
│       ├── ArgumentParser.hs           # From: terminal/impl/Terminal/Chomp.hs
│       ├── Command.hs                 # From: terminal/impl/Terminal/Command.hs
│       ├── Completion.hs              # From: terminal/impl/Terminal/Completion.hs
│       ├── Error.hs                   # From: terminal/impl/Terminal/Error.hs
│       ├── Helpers.hs                 # From: terminal/impl/Terminal/Helpers.hs
│       ├── Internal.hs                # From: terminal/impl/Terminal/Internal.hs
│       ├── Parser.hs                  # From: terminal/impl/Terminal/Parser.hs
│       ├── Types.hs                   # From: terminal/impl/Terminal/Types.hs
│       ├── ArgumentParser/
│       │   ├── Arguments.hs           # From: terminal/impl/Terminal/Chomp/Arguments.hs
│       │   ├── Flags.hs               # From: terminal/impl/Terminal/Chomp/Flags.hs
│       │   ├── Parser.hs              # From: terminal/impl/Terminal/Chomp/Parser.hs
│       │   ├── Processing.hs          # From: terminal/impl/Terminal/Chomp/Processing.hs
│       │   ├── Suggestions.hs         # From: terminal/impl/Terminal/Chomp/Suggestion.hs
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
│       ├── ArgumentParserProps.hs     # From: test/Property/Terminal/ChompProps.hs
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
# Example cabal.project for optimal parallel builds with refined package structure
packages: 
  libs/canopy-foundation
  libs/canopy-syntax-tree  
  libs/canopy-language-parser
  libs/canopy-type-system
  libs/canopy-analyzer
  libs/canopy-code-generator
  libs/canopy-diagnostics
  libs/canopy-project-management
  compiler-orchestrator
  builder
  terminal

-- Enable parallel builds
jobs: $ncpus

-- Optimize compilation flags per package based on criticality and refined architecture
package canopy-foundation
  optimization: 2  -- Core foundation needs optimization
  
package canopy-language-parser  
  optimization: 1  -- Parser doesn't need heavy optimization

package canopy-type-system
  optimization: 2  -- Critical path needs optimization

package canopy-analyzer
  optimization: 2  -- Analysis and optimization are performance-critical

package canopy-project-management
  optimization: 1  -- Mainly data handling

package compiler-orchestrator
  optimization: 2  -- High-level coordination needs optimization

package canopy-code-generator
  optimization: 1  -- Final stage, less critical for compile time
```

### 5. Module Organization
- **Smaller Modules**: Following CLAUDE.md 15-line function limit
- **Clear Exports**: Only export necessary functions to reduce interface surface
- **Strategic Re-exports**: Central modules re-export commonly used functions

## 📋 Implementation Phases

### Phase 1: Foundation Setup (Week 1)
- Create multi-package structure with cabal files
- Move `canopy-foundation` modules and establish basic build
- Update import statements to use new structure with semantic names
- Verify basic compilation works

### Phase 2: Syntax Tree and Parser Separation (Week 2)  
- Extract `canopy-syntax-tree` package with AST definitions
- Extract `canopy-language-parser` package with parsing logic  
- Update all import statements throughout codebase to use clear names
- Ensure parser tests pass with new `ArgumentParser` modules

### Phase 3: Type System Extraction (Week 2-3)
- Create `canopy-type-system` with type inference and name resolution
- This is the largest migration - requires careful import management
- Update builder and terminal to use new type system interface
- Verify type system tests pass with improved module organization

### Phase 4: Analysis and Code Generation (Week 3)
- Extract `canopy-analyzer` package with better separation of analysis vs optimization
- Extract `canopy-code-generator` package
- These have fewer interdependencies, should be straightforward
- Update golden tests for JavaScript generation with new names
- Verify analysis and optimization passes work correctly

### Phase 5: Diagnostics and Project Management (Week 4)
- Extract `canopy-diagnostics` package (was `canopy-reporting`)
- **NEW**: Extract `canopy-project-management` package for JSON config handling
- Move `Canopy.Licenses` from compiler to project-management package
- Update all error handling throughout system  
- Ensure error messages still format correctly with improved names
- Test comprehensive diagnostic and error reporting

### Phase 6: Compilation Orchestration (Week 4-5)
- **NEW**: Extract `compiler-orchestrator` package for high-level compilation coordination
- Move `Compile.hs` from compiler to compiler-orchestrator
- Create clean compilation API for builder and terminal to use
- Verify compilation pipeline coordination works correctly

### Phase 7: Builder and Terminal Updates (Week 5-6)
- Update `builder` package to use new library structure with refined responsibilities
- Update `terminal` package to use shared environment patterns from foundation
- Verify all CLI commands work correctly with new orchestrator API
- Update integration tests to work with refined package structure

### Phase 8: Testing and CI (Week 6)
- Reorganize test suites per package including new packages
- Update CI configuration for optimal multi-package builds
- Add package-level benchmarks for all new packages
- Verify parallel compilation works correctly with refined structure

### Phase 9: Documentation and Polish (Week 7)
- Update CLAUDE.md with refined architecture guidelines and new packages
- Create package-level documentation for all new packages
- Add migration guide for contributors showing package reorganization
- Performance validation and optimization of refined structure

## 🔧 Build Configuration

### Root cabal.project
```yaml
packages: 
  libs/canopy-foundation
  libs/canopy-syntax-tree  
  libs/canopy-language-parser
  libs/canopy-type-system
  libs/canopy-analyzer
  libs/canopy-code-generator
  libs/canopy-diagnostics
  libs/canopy-project-management
  compiler-orchestrator
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

-- Package-specific optimizations based on refined optimal architecture
package canopy-foundation
  optimization: 2
  ghc-options: -O2 -funbox-strict-fields

package canopy-type-system  
  optimization: 2
  ghc-options: -O2 -funbox-strict-fields -fspecialise-aggressively

package canopy-analyzer
  optimization: 2
  ghc-options: -O2 -fspecialise-aggressively

package compiler-orchestrator
  optimization: 2
  ghc-options: -O2 -funbox-strict-fields

package canopy-language-parser
  optimization: 1
  ghc-options: -O1

package canopy-project-management
  optimization: 1
  ghc-options: -O1

-- Development settings
if impl(ghc >= 9.2)
  package *
    ghc-options: -Wno-unused-packages
```

### Example Package cabal File
```yaml
# libs/canopy-foundation/canopy-foundation.cabal
cabal-version: 2.2
name: canopy-foundation
version: 0.19.1
synopsis: Foundational types and utilities for Canopy compiler
description: Core types, names, collections, and data structures that form the base of all other Canopy compiler packages

library
  exposed-modules:
    Canopy.Foundation.ModuleName
    Canopy.Foundation.Package  
    Canopy.Foundation.Version
    Canopy.Foundation.Name
    Canopy.Foundation.Text
    Canopy.Collections.Bag
    Canopy.Collections.Index
    Canopy.Collections.NonEmptyList
    Canopy.Collections.OneOrMore
    Canopy.Collections.Utf8
    Canopy.Collections.MapUtilities
    Canopy.Numeric.Float
    Canopy.Numeric.Magnitude
    Canopy.Numeric.Constraint

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

## 🎉 Refined Architecture Benefits

### **Optimal Separation of Concerns**
The refined architecture addresses all identified issues while maintaining the excellent foundation:

#### **Environment Pattern Consolidation** ✅
- Shared environment utilities in `canopy-foundation/Environment/`
- Eliminates duplication across terminal commands
- Reusable project detection and configuration patterns

#### **Better Package Boundaries** ✅
- `canopy-project-management` handles all JSON configuration and license management
- `compiler-orchestrator` provides clean compilation API
- `canopy-analyzer` better separates analysis from transformation
- `builder` focused on build coordination, not compilation details

#### **Module Misplacement Fixed** ✅
- `Canopy.Licenses` moved from compiler to project-management where it belongs
- `Compile.hs` extracted to dedicated orchestrator package
- JSON configuration consolidated in appropriate package

#### **Cleaner Dependencies** ✅
- Terminal commands depend on shared foundation patterns
- Builder uses orchestrator API instead of direct compiler access
- Clear layering from foundation → core libs → orchestrator → builder → terminal

### **Expected Performance Improvements**

#### **Compile Time Optimizations**:
- **Parallel Compilation**: Up to 4x faster on multi-core systems with refined package structure
- **Incremental Builds**: 5-10x faster for typical changes due to better boundaries
- **Reduced Rebuilds**: Changes isolated to more specific packages
- **Smaller Interface Surface**: Refined packages have cleaner APIs

#### **Development Experience**:
- **Clearer Ownership**: Each package has focused, well-defined responsibilities
- **Better Reusability**: Shared patterns extracted for reuse across commands
- **Easier Debugging**: Issues confined to specific packages with clear boundaries
- **Improved IDE Support**: Smaller, focused compilation units

### **Backward Compatibility Maintained** ✅
All terminal commands (`canopy make`, `canopy install`, etc.) work exactly as before. Internal refactoring provides better organization without breaking changes.

This refined architecture transforms the already-excellent Canopy compiler into an optimally-structured, maintainable, and blazingly-fast multi-package system that demonstrates best practices in Haskell software architecture.