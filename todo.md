# Canopy CLAUDE.md Compliance Refactoring Checklist

This checklist tracks comprehensive refactoring of ALL modules in the Canopy compiler project to achieve complete CLAUDE.md compliance. Each item represents a `/refactor MODULENAME` command for systematic code quality improvement.

## 🔴 CRITICAL - High Priority Refactoring

### Builder Core Modules

- [x] `/refactor Build.hs` - Main build orchestration module 
- [x] `/refactor File.hs` - File system operations and I/O
- [ ] `/refactor Build/Types.hs` - Core build system types
- [ ] `/refactor Build/Config.hs` - Build configuration management
- [ ] `/refactor Build/Crawl.hs` - Module discovery and crawling
- [ ] `/refactor Build/Dependencies.hs` - Dependency resolution
- [ ] `/refactor Build/Module/Check.hs` - Module validation and checking
- [ ] `/refactor Build/Paths.hs` - Path-based build operations

### Compiler Core Modules

- [x] `/refactor Type/Solve.hs` - Type constraint solving (CRITICAL)
- [ ] `/refactor Parse/Module.hs` - Module parsing logic
- [ ] `/refactor Parse/Expression.hs` - Expression parsing 
- [ ] `/refactor Generate/JavaScript.hs` - JavaScript code generation
- [ ] `/refactor Type/Unify.hs` - Type unification algorithm
- [ ] `/refactor Type/Type.hs` - Core type system
- [ ] `/refactor Type/Error.hs` - Type error reporting
- [ ] `/refactor Canonicalize/Expression.hs` - Expression canonicalization
- [ ] `/refactor Canonicalize/Module.hs` - Module canonicalization
- [ ] `/refactor Compile.hs` - Main compilation orchestrator

### Terminal Core Modules

- [ ] `/refactor Make.hs` - Build command implementation
- [ ] `/refactor Install.hs` - Package installation
- [ ] `/refactor Repl.hs` - Interactive REPL implementation
- [ ] `/refactor Develop.hs` - Development server
- [ ] `/refactor Bump.hs` - Version bumping
- [ ] `/refactor Publish.hs` - Package publishing
- [ ] `/refactor Diff.hs` - Package diffing
- [ ] `/refactor Init.hs` - Project initialization
- [ ] `/refactor Watch.hs` - File watching

## 🟡 HIGH - Parser Modules

### Parse System

- [ ] `/refactor Parse/Declaration.hs` - Declaration parsing
- [ ] `/refactor Parse/Pattern.hs` - Pattern parsing
- [ ] `/refactor Parse/Type.hs` - Type annotation parsing  
- [ ] `/refactor Parse/Primitives.hs` - Parsing primitives
- [ ] `/refactor Parse/String.hs` - String literal parsing
- [ ] `/refactor Parse/Number.hs` - Number literal parsing
- [ ] `/refactor Parse/Keyword.hs` - Keyword parsing
- [ ] `/refactor Parse/Variable.hs` - Variable parsing
- [ ] `/refactor Parse/Symbol.hs` - Symbol parsing
- [ ] `/refactor Parse/Space.hs` - Whitespace handling
- [ ] `/refactor Parse/Shader.hs` - Shader parsing

## 🟡 HIGH - Type System Modules

### Type Inference

- [ ] `/refactor Type/Constrain/Expression.hs` - Expression constraints
- [ ] `/refactor Type/Constrain/Module.hs` - Module constraints  
- [ ] `/refactor Type/Constrain/Pattern.hs` - Pattern constraints
- [ ] `/refactor Type/Instantiate.hs` - Type instantiation
- [ ] `/refactor Type/Occurs.hs` - Occurs check
- [ ] `/refactor Type/UnionFind.hs` - Union-find data structure

## 🟡 HIGH - Code Generation

### JavaScript Backend

- [ ] `/refactor Generate/JavaScript/Expression.hs` - JS expression generation
- [ ] `/refactor Generate/JavaScript/Builder.hs` - JS builder utilities
- [ ] `/refactor Generate/JavaScript/Functions.hs` - JS function generation
- [ ] `/refactor Generate/JavaScript/Name.hs` - JS name generation
- [ ] `/refactor Generate/Html.hs` - HTML generation
- [ ] `/refactor Generate/Mode.hs` - Generation modes

