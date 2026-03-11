{-# LANGUAGE OverloadedStrings #-}

-- | Canonicalize.ResolveAbilities - Rewrite ability method calls to impl dict accesses
--
-- After type checking, this module walks the canonical AST and rewrites each
-- 'AbilityMethodCall' node into a concrete impl dictionary method access.
-- The rewritten expression is a standard 'Access' on a 'VarTopLevel' pointing
-- to the impl dictionary global (e.g. @$impl$Show$Int.show@).
--
-- This pass runs BETWEEN type checking and optimization, so the optimizer
-- and code generator see only standard AST nodes.
--
-- == Resolution Strategy
--
-- For each top-level definition:
--   1. Look up its solved type annotation
--   2. Peel off function arrows to get argument types
--   3. Match argument types to pattern variable names
--   4. Walk the body; when an 'AbilityMethodCall' is found in a 'Call',
--      determine the argument type and look up the impl dict
--   5. Rewrite to @Access (VarTopLevel home dictName) methodName@
--
-- == Limitations (v1)
--
-- * Only monomorphic ability calls are resolved
-- * Parametric impls are not supported yet
-- * Ability methods in polymorphic positions produce fallback references
--
-- @since 0.20.0
module Canonicalize.ResolveAbilities
  ( rewriteModule,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.ModuleName as ModuleName
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Reporting.Annotation as Ann

-- | Index of available impls, keyed by (abilityName, typeKey).
type ImplIndex = Map.Map (Name.Name, String) (ModuleName.Canonical, Name.Name)

-- | Local type environment: variable name -> canonical type.
type TypeEnv = Map.Map Name.Name Can.Type

-- | Rewrite all 'AbilityMethodCall' nodes in a module to concrete impl accesses.
rewriteModule ::
  Map.Map Name.Name Can.Annotation ->
  [Can.Impl] ->
  ModuleName.Canonical ->
  Can.Module ->
  Can.Module
rewriteModule annotations localImpls home modul =
  let implIndex = buildImplIndex home localImpls
  in modul { Can._decls = rewriteDecls implIndex annotations home (Can._decls modul) }

-- IMPL INDEX

buildImplIndex :: ModuleName.Canonical -> [Can.Impl] -> ImplIndex
buildImplIndex home impls =
  foldl (addImpl home) Map.empty impls

addImpl :: ModuleName.Canonical -> ImplIndex -> Can.Impl -> ImplIndex
addImpl home acc (Can.Impl abilityName implType _methods) =
  let typeKey = typeToKey implType
      dictName = Name.fromChars ("$impl$" <> Name.toChars abilityName <> "$" <> typeKey)
  in Map.insert (abilityName, typeKey) (home, dictName) acc

typeToKey :: Can.Type -> String
typeToKey canType =
  case canType of
    Can.TType _ name args -> Name.toChars name <> concatMap (\a -> "_" <> typeToKey a) args
    Can.TAlias _ name args _ -> Name.toChars name <> concatMap (\(_, a) -> "_" <> typeToKey a) args
    Can.TVar name -> Name.toChars name
    Can.TRecord _ _ -> "Record"
    Can.TUnit -> "Unit"
    Can.TTuple a b mc -> "Tuple_" <> typeToKey a <> "_" <> typeToKey b <> maybe "" (\c -> "_" <> typeToKey c) mc
    Can.TLambda a b -> "Func_" <> typeToKey a <> "_" <> typeToKey b

-- REWRITE DECLARATIONS

rewriteDecls :: ImplIndex -> Map.Map Name.Name Can.Annotation -> ModuleName.Canonical -> Can.Decls -> Can.Decls
rewriteDecls idx annotations home decls =
  case decls of
    Can.Declare def rest ->
      Can.Declare (rewriteDefWithAnnotation idx annotations home def) (rewriteDecls idx annotations home rest)
    Can.DeclareRec def defs rest ->
      Can.DeclareRec
        (rewriteDefWithAnnotation idx annotations home def)
        (fmap (rewriteDefWithAnnotation idx annotations home) defs)
        (rewriteDecls idx annotations home rest)
    Can.SaveTheEnvironment ->
      Can.SaveTheEnvironment

rewriteDefWithAnnotation ::
  ImplIndex ->
  Map.Map Name.Name Can.Annotation ->
  ModuleName.Canonical ->
  Can.Def ->
  Can.Def
rewriteDefWithAnnotation idx annotations home def =
  let defName = extractDefName def
      typeEnv = buildTypeEnv annotations defName def
  in rewriteDef idx typeEnv home def

extractDefName :: Can.Def -> Name.Name
extractDefName (Can.Def (Ann.At _ name) _ _) = name
extractDefName (Can.TypedDef (Ann.At _ name) _ _ _ _) = name

-- | Build a type environment from a definition's solved annotation.
buildTypeEnv ::
  Map.Map Name.Name Can.Annotation ->
  Name.Name ->
  Can.Def ->
  TypeEnv
buildTypeEnv annotations defName def =
  case Map.lookup defName annotations of
    Nothing -> Map.empty
    Just (Can.Forall _ tipe) ->
      case def of
        Can.Def _ patterns _ ->
          matchPatternsToType patterns tipe
        Can.TypedDef _ _ typedArgs _ _ ->
          buildFromTypedArgs typedArgs

-- | Match patterns against a function type to extract argument types.
matchPatternsToType :: [Can.Pattern] -> Can.Type -> TypeEnv
matchPatternsToType [] _ = Map.empty
matchPatternsToType (pat : pats) tipe =
  case tipe of
    Can.TLambda argType resultType ->
      Map.union (extractPatternVars pat argType) (matchPatternsToType pats resultType)
    _ -> Map.empty

-- | Build type env from typed arguments (from TypedDef).
buildFromTypedArgs :: [(Can.Pattern, Can.Type)] -> TypeEnv
buildFromTypedArgs = foldl (\acc (pat, tipe) -> Map.union (extractPatternVars pat tipe) acc) Map.empty

-- | Extract variable names from a pattern and associate them with a type.
extractPatternVars :: Can.Pattern -> Can.Type -> TypeEnv
extractPatternVars (Ann.At _ pat) tipe =
  case pat of
    Can.PVar name -> Map.singleton name tipe
    Can.PAnything -> Map.empty
    Can.PAlias innerPat name -> Map.insert name tipe (extractPatternVars innerPat tipe)
    _ -> Map.empty

-- REWRITE DEFINITIONS

rewriteDef :: ImplIndex -> TypeEnv -> ModuleName.Canonical -> Can.Def -> Can.Def
rewriteDef idx env home def =
  case def of
    Can.Def name args body ->
      Can.Def name args (rewriteExpr idx env home body)
    Can.TypedDef name freeVars typedArgs body resultType ->
      Can.TypedDef name freeVars typedArgs (rewriteExpr idx env home body) resultType

-- REWRITE EXPRESSIONS

rewriteExpr :: ImplIndex -> TypeEnv -> ModuleName.Canonical -> Can.Expr -> Can.Expr
rewriteExpr idx env home (Ann.At region expr) =
  Ann.At region (rewriteExpr_ idx env home region expr)

rewriteExpr_ :: ImplIndex -> TypeEnv -> ModuleName.Canonical -> Ann.Region -> Can.Expr_ -> Can.Expr_
rewriteExpr_ idx env home region expr =
  case expr of
    Can.Call func args ->
      rewriteCall idx env home region func args
    Can.AbilityMethodCall _aHome abilityName methodName annotation ->
      resolveStandaloneMethod idx home region abilityName methodName annotation
    Can.Lambda patterns body ->
      Can.Lambda patterns (rewriteExpr idx env home body)
    Can.If branches finally ->
      Can.If
        (fmap (\(c, b) -> (rewriteExpr idx env home c, rewriteExpr idx env home b)) branches)
        (rewriteExpr idx env home finally)
    Can.Let def body ->
      Can.Let (rewriteDef idx env home def) (rewriteExpr idx env home body)
    Can.LetRec defs body ->
      Can.LetRec (fmap (rewriteDef idx env home) defs) (rewriteExpr idx env home body)
    Can.LetDestruct pat e body ->
      Can.LetDestruct pat (rewriteExpr idx env home e) (rewriteExpr idx env home body)
    Can.Case e branches ->
      Can.Case (rewriteExpr idx env home e) (fmap (rewriteBranch idx env home) branches)
    Can.List es ->
      Can.List (fmap (rewriteExpr idx env home) es)
    Can.Negate e ->
      Can.Negate (rewriteExpr idx env home e)
    Can.BinopOp kind ann left right ->
      Can.BinopOp kind ann (rewriteExpr idx env home left) (rewriteExpr idx env home right)
    Can.Access e field ->
      Can.Access (rewriteExpr idx env home e) field
    Can.Update name e fields ->
      Can.Update name (rewriteExpr idx env home e) (fmap (rewriteFieldUpdate idx env home) fields)
    Can.Record fields ->
      Can.Record (fmap (rewriteExpr idx env home) fields)
    Can.Tuple a b mc ->
      Can.Tuple (rewriteExpr idx env home a) (rewriteExpr idx env home b) (fmap (rewriteExpr idx env home) mc)
    Can.StringConcat parts ->
      Can.StringConcat (fmap (rewriteExpr idx env home) parts)
    _ -> expr

rewriteBranch :: ImplIndex -> TypeEnv -> ModuleName.Canonical -> Can.CaseBranch -> Can.CaseBranch
rewriteBranch idx env home (Can.CaseBranch pat body) =
  Can.CaseBranch pat (rewriteExpr idx env home body)

rewriteFieldUpdate :: ImplIndex -> TypeEnv -> ModuleName.Canonical -> Can.FieldUpdate -> Can.FieldUpdate
rewriteFieldUpdate idx env home (Can.FieldUpdate r e) =
  Can.FieldUpdate r (rewriteExpr idx env home e)

-- | Rewrite a Call expression where the function might be an AbilityMethodCall.
rewriteCall ::
  ImplIndex -> TypeEnv -> ModuleName.Canonical -> Ann.Region ->
  Can.Expr -> [Can.Expr] ->
  Can.Expr_
rewriteCall idx env home region func args =
  case Ann.toValue func of
    Can.AbilityMethodCall _aHome abilityName methodName _annotation ->
      let rewrittenArgs = fmap (rewriteExpr idx env home) args
          resolvedType = inferArgType env args
      in case resolvedType of
           Just concreteType ->
             let typeKey = typeToKey concreteType
             in case Map.lookup (abilityName, typeKey) idx of
                  Just (implHome, dictName) ->
                    let dictRef = Ann.At region (Can.VarTopLevel implHome dictName)
                        accessExpr = Ann.At region (Can.Access dictRef (Ann.At region methodName))
                    in Can.Call accessExpr rewrittenArgs
                  Nothing ->
                    Can.Call (rewriteExpr idx env home func) rewrittenArgs
           Nothing ->
             Can.Call (rewriteExpr idx env home func) rewrittenArgs
    _ ->
      Can.Call (rewriteExpr idx env home func) (fmap (rewriteExpr idx env home) args)

-- | Resolve a standalone method reference (not in a Call position).
resolveStandaloneMethod ::
  ImplIndex -> ModuleName.Canonical -> Ann.Region ->
  Name.Name -> Name.Name -> Can.Annotation ->
  Can.Expr_
resolveStandaloneMethod _idx _home _region _abilityName methodName _annotation =
  Can.VarLocal methodName

-- | Try to infer the concrete type of the first argument to an ability method.
inferArgType :: TypeEnv -> [Can.Expr] -> Maybe Can.Type
inferArgType _ [] = Nothing
inferArgType env (Ann.At _ firstArg : _) =
  case firstArg of
    Can.VarLocal name -> Map.lookup name env
    Can.VarTopLevel _ _ -> Nothing
    Can.Int _ -> Just (Can.TType ModuleName.basics (Name.fromChars "Int") [])
    Can.Float _ -> Just (Can.TType ModuleName.basics (Name.fromChars "Float") [])
    Can.Str _ -> Just (Can.TType ModuleName.basics (Name.fromChars "String") [])
    Can.Chr _ -> Just (Can.TType ModuleName.basics (Name.fromChars "Char") [])
    Can.List _ -> Just (Can.TType ModuleName.list (Name.fromChars "List") [])
    Can.Unit -> Just Can.TUnit
    _ -> Nothing
