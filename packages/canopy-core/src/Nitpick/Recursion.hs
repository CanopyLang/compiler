{-# LANGUAGE OverloadedStrings #-}

-- | Detect obvious infinite recursion patterns in canonical AST.
--
-- Scans @let rec@ bindings for definitions where every branch of the
-- body calls the function recursively without any base case. Only flags
-- the most obvious patterns to minimize false positives:
--
-- * @f x = f x@ (direct self-call, identical arguments)
-- * @f x = f (x + 1)@ (growing arguments, no termination)
-- * @f x = g (f x)@ (self-call wrapped in another call)
--
-- This check runs after canonicalization and before type checking,
-- as part of the nitpick phase.
--
-- @since 0.20.1
module Nitpick.Recursion
  ( checkRecursion,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Name as Name
import qualified Data.Text as Text
import qualified Reporting.Annotation as Ann
import qualified Reporting.Warning as Warning

-- | Check a list of recursive definitions for obvious infinite recursion.
--
-- Returns warnings for definitions where all branches recurse without
-- a base case. Conservative: only flags patterns that are almost
-- certainly infinite.
--
-- @since 0.20.1
checkRecursion :: [Can.Def] -> [Warning.Warning]
checkRecursion = concatMap checkOneDef

-- | Check a single definition for infinite recursion.
checkOneDef :: Can.Def -> [Warning.Warning]
checkOneDef (Can.Def (Ann.At _ name) _args body) =
  [Warning.PotentialInfiniteRecursion (Text.pack (Name.toChars name))
  | isObviousInfiniteRecursion name body]
checkOneDef (Can.TypedDef (Ann.At _ name) _ _args body _) =
  [Warning.PotentialInfiniteRecursion (Text.pack (Name.toChars name))
  | isObviousInfiniteRecursion name body]

-- | Determine if a function body is obviously infinitely recursive.
--
-- A body is "obviously infinite" when every execution path contains
-- a recursive call to the function and there is no base case.
isObviousInfiniteRecursion :: Name.Name -> Can.Expr -> Bool
isObviousInfiniteRecursion name body =
  allPathsRecurse name (Ann.toValue body)

-- | Check if all execution paths in an expression recurse on the given name.
allPathsRecurse :: Name.Name -> Can.Expr_ -> Bool
allPathsRecurse name expr =
  case expr of
    Can.VarLocal _ -> False
    Can.VarTopLevel _ _ -> False
    Can.VarRuntime _ _ -> False
    Can.VarForeign {} -> False
    Can.VarCtor {} -> False
    Can.VarDebug {} -> False
    Can.VarOperator {} -> False
    Can.Chr _ -> False
    Can.Str _ -> False
    Can.Int _ -> False
    Can.Float _ -> False
    Can.List _ -> False
    Can.Negate _ -> False
    Can.BinopOp {} -> False
    Can.Lambda _ _ -> False
    Can.Record _ -> False
    Can.Unit -> False
    Can.Tuple _ _ _ -> False
    Can.Shader _ _ -> False
    Can.StringConcat _ -> False
    Can.AbilityMethodCall {} -> False
    Can.Accessor _ -> False
    Can.Access _ _ -> False
    Can.Update {} -> False
    Can.Hole {} -> False
    Can.Call fn args -> isDirectSelfCall name fn
    Can.If branches elseExpr ->
      all (allPathsRecurseLocated name . snd) branches
        && allPathsRecurseLocated name elseExpr
    Can.Let _ body -> allPathsRecurseLocated name body
    Can.LetRec _ body -> allPathsRecurseLocated name body
    Can.LetDestruct _ _ body -> allPathsRecurseLocated name body
    Can.Case _ branches ->
      all (\(Can.CaseBranch _ branchBody) -> allPathsRecurseLocated name branchBody) branches

-- | Check if all paths in a located expression recurse.
allPathsRecurseLocated :: Name.Name -> Can.Expr -> Bool
allPathsRecurseLocated name (Ann.At _ expr) = allPathsRecurse name expr

-- | Check if a call expression is a direct self-call.
isDirectSelfCall :: Name.Name -> Can.Expr -> Bool
isDirectSelfCall name (Ann.At _ (Can.VarLocal n)) = n == name
isDirectSelfCall _ _ = False
