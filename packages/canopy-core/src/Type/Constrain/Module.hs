{-# LANGUAGE OverloadedStrings #-}

module Type.Constrain.Module
  ( constrain,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.ModuleName as ModuleName
import Control.Monad (forM)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Type as TypeError
import qualified Type.Constrain.Expression as Expr
import qualified Type.Instantiate as Instantiate
import qualified Type.Type as Type
import Type.Type (Constraint (..), Type (..), mkFlexVar, nameToRigid, never, (==>))

-- CONSTRAIN

constrain :: Can.Module -> IO Constraint
constrain (Can.Module home _ _ decls unions aliases _ effects _ guards _ _) =
  letDerived home unions aliases =<< case effects of
    Can.NoEffects ->
      constrainDecls guards decls CSaveTheEnvironment
    Can.Ports ports ->
      Map.foldrWithKey letPort (constrainDecls guards decls CSaveTheEnvironment) ports
    Can.FFI ->
      constrainDecls guards decls CSaveTheEnvironment
    Can.Manager r0 r1 r2 manager ->
      case manager of
        Can.Cmd cmdName ->
          (constrainEffects home r0 r1 r2 manager >>= constrainDecls guards decls) >>= letCmd home cmdName
        Can.SubManager subName ->
          (constrainEffects home r0 r1 r2 manager >>= constrainDecls guards decls) >>= letSub home subName
        Can.Fx cmdName subName ->
          ((constrainEffects home r0 r1 r2 manager >>= constrainDecls guards decls) >>= letSub home subName) >>= letCmd home cmdName

-- CONSTRAIN DECLARATIONS

constrainDecls :: Map Name.Name Can.GuardInfo -> Can.Decls -> Constraint -> IO Constraint
constrainDecls guards decls finalConstraint =
  case decls of
    Can.Declare def otherDecls ->
      do
        v <- mkFlexVar
        rtv <- case def of
          Can.TypedDef _ freeVars _ _ _ ->
            Map.traverseWithKey (\k _ -> nameToRigid k) freeVars
          Can.Def _ _ _ ->
            return Map.empty
        constrainDecls guards otherDecls finalConstraint >>= \con ->
          Expr.constrainDef guards (Map.map VarN rtv) def con (TypeError.NoExpectation (VarN v))
    Can.DeclareRec def defs otherDecls ->
      do
        let allDefs = def : defs
        rtvMaps <- forM allDefs $ \d -> case d of
          Can.TypedDef _ freeVars _ _ _ ->
            Map.traverseWithKey (\k _ -> nameToRigid k) freeVars
          Can.Def _ _ _ ->
            return Map.empty
        let combinedRtv = Map.unions (fmap (Map.map VarN) rtvMaps)
        constrainDecls guards otherDecls finalConstraint >>= Expr.constrainRecursiveDefs guards combinedRtv allDefs
    Can.SaveTheEnvironment ->
      return finalConstraint

-- PORT HELPERS

letPort :: Name.Name -> Can.Port -> IO Constraint -> IO Constraint
letPort name port_ makeConstraint =
  case port_ of
    Can.Incoming freeVars _ srcType ->
      do
        vars <- Map.traverseWithKey (\k _ -> nameToRigid k) freeVars
        tipe <- Instantiate.fromSrcType (Map.map VarN vars) srcType
        let header = Map.singleton name (Ann.At Ann.zero tipe)
        CLet (Map.elems vars) [] header CTrue <$> makeConstraint <*> pure Nothing
    Can.Outgoing freeVars _ srcType ->
      do
        vars <- Map.traverseWithKey (\k _ -> nameToRigid k) freeVars
        tipe <- Instantiate.fromSrcType (Map.map VarN vars) srcType
        let header = Map.singleton name (Ann.At Ann.zero tipe)
        CLet (Map.elems vars) [] header CTrue <$> makeConstraint <*> pure Nothing

-- EFFECT MANAGER HELPERS

letCmd :: ModuleName.Canonical -> Name.Name -> Constraint -> IO Constraint
letCmd home tipe constraint =
  do
    msgVar <- mkFlexVar
    let msg = VarN msgVar
    let cmdType = FunN (AppN home tipe [msg]) (AppN ModuleName.cmd Name.cmd [msg])
    let header = Map.singleton "command" (Ann.At Ann.zero cmdType)
    return $ CLet [msgVar] [] header CTrue constraint Nothing

letSub :: ModuleName.Canonical -> Name.Name -> Constraint -> IO Constraint
letSub home tipe constraint =
  do
    msgVar <- mkFlexVar
    let msg = VarN msgVar
    let subType = FunN (AppN home tipe [msg]) (AppN ModuleName.sub Name.sub [msg])
    let header = Map.singleton "subscription" (Ann.At Ann.zero subType)
    return $ CLet [msgVar] [] header CTrue constraint Nothing

constrainEffects :: ModuleName.Canonical -> Ann.Region -> Ann.Region -> Ann.Region -> Can.Manager -> IO Constraint
constrainEffects home r0 r1 r2 manager =
  do
    s0 <- mkFlexVar
    s1 <- mkFlexVar
    s2 <- mkFlexVar
    m1 <- mkFlexVar
    m2 <- mkFlexVar
    sm1 <- mkFlexVar
    sm2 <- mkFlexVar

    let state0 = VarN s0
    let state1 = VarN s1
    let state2 = VarN s2
    let msg1 = VarN m1
    let msg2 = VarN m2
    let self1 = VarN sm1
    let self2 = VarN sm2

    let onSelfMsg = router msg2 self2 ==> self2 ==> state2 ==> task state2
    let onEffects =
          case manager of
            Can.Cmd cmd -> router msg1 self1 ==> effectList home cmd msg1 ==> state1 ==> task state1
            Can.SubManager sub -> router msg1 self1 ==> effectList home sub msg1 ==> state1 ==> task state1
            Can.Fx cmd sub -> router msg1 self1 ==> effectList home cmd msg1 ==> effectList home sub msg1 ==> state1 ==> task state1

    let effectCons =
          CAnd
            [ CLocal r0 "init" (TypeError.NoExpectation (task state0)),
              CLocal r1 "onEffects" (TypeError.NoExpectation onEffects),
              CLocal r2 "onSelfMsg" (TypeError.NoExpectation onSelfMsg),
              CEqual r1 TypeError.Effects state0 (TypeError.NoExpectation state1),
              CEqual r2 TypeError.Effects state0 (TypeError.NoExpectation state2),
              CEqual r2 TypeError.Effects self1 (TypeError.NoExpectation self2)
            ]

    CLet [] [s0, s1, s2, m1, m2, sm1, sm2] Map.empty effectCons
      <$> case manager of
        Can.Cmd cmd ->
          checkMap "cmdMap" home cmd CSaveTheEnvironment
        Can.SubManager sub ->
          checkMap "subMap" home sub CSaveTheEnvironment
        Can.Fx cmd sub ->
          checkMap "subMap" home sub CSaveTheEnvironment >>= checkMap "cmdMap" home cmd
      <*> pure Nothing

effectList :: ModuleName.Canonical -> Name.Name -> Type -> Type
effectList home name msg =
  AppN ModuleName.list Name.list [AppN home name [msg]]

task :: Type -> Type
task answer =
  AppN ModuleName.platform Name.task [never, answer]

router :: Type -> Type -> Type
router msg self =
  AppN ModuleName.platform Name.router [msg, self]

checkMap :: Name.Name -> ModuleName.Canonical -> Name.Name -> Constraint -> IO Constraint
checkMap name home tipe constraint =
  do
    a <- mkFlexVar
    b <- mkFlexVar
    let mapType = toMapType home tipe (VarN a) (VarN b)
    let mapCon = CLocal Ann.zero name (TypeError.NoExpectation mapType)
    return $ CLet [a, b] [] Map.empty mapCon constraint Nothing

toMapType :: ModuleName.Canonical -> Name.Name -> Type -> Type -> Type
toMapType home tipe a b =
  (a ==> b) ==> AppN home tipe [a] ==> AppN home tipe [b]

-- DERIVED FUNCTION TYPES

-- | Introduce type bindings for derived functions from @deriving@ clauses.
--
-- Works like 'letPort' — wraps the constraint in 'CLet' with a header
-- that maps each derived function name to its type.
--
-- @since 0.20.0
letDerived ::
  ModuleName.Canonical ->
  Map Name.Name Can.Union ->
  Map Name.Name Can.Alias ->
  Constraint ->
  IO Constraint
letDerived home unions aliases constraint =
  do
    let unionBindings = Map.foldlWithKey' (derivedUnionBindings home) [] unions
    aliasBindings <- derivedAllAliasBindings home aliases
    foldDerivedBindings (unionBindings ++ aliasBindings) constraint

-- | A derived binding pairs a name and type with any rigid type variables
-- that must be universally quantified (for parametric type aliases).
type DerivedBinding = ([Type.Variable], Name.Name, Type)

foldDerivedBindings :: [DerivedBinding] -> Constraint -> IO Constraint
foldDerivedBindings [] constraint = return constraint
foldDerivedBindings ((rigids, name, tipe) : rest) constraint =
  do
    inner <- foldDerivedBindings rest constraint
    let header = Map.singleton name (Ann.At Ann.zero tipe)
    return (CLet rigids [] header CTrue inner Nothing)

derivedUnionBindings ::
  ModuleName.Canonical ->
  [DerivedBinding] ->
  Name.Name ->
  Can.Union ->
  [DerivedBinding]
derivedUnionBindings home acc typeName (Can.Union _ _ _ _ _ clauses) =
  let selfType = AppN home typeName []
   in foldl (addDerivedBinding [] selfType typeName) acc clauses

derivedAllAliasBindings ::
  ModuleName.Canonical ->
  Map Name.Name Can.Alias ->
  IO [DerivedBinding]
derivedAllAliasBindings home aliases =
  Map.foldlWithKey' go (return []) aliases
  where
    go acc typeName alias =
      do
        prev <- acc
        bindings <- derivedAliasBindings home typeName alias
        return (bindings ++ prev)

derivedAliasBindings ::
  ModuleName.Canonical ->
  Name.Name ->
  Can.Alias ->
  IO [DerivedBinding]
derivedAliasBindings home typeName (Can.Alias typeParams _ canType _ clauses) =
  do
    rigidVars <- traverse (\n -> do { v <- nameToRigid n; return (n, v) }) typeParams
    let freeVarsMap = Map.fromList [(n, VarN v) | (n, v) <- rigidVars]
    expandedType <- Instantiate.fromSrcType freeVarsMap canType
    let typeArgs = [(n, VarN v) | (n, v) <- rigidVars]
    let selfType = AliasN home typeName typeArgs expandedType
    let vars = [v | (_, v) <- rigidVars]
    return (foldl (addDerivedBinding vars selfType typeName) [] clauses)

addDerivedBinding ::
  [Type.Variable] ->
  Type ->
  Name.Name ->
  [DerivedBinding] ->
  Can.DerivingClause ->
  [DerivedBinding]
addDerivedBinding rigids selfType typeName acc clause =
  let nameChars = Name.toChars typeName
      isParametric = not (null rigids)
   in case clause of
        Can.DeriveOrd ->
          acc
        Can.DeriveEncode _
          | isParametric -> acc
          | otherwise ->
              (rigids, Name.fromChars ("encode" ++ nameChars), FunN selfType (AppN ModuleName.jsonEncode Name.value [])) : acc
        Can.DeriveDecode _
          | isParametric -> acc
          | otherwise ->
              (rigids, Name.fromChars (lowerFirst nameChars ++ "Decoder"), AppN ModuleName.jsonDecode (Name.fromChars "Decoder") [selfType]) : acc
        Can.DeriveEnum ->
          ([], Name.fromChars ("all" ++ nameChars), AppN ModuleName.list Name.list [selfType]) : acc

lowerFirst :: String -> String
lowerFirst [] = []
lowerFirst (c : cs) = toLower c : cs
  where
    toLower ch
      | ch >= 'A' && ch <= 'Z' = toEnum (fromEnum ch + 32)
      | otherwise = ch