## 🟡 HIGH - Canonicalization

### AST Transformation

- [ ] `/refactor Canonicalize/Pattern.hs` - Pattern canonicalization
- [ ] `/refactor Canonicalize/Type.hs` - Type canonicalization
- [ ] `/refactor Canonicalize/Environment.hs` - Environment handling
- [ ] `/refactor Canonicalize/Environment/Local.hs` - Local environment
- [ ] `/refactor Canonicalize/Environment/Foreign.hs` - Foreign environment  
- [ ] `/refactor Canonicalize/Environment/Dups.hs` - Duplicate detection
- [ ] `/refactor Canonicalize/Effects.hs` - Effect handling

## 🟠 MEDIUM - Build System

### Builder Support

- [ ] `/refactor BackgroundWriter.hs` - Background writing operations
- [ ] `/refactor Generate.hs` - Generation utilities
- [ ] `/refactor Http.hs` - HTTP utilities
- [ ] `/refactor Reporting.hs` - Build reporting
- [ ] `/refactor Deps/Solver.hs` - Dependency solver
- [ ] `/refactor Deps/Registry.hs` - Package registry
- [ ] `/refactor Deps/Bump.hs` - Version bumping logic
- [ ] `/refactor Deps/Diff.hs` - Package diffing
- [ ] `/refactor Deps/Website.hs` - Website operations
- [ ] `/refactor Deps/CustomRepositoryDataIO.hs` - Custom repository I/O

### Canopy Core Types

- [ ] `/refactor Canopy/Details.hs` - Project details
- [ ] `/refactor Canopy/Outline.hs` - Project outline
- [ ] `/refactor Canopy/CustomRepositoryData.hs` - Custom repository data
- [ ] `/refactor Canopy/PackageOverrideData.hs` - Package override data

### Stuff Utilities

- [ ] `/refactor Stuff.hs` - General utilities
- [ ] `/refactor Stuff/Cache.hs` - Caching utilities
- [ ] `/refactor Stuff/Discovery.hs` - Discovery utilities
- [ ] `/refactor Stuff/Locking.hs` - Locking mechanisms
- [ ] `/refactor Stuff/Paths.hs` - Path utilities

### Logging and Reporting

- [ ] `/refactor Logging/Logger.hs` - Logging system
- [ ] `/refactor Reporting/Task.hs` - Task reporting
- [ ] `/refactor Reporting/Build.hs` - Build reporting
- [ ] `/refactor Reporting/Exit.hs` - Exit handling
- [ ] `/refactor Reporting/Exit/Help.hs` - Help text
- [ ] `/refactor Reporting/Ask.hs` - User interaction
- [ ] `/refactor Reporting/Attempt.hs` - Attempt tracking
- [ ] `/refactor Reporting/Details.hs` - Detailed reporting
- [ ] `/refactor Reporting/Key.hs` - Reporting keys
- [ ] `/refactor Reporting/Platform.hs` - Platform reporting
- [ ] `/refactor Reporting/Style.hs` - Styling utilities

## 🟠 MEDIUM - Compiler Support

### AST Modules

- [ ] `/refactor AST/Source.hs` - Source AST
- [ ] `/refactor AST/Canonical.hs` - Canonical AST
- [ ] `/refactor AST/Optimized.hs` - Optimized AST
- [ ] `/refactor AST/Utils/Binop.hs` - Binary operator utilities
- [ ] `/refactor AST/Utils/Shader.hs` - Shader utilities
- [ ] `/refactor AST/Utils/Type.hs` - Type utilities

### Canopy Compiler

- [ ] `/refactor Canopy/Compiler/Type.hs` - Compiler type operations
- [ ] `/refactor Canopy/Compiler/Type/Extract.hs` - Type extraction
- [ ] `/refactor Canopy/Compiler/Imports.hs` - Import handling

### Core Data Types

