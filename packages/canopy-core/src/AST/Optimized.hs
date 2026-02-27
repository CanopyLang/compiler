-- | AST.Optimized - Optimized AST for efficient code generation
--
-- This module defines the Optimized AST representation used after optimization
-- passes and before final code generation. The Optimized AST is designed for
-- maximum efficiency in code generation with simplified constructs, resolved
-- dependencies, and optimized control flow.
--
-- The optimization process transforms the Canonical AST by:
-- * Simplifying expression forms for efficient codegen
-- * Resolving all variable references to global/local classification
-- * Optimizing pattern matching with decision trees
-- * Flattening nested scopes and optimizing function calls
-- * Building dependency graphs for dead code elimination
--
-- == Key Features
--
-- * **Simplified Expressions** - Minimal expression forms optimized for codegen
-- * **Global Variables** - All references resolved to global or local classification
-- * **Decision Trees** - Pattern matching optimized with decision tree compilation
-- * **Dependency Graphs** - Complete dependency tracking for optimization
-- * **Tail Call Optimization** - Explicit tail call representation
-- * **Kernel Integration** - Direct support for kernel function calls
--
-- == Architecture
--
-- The Optimized AST represents the final form before code generation:
--
-- * 'Expr' - Simplified expressions with efficient representations
-- * 'Global' - Global variable references with canonical module information
-- * 'Def' - Optimized definitions with tail call forms
-- * 'Decider' - Decision trees for efficient pattern matching compilation
-- * 'GlobalGraph' - Complete dependency graphs for linking and optimization
--
-- Each construct is designed for direct translation to target languages
-- with minimal additional processing required.
--
-- == Optimization Strategy
--
-- The Optimized AST incorporates several key optimizations:
--
-- * **Variable Classification** - Efficient local vs global access patterns
-- * **Pattern Compilation** - Decision trees minimize runtime pattern testing
-- * **Tail Call Optimization** - Explicit tail calls avoid stack growth
-- * **Dead Code Elimination** - Dependency graphs enable precise DCE
-- * **Constructor Optimization** - Efficient representations for enums and unboxing
--
-- == Usage Examples
--
-- === Global Variable References
--
-- @
-- -- Local variable (function parameter)
-- let localVar = VarLocal "x"
--
-- -- Global function from same module
-- let globalVar = VarGlobal (Global currentModule "helper")
--
-- -- Kernel function
-- let kernelVar = VarKernel "eq" "$eq"
-- @
--
-- === Optimized Function Definitions
--
-- @
-- -- Simple definition
-- let simpleDef = Def "square" (Call (VarLocal "x") [VarLocal "x"])
--
-- -- Tail-optimized recursive function
-- let tailDef = TailDef "factorial" ["n", "acc"] 
--   (TailCall "factorial" [("n", Call subtract [VarLocal "n", Int 1]),
--                         ("acc", Call multiply [VarLocal "n", VarLocal "acc"])])
-- @
--
-- === Decision Tree Pattern Matching
--
-- @
-- -- Optimized case expression with decision tree
-- let optimizedCase = Case "input" "result" decisionTree
--   [(0, Str "nothing"),    -- Nothing branch
--    (1, VarLocal "value")] -- Just branch
-- @
--
-- === Dependency Graph Construction
--
-- @
-- -- Build global dependency graph
-- let graph = addGlobalGraph moduleGraph1 moduleGraph2
-- let finalGraph = addKernel "customOp" kernelChunks graph
-- @
--
-- == Error Handling
--
-- The Optimized AST assumes successful optimization - any optimization
-- failures should be caught during the optimization phases. The optimized
-- representation should be ready for direct code generation.
--
-- == Performance Characteristics
--
-- * **Memory Usage**: Optimized for minimal allocation during codegen
-- * **Code Generation**: Direct translation with minimal processing overhead
-- * **Pattern Matching**: O(log n) pattern tests via decision trees
-- * **Variable Access**: O(1) local access, O(1) global lookup
-- * **Dependency Analysis**: Pre-computed graphs enable fast analysis
--
-- == Thread Safety
--
-- All Optimized AST types are immutable and thread-safe. Code generation
-- can be parallelized across modules using the dependency graph information.
--
-- @since 0.19.1
module AST.Optimized
  ( Def (..),
    Expr (..),
    Global (..),
    Path (..),
    Destructor (..),
    Decider (..),
    Choice (..),
    GlobalGraph (..),
    LocalGraph (..),
    Main (..),
    Node (..),
    EffectsType (..),
    empty,
    addGlobalGraph,
    addLocalGraph,
    addKernel,
    toKernelGlobal,
  )
where

import AST.Optimized.Expr
  ( Choice (..),
    Decider (..),
    Def (..),
    Destructor (..),
    Expr (..),
    Global (..),
    Path (..),
  )
import AST.Optimized.Graph
  ( EffectsType (..),
    GlobalGraph (..),
    LocalGraph (..),
    Main (..),
    Node (..),
    addGlobalGraph,
    addKernel,
    addLocalGraph,
    empty,
    toKernelGlobal,
  )

