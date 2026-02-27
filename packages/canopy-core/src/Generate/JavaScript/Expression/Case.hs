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
      [ JS.Switch
          ( case edges of
              firstEdge : _ -> generateCaseTest genExpr mode root path (fst firstEdge)
              [] -> InternalError.report
                "Generate.JavaScript.Expression.Case.generateDecider"
                "Empty edges list in FanOut"
                "A FanOut decision node must have at least one edge. The decision tree builder should never create a FanOut with zero edges."
          )
          ( foldr
              (\edge cases -> generateCaseBranch genExpr codeToStmts mode label root edge : cases)
              [JS.Default (generateDecider genExpr codeToStmts mode label root fallback)]
              edges
          )
      ]

-- | Generate JavaScript expression for a single if-chain test in a decision tree.
--
-- @since 0.19.1
generateIfTest :: CodeGenerator -> Mode.Mode -> Name.Name -> (DT.Path, DT.Test) -> JS.Expr
generateIfTest genExpr mode root (path, test) =
  let value = pathToJsExpr genExpr mode root path
   in case test of
        DT.IsCtor home name index _ opts ->
          let tag =
                case mode of
                  Mode.Dev _ _ _ _ -> JS.Access value JsName.dollar
                  Mode.Prod {} ->
                    case opts of
                      Can.Normal -> JS.Access value JsName.dollar
                      Can.Enum -> value
                      Can.Unbox -> value
           in Call.strictEq tag $
                case mode of
                  Mode.Dev _ _ _ _ -> JS.String (Name.toBuilder name)
                  Mode.Prod {} -> JS.Int (ctorToInt home name index)
        DT.IsBool True ->
          value
        DT.IsBool False ->
          JS.Prefix JS.PrefixNot value
        DT.IsInt int ->
          Call.strictEq value (JS.Int int)
        DT.IsChr char ->
          Call.strictEq (JS.String (Utf8.toBuilder char)) $
            case mode of
              Mode.Dev _ _ _ _ -> JS.Call (JS.Access value (JsName.fromLocal "valueOf")) []
              Mode.Prod {} -> value
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
generateCaseValue mode test =
  case test of
    DT.IsCtor home name index _ _ ->
      case mode of
        Mode.Dev _ _ _ _ -> JS.String (Name.toBuilder name)
        Mode.Prod {} -> JS.Int (ctorToInt home name index)
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
            else case mode of
              Mode.Dev _ _ _ _ ->
                JS.Access value JsName.dollar
              Mode.Prod {} ->
                case opts of
                  Can.Normal ->
                    JS.Access value JsName.dollar
                  Can.Enum ->
                    value
                  Can.Unbox ->
                    value
        DT.IsInt _ ->
          value
        DT.IsStr _ ->
          value
        DT.IsChr _ ->
          case mode of
            Mode.Dev _ _ _ _ ->
              JS.Call (JS.Access value (JsName.fromLocal "valueOf")) []
            Mode.Prod {} ->
              value
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

-- PATTERN PATHS

-- | Generate JavaScript expression to access a value at a decision tree path.
--
-- Translates decision tree paths (Index, Unbox, Empty) into JavaScript
-- field access expressions.
--
-- @since 0.19.1
pathToJsExpr :: CodeGenerator -> Mode.Mode -> Name.Name -> DT.Path -> JS.Expr
pathToJsExpr genExpr mode root path =
  case path of
    DT.Index index subPath ->
      JS.Access (pathToJsExpr genExpr mode root subPath) (JsName.fromIndex index)
    DT.Unbox subPath ->
      case mode of
        Mode.Dev _ _ _ _ ->
          JS.Access (pathToJsExpr genExpr mode root subPath) (JsName.fromIndex Index.first)
        Mode.Prod {} ->
          pathToJsExpr genExpr mode root subPath
    DT.Empty ->
      JS.Ref (JsName.fromLocal root)

-- INTERNAL HELPERS

-- | Convert constructor to integer tag for production mode.
--
-- Red-black tree constructors use negative indices for the tree balancing
-- algorithm; all others use zero-based machine indices.
--
-- @since 0.19.1
ctorToInt :: CtorToInt
ctorToInt home name index =
  if home == ModuleName.dict && name == "RBNode_elm_builtin" || name == "RBEmpty_elm_builtin"
    then negate (Index.toHuman index)
    else Index.toMachine index
