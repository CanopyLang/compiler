{-# LANGUAGE OverloadedStrings #-}

-- | JavaScript call expression generation for the Canopy compiler.
--
-- This module handles code generation for function calls, including:
-- core library call optimizations, arithmetic and bitwise operations,
-- string operations, and comparison helpers.
--
-- These functions are used by the main expression generator in
-- "Generate.JavaScript.Expression".
--
-- @since 0.19.1
module Generate.JavaScript.Expression.Call
  ( generateCall,
    generateCallHelp,
    generateGlobalCall,
    generateNormalCall,
    callHelpers,
    generateCoreCall,
    generateTupleCall,
    generateJsArrayCall,
    generateBitwiseCall,
    generateBasicsCall,
    equal,
    notEqual,
    cmp,
    isLiteral,
    apply,
    append,
    jsAppend,
    toSeqs,
    isStringLiteral,
    strictEq,
    strictNEq,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.IntMap.Strict as IntMap
import qualified Data.List as List
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.Mode as Mode

-- | Type alias for the main expression generator to avoid circular imports.
--
-- This callback pattern allows Call functions to call back into the main
-- generator without creating a circular module dependency.
--
-- @since 0.19.1
type ExprGenerator = Mode.Mode -> Opt.Expr -> JS.Expr

-- CALLS

-- | Generate JavaScript for a function call expression.
--
-- Dispatches to specialized generators for core library calls and
-- box-wrapped function calls, falling back to general call generation.
--
-- @since 0.19.1
generateCall :: ExprGenerator -> Mode.Mode -> Opt.Expr -> [Opt.Expr] -> JS.Expr
generateCall genExpr mode func args =
  case func of
    Opt.VarGlobal global@(Opt.Global (ModuleName.Canonical pkg _) _)
      | Pkg.isCore pkg ->
        generateCoreCall genExpr mode global args
    Opt.VarBox _ ->
      case mode of
        Mode.Dev _ _ _ _ _ ->
          generateCallHelp genExpr mode func args
        Mode.Prod {} ->
          case args of
            [arg] ->
              genExpr mode arg
            _ ->
              generateCallHelp genExpr mode func args
    -- WILDCARD AUDIT: All non-VarGlobal/non-VarBox calls use the generic
    -- call helper. New Opt.Expr variants that need specialised call codegen
    -- should be added above this catch-all.
    _ ->
      generateCallHelp genExpr mode func args

-- | Generate JavaScript for a general (non-specialized) call.
--
-- @since 0.19.1
generateCallHelp :: ExprGenerator -> Mode.Mode -> Opt.Expr -> [Opt.Expr] -> JS.Expr
generateCallHelp genExpr mode func args =
  generateNormalCall
    (genExpr mode func)
    (fmap (genExpr mode) args)

-- | Generate a call to a global (module-qualified) function.
--
-- @since 0.19.1
generateGlobalCall :: ModuleName.Canonical -> Name.Name -> [JS.Expr] -> JS.Expr
generateGlobalCall home name = generateNormalCall (JS.Ref (JsName.fromGlobal home name))

-- | Generate a normal function call, using Fn helpers for multi-arg calls.
--
-- Uses the A2..A9 helpers for 2-9 argument calls for performance,
-- and falls back to curried single-argument calls for other arities.
--
-- @since 0.19.1
generateNormalCall :: JS.Expr -> [JS.Expr] -> JS.Expr
generateNormalCall func args =
  case IntMap.lookup (length args) callHelpers of
    Just helper ->
      JS.Call helper (func : args)
    Nothing ->
      List.foldl' (\f a -> JS.Call f [a]) func args

-- | Pre-built A2..A9 helper function references.
--
-- @since 0.19.1
{-# NOINLINE callHelpers #-}
callHelpers :: IntMap.IntMap JS.Expr
callHelpers =
  IntMap.fromList $
    fmap (\n -> (n, JS.Ref (JsName.makeA n))) [2 .. 9]

-- CORE CALLS

-- | Generate JavaScript for calls to core library functions.
--
-- Dispatches to module-specific generators for Basics, Bitwise, Tuple, and
-- JsArray modules. Falls back to general global call for other core modules.
--
-- @since 0.19.1
generateCoreCall :: ExprGenerator -> Mode.Mode -> Opt.Global -> [Opt.Expr] -> JS.Expr
generateCoreCall genExpr mode (Opt.Global home@(ModuleName.Canonical _ moduleName) name) args
  | moduleName == Name.basics = generateBasicsCall genExpr mode home name args
  | moduleName == Name.bitwise = generateBitwiseCall home name (fmap (genExpr mode) args)
  | moduleName == Name.tuple = generateTupleCall home name (fmap (genExpr mode) args)
  | moduleName == Name.jsArray = generateJsArrayCall home name (fmap (genExpr mode) args)
  | otherwise = generateGlobalCall home name (fmap (genExpr mode) args)

-- | Optimize Tuple.first and Tuple.second to direct field access.
--
-- @since 0.19.1
generateTupleCall :: ModuleName.Canonical -> Name.Name -> [JS.Expr] -> JS.Expr
generateTupleCall home name args =
  case args of
    [value] ->
      case name of
        "first" -> JS.Access value (JsName.fromLocal "a")
        "second" -> JS.Access value (JsName.fromLocal "b")
        _ -> generateGlobalCall home name args
    _ ->
      generateGlobalCall home name args

-- | Optimize JsArray.singleton and JsArray.unsafeGet to native JS constructs.
--
-- @since 0.19.1
generateJsArrayCall :: ModuleName.Canonical -> Name.Name -> [JS.Expr] -> JS.Expr
generateJsArrayCall home name args =
  case args of
    [entry] | name == "singleton" -> JS.Array [entry]
    [index, array] | name == "unsafeGet" -> JS.Index array index
    _ -> generateGlobalCall home name args

-- | Optimize bitwise operations to native JavaScript operators.
--
-- @since 0.19.1
generateBitwiseCall :: ModuleName.Canonical -> Name.Name -> [JS.Expr] -> JS.Expr
generateBitwiseCall home name args =
  case args of
    [arg] ->
      case name of
        "complement" -> JS.Prefix JS.PrefixComplement arg
        _ -> generateGlobalCall home name args
    [left, right] ->
      case name of
        "and" -> JS.Infix JS.OpBitwiseAnd left right
        "or" -> JS.Infix JS.OpBitwiseOr left right
        "xor" -> JS.Infix JS.OpBitwiseXor left right
        "shiftLeftBy" -> JS.Infix JS.OpLShift right left
        "shiftRightBy" -> JS.Infix JS.OpSpRShift right left
        "shiftRightZfBy" -> JS.Infix JS.OpZfRShift right left
        _ -> generateGlobalCall home name args
    _ ->
      generateGlobalCall home name args

-- | Optimize Basics module calls to native JavaScript operators.
--
-- Converts common Basics operations like arithmetic, comparison, and boolean
-- operations to their JavaScript equivalents for maximum performance.
--
-- @since 0.19.1
generateBasicsCall :: ExprGenerator -> Mode.Mode -> ModuleName.Canonical -> Name.Name -> [Opt.Expr] -> JS.Expr
generateBasicsCall genExpr mode home name args =
  case args of
    [canopyArg] ->
      let arg = genExpr mode canopyArg
       in case name of
            "not" -> JS.Prefix JS.PrefixNot arg
            "negate" -> JS.Prefix JS.PrefixNegate arg
            "toFloat" -> arg
            "truncate" -> JS.Infix JS.OpBitwiseOr arg (JS.Int 0)
            _ -> generateGlobalCall home name [arg]
    [canopyLeft, canopyRight] ->
      case name of
        "append" -> append genExpr mode canopyLeft canopyRight
        "apL" -> genExpr mode $ apply canopyLeft canopyRight
        "apR" -> genExpr mode $ apply canopyRight canopyLeft
        _ ->
          let left = genExpr mode canopyLeft
              right = genExpr mode canopyRight
           in case name of
                "add" -> JS.Infix JS.OpAdd left right
                "sub" -> JS.Infix JS.OpSub left right
                "mul" -> JS.Infix JS.OpMul left right
                "fdiv" -> JS.Infix JS.OpDiv left right
                "idiv" -> JS.Infix JS.OpBitwiseOr (JS.Infix JS.OpDiv left right) (JS.Int 0)
                "eq" -> equal left right
                "neq" -> notEqual left right
                "lt" -> cmp JS.OpLt JS.OpLt 0 left right
                "gt" -> cmp JS.OpGt JS.OpGt 0 left right
                "le" -> cmp JS.OpLe JS.OpLt 1 left right
                "ge" -> cmp JS.OpGe JS.OpGt (-1) left right
                "or" -> JS.Infix JS.OpOr left right
                "and" -> JS.Infix JS.OpAnd left right
                "xor" -> JS.Infix JS.OpNe left right
                "remainderBy" -> JS.Infix JS.OpMod right left
                _ -> generateGlobalCall home name [left, right]
    _ ->
      generateGlobalCall home name (fmap (genExpr mode) args)

-- EQUALITY AND COMPARISON

-- | Generate JavaScript equality check, using strict equality for literals.
--
-- @since 0.19.1
equal :: JS.Expr -> JS.Expr -> JS.Expr
equal left right =
  if isLiteral left || isLiteral right
    then strictEq left right
    else JS.Call (JS.Ref (JsName.fromKernel Name.utils "eq")) [left, right]

-- | Generate JavaScript inequality check.
--
-- @since 0.19.1
notEqual :: JS.Expr -> JS.Expr -> JS.Expr
notEqual left right =
  if isLiteral left || isLiteral right
    then strictNEq left right
    else
      JS.Prefix JS.PrefixNot $
        JS.Call (JS.Ref (JsName.fromKernel Name.utils "eq")) [left, right]

-- | Generate JavaScript comparison using utils.cmp for non-literals.
--
-- @since 0.19.1
cmp :: JS.InfixOp -> JS.InfixOp -> Int -> JS.Expr -> JS.Expr -> JS.Expr
cmp idealOp backupOp backupInt left right =
  if isLiteral left || isLiteral right
    then JS.Infix idealOp left right
    else
      JS.Infix
        backupOp
        (JS.Call (JS.Ref (JsName.fromKernel Name.utils "cmp")) [left, right])
        (JS.Int backupInt)

-- | Check if a JavaScript expression is a literal value.
--
-- @since 0.19.1
isLiteral :: JS.Expr -> Bool
isLiteral expr =
  case expr of
    JS.String _ -> True
    JS.Float _ -> True
    JS.Int _ -> True
    JS.Bool _ -> True
    _ -> False

-- FUNCTION APPLICATION

-- | Optimize function application for accessors and partial application.
--
-- @since 0.19.1
apply :: Opt.Expr -> Opt.Expr -> Opt.Expr
apply func value =
  case func of
    Opt.Accessor field ->
      Opt.Access value field
    Opt.Call f args ->
      Opt.Call f (args <> [value])
    _ ->
      Opt.Call func [value]

-- STRING APPEND

-- | Generate optimized string or list append operations.
--
-- Uses native JavaScript @+@ for string concatenation when strings are
-- involved, falling back to the @utils.ap@ function for list append.
--
-- @since 0.19.1
append :: ExprGenerator -> Mode.Mode -> Opt.Expr -> Opt.Expr -> JS.Expr
append genExpr mode left right =
  let seqs = genExpr mode left : toSeqs genExpr mode right
   in if any isStringLiteral seqs
        then foldr1 (JS.Infix JS.OpAdd) seqs
        else foldr1 jsAppend seqs

-- | Generate utils.ap call for list append.
--
-- @since 0.19.1
jsAppend :: JS.Expr -> JS.Expr -> JS.Expr
jsAppend a b =
  JS.Call (JS.Ref (JsName.fromKernel Name.utils "ap")) [a, b]

-- | Flatten nested append calls into a sequence for optimization.
--
-- @since 0.19.1
toSeqs :: ExprGenerator -> Mode.Mode -> Opt.Expr -> [JS.Expr]
toSeqs genExpr mode expr =
  case expr of
    Opt.Call (Opt.VarGlobal (Opt.Global home "append")) [left, right]
      | home == ModuleName.basics ->
        genExpr mode left : toSeqs genExpr mode right
    _ ->
      [genExpr mode expr]

-- | Check if a JavaScript expression is a string literal.
--
-- @since 0.19.1
isStringLiteral :: JS.Expr -> Bool
isStringLiteral expr =
  case expr of
    JS.String _ -> True
    _ -> False

-- STRICT EQUALITY HELPERS

-- | Generate optimized strict equality with special cases for 0 and booleans.
--
-- @since 0.19.1
strictEq :: JS.Expr -> JS.Expr -> JS.Expr
strictEq left right =
  case left of
    JS.Int 0 ->
      JS.Prefix JS.PrefixNot right
    JS.Bool bool ->
      if bool then right else JS.Prefix JS.PrefixNot right
    _ ->
      case right of
        JS.Int 0 ->
          JS.Prefix JS.PrefixNot left
        JS.Bool bool ->
          if bool then left else JS.Prefix JS.PrefixNot left
        _ ->
          JS.Infix JS.OpEq left right

-- | Generate optimized strict inequality with special cases for 0 and booleans.
--
-- @since 0.19.1
strictNEq :: JS.Expr -> JS.Expr -> JS.Expr
strictNEq left right =
  case left of
    JS.Int 0 ->
      JS.Prefix JS.PrefixNot (JS.Prefix JS.PrefixNot right)
    JS.Bool bool ->
      if bool then JS.Prefix JS.PrefixNot right else right
    _ ->
      case right of
        JS.Int 0 ->
          JS.Prefix JS.PrefixNot (JS.Prefix JS.PrefixNot left)
        JS.Bool bool ->
          if bool then JS.Prefix JS.PrefixNot left else left
        _ ->
          JS.Infix JS.OpNe left right