- [ ] `/refactor Canopy/ModuleName.hs` - Module name handling
- [ ] `/refactor Canopy/Package.hs` - Package operations
- [ ] `/refactor Canopy/Version.hs` - Version handling
- [ ] `/refactor Canopy/Constraint.hs` - Constraint handling
- [ ] `/refactor Canopy/Float.hs` - Float utilities
- [ ] `/refactor Canopy/String.hs` - String utilities
- [ ] `/refactor Canopy/Magnitude.hs` - Magnitude handling
- [ ] `/refactor Canopy/Interface.hs` - Interface operations
- [ ] `/refactor Canopy/Kernel.hs` - Kernel operations
- [ ] `/refactor Canopy/Licenses.hs` - License handling
- [ ] `/refactor Canopy/Docs.hs` - Documentation generation

### Data Structures

- [ ] `/refactor Data/Name.hs` - Name data structure
- [ ] `/refactor Data/Bag.hs` - Bag data structure
- [ ] `/refactor Data/Index.hs` - Index data structure
- [ ] `/refactor Data/NonEmptyList.hs` - Non-empty list
- [ ] `/refactor Data/OneOrMore.hs` - One-or-more structure
- [ ] `/refactor Data/Utf8.hs` - UTF-8 handling
- [ ] `/refactor Data/Map/Utils.hs` - Map utilities

### JSON Support

- [ ] `/refactor Json/Encode.hs` - JSON encoding
- [ ] `/refactor Json/Decode.hs` - JSON decoding
- [ ] `/refactor Json/String.hs` - JSON string handling

### Optimization

- [ ] `/refactor Optimize/Expression.hs` - Expression optimization
- [ ] `/refactor Optimize/Case.hs` - Case optimization
- [ ] `/refactor Optimize/DecisionTree.hs` - Decision tree optimization
- [ ] `/refactor Optimize/Module.hs` - Module optimization
- [ ] `/refactor Optimize/Names.hs` - Name optimization
- [ ] `/refactor Optimize/Port.hs` - Port optimization

### Nitpicking

- [ ] `/refactor Nitpick/Debug.hs` - Debug nitpicking
- [ ] `/refactor Nitpick/PatternMatches.hs` - Pattern match analysis

### Error Reporting

- [ ] `/refactor Reporting/Error.hs` - Error reporting
- [ ] `/refactor Reporting/Error/Canonicalize.hs` - Canonicalize errors
- [ ] `/refactor Reporting/Error/Type.hs` - Type errors
- [ ] `/refactor Reporting/Error/Syntax.hs` - Syntax errors
- [ ] `/refactor Reporting/Error/Pattern.hs` - Pattern errors
- [ ] `/refactor Reporting/Error/Docs.hs` - Documentation errors
- [ ] `/refactor Reporting/Error/Import.hs` - Import errors
- [ ] `/refactor Reporting/Error/Json.hs` - JSON errors
- [ ] `/refactor Reporting/Error/Main.hs` - Main function errors

### Reporting Infrastructure

- [ ] `/refactor Reporting/Annotation.hs` - Annotation handling
- [ ] `/refactor Reporting/Doc.hs` - Document generation
- [ ] `/refactor Reporting/Report.hs` - Report generation
- [ ] `/refactor Reporting/Result.hs` - Result handling
- [ ] `/refactor Reporting/Suggest.hs` - Suggestion system
- [ ] `/refactor Reporting/Warning.hs` - Warning system
- [ ] `/refactor Reporting/Render/Code.hs` - Code rendering
- [ ] `/refactor Reporting/Render/Type.hs` - Type rendering
- [ ] `/refactor Reporting/Render/Type/Localizer.hs` - Type localization

## 🟠 MEDIUM - Terminal Commands

### Make System

- [ ] `/refactor Make/Types.hs` - Make types
- [ ] `/refactor Make/Parser.hs` - Make parsing
- [ ] `/refactor Make/Environment.hs` - Make environment
- [ ] `/refactor Make/Generation.hs` - Make generation
- [ ] `/refactor Make/Builder.hs` - Make builder
- [ ] `/refactor Make/Output.hs` - Make output

### Install System

