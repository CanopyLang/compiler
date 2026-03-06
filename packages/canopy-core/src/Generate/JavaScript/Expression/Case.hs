{-# LANGUAGE OverloadedStrings #-}

-- | JavaScript case expression generation for the Canopy compiler.
--
-- This module handles code generation for case expressions and pattern
-- matching, including decision tree compilation to JavaScript switch and
-- if statements, and path expression generation for nested pattern access.
--
-- These functions are used by the main expression generator in
-- "Generate.JavaScript.Expression".
--
-- @since 0.19.1
module Generate.JavaScript.Expression.Case
  ( generateCase,
    goto,
    generateDecider,
    generateIfTest,
    generateCaseBranch,
    generateCaseValue,
    generateCaseTest,
    pathToJsExpr,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.ModuleName as ModuleName
import qualified Data.List as List
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Expression.Call as Call
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.Mode as Mode
import qualified Optimize.DecisionTree as DT
import qualified Reporting.InternalError as InternalError

-- | Type alias for the main expression generator to avoid circular imports.
--
-- @since 0.19.1
type CodeGenerator = Mode.Mode -> Opt.Expr -> JS.Expr

-- | Type alias for the ctorToInt function.
--
-- @since 0.19.1
type CtorToInt = ModuleName.Canonical -> Name.Name -> Index.ZeroBased -> Int

-- CASE EXPRESSIONS

-- | Generate JavaScript statements for a case expression.
--
-- Compiles the decision tree and jump table into JavaScript switch/if
-- statements with labeled while loops for fall-through handling.
--
-- @since 0.19.1
generateCase :: CodeGenerator -> (Mode.Mode -> Opt.Expr -> [JS.Stmt]) -> Mode.Mode -> Name.Name -> Name.Name -> Opt.Decider Opt.Choice -> [(Int, Opt.Expr)] -> [JS.Stmt]
generateCase genExpr codeToStmts mode label root decider = foldr (goto codeToStmts mode label) (generateDecider genExpr codeToStmts mode label root decider)

-- | Generate a labeled while loop for a case branch jump target.
--
-- @since 0.19.1
goto :: (Mode.Mode -> Opt.Expr -> [JS.Stmt]) -> Mode.Mode -> Name.Name -> (Int, Opt.Expr) -> [JS.Stmt] -> [JS.Stmt]
goto codeToStmts mode label (index, branch) stmts =
  let labeledDeciderStmt =
        JS.Labelled
          (JsName.makeLabel label index)
          (JS.While (JS.Bool True) (JS.Block stmts))
   in labeledDeciderStmt : codeToStmts mode branch

-- | Compile a decision tree node to JavaScript statements.
--
-- Handles Leaf (inline or jump), Chain (if test), and FanOut (switch)
-- decision tree nodes.
--
-- @since 0.19.1
generateDecider :: CodeGenerator -> (Mode.Mode -> Opt.Expr -> [JS.Stmt]) -> Mode.Mode -> Name.Name -> Name.Name -> Opt.Decider Opt.Choice -> [JS.Stmt]
generateDecider genExpr codeToStmts mode label root decisionTree =
  case decisionTree of
    Opt.Leaf (Opt.Inline branch) ->
      codeToStmts mode branch
    Opt.Leaf (Opt.Jump index) ->
      [JS.Break (Just (JsName.makeLabel label index))]
    Opt.Chain testChain success failure ->
      [ JS.IfStmt
          (List.foldl1' (JS.Infix JS.OpAnd) (fmap (generateIfTest genExpr mode root) testChain))
          (JS.Block $ generateDecider genExpr codeToStmts mode label root success)
          (JS.Block $ generateDecider genExpr codeToStmts mode label root failure)
      ]
    Opt.FanOut path edges fallback ->
      generateFanOut genExpr codeToStmts mode label root path edges fallback

-- | Generate a JavaScript switch statement for a FanOut decision node.
--
-- @since 0.19.2
generateFanOut :: CodeGenerator -> (Mode.Mode -> Opt.Expr -> [JS.Stmt]) -> Mode.Mode -> Name.Name -> Name.Name -> DT.Path -> [(DT.Test, Opt.Decider Opt.Choice)] -> Opt.Decider Opt.Choice -> [JS.Stmt]
generateFanOut genExpr codeToStmts mode label root path edges fallback =
  [ JS.Switch
      (fanOutSwitchExpr genExpr mode root path edges)
      ( foldr
          (\edge cases -> generateCaseBranch genExpr codeToStmts mode label root edge : cases)
          [JS.Default (generateDecider genExpr codeToStmts mode label root fallback)]
          edges
      )
  ]

-- | Extract the switch expression for a FanOut, requiring at least one edge.
--
-- @since 0.19.2
fanOutSwitchExpr :: CodeGenerator -> Mode.Mode -> Name.Name -> DT.Path -> [(DT.Test, Opt.Decider Opt.Choice)] -> JS.Expr
fanOutSwitchExpr genExpr mode root path = \case
  firstEdge : _ -> generateCaseTest genExpr mode root path (fst firstEdge)
  [] -> InternalError.report
    "Generate.JavaScript.Expression.Case.fanOutSwitchExpr"
    "Empty edges list in FanOut decision node"
    "A FanOut decision node must have at least one edge. The decision tree builder should never create a FanOut with zero edges. This indicates a bug in Optimize.DecisionTree."

-- | Generate JavaScript expression for a single if-chain test in a decision tree.
--
-- @since 0.19.1
generateIfTest :: CodeGenerator -> Mode.Mode -> Name.Name -> (DT.Path, DT.Test) -> JS.Expr
generateIfTest genExpr mode root (path, test) =
  let value = pathToJsExpr genExpr mode root path
   in case test of
        DT.IsCtor home name index _ opts ->
          Call.strictEq (ctorTag mode opts value) (ctorTagValue mode home name index)
        DT.IsBool True ->
          value
        DT.IsBool False ->
          JS.Prefix JS.PrefixNot value
        DT.IsInt int ->
          Call.strictEq value (JS.Int int)
        DT.IsChr char ->
          Call.strictEq (JS.String (Utf8.toBuilder char)) (chrValueAccess mode value)
        DT.IsStr string ->
          Call.strictEq value (JS.String (Utf8.toBuilder string))
        DT.IsCons ->
          JS.Access value (JsName.fromLocal "b")
        DT.IsNil ->
          JS.Prefix JS.PrefixNot $
            JS.Access value (JsName.fromLocal "b")
        DT.IsTuple ->
          InternalError.report
            "Generate.JavaScript.Expression.Case.generateIfTest"
            "COMPILER BUG - there should never be tests on a tuple"
            "Tuples are structurally matched and should never appear as a test in the decision tree. This indicates a bug in the pattern match compiler."

-- | Extract the tag accessor for a constructor in a given mode and ctor opts.
--
-- @since 0.19.2
ctorTag :: Mode.Mode -> Can.CtorOpts -> JS.Expr -> JS.Expr
ctorTag (Mode.Dev _ _ _ _ _) _ value = JS.Access value JsName.dollar
ctorTag (Mode.Prod {}) Can.Normal value = JS.Access value JsName.dollar
ctorTag (Mode.Prod {}) Can.Enum value = value
ctorTag (Mode.Prod {}) Can.Unbox value = value

-- | Generate the tag comparison value for a constructor.
--
-- @since 0.19.2
ctorTagValue :: Mode.Mode -> ModuleName.Canonical -> Name.Name -> Index.ZeroBased -> JS.Expr
ctorTagValue (Mode.Dev _ _ _ _ _) _ name _ = JS.String (Name.toBuilder name)
ctorTagValue (Mode.Prod {}) home name index = JS.Int (ctorToInt home name index)

-- | Access the underlying value of a Chr for comparison.
--
-- @since 0.19.2
chrValueAccess :: Mode.Mode -> JS.Expr -> JS.Expr
chrValueAccess (Mode.Dev _ _ _ _ _) value = JS.Call (JS.Access value (JsName.fromLocal "valueOf")) []
chrValueAccess (Mode.Prod {}) value = value

-- | Generate a single case branch (test + subtree) for a switch statement.
--
-- @since 0.19.1
generateCaseBranch :: CodeGenerator -> (Mode.Mode -> Opt.Expr -> [JS.Stmt]) -> Mode.Mode -> Name.Name -> Name.Name -> (DT.Test, Opt.Decider Opt.Choice) -> JS.Case
generateCaseBranch genExpr codeToStmts mode label root (test, subTree) =
  JS.Case
    (generateCaseValue mode test)
    (generateDecider genExpr codeToStmts mode label root subTree)

-- | Generate a JavaScript case value expression for a switch statement.
--
-- @since 0.19.1
generateCaseValue :: Mode.Mode -> DT.Test -> JS.Expr
generateCaseValue mode = \case
  DT.IsCtor home name index _ _ ->
    ctorTagValue mode home name index
  DT.IsInt int ->
    JS.Int int
  DT.IsChr char ->
    JS.String (Utf8.toBuilder char)
  DT.IsStr string ->
    JS.String (Utf8.toBuilder string)
  DT.IsBool _ ->
    InternalError.report
      "Generate.JavaScript.Expression.Case.generateCaseValue"
      "COMPILER BUG - there should never be three tests on a boolean"
      "Booleans only have two constructors (True/False) so at most two tests are ever needed. This indicates a bug in the decision tree builder."
  DT.IsCons ->
    InternalError.report
      "Generate.JavaScript.Expression.Case.generateCaseValue"
      "COMPILER BUG - there should never be three tests on a list"
      "Lists only have two structural cases (Cons/Nil) so at most two tests are ever needed. This indicates a bug in the decision tree builder."
  DT.IsNil ->
    InternalError.report
      "Generate.JavaScript.Expression.Case.generateCaseValue"
      "COMPILER BUG - there should never be three tests on a list"
      "Lists only have two structural cases (Cons/Nil) so at most two tests are ever needed. This indicates a bug in the decision tree builder."
  DT.IsTuple ->
    InternalError.report
      "Generate.JavaScript.Expression.Case.generateCaseValue"
      "COMPILER BUG - there should never be three tests on a tuple"
      "Tuples are structurally matched and should never appear as a case value in the decision tree. This indicates a bug in the pattern match compiler."

-- | Generate the switch expression for a FanOut decision node.
--
-- @since 0.19.1
generateCaseTest :: CodeGenerator -> Mode.Mode -> Name.Name -> DT.Path -> DT.Test -> JS.Expr
generateCaseTest genExpr mode root path exampleTest =
  let value = pathToJsExpr genExpr mode root path
   in case exampleTest of
        DT.IsCtor home name _ _ opts ->
          if name == Name.bool && home == ModuleName.basics
            then value
            else ctorSwitchExpr mode opts value
        DT.IsInt _ ->
          value
        DT.IsStr _ ->
          value
        DT.IsChr _ ->
          chrValueAccess mode value
        DT.IsBool _ ->
          InternalError.report
            "Generate.JavaScript.Expression.Case.generateCaseTest"
            "COMPILER BUG - there should never be three tests on a boolean"
            "Booleans only have two constructors (True/False) so at most two tests are ever needed. This indicates a bug in the decision tree builder."
        DT.IsCons ->
          InternalError.report
            "Generate.JavaScript.Expression.Case.generateCaseTest"
            "COMPILER BUG - there should never be three tests on a list"
            "Lists only have two structural cases (Cons/Nil) so at most two tests are ever needed. This indicates a bug in the decision tree builder."
        DT.IsNil ->
          InternalError.report
            "Generate.JavaScript.Expression.Case.generateCaseTest"
            "COMPILER BUG - there should never be three tests on a list"
            "Lists only have two structural cases (Cons/Nil) so at most two tests are ever needed. This indicates a bug in the decision tree builder."
        DT.IsTuple ->
          InternalError.report
            "Generate.JavaScript.Expression.Case.generateCaseTest"
            "COMPILER BUG - there should never be three tests on a tuple"
            "Tuples are structurally matched and should never appear as a case test. This indicates a bug in the pattern match compiler."

-- | Generate the switch discriminant expression for a constructor in a given mode.
--
-- @since 0.19.2
ctorSwitchExpr :: Mode.Mode -> Can.CtorOpts -> JS.Expr -> JS.Expr
ctorSwitchExpr (Mode.Dev _ _ _ _ _) _ value = JS.Access value JsName.dollar
ctorSwitchExpr (Mode.Prod {}) Can.Normal value = JS.Access value JsName.dollar
ctorSwitchExpr (Mode.Prod {}) Can.Enum value = value
ctorSwitchExpr (Mode.Prod {}) Can.Unbox value = value

-- PATTERN PATHS

-- | Generate JavaScript expression to access a value at a decision tree path.
--
-- Translates decision tree paths (Index, Unbox, Empty) into JavaScript
-- field access expressions.
--
-- @since 0.19.1
pathToJsExpr :: CodeGenerator -> Mode.Mode -> Name.Name -> DT.Path -> JS.Expr
pathToJsExpr genExpr mode root = \case
  DT.Index index subPath ->
    JS.Access (pathToJsExpr genExpr mode root subPath) (JsName.fromIndex index)
  DT.Unbox subPath ->
    unboxPath genExpr mode root subPath
  DT.Empty ->
    JS.Ref (JsName.fromLocal root)

-- | Generate the unbox path expression based on compilation mode.
--
-- In dev mode, unboxed values are accessed at index 0. In prod mode,
-- the unbox is a no-op since single-constructor types are unwrapped.
--
-- @since 0.19.2
unboxPath :: CodeGenerator -> Mode.Mode -> Name.Name -> DT.Path -> JS.Expr
unboxPath genExpr mode@(Mode.Dev _ _ _ _ _) root subPath =
  JS.Access (pathToJsExpr genExpr mode root subPath) (JsName.fromIndex Index.first)
unboxPath genExpr mode@(Mode.Prod {}) root subPath =
  pathToJsExpr genExpr mode root subPath

-- INTERNAL HELPERS

-- | Convert constructor to integer tag for production mode.
--
-- Red-black tree constructors use negative indices starting at -3 to avoid
-- collision with list tags (-1 for Nil, -2 for Cons). All other constructors
-- use zero-based machine indices.
--
-- @since 0.19.1
ctorToInt :: CtorToInt
ctorToInt home name index =
  if home == ModuleName.dict && name == "RBNode_elm_builtin" || name == "RBEmpty_elm_builtin"
    then negate (Index.toHuman index) - 2
    else Index.toMachine index
