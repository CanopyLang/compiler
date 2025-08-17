# Canopy CLAUDE.md Compliance Refactoring Checklist

This checklist tracks comprehensive refactoring of ALL modules in the Canopy compiler project to achieve complete CLAUDE.md compliance. Each item represents a "run command `/refactor MODULENAME`" for systematic code quality improvement.

## 🔴 CRITICAL - High Priority Refactoring

### Builder Core Modules

- [x] run command `/refactor Build.hs` - Main build orchestration module
- [x] run command `/refactor File.hs` - File system operations and I/O
- [x] run command `/refactor Build/Types.hs` - Core build system types
- [x] run command `/refactor Build/Config.hs` - Build configuration management
- [x] run command `/refactor Build/Crawl.hs` - Module discovery and crawling
- [x] run command `/refactor Build/Dependencies.hs` - Dependency resolution
- [ ] run command `/refactor Build/Module/Check.hs` - Module validation and checking
- [ ] run command `/refactor Build/Paths.hs` - Path-based build operations

### Compiler Core Modules

- [ ] run command `/refactor Type/Solve.hs` - Type constraint solving (CRITICAL)
- [ ] run command `/refactor Parse/Module.hs` - Module parsing logic
- [ ] run command `/refactor Parse/Expression.hs` - Expression parsing
- [ ] run command `/refactor Generate/JavaScript.hs` - JavaScript code generation
- [ ] run command `/refactor Type/Unify.hs` - Type unification algorithm
- [ ] run command `/refactor Type/Type.hs` - Core type system
- [ ] run command `/refactor Type/Error.hs` - Type error reporting
- [ ] run command `/refactor Canonicalize/Expression.hs` - Expression canonicalization
- [ ] run command `/refactor Canonicalize/Module.hs` - Module canonicalization
- [ ] run command `/refactor Compile.hs` - Main compilation orchestrator

### Terminal Core Modules

- [ ] run command `/refactor Make.hs` - Build command implementation
- [ ] run command `/refactor Install.hs` - Package installation
- [ ] run command `/refactor Repl.hs` - Interactive REPL implementation
- [ ] run command `/refactor Develop.hs` - Development server
- [ ] run command `/refactor Bump.hs` - Version bumping
- [ ] run command `/refactor Publish.hs` - Package publishing
- [ ] run command `/refactor Diff.hs` - Package diffing
- [ ] run command `/refactor Init.hs` - Project initialization
- [ ] run command `/refactor Watch.hs` - File watching

## 🟡 HIGH - Parser Modules

### Parse System

- [ ] run command `/refactor Parse/Declaration.hs` - Declaration parsing
- [ ] run command `/refactor Parse/Pattern.hs` - Pattern parsing
- [ ] run command `/refactor Parse/Type.hs` - Type annotation parsing
- [ ] run command `/refactor Parse/Primitives.hs` - Parsing primitives
- [ ] run command `/refactor Parse/String.hs` - String literal parsing
- [ ] run command `/refactor Parse/Number.hs` - Number literal parsing
- [ ] run command `/refactor Parse/Keyword.hs` - Keyword parsing
- [ ] run command `/refactor Parse/Variable.hs` - Variable parsing
- [ ] run command `/refactor Parse/Symbol.hs` - Symbol parsing
- [ ] run command `/refactor Parse/Space.hs` - Whitespace handling
- [ ] run command `/refactor Parse/Shader.hs` - Shader parsing

## 🟡 HIGH - Type System Modules

### Type Inference

- [ ] run command `/refactor Type/Constrain/Expression.hs` - Expression constraints
- [ ] run command `/refactor Type/Constrain/Module.hs` - Module constraints
- [ ] run command `/refactor Type/Constrain/Pattern.hs` - Pattern constraints
- [ ] run command `/refactor Type/Instantiate.hs` - Type instantiation
- [ ] run command `/refactor Type/Occurs.hs` - Occurs check
- [ ] run command `/refactor Type/UnionFind.hs` - Union-find data structure

## 🟡 HIGH - Code Generation

### JavaScript Backend

