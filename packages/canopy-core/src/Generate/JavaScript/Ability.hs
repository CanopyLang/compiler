{-# LANGUAGE OverloadedStrings #-}

-- | Generate.JavaScript.Ability - JavaScript code generation for ability impls
--
-- This module handles code generation for the ability system's dictionary-passing
-- style. Each 'impl' declaration is compiled to a JavaScript object literal whose
-- keys are method names and whose values are the generated method functions.
--
-- == Dictionary-Passing Style
--
-- Canopy abilities follow the same pattern as Haskell type-class dictionaries:
-- instead of relying on dynamic dispatch, the compiler passes explicit dictionary
-- objects to functions that require ability constraints.
--
-- A Canopy impl such as:
--
-- @
-- impl Show for Int
--   show n = Int.toString n
-- @
--
-- compiles to JavaScript like:
--
-- @
-- var $author$pkg$Module$impl$Show$Int = { show: function(n) { return ... } };
-- @
--
-- @since 0.20.0
module Generate.JavaScript.Ability
  ( generateImplDict,
    implDictName,
  )
where

import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Expression as Expr
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.Mode as Mode

-- | Generate the JavaScript variable declaration for an impl dictionary.
--
-- The declaration has the form:
--
-- @
-- var $pkg$Module$impl$AbilityName$TypeName = { method1: fn1, method2: fn2 };
-- @
--
-- Each method body is generated with 'Expr.generate' using the current mode.
--
-- @since 0.20.0
generateImplDict ::
  Mode.Mode ->
  Opt.Global ->
  Name.Name ->
  Map Name.Name Opt.Expr ->
  JS.Stmt
generateImplDict mode global _abilityName methods =
  let jsName = globalToJsName global
      jsObject = JS.Object (Map.foldrWithKey (buildMethodPair mode) [] methods)
  in JS.Var jsName jsObject

-- | Convert a global to its JavaScript variable name.
--
-- @since 0.20.0
globalToJsName :: Opt.Global -> JsName.Name
globalToJsName (Opt.Global home name) =
  JsName.fromGlobal home name

-- | Build a key-value pair for a method in the dictionary object.
--
-- @since 0.20.0
buildMethodPair ::
  Mode.Mode ->
  Name.Name ->
  Opt.Expr ->
  [(JsName.Name, JS.Expr)] ->
  [(JsName.Name, JS.Expr)]
buildMethodPair mode methodName methodBody acc =
  let jsKey = JsName.fromLocal methodName
      jsVal = Expr.codeToExpr (Expr.generate mode methodBody)
  in (jsKey, jsVal) : acc

-- | Derive the dictionary global name for an impl.
--
-- Constructs the canonical 'Opt.Global' that identifies an impl's dictionary
-- within the dependency graph. The name encodes both the ability name and the
-- type name so that multiple impls for the same ability do not collide.
--
-- @since 0.20.0
implDictName :: ModuleName.Canonical -> Name.Name -> String -> Opt.Global
implDictName home abilityName typeName =
  let dictName = Name.fromChars ("$impl$" <> Name.toChars abilityName <> "$" <> typeName)
  in Opt.Global home dictName