- [ ] `/refactor Install/Types.hs` - Install types
- [ ] `/refactor Install/Arguments.hs` - Install arguments
- [ ] `/refactor Install/Display.hs` - Install display
- [ ] `/refactor Install/Changes.hs` - Install changes
- [ ] `/refactor Install/Execution.hs` - Install execution
- [ ] `/refactor Install/AppPlan.hs` - Application install plan
- [ ] `/refactor Install/PkgPlan.hs` - Package install plan

### Development Server

- [ ] `/refactor Develop/Types.hs` - Development types
- [ ] `/refactor Develop/Environment.hs` - Development environment
- [ ] `/refactor Develop/MimeTypes.hs` - MIME type handling
- [ ] `/refactor Develop/Socket.hs` - Socket operations
- [ ] `/refactor Develop/Server.hs` - Server implementation
- [ ] `/refactor Develop/Compilation.hs` - Development compilation
- [ ] `/refactor Develop/StaticFiles.hs` - Static file serving
- [ ] `/refactor Develop/StaticFiles/Build.hs` - Static file building
- [ ] `/refactor Develop/Generate/Index.hs` - Index generation
- [ ] `/refactor Develop/Generate/Help.hs` - Help generation

### CLI System

- [ ] `/refactor CLI/Types.hs` - CLI types
- [ ] `/refactor CLI/Parsers.hs` - CLI parsing
- [ ] `/refactor CLI/Commands.hs` - CLI commands
- [ ] `/refactor CLI/Documentation.hs` - CLI documentation

### Bump System

- [ ] `/refactor Bump/Types.hs` - Bump types
- [ ] `/refactor Bump/Environment.hs` - Bump environment
- [ ] `/refactor Bump/Operations.hs` - Bump operations
- [ ] `/refactor Bump/Validation.hs` - Bump validation
- [ ] `/refactor Bump/Analysis.hs` - Bump analysis

### Diff System

- [ ] `/refactor Diff/Types.hs` - Diff types
- [ ] `/refactor Diff/Environment.hs` - Diff environment
- [ ] `/refactor Diff/Output.hs` - Diff output
- [ ] `/refactor Diff/Outline.hs` - Diff outline
- [ ] `/refactor Diff/Execution.hs` - Diff execution
- [ ] `/refactor Diff/Documentation.hs` - Diff documentation

### Init System

- [ ] `/refactor Init/Types.hs` - Init types
- [ ] `/refactor Init/Environment.hs` - Init environment
- [ ] `/refactor Init/Display.hs` - Init display
- [ ] `/refactor Init/Project.hs` - Project initialization
- [ ] `/refactor Init/Validation.hs` - Init validation

### Publish System

- [ ] `/refactor Publish/Types.hs` - Publish types
- [ ] `/refactor Publish/Environment.hs` - Publish environment
- [ ] `/refactor Publish/Registry.hs` - Registry operations
- [ ] `/refactor Publish/Git.hs` - Git operations
- [ ] `/refactor Publish/Progress.hs` - Progress tracking
- [ ] `/refactor Publish/Validation.hs` - Publish validation

### REPL System

- [ ] `/refactor Repl/Types.hs` - REPL types
- [ ] `/refactor Repl/State.hs` - REPL state management
- [ ] `/refactor Repl/Commands.hs` - REPL commands
- [ ] `/refactor Repl/Eval.hs` - REPL evaluation

---

## Validation Commands

```bash
# Build validation
make build

# Test validation  
make test

# Style validation
make lint
make format

# Check for violations
grep -r "_ = True\|_ = False" test/   # MUST return nothing
rg "function.*{.*\n.*\n.*\n.*\n.*\n.*\n.*\n.*\n.*\n.*\n.*\n.*\n.*\n.*\n.*\n.*}" --multiline src/ # Functions >15 lines
```

## Progress Tracking

**Total Modules**: 180+
**Completed**: 2 
**Remaining**: 178+
**Completion**: 1.1%

### Recently Completed

- ✅ **File.hs** - File system operations (24-line functions decomposed, code duplication eliminated)
- ✅ **Type/Solve.hs** - Type constraint solving (119-line solve function decomposed to 7 lines)

### Next Priority

- **Build/Types.hs** - Fix import issues introduced during Build module refactoring
- **Parse/Module.hs** - Critical parser module for Canopy files
- **Parse/Expression.hs** - Core expression parsing logic