- [ ] run command `/refactor Generate/JavaScript/Expression.hs` - JS expression generation
- [ ] run command `/refactor Generate/JavaScript/Builder.hs` - JS builder utilities
- [ ] run command `/refactor Generate/JavaScript/Functions.hs` - JS function generation
- [ ] run command `/refactor Generate/JavaScript/Name.hs` - JS name generation
- [ ] run command `/refactor Generate/Html.hs` - HTML generation
- [ ] run command `/refactor Generate/Mode.hs` - Generation modes

## 🟡 HIGH - Canonicalization

### AST Transformation

- [ ] run command `/refactor Canonicalize/Pattern.hs` - Pattern canonicalization
- [ ] run command `/refactor Canonicalize/Type.hs` - Type canonicalization
- [ ] run command `/refactor Canonicalize/Environment.hs` - Environment handling
- [ ] run command `/refactor Canonicalize/Environment/Local.hs` - Local environment
- [ ] run command `/refactor Canonicalize/Environment/Foreign.hs` - Foreign environment
- [ ] run command `/refactor Canonicalize/Environment/Dups.hs` - Duplicate detection
- [ ] run command `/refactor Canonicalize/Effects.hs` - Effect handling

## 🟠 MEDIUM - Build System

### Builder Support

- [ ] run command `/refactor BackgroundWriter.hs` - Background writing operations
- [ ] run command `/refactor Generate.hs` - Generation utilities
- [ ] run command `/refactor Http.hs` - HTTP utilities
- [ ] run command `/refactor Reporting.hs` - Build reporting
- [ ] run command `/refactor Deps/Solver.hs` - Dependency solver
- [ ] run command `/refactor Deps/Registry.hs` - Package registry
- [ ] run command `/refactor Deps/Bump.hs` - Version bumping logic
- [ ] run command `/refactor Deps/Diff.hs` - Package diffing
- [ ] run command `/refactor Deps/Website.hs` - Website operations
- [ ] run command `/refactor Deps/CustomRepositoryDataIO.hs` - Custom repository I/O

### Canopy Core Types

- [ ] run command `/refactor Canopy/Details.hs` - Project details
- [ ] run command `/refactor Canopy/Outline.hs` - Project outline
- [ ] run command `/refactor Canopy/CustomRepositoryData.hs` - Custom repository data
- [ ] run command `/refactor Canopy/PackageOverrideData.hs` - Package override data

### Stuff Utilities

- [ ] run command `/refactor Stuff.hs` - General utilities
- [ ] run command `/refactor Stuff/Cache.hs` - Caching utilities
- [ ] run command `/refactor Stuff/Discovery.hs` - Discovery utilities
- [ ] run command `/refactor Stuff/Locking.hs` - Locking mechanisms
- [ ] run command `/refactor Stuff/Paths.hs` - Path utilities

### Logging and Reporting

- [ ] run command `/refactor Logging/Logger.hs` - Logging system
- [ ] run command `/refactor Reporting/Task.hs` - Task reporting
- [ ] run command `/refactor Reporting/Build.hs` - Build reporting
- [ ] run command `/refactor Reporting/Exit.hs` - Exit handling
- [ ] run command `/refactor Reporting/Exit/Help.hs` - Help text
- [ ] run command `/refactor Reporting/Ask.hs` - User interaction
- [ ] run command `/refactor Reporting/Attempt.hs` - Attempt tracking
- [ ] run command `/refactor Reporting/Details.hs` - Detailed reporting
- [ ] run command `/refactor Reporting/Key.hs` - Reporting keys
- [ ] run command `/refactor Reporting/Platform.hs` - Platform reporting
- [ ] run command `/refactor Reporting/Style.hs` - Styling utilities

## 🟠 MEDIUM - Compiler Support

### AST Modules

- [ ] run command `/refactor AST/Source.hs` - Source AST
- [ ] run command `/refactor AST/Canonical.hs` - Canonical AST
- [ ] run command `/refactor AST/Optimized.hs` - Optimized AST
- [ ] run command `/refactor AST/Utils/Binop.hs` - Binary operator utilities
- [ ] run command `/refactor AST/Utils/Shader.hs` - Shader utilities
- [ ] run command `/refactor AST/Utils/Type.hs` - Type utilities

### Canopy Compiler

