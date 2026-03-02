{-# LANGUAGE OverloadedStrings #-}

-- | Shared helper functions for lint rule implementations.
--
-- Provides AST traversal utilities, name collection, and pattern analysis
-- functions used by multiple lint rules.
--
-- @since 0.19.2
module Lint.Rules.Helpers
  ( -- * Expression Traversal
    childExprs,
    defExprs,

    -- * Name Collection
    collectUsedNames,
    collectNamesInExpr,
    collectNamesInDef,

    -- * Pattern Utilities
    patternNames,
    patternNames_,
    patternLocatedNames,
    defNames,

    -- * Region Utilities
    regionLineRange,
  )
where

import qualified AST.Source as Src
import qualified Canopy.Data.Name as Name
import qualified Data.Set as Set
import qualified Reporting.Annotation as Ann

-- EXPRESSION TRAVERSAL

-- | Collect direct child expressions of an expression node.
--
-- Used by rules that need to recursively walk the expression tree
-- without reimplementing the traversal for each expression form.
--
-- @since 0.19.1
childExprs :: Src.Expr_ -> [Src.Expr]
childExprs (Src.Call f args) = f : args
childExprs (Src.If branches elseBranch) =
  concatMap (\(cond, body) -> [cond, body]) branches ++ [elseBranch]
childExprs (Src.Let defs body) =
  concatMap (defExprs . Ann.toValue) defs ++ [body]
childExprs (Src.Case scrutinee branches) =
  scrutinee : map snd branches
childExprs (Src.Lambda _ body) = [body]
childExprs (Src.List items) = items
childExprs (Src.Binops pairs last_) =
  map fst pairs ++ [last_]
childExprs (Src.Negate e) = [e]
childExprs (Src.Access e _) = [e]
childExprs (Src.Update _ fields) = map snd fields
childExprs (Src.Record fields) = map snd fields
childExprs (Src.Tuple e1 e2 rest) = e1 : e2 : rest
childExprs _ = []

-- | Extract child expressions from a local definition.
--
-- @since 0.19.1
defExprs :: Src.Def -> [Src.Expr]
defExprs (Src.Define _ _ body _) = [body]
defExprs (Src.Destruct _ body) = [body]

-- NAME COLLECTION

-- | Build the set of all name tokens that appear in the module body.
--
-- Used by the unused import rule to determine which imports are referenced.
--
-- @since 0.19.1
collectUsedNames :: Src.Module -> Set.Set String
collectUsedNames modul =
  Set.fromList
    ( concatMap (collectNamesInValue . Ann.toValue) (Src._values modul)
        ++ concatMap (collectNamesInUnion . Ann.toValue) (Src._unions modul)
        ++ concatMap (collectNamesInAlias . Ann.toValue) (Src._aliases modul)
    )

-- | Collect all name tokens from a value definition.
collectNamesInValue :: Src.Value -> [String]
collectNamesInValue (Src.Value _ _ expr _ _) =
  collectNamesInExpr (Ann.toValue expr)

-- | Collect all name tokens from a union type definition.
collectNamesInUnion :: Src.Union -> [String]
collectNamesInUnion (Src.Union _ _ ctors) =
  concatMap collectNamesInCtor ctors

-- | Collect names from a constructor definition.
collectNamesInCtor :: (Ann.Located Name.Name, [Src.Type]) -> [String]
collectNamesInCtor (_, types) =
  concatMap (collectNamesInType . Ann.toValue) types

-- | Collect names from a type alias definition.
collectNamesInAlias :: Src.Alias -> [String]
collectNamesInAlias (Src.Alias _ _ t) =
  collectNamesInType (Ann.toValue t)

-- | Collect all identifier tokens used in an expression.
--
-- @since 0.19.1
collectNamesInExpr :: Src.Expr_ -> [String]
collectNamesInExpr (Src.Var _ n) = [Name.toChars n]
collectNamesInExpr (Src.VarQual _ modN n) = [Name.toChars modN, Name.toChars n]
collectNamesInExpr (Src.Call f args) =
  collectNamesInExpr (Ann.toValue f)
    ++ concatMap (collectNamesInExpr . Ann.toValue) args
collectNamesInExpr (Src.If branches elseBranch) =
  concatMap collectBranchNames branches
    ++ collectNamesInExpr (Ann.toValue elseBranch)
collectNamesInExpr (Src.Let defs body) =
  concatMap (collectNamesInDef . Ann.toValue) defs
    ++ collectNamesInExpr (Ann.toValue body)
collectNamesInExpr (Src.Case scrutinee branches) =
  collectNamesInExpr (Ann.toValue scrutinee)
    ++ concatMap (collectNamesInExpr . Ann.toValue . snd) branches
collectNamesInExpr (Src.Lambda _ body) = collectNamesInExpr (Ann.toValue body)
collectNamesInExpr (Src.List items) = concatMap (collectNamesInExpr . Ann.toValue) items
collectNamesInExpr (Src.Binops pairs last_) =
  concatMap (collectNamesInExpr . Ann.toValue . fst) pairs
    ++ collectNamesInExpr (Ann.toValue last_)
collectNamesInExpr (Src.Negate e) = collectNamesInExpr (Ann.toValue e)
collectNamesInExpr (Src.Access e _) = collectNamesInExpr (Ann.toValue e)
collectNamesInExpr (Src.Update (Ann.At _ n) fields) =
  Name.toChars n : concatMap (collectNamesInExpr . Ann.toValue . snd) fields
collectNamesInExpr (Src.Record fields) =
  concatMap (collectNamesInExpr . Ann.toValue . snd) fields
collectNamesInExpr (Src.Tuple e1 e2 rest) =
  collectNamesInExpr (Ann.toValue e1)
    ++ collectNamesInExpr (Ann.toValue e2)
    ++ concatMap (collectNamesInExpr . Ann.toValue) rest
collectNamesInExpr _ = []

-- | Collect names from a branch pair.
collectBranchNames :: (Src.Expr, Src.Expr) -> [String]
collectBranchNames (cond, body) =
  collectNamesInExpr (Ann.toValue cond)
    ++ collectNamesInExpr (Ann.toValue body)

-- | Collect names in a local definition.
--
-- @since 0.19.1
collectNamesInDef :: Src.Def -> [String]
collectNamesInDef (Src.Define _ _ body _) = collectNamesInExpr (Ann.toValue body)
collectNamesInDef (Src.Destruct _ body) = collectNamesInExpr (Ann.toValue body)

-- | Collect names referenced in a type expression.
collectNamesInType :: Src.Type_ -> [String]
collectNamesInType (Src.TType _ n args) =
  Name.toChars n : concatMap (collectNamesInType . Ann.toValue) args
collectNamesInType (Src.TTypeQual _ modN n args) =
  Name.toChars modN : Name.toChars n : concatMap (collectNamesInType . Ann.toValue) args
collectNamesInType (Src.TLambda a b) =
  collectNamesInType (Ann.toValue a) ++ collectNamesInType (Ann.toValue b)
collectNamesInType (Src.TRecord fields _) =
  concatMap (collectNamesInType . Ann.toValue . snd) fields
collectNamesInType (Src.TTuple a b rest) =
  collectNamesInType (Ann.toValue a)
    ++ collectNamesInType (Ann.toValue b)
    ++ concatMap (collectNamesInType . Ann.toValue) rest
collectNamesInType _ = []

-- PATTERN UTILITIES

-- | Extract all variable names bound by a pattern.
--
-- @since 0.19.2
patternNames :: Src.Pattern -> [String]
patternNames (Ann.At _ pat_) = patternNames_ pat_

-- | Extract variable names from a pattern node.
--
-- @since 0.19.2
patternNames_ :: Src.Pattern_ -> [String]
patternNames_ (Src.PVar n) = [Name.toChars n]
patternNames_ (Src.PRecord fields) = map (Name.toChars . Ann.toValue) fields
patternNames_ (Src.PAlias subPat (Ann.At _ n)) = Name.toChars n : patternNames subPat
patternNames_ (Src.PCtor _ _ subPats) = concatMap patternNames subPats
patternNames_ (Src.PCtorQual _ _ _ subPats) = concatMap patternNames subPats
patternNames_ (Src.PTuple p1 p2 rest) = concatMap patternNames (p1 : p2 : rest)
patternNames_ (Src.PList pats) = concatMap patternNames pats
patternNames_ (Src.PCons hd tl) = patternNames hd ++ patternNames tl
patternNames_ Src.PAnything = []
patternNames_ Src.PUnit = []
patternNames_ (Src.PChr _) = []
patternNames_ (Src.PStr _) = []
patternNames_ (Src.PInt _) = []

-- | Extract all located variable names from a list of patterns.
--
-- Returns @(region, name)@ pairs so that warnings carry the precise location
-- of the binding that causes the shadow.
--
-- @since 0.19.2
patternLocatedNames :: [Src.Pattern] -> [(Ann.Region, String)]
patternLocatedNames = concatMap go
  where
    go (Ann.At _ pat_) = goInner pat_
    goInner (Src.PVar n) = [(Ann.zero, Name.toChars n)]
    goInner (Src.PRecord fields) = map locatedField fields
    goInner (Src.PAlias subPat (Ann.At region n)) =
      (region, Name.toChars n) : concatMap go [subPat]
    goInner (Src.PCtor _ _ subPats) = concatMap go subPats
    goInner (Src.PCtorQual _ _ _ subPats) = concatMap go subPats
    goInner (Src.PTuple p1 p2 rest) = concatMap go (p1 : p2 : rest)
    goInner (Src.PList pats) = concatMap go pats
    goInner (Src.PCons hd tl) = concatMap go [hd, tl]
    goInner Src.PAnything = []
    goInner Src.PUnit = []
    goInner (Src.PChr _) = []
    goInner (Src.PStr _) = []
    goInner (Src.PInt _) = []
    locatedField (Ann.At region n) = (region, Name.toChars n)

-- | Extract the names bound by a definition.
--
-- @since 0.19.2
defNames :: Src.Def -> [String]
defNames (Src.Define (Ann.At _ n) _ _ _) = [Name.toChars n]
defNames (Src.Destruct pat _) = patternNames pat

-- REGION UTILITIES

-- | Extract the 1-indexed start and end lines from a region.
--
-- @since 0.19.1
regionLineRange :: Ann.Region -> (Int, Int)
regionLineRange (Ann.Region (Ann.Position startRow _) (Ann.Position endRow _)) =
  (fromIntegral startRow, fromIntegral endRow)
