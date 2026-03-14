{-# LANGUAGE OverloadedStrings #-}

-- | Type.Solve.Pool - Pool management, type-to-variable conversion, generalization, copy/restore
--
-- This module contains the lower-level infrastructure of the type constraint solver:
--
--   * Pool management: 'introduce', 'register', 'ensurePoolSize'
--   * Type-to-variable: 'typeToVariable', 'srcTypeToVariable' and all convert helpers
--   * Generalization: 'generalize', 'adjustAllRanks', 'adjustRank', 'poolToRankTable',
--     'registerOldPoolVariables', 'registerOrGeneralizeYoungVars', 'performGeneralization'
--   * Copy/restore: 'makeCopy', 'restore', 'traverseFlatType' and all helpers
--
-- All functions are pure infrastructure with no dependency on the high-level
-- 'Type.Solve' solver logic, which prevents circular imports.
module Type.Solve.Pool
  ( -- * Pool types (re-exported for callers)
    Pools,

    -- * Pool management
    introduce,
    register,
    ensurePoolSize,

    -- * Generalization
    performGeneralization,
    generalize,
    adjustAllRanks,
    adjustRank,
    poolToRankTable,
    registerOldPoolVariables,
    registerOrGeneralizeYoungVars,
    collectAmbientVariables,

    -- * Type-to-variable conversion
    typeToVariable,
    srcTypeToVariable,

    -- * Copy and restore
    makeCopy,
    restore,
    traverseFlatType,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Control.Monad as Monad
import Data.Foldable (for_, maximumBy, traverse_)
import Data.IORef
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Vector as Vector
import qualified Data.Vector.Mutable as MVector
import qualified Reporting.InternalError as InternalError
import Type.Type as Type
import qualified Type.UnionFind as UF

-- | Pool of type variables grouped by rank.
--
-- The outer 'IORef' allows growing the vector when new ranks are introduced.
-- Each slot at index @r@ holds the list of 'Variable's registered at rank @r@.
type Pools = IORef (MVector.IOVector [Variable])

-- POOL MANAGEMENT

-- | Ensure the pools vector is large enough to accommodate @rank@.
--
-- Grows the underlying mutable vector by doubling when the rank exceeds the
-- current capacity, initialising new slots with empty lists.
ensurePoolSize :: Int -> Pools -> IO ()
ensurePoolSize rank poolsRef = do
  currentPools <- readIORef poolsRef
  let currentSize = MVector.length currentPools
  if rank < currentSize
    then return ()
    else do
      let newSize = rank + 1
      newPools <- MVector.grow currentPools (newSize - currentSize)
      for_ [currentSize .. newSize - 1] $ \i ->
        MVector.write newPools i []
      writeIORef poolsRef newPools

-- | Register a fresh 'Variable' at @rank@ in the given pool.
--
-- Creates a new union-find node with the supplied 'Content' and adds it to
-- the pool slot for @rank@.
register :: Int -> Pools -> Content -> IO Variable
register rank pools content = do
  var <- UF.fresh (Descriptor content rank noMark Nothing)
  ensurePoolSize rank pools
  currentPools <- readIORef pools
  MVector.modify currentPools (var :) rank
  return var

-- | Register existing variables at @rank@ in the given pool.
--
-- Updates each variable's descriptor rank to @rank@ and appends the list to the
-- rank-@rank@ slot in the pool.
introduce :: Int -> Pools -> [Variable] -> IO ()
introduce rank pools variables = do
  ensurePoolSize rank pools
  currentPools <- readIORef pools
  MVector.modify currentPools (variables ++) rank
  for_ variables $ \var ->
    UF.modify var $ \(Descriptor content _ mark copy) ->
      Descriptor content rank mark copy

-- Shared constant content values, marked NOINLINE to prevent duplication.

{-# NOINLINE emptyRecord1 #-}
emptyRecord1 :: Content
emptyRecord1 =
  Structure EmptyRecord1

{-# NOINLINE unit1 #-}
unit1 :: Content
unit1 =
  Structure Unit1

-- TYPE TO VARIABLE

-- | Convert a 'Type.Type' to a union-find 'Variable' at @rank@, allocating fresh
-- variables for each node and registering them in @pools@.
typeToVariable :: Int -> Pools -> Type -> IO Variable
typeToVariable rank pools = typeToVar rank pools Map.empty

-- | Internal worker for 'typeToVariable' with an alias dictionary.
--
-- The @aliasDict@ maps placeholder names (from 'PlaceHolder') to previously
-- allocated variables, enabling alias expansion.
--
-- PERF: Kept at top-level (not a @where@ binding) to avoid the known
-- ~1.5 s slowdown that manifests when @typeToVar@\/'register@ are local.
typeToVar :: Int -> Pools -> Map Name.Name Variable -> Type -> IO Variable
typeToVar rank pools aliasDict tipe =
  let go = typeToVar rank pools aliasDict
  in case tipe of
    VarN v -> return v
    AppN home name args -> convertAppType rank pools go home name args
    FunN a b -> convertFunType rank pools go a b
    AliasN home name args aliasType -> convertAliasType rank pools go home name args aliasType
    PlaceHolder name ->
      maybe
        (InternalError.report
          "Type.Solve.Pool.typeToVar"
          ("Unknown placeholder `" <> Text.pack (Name.toChars name) <> "` not in alias dict with " <> Text.pack (show (Map.size aliasDict)) <> " entries")
          "Alias dictionary missing expected type variable. This indicates a bug in alias type expansion.")
        return
        (Map.lookup name aliasDict)
    RecordN fields ext -> convertRecordType rank pools go fields ext
    EmptyRecordN -> register rank pools emptyRecord1
    UnitN -> register rank pools unit1
    TupleN a b c -> convertTupleType rank pools go a b c

convertAppType :: Int -> Pools -> (Type -> IO Variable) -> ModuleName.Canonical -> Name.Name -> [Type] -> IO Variable
convertAppType rank pools go home name args = do
  argVars <- traverse go args
  register rank pools (Structure (App1 home name argVars))

convertFunType :: Int -> Pools -> (Type -> IO Variable) -> Type -> Type -> IO Variable
convertFunType rank pools go a b = do
  aVar <- go a
  bVar <- go b
  register rank pools (Structure (Fun1 aVar bVar))

convertAliasType :: Int -> Pools -> (Type -> IO Variable) -> ModuleName.Canonical -> Name.Name -> [(Name.Name, Type)] -> Type -> IO Variable
convertAliasType rank pools go home name args aliasType = do
  argVars <- traverse (traverse go) args
  aliasVar <- typeToVar rank pools (Map.fromList argVars) aliasType
  register rank pools (Alias home name argVars aliasVar)

convertRecordType :: Int -> Pools -> (Type -> IO Variable) -> Map.Map Name.Name Type -> Type -> IO Variable
convertRecordType rank pools go fields ext = do
  fieldVars <- traverse go fields
  extVar <- go ext
  register rank pools (Structure (Record1 fieldVars extVar))

convertTupleType :: Int -> Pools -> (Type -> IO Variable) -> Type -> Type -> Maybe Type -> IO Variable
convertTupleType rank pools go a b c = do
  aVar <- go a
  bVar <- go b
  cVar <- traverse go c
  register rank pools (Structure (Tuple1 aVar bVar cVar))

-- SOURCE TYPE TO VARIABLE

-- | Convert a canonical source 'Can.Type' (from explicit annotations) to a
-- 'Variable' at @rank@.
--
-- @freeVars@ maps the free type-variable names in @srcType@ to unit; a fresh
-- flex variable is allocated for each.
srcTypeToVariable :: Int -> Pools -> Map Name.Name () -> Can.Type -> IO Variable
srcTypeToVariable rank pools freeVars srcType =
  let nameToContent name
        | Name.isNumberType name = FlexSuper Number (Just name)
        | Name.isComparableType name = FlexSuper Comparable (Just name)
        | Name.isAppendableType name = FlexSuper Appendable (Just name)
        | Name.isCompappendType name = FlexSuper CompAppend (Just name)
        | otherwise = FlexVar (Just name)

      makeVar name _ =
        UF.fresh (Descriptor (nameToContent name) rank noMark Nothing)
   in do
        flexVars <- Map.traverseWithKey makeVar freeVars
        ensurePoolSize rank pools
        currentPools <- readIORef pools
        MVector.modify currentPools (Map.elems flexVars ++) rank
        srcTypeToVar rank pools flexVars srcType

srcTypeToVar :: Int -> Pools -> Map Name.Name Variable -> Can.Type -> IO Variable
srcTypeToVar rank pools flexVars srcType =
  let go = srcTypeToVar rank pools flexVars
  in case srcType of
    Can.TLambda argument result -> convertSrcLambdaType rank pools go argument result
    Can.TVar name ->
      maybe
        (InternalError.report
          "Type.Solve.Pool.srcTypeToVar"
          ("Unknown type variable `" <> Text.pack (Name.toChars name) <> "` not in flexVars map with " <> Text.pack (show (Map.size flexVars)) <> " entries")
          "Flex vars dictionary missing expected variable. This indicates a bug in type variable allocation.")
        return
        (Map.lookup name flexVars)
    Can.TType home name args -> convertSrcAppType rank pools go home name args
    Can.TRecord fields maybeExt -> convertSrcRecordType rank pools flexVars fields maybeExt
    Can.TUnit -> register rank pools unit1
    Can.TTuple a b c -> convertSrcTupleType rank pools go a b c
    Can.TAlias home name args aliasType -> convertSrcAliasType rank pools go home name args aliasType

convertSrcLambdaType :: Int -> Pools -> (Can.Type -> IO Variable) -> Can.Type -> Can.Type -> IO Variable
convertSrcLambdaType rank pools go argument result = do
  argVar <- go argument
  resultVar <- go result
  register rank pools (Structure (Fun1 argVar resultVar))

convertSrcAppType :: Int -> Pools -> (Can.Type -> IO Variable) -> ModuleName.Canonical -> Name.Name -> [Can.Type] -> IO Variable
convertSrcAppType rank pools go home name args = do
  argVars <- traverse go args
  register rank pools (Structure (App1 home name argVars))

convertSrcRecordType :: Int -> Pools -> Map Name.Name Variable -> Map.Map Name.Name Can.FieldType -> Maybe Name.Name -> IO Variable
convertSrcRecordType rank pools flexVars fields maybeExt = do
  fieldVars <- traverse (srcFieldTypeToVar rank pools flexVars) fields
  extVar <- case maybeExt of
    Nothing -> register rank pools emptyRecord1
    Just ext ->
      maybe
        (InternalError.report
          "Type.Solve.Pool.convertSrcRecordType"
          ("Unknown record extension `" <> Text.pack (Name.toChars ext) <> "` not in flexVars map with " <> Text.pack (show (Map.size flexVars)) <> " entries")
          "Flex vars dictionary missing record extension variable. This indicates a bug in type variable allocation.")
        return
        (Map.lookup ext flexVars)
  register rank pools (Structure (Record1 fieldVars extVar))

convertSrcTupleType :: Int -> Pools -> (Can.Type -> IO Variable) -> Can.Type -> Can.Type -> Maybe Can.Type -> IO Variable
convertSrcTupleType rank pools go a b c = do
  aVar <- go a
  bVar <- go b
  cVar <- traverse go c
  register rank pools (Structure (Tuple1 aVar bVar cVar))

convertSrcAliasType :: Int -> Pools -> (Can.Type -> IO Variable) -> ModuleName.Canonical -> Name.Name -> [(Name.Name, Can.Type)] -> Can.AliasType -> IO Variable
convertSrcAliasType rank pools go home name args aliasType = do
  argVars <- traverse (traverse go) args
  aliasVar <- case aliasType of
    Can.Holey tipe -> srcTypeToVar rank pools (Map.fromList argVars) tipe
    Can.Filled tipe -> go tipe
  register rank pools (Alias home name argVars aliasVar)

srcFieldTypeToVar :: Int -> Pools -> Map Name.Name Variable -> Can.FieldType -> IO Variable
srcFieldTypeToVar rank pools flexVars (Can.FieldType _ srcTipe) =
  srcTypeToVar rank pools flexVars srcTipe

-- GENERALIZATION

-- | Collect all variables reachable from @ambientRigids@ through the type graph.
--
-- Used by 'performGeneralization' to identify which variables must not be
-- generalised (they are "ambient" and belong to an outer scope).
collectAmbientVariables :: [Variable] -> IO [Variable]
collectAmbientVariables ambientRigids = do
  let go visited var = do
        desc <- UF.get var
        case desc of
          Descriptor (Alias _ _ _ actualVar) _ _ _ ->
            if any (== actualVar) visited
              then return visited
              else go (var : visited) actualVar
          Descriptor (Structure term) _ _ _ -> do
            termVars <- getTermVariables term
            Monad.foldM go (var : visited) termVars
          _ ->
            return (var : visited)
  Monad.foldM go [] ambientRigids
  where
    getTermVariables term = case term of
      App1 _ _ args -> return args
      Fun1 arg result -> return [arg, result]
      EmptyRecord1 -> return []
      Record1 fields ext -> return (Map.elems fields <> [ext])
      Unit1 -> return []
      Tuple1 a b maybeC -> return ([a, b] <> maybe [] pure maybeC)

-- | Run generalisation for the current let-rank pool.
--
-- Adjusts ranks, registers old-rank variables back into lower pools, and
-- marks young-rank variables that are not ambient as generic (rank = 'noRank').
-- Resets the @nextRank@ slot in @nextPools@ to @[]@ after completion.
performGeneralization :: Mark -> Mark -> Int -> Pools -> [Variable] -> IO ()
performGeneralization youngMark visitMark nextRank nextPools ambientRigids = do
  ambientVars <- collectAmbientVariables ambientRigids
  generalize youngMark visitMark nextRank nextPools ambientVars
  currentPools <- readIORef nextPools
  MVector.write currentPools nextRank []

-- | Core generalisation algorithm.
--
-- Reads @youngRank@'s pool, builds a rank table, adjusts all ranks, re-registers
-- variables at their adjusted ranks, and generalises (sets to 'noRank') those
-- that are not in @ambientVars@.
generalize :: Mark -> Mark -> Int -> Pools -> [Variable] -> IO ()
generalize youngMark visitMark youngRank pools ambientVars = do
  currentPools <- readIORef pools
  youngVars <- MVector.read currentPools youngRank
  rankTable <- poolToRankTable youngMark youngRank youngVars
  adjustAllRanks youngMark visitMark rankTable
  registerOldPoolVariables pools rankTable
  registerOrGeneralizeYoungVars pools youngRank rankTable ambientVars

-- | Build a rank-indexed table of variables from @youngRank@'s pool.
--
-- Marks each variable with @youngMark@ during the pass to detect cycles.
-- The resulting vector has one slot per rank from 0 to @max(youngRank, maxRank)@.
poolToRankTable :: Mark -> Int -> [Variable] -> IO (Vector.Vector [Variable])
poolToRankTable youngMark youngRank youngInhabitants = do
  maxRank <- Monad.foldM (\acc var -> do
    (Descriptor _ rank _ _) <- UF.get var
    return (max acc rank)) youngRank youngInhabitants
  mutableTable <- MVector.replicate (maxRank + 1) []
  for_ youngInhabitants $ \var -> do
    (Descriptor content rank _ copy) <- UF.get var
    UF.set var (Descriptor content rank youngMark copy)
    MVector.modify mutableTable (var :) rank
  Vector.unsafeFreeze mutableTable

-- | Re-register all old-rank (non-young) variables back into their respective pools.
--
-- Skips redundant (unioned-away) variables.
registerOldPoolVariables :: Pools -> Vector.Vector [Variable] -> IO ()
registerOldPoolVariables pools rankTable =
  Vector.forM_ (Vector.unsafeInit rankTable) $ \vars ->
    for_ vars $ \var -> do
      isRedundant <- UF.redundant var
      if isRedundant
        then return ()
        else registerVariableInOldPool pools var

registerVariableInOldPool :: Pools -> Variable -> IO ()
registerVariableInOldPool pools var = do
  (Descriptor _ rank _ _) <- UF.get var
  ensurePoolSize rank pools
  currentPools <- readIORef pools
  MVector.modify currentPools (var :) rank

-- | For each young-rank variable, either re-register it in a lower pool or
-- generalise it by setting its rank to 'noRank'.
registerOrGeneralizeYoungVars :: Pools -> Int -> Vector.Vector [Variable] -> [Variable] -> IO ()
registerOrGeneralizeYoungVars pools youngRank rankTable ambientVars =
  for_ (Vector.unsafeLast rankTable) $ \var -> do
    isRedundant <- UF.redundant var
    if isRedundant
      then return ()
      else registerOrGeneralizeVariable pools youngRank var ambientVars

registerOrGeneralizeVariable :: Pools -> Int -> Variable -> [Variable] -> IO ()
registerOrGeneralizeVariable pools youngRank var ambientVars = do
  (Descriptor content rank mark copy) <- UF.get var
  isAmbientList <- mapM (`UF.equivalent` var) ambientVars
  let isAmbient = or isAmbientList
  if rank < youngRank || isAmbient
    then do
      ensurePoolSize rank pools
      currentPools <- readIORef pools
      MVector.modify currentPools (var :) rank
    else UF.set var $ Descriptor content noRank mark copy

-- ADJUST RANK

-- | Traverse all ranks in the rank table and adjust each variable's rank.
adjustAllRanks :: Mark -> Mark -> Vector.Vector [Variable] -> IO ()
adjustAllRanks youngMark visitMark rankTable =
  Vector.imapM_ (traverse_ . adjustRank youngMark visitMark) rankTable

-- | Adjust a single variable's rank so that ranks never increase deeper in the graph.
--
-- Variables marked with @youngMark@ are visited; those marked with @visitMark@
-- have already been processed; all others get @min groupRank rank@.
adjustRank :: Mark -> Mark -> Int -> Variable -> IO Int
adjustRank youngMark visitMark groupRank var = do
  (Descriptor content rank mark copy) <- UF.get var
  if mark == youngMark
    then do
      UF.set var $ Descriptor content rank visitMark copy
      maxRank <- adjustRankContent youngMark visitMark groupRank content
      UF.set var $ Descriptor content maxRank visitMark copy
      return maxRank
    else
      if mark == visitMark
        then return rank
        else do
          let minRank = min groupRank rank
          UF.set var $ Descriptor content minRank visitMark copy
          return minRank

adjustRankContent :: Mark -> Mark -> Int -> Content -> IO Int
adjustRankContent youngMark visitMark groupRank content =
  let go = adjustRank youngMark visitMark groupRank
  in case content of
    FlexVar _ -> return groupRank
    FlexSuper _ _ -> return groupRank
    RigidVar _ -> return groupRank
    RigidSuper _ _ -> return groupRank
    Structure flatType -> adjustRankStructure go flatType
    Alias _ _ args realVar -> adjustRankAlias go args realVar
    Error -> return groupRank

adjustRankStructure :: (Variable -> IO Int) -> FlatType -> IO Int
adjustRankStructure go flatType = case flatType of
  App1 _ _ args -> Monad.foldM (\rank arg -> max rank <$> go arg) outermostRank args
  Fun1 arg result -> max <$> go arg <*> go result
  EmptyRecord1 -> return outermostRank
  Record1 fields extension -> adjustRankRecord go fields extension
  Unit1 -> return outermostRank
  Tuple1 a b maybeC -> adjustRankTuple go a b maybeC

adjustRankRecord :: (Variable -> IO Int) -> Map.Map Name.Name Variable -> Variable -> IO Int
adjustRankRecord go fields extension = do
  extRank <- go extension
  Monad.foldM (\rank field -> max rank <$> go field) extRank fields

adjustRankTuple :: (Variable -> IO Int) -> Variable -> Variable -> Maybe Variable -> IO Int
adjustRankTuple go a b maybeC = do
  ma <- go a
  mb <- go b
  case maybeC of
    Nothing -> return (max ma mb)
    Just c -> max (max ma mb) <$> go c

adjustRankAlias :: (Variable -> IO Int) -> [(Name.Name, Variable)] -> Variable -> IO Int
adjustRankAlias go args realVar = do
  argsRank <- Monad.foldM (\rank (_, argVar) -> max rank <$> go argVar) outermostRank args
  realRank <- go realVar
  return (max argsRank realRank)

-- COPY

-- | Instantiate a polymorphic type variable by making a deep copy.
--
-- Rigid type variables in the copy are converted to flexible variables, except
-- when an ambient rigid with the same name exists — in that case the copy
-- unifies with the ambient rigid instead.
--
-- After copying, the copy-link fields written by 'makeCopyHelp' are cleaned up
-- by 'restore'.
makeCopy :: Int -> Pools -> [(Int, Variable)] -> Variable -> IO Variable
makeCopy rank pools ambientRigids var = do
  copy <- makeCopyHelp rank pools ambientRigids var
  restore var
  return copy

makeCopyHelp :: Int -> Pools -> [(Int, Variable)] -> Variable -> IO Variable
makeCopyHelp maxRank pools ambientRigids variable = do
  (Descriptor content rank _ maybeCopy) <- UF.get variable
  case content of
    Error ->
      return variable
    _ -> case maybeCopy of
      Just copy ->
        return copy
      Nothing -> handleNoCopy maxRank pools ambientRigids variable content rank

handleNoCopy :: Int -> Pools -> [(Int, Variable)] -> Variable -> Content -> Int -> IO Variable
handleNoCopy maxRank pools ambientRigids variable content rank
  | rank /= noRank =
      case content of
        RigidVar name -> checkForHigherRankRigid name variable rank ambientRigids
        RigidSuper super name -> checkForHigherRankRigidSuper name super variable rank ambientRigids
        _ -> return variable
  | otherwise =
      createAndLinkCopy maxRank pools ambientRigids variable content rank

-- | Check if there's a higher-rank version of a 'RigidVar' in ambient rigids.
--
-- Prefers the highest-rank match (most local scope) when multiple exist.
checkForHigherRankRigid :: Name.Name -> Variable -> Int -> [(Int, Variable)] -> IO Variable
checkForHigherRankRigid name variable currentRank ambientRigids = do
  matchingRigid <- findMatchingRigid name ambientRigids
  case matchingRigid of
    Just higherRigid -> do
      (Descriptor _ higherRank _ _) <- UF.get higherRigid
      if higherRank > currentRank
        then return higherRigid
        else return variable
    Nothing ->
      return variable

-- | Check if there's a higher-rank version of a 'RigidSuper' in ambient rigids.
checkForHigherRankRigidSuper :: Name.Name -> SuperType -> Variable -> Int -> [(Int, Variable)] -> IO Variable
checkForHigherRankRigidSuper name super variable currentRank ambientRigids = do
  matchingRigid <- findMatchingRigidSuper name super ambientRigids
  case matchingRigid of
    Just higherRigid -> do
      (Descriptor _ higherRank _ _) <- UF.get higherRigid
      if higherRank > currentRank
        then return higherRigid
        else return variable
    Nothing ->
      return variable

createFreshCopy :: Int -> Pools -> Content -> IO Variable
createFreshCopy maxRank pools content = do
  let makeDescriptor c = Descriptor c maxRank noMark Nothing
  copy <- UF.fresh $ makeDescriptor content
  ensurePoolSize maxRank pools
  currentPools <- readIORef pools
  MVector.modify currentPools (copy :) maxRank
  return copy

linkVariableToCopy :: Variable -> Content -> Int -> Variable -> IO ()
linkVariableToCopy variable content rank copy =
  UF.set variable $ Descriptor content rank noMark (Just copy)

processCopyContent :: Int -> Pools -> [(Int, Variable)] -> Variable -> Content -> Int -> IO Variable
processCopyContent maxRank pools ambientRigids copy content originalRank = do
  let makeDescriptor c = Descriptor c maxRank noMark Nothing
  case content of
    Structure term -> copyStructureContent maxRank pools ambientRigids copy makeDescriptor term
    FlexVar _ -> return copy
    FlexSuper _ _ -> return copy
    RigidVar name -> copyRigidVarContent ambientRigids copy makeDescriptor name originalRank
    RigidSuper super name -> copyRigidSuperContent ambientRigids copy makeDescriptor super name originalRank
    Alias home name args realType -> copyAliasContent maxRank pools ambientRigids copy makeDescriptor home name args realType
    Error -> return copy

copyStructureContent :: Int -> Pools -> [(Int, Variable)] -> Variable -> (Content -> Descriptor) -> FlatType -> IO Variable
copyStructureContent maxRank pools ambientRigids copy makeDescriptor term = do
  newTerm <- traverseFlatType (makeCopyHelp maxRank pools ambientRigids) term
  UF.set copy $ makeDescriptor (Structure newTerm)
  return copy

-- | Copy a 'RigidVar' by converting it to 'FlexVar'.
--
-- Generalized variables (rank 0) always become 'FlexVar'. Non-generalized
-- ones check for a matching ambient rigid to unify with instead.
copyRigidVarContent :: [(Int, Variable)] -> Variable -> (Content -> Descriptor) -> Name.Name -> Int -> IO Variable
copyRigidVarContent ambientRigids copy makeDescriptor name originalRank = do
  if originalRank == noRank
    then do
      UF.set copy . makeDescriptor $ FlexVar (Just name)
      return copy
    else do
      matchingRigid <- findMatchingRigid name ambientRigids
      case matchingRigid of
        Just rigidVar -> do
          UF.union copy rigidVar (makeDescriptor (RigidVar name))
          return copy
        Nothing -> do
          UF.set copy . makeDescriptor $ FlexVar (Just name)
          return copy

-- | Find an ambient rigid variable with matching name.
--
-- Returns the highest-rank match (most local scope) when multiple exist.
findMatchingRigid :: Name.Name -> [(Int, Variable)] -> IO (Maybe Variable)
findMatchingRigid targetName rigids = do
  matches <- collectMatches rigids
  case matches of
    [] -> return Nothing
    _ -> do
      let (_, bestVar) = maximumBy (\(r1, _) (r2, _) -> compare r1 r2) matches
      return (Just bestVar)
  where
    collectMatches [] = return []
    collectMatches ((rank, var) : rest) = do
      desc <- UF.get var
      case desc of
        Descriptor (RigidVar rigidName) _ _ _ | rigidName == targetName ->
          fmap ((rank, var) :) (collectMatches rest)
        Descriptor (RigidSuper _ rigidName) _ _ _ | rigidName == targetName ->
          fmap ((rank, var) :) (collectMatches rest)
        _ -> collectMatches rest

-- | Copy a 'RigidSuper' by converting it to 'FlexSuper'.
--
-- Generalized variables (rank 0) always become 'FlexSuper'. Non-generalized
-- ones check for a matching ambient rigid to unify with instead.
copyRigidSuperContent :: [(Int, Variable)] -> Variable -> (Content -> Descriptor) -> SuperType -> Name.Name -> Int -> IO Variable
copyRigidSuperContent ambientRigids copy makeDescriptor super name originalRank = do
  if originalRank == noRank
    then do
      UF.set copy . makeDescriptor $ FlexSuper super (Just name)
      return copy
    else do
      matchingRigid <- findMatchingRigidSuper name super ambientRigids
      case matchingRigid of
        Just rigidVar -> do
          UF.union copy rigidVar (makeDescriptor (RigidSuper super name))
          return copy
        Nothing -> do
          UF.set copy . makeDescriptor $ FlexSuper super (Just name)
          return copy

-- | Find an ambient 'RigidSuper' variable with matching name and compatible supertype.
--
-- Returns the highest-rank match. A 'RigidVar' with the same name can also match
-- any supertype.
findMatchingRigidSuper :: Name.Name -> SuperType -> [(Int, Variable)] -> IO (Maybe Variable)
findMatchingRigidSuper targetName targetSuper rigids = do
  matches <- collectMatches rigids
  case matches of
    [] -> return Nothing
    _ -> do
      let (_, bestVar) = maximumBy (\(r1, _) (r2, _) -> compare r1 r2) matches
      return (Just bestVar)
  where
    collectMatches [] = return []
    collectMatches ((rank, var) : rest) = do
      desc <- UF.get var
      case desc of
        Descriptor (RigidSuper rigidSuper rigidName) _ _ _
          | rigidName == targetName && rigidSuper == targetSuper ->
            fmap ((rank, var) :) (collectMatches rest)
        Descriptor (RigidVar rigidName) _ _ _ | rigidName == targetName ->
          fmap ((rank, var) :) (collectMatches rest)
        _ -> collectMatches rest

copyAliasContent :: Int -> Pools -> [(Int, Variable)] -> Variable -> (Content -> Descriptor) -> ModuleName.Canonical -> Name.Name -> [(Name.Name, Variable)] -> Variable -> IO Variable
copyAliasContent maxRank pools ambientRigids copy makeDescriptor home name args realType = do
  newArgs <- traverse (traverse (makeCopyHelp maxRank pools ambientRigids)) args
  newRealType <- makeCopyHelp maxRank pools ambientRigids realType
  UF.set copy $ makeDescriptor (Alias home name newArgs newRealType)
  return copy

createAndLinkCopy :: Int -> Pools -> [(Int, Variable)] -> Variable -> Content -> Int -> IO Variable
createAndLinkCopy maxRank pools ambientRigids variable content rank = do
  copy <- createFreshCopy maxRank pools content
  linkVariableToCopy variable content rank copy
  processCopyContent maxRank pools ambientRigids copy content rank

-- RESTORE

-- | Remove copy-link fields set during 'makeCopy'.
--
-- Called by 'makeCopy' after the deep-copy traversal to clean up the temporary
-- copy links, restoring each variable's copy field to 'Nothing'.
restore :: Variable -> IO ()
restore variable = do
  (Descriptor content _ _ maybeCopy) <- UF.get variable
  case maybeCopy of
    Nothing -> return ()
    Just _ -> resetVariableAndRestoreContent variable content

resetVariableAndRestoreContent :: Variable -> Content -> IO ()
resetVariableAndRestoreContent variable content = do
  UF.set variable $ Descriptor content noRank noMark Nothing
  restoreContent content

restoreContent :: Content -> IO ()
restoreContent content = case content of
  FlexVar _ -> return ()
  FlexSuper _ _ -> return ()
  RigidVar _ -> return ()
  RigidSuper _ _ -> return ()
  Structure term -> restoreStructureContent term
  Alias _ _ args var -> restoreAliasContent args var
  Error -> return ()

restoreStructureContent :: FlatType -> IO ()
restoreStructureContent term = case term of
  App1 _ _ args -> traverse_ restore args
  Fun1 arg result -> restoreFunctionContent arg result
  EmptyRecord1 -> return ()
  Record1 fields ext -> restoreRecordContent fields ext
  Unit1 -> return ()
  Tuple1 a b maybeC -> restoreTupleContent a b maybeC

restoreFunctionContent :: Variable -> Variable -> IO ()
restoreFunctionContent arg result = do
  restore arg
  restore result

restoreRecordContent :: Map.Map Name.Name Variable -> Variable -> IO ()
restoreRecordContent fields ext = do
  traverse_ restore fields
  restore ext

restoreTupleContent :: Variable -> Variable -> Maybe Variable -> IO ()
restoreTupleContent a b maybeC = do
  restore a
  restore b
  for_ maybeC restore

restoreAliasContent :: [(Name.Name, Variable)] -> Variable -> IO ()
restoreAliasContent args var = do
  traverse_ (traverse restore) args
  restore var

-- TRAVERSE FLAT TYPE

-- | Apply an effectful function to every immediate child variable in a 'FlatType'.
traverseFlatType :: (Variable -> IO Variable) -> FlatType -> IO FlatType
traverseFlatType f flatType =
  case flatType of
    App1 home name args ->
      fmap (App1 home name) (traverse f args)
    Fun1 a b ->
      Monad.liftM2 Fun1 (f a) (f b)
    EmptyRecord1 ->
      pure EmptyRecord1
    Record1 fields ext ->
      Monad.liftM2 Record1 (traverse f fields) (f ext)
    Unit1 ->
      pure Unit1
    Tuple1 a b cs ->
      Monad.liftM3 Tuple1 (f a) (f b) (traverse f cs)