- [ ] run command `/refactor Canopy/Compiler/Type.hs` - Compiler type operations
- [ ] run command `/refactor Canopy/Compiler/Type/Extract.hs` - Type extraction
- [ ] run command `/refactor Canopy/Compiler/Imports.hs` - Import handling

### Core Data Types

- [ ] run command `/refactor Canopy/ModuleName.hs` - Module name handling
- [ ] run command `/refactor Canopy/Package.hs` - Package operations
- [ ] run command `/refactor Canopy/Version.hs` - Version handling
- [ ] run command `/refactor Canopy/Constraint.hs` - Constraint handling
- [ ] run command `/refactor Canopy/Float.hs` - Float utilities
- [ ] run command `/refactor Canopy/String.hs` - String utilities
- [ ] run command `/refactor Canopy/Magnitude.hs` - Magnitude handling
- [ ] run command `/refactor Canopy/Interface.hs` - Interface operations
- [ ] run command `/refactor Canopy/Kernel.hs` - Kernel operations
- [ ] run command `/refactor Canopy/Licenses.hs` - License handling
- [ ] run command `/refactor Canopy/Docs.hs` - Documentation generation

### Data Structures

- [ ] run command `/refactor Data/Name.hs` - Name data structure
- [ ] run command `/refactor Data/Bag.hs` - Bag data structure
- [ ] run command `/refactor Data/Index.hs` - Index data structure
- [ ] run command `/refactor Data/NonEmptyList.hs` - Non-empty list
- [ ] run command `/refactor Data/OneOrMore.hs` - One-or-more structure
- [ ] run command `/refactor Data/Utf8.hs` - UTF-8 handling
- [ ] run command `/refactor Data/Map/Utils.hs` - Map utilities

### JSON Support

- [ ] run command `/refactor Json/Encode.hs` - JSON encoding
- [ ] run command `/refactor Json/Decode.hs` - JSON decoding
- [ ] run command `/refactor Json/String.hs` - JSON string handling

### Optimization

- [ ] run command `/refactor Optimize/Expression.hs` - Expression optimization
- [ ] run command `/refactor Optimize/Case.hs` - Case optimization
- [ ] run command `/refactor Optimize/DecisionTree.hs` - Decision tree optimization
- [ ] run command `/refactor Optimize/Module.hs` - Module optimization
- [ ] run command `/refactor Optimize/Names.hs` - Name optimization
- [ ] run command `/refactor Optimize/Port.hs` - Port optimization

### Nitpicking

- [ ] run command `/refactor Nitpick/Debug.hs` - Debug nitpicking
- [ ] run command `/refactor Nitpick/PatternMatches.hs` - Pattern match analysis

### Error Reporting

- [ ] run command `/refactor Reporting/Error.hs` - Error reporting
- [ ] run command `/refactor Reporting/Error/Canonicalize.hs` - Canonicalize errors
- [ ] run command `/refactor Reporting/Error/Type.hs` - Type errors
- [ ] run command `/refactor Reporting/Error/Syntax.hs` - Syntax errors
- [ ] run command `/refactor Reporting/Error/Pattern.hs` - Pattern errors
- [ ] run command `/refactor Reporting/Error/Docs.hs` - Documentation errors
- [ ] run command `/refactor Reporting/Error/Import.hs` - Import errors
- [ ] run command `/refactor Reporting/Error/Json.hs` - JSON errors
- [ ] run command `/refactor Reporting/Error/Main.hs` - Main function errors

### Reporting Infrastructure

- [ ] run command `/refactor Reporting/Annotation.hs` - Annotation handling
- [ ] run command `/refactor Reporting/Doc.hs` - Document generation
- [ ] run command `/refactor Reporting/Report.hs` - Report generation
- [ ] run command `/refactor Reporting/Result.hs` - Result handling
- [ ] run command `/refactor Reporting/Suggest.hs` - Suggestion system
- [ ] run command `/refactor Reporting/Warning.hs` - Warning system
- [ ] run command `/refactor Reporting/Render/Code.hs` - Code rendering
- [ ] run command `/refactor Reporting/Render/Type.hs` - Type rendering
- [ ] run command `/refactor Reporting/Render/Type/Localizer.hs` - Type localization

## 🟠 MEDIUM - Terminal Commands

### Make System

- [ ] run command `/refactor Make/Types.hs` - Make types
- [ ] run command `/refactor Make/Parser.hs` - Make parsing
- [ ] run command `/refactor Make/Environment.hs` - Make environment
- [ ] run command `/refactor Make/Generation.hs` - Make generation
- [ ] run command `/refactor Make/Builder.hs` - Make builder
- [ ] run command `/refactor Make/Output.hs` - Make output

### Install System

- [ ] run command `/refactor Install/Types.hs` - Install types
- [ ] run command `/refactor Install/Arguments.hs` - Install arguments
- [ ] run command `/refactor Install/Display.hs` - Install display
- [ ] run command `/refactor Install/Changes.hs` - Install changes
- [ ] run command `/refactor Install/Execution.hs` - Install execution
- [ ] run command `/refactor Install/AppPlan.hs` - Application install plan
- [ ] run command `/refactor Install/PkgPlan.hs` - Package install plan

### Development Server

- [ ] run command `/refactor Develop/Types.hs` - Development types
- [ ] run command `/refactor Develop/Environment.hs` - Development environment
- [ ] run command `/refactor Develop/MimeTypes.hs` - MIME type handling
- [ ] run command `/refactor Develop/Socket.hs` - Socket operations
- [ ] run command `/refactor Develop/Server.hs` - Server implementation
- [ ] run command `/refactor Develop/Compilation.hs` - Development compilation
- [ ] run command `/refactor Develop/StaticFiles.hs` - Static file serving
- [ ] run command `/refactor Develop/StaticFiles/Build.hs` - Static file building
- [ ] run command `/refactor Develop/Generate/Index.hs` - Index generation
- [ ] run command `/refactor Develop/Generate/Help.hs` - Help generation

### CLI System

- [ ] run command `/refactor CLI/Types.hs` - CLI types
- [ ] run command `/refactor CLI/Parsers.hs` - CLI parsing
- [ ] run command `/refactor CLI/Commands.hs` - CLI commands
- [ ] run command `/refactor CLI/Documentation.hs` - CLI documentation

### Bump System

- [ ] run command `/refactor Bump/Types.hs` - Bump types
- [ ] run command `/refactor Bump/Environment.hs` - Bump environment
- [ ] run command `/refactor Bump/Operations.hs` - Bump operations
- [ ] run command `/refactor Bump/Validation.hs` - Bump validation
- [ ] run command `/refactor Bump/Analysis.hs` - Bump analysis

### Diff System

- [ ] run command `/refactor Diff/Types.hs` - Diff types
- [ ] run command `/refactor Diff/Environment.hs` - Diff environment
- [ ] run command `/refactor Diff/Output.hs` - Diff output
- [ ] run command `/refactor Diff/Outline.hs` - Diff outline
- [ ] run command `/refactor Diff/Execution.hs` - Diff execution
- [ ] run command `/refactor Diff/Documentation.hs` - Diff documentation

### Init System

- [ ] run command `/refactor Init/Types.hs` - Init types
- [ ] run command `/refactor Init/Environment.hs` - Init environment
- [ ] run command `/refactor Init/Display.hs` - Init display
- [ ] run command `/refactor Init/Project.hs` - Project initialization
- [ ] run command `/refactor Init/Validation.hs` - Init validation

### Publish System

- [ ] run command `/refactor Publish/Types.hs` - Publish types
- [ ] run command `/refactor Publish/Environment.hs` - Publish environment
- [ ] run command `/refactor Publish/Registry.hs` - Registry operations
- [ ] run command `/refactor Publish/Git.hs` - Git operations
- [ ] run command `/refactor Publish/Progress.hs` - Progress tracking
- [ ] run command `/refactor Publish/Validation.hs` - Publish validation

### REPL System

- [ ] run command `/refactor Repl/Types.hs` - REPL types
- [ ] run command `/refactor Repl/State.hs` - REPL state management
- [ ] run command `/refactor Repl/Commands.hs` - REPL commands
- [ ] run command `/refactor Repl/Eval.hs` - REPL evaluation

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
