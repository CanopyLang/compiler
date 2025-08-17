{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}

module Type.Solve
  ( run,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.ModuleName as ModuleName
import Control.Lens (makeLenses, (^.), (.~), (&), (%~))
import Control.Monad (foldM, liftM2, liftM3)
import Data.Foldable (for_, traverse_)
import Data.Map.Strict (Map, (!))
import qualified Data.Map.Strict as Map
import qualified Data.Name as Name
import Data.NonEmptyList (List)
import qualified Data.NonEmptyList as NE
import qualified Data.Vector as Vector
import qualified Data.Vector.Mutable as MVector
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Type as Error
import qualified Reporting.Render.Type as RT
import qualified Reporting.Render.Type.Localizer as L
import qualified Type.Error as ET
import qualified Type.Occurs as Occurs
import Type.Type as Type
import qualified Type.Unify as Unify
import qualified Type.UnionFind as UF

-- TYPES

type Env = Map Name.Name Variable

type Pools = MVector.IOVector [Variable]

data State = State
  { _stateEnv :: !Env,
    _stateMark :: !Mark,
    _stateErrors :: ![Error.Error]
  }

makeLenses ''State

data SolveConfig = SolveConfig
  { _solveEnv :: !Env,
    _solveRank :: !Int,
    _solvePools :: !Pools,
    _solveState :: !State
  }

makeLenses ''SolveConfig

{-# NOINLINE emptyState #-}
emptyState :: State
emptyState = State
  { _stateEnv = Map.empty
  , _stateMark = nextMark noMark
  , _stateErrors = []
  }

-- RUN SOLVER

run :: Constraint -> IO (Either (List Error.Error) (Map Name.Name Can.Annotation))
run constraint = do
  pools <- MVector.replicate 8 []
  let config = createSolveConfig Map.empty outermostRank pools emptyState
  finalState <- solve config constraint
  case finalState ^. stateErrors of
    [] -> Right <$> traverse Type.toAnnotation (finalState ^. stateEnv)
    e : es -> return $ Left (NE.List e es)

createSolveConfig :: Env -> Int -> Pools -> State -> SolveConfig
createSolveConfig env rank pools state = SolveConfig
  { _solveEnv = env
  , _solveRank = rank
  , _solvePools = pools
  , _solveState = state
  }

-- SOLVER

solve :: SolveConfig -> Constraint -> IO State
solve config constraint = case constraint of
  CTrue -> return (config ^. solveState)
  CSaveTheEnvironment -> return $ config ^. solveState & stateEnv .~ (config ^. solveEnv)
  CEqual region category tipe expectation -> 
    solveEqual config region category tipe expectation
  CLocal region name expectation -> 
    solveLocal config region name expectation
  CForeign region name forall expectation -> 
    solveForeign config region name forall expectation
  CPattern region category tipe expectation -> 
    solvePattern config region category tipe expectation
  CAnd constraints -> 
    foldM (solve . updateSolveState config) (config ^. solveState) constraints
  CLet [] flexs _ headerCon CTrue -> 
    solveSimpleLet config flexs headerCon
  CLet [] [] header headerCon subCon -> 
    solveEmptyLet config header headerCon subCon
  CLet rigids flexs header headerCon subCon -> 
    solveFullLet config rigids flexs header headerCon subCon

isGeneric :: Variable -> IO ()
isGeneric var = do
  (Descriptor _ rank _ _) <- UF.get var
  if rank == noRank
    then return ()
    else do
      tipe <- Type.toErrorType var
      error (createCompilerBugMessage tipe rank)

createCompilerBugMessage :: ET.Type -> Int -> String
createCompilerBugMessage tipe rank =
  "You ran into a compiler bug. Here are some details for the developers:\n\n"
    <> "    " <> show (ET.toDoc L.empty RT.None tipe)
    <> " [rank = " <> show rank <> "]\n\n"
    <> "Please create an <http://sscce.org/> and then report it\n"
    <> "at <https://github.com/canopy/compiler/issues>\n\n"

updateSolveState :: SolveConfig -> State -> SolveConfig
updateSolveState config newState = config & solveState .~ newState

solveEqual :: SolveConfig -> A.Region -> Error.Category -> Type -> Error.Expected Type -> IO State
solveEqual config region category tipe expectation = do
  actual <- typeToVariable (config ^. solveRank) (config ^. solvePools) tipe
  expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
  handleUnifyResult config actual expected (createEqualError region category expectation)

solveLocal :: SolveConfig -> A.Region -> Name.Name -> Error.Expected Type -> IO State
solveLocal config region name expectation = do
  actual <- makeCopy (config ^. solveRank) (config ^. solvePools) ((config ^. solveEnv) ! name)
  expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
  handleUnifyResult config actual expected (createLocalError region name expectation)

solveForeign :: SolveConfig -> A.Region -> Name.Name -> Can.Annotation -> Error.Expected Type -> IO State
solveForeign config region name (Can.Forall freeVars srcType) expectation = do
  actual <- srcTypeToVariable (config ^. solveRank) (config ^. solvePools) freeVars srcType
  expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
  handleUnifyResult config actual expected (createForeignError region name expectation)

solvePattern :: SolveConfig -> A.Region -> Error.PCategory -> Type -> Error.PExpected Type -> IO State
solvePattern config region category tipe expectation = do
  actual <- typeToVariable (config ^. solveRank) (config ^. solvePools) tipe
  expected <- patternExpectationToVariable (config ^. solveRank) (config ^. solvePools) expectation
  handlePatternUnifyResult config actual expected (createPatternError region category expectation)

handleUnifyResult :: SolveConfig -> Variable -> Variable -> (ET.Type -> ET.Type -> Error.Error) -> IO State
handleUnifyResult config actual expected errorFunc = do
  answer <- Unify.unify actual expected
  case answer of
    Unify.Ok vars -> do
      introduce (config ^. solveRank) (config ^. solvePools) vars
      return (config ^. solveState)
    Unify.Err vars actualType expectedType -> do
      introduce (config ^. solveRank) (config ^. solvePools) vars
      return $ addError (config ^. solveState) (errorFunc actualType expectedType)

handlePatternUnifyResult :: SolveConfig -> Variable -> Variable -> (ET.Type -> ET.Type -> Error.Error) -> IO State
handlePatternUnifyResult config actual expected errorFunc = do
  answer <- Unify.unify actual expected
  case answer of
    Unify.Ok vars -> do
      introduce (config ^. solveRank) (config ^. solvePools) vars
      return (config ^. solveState)
    Unify.Err vars actualType expectedType -> do
      introduce (config ^. solveRank) (config ^. solvePools) vars
      return $ addError (config ^. solveState) (errorFunc actualType expectedType)

createEqualError :: A.Region -> Error.Category -> Error.Expected Type -> ET.Type -> ET.Type -> Error.Error
createEqualError region category expectation actualType expectedType =
  let expectedET = convertExpectedToET expectation expectedType
  in Error.BadExpr region category actualType expectedET

createLocalError :: A.Region -> Name.Name -> Error.Expected Type -> ET.Type -> ET.Type -> Error.Error
createLocalError region name expectation actualType expectedType =
  let expectedET = convertExpectedToET expectation expectedType
  in Error.BadExpr region (Error.Local name) actualType expectedET

createForeignError :: A.Region -> Name.Name -> Error.Expected Type -> ET.Type -> ET.Type -> Error.Error
createForeignError region name expectation actualType expectedType =
  let expectedET = convertExpectedToET expectation expectedType
  in Error.BadExpr region (Error.Foreign name) actualType expectedET

createPatternError :: A.Region -> Error.PCategory -> Error.PExpected Type -> ET.Type -> ET.Type -> Error.Error
createPatternError region category expectation actualType expectedType =
  let expectedPET = convertPExpectedToET expectation expectedType
  in Error.BadPattern region category actualType expectedPET

convertExpectedToET :: Error.Expected Type -> ET.Type -> Error.Expected ET.Type
convertExpectedToET expectation etType = Error.typeReplace expectation etType

convertPExpectedToET :: Error.PExpected Type -> ET.Type -> Error.PExpected ET.Type
convertPExpectedToET expectation etType = Error.ptypeReplace expectation etType

-- EXPECTATIONS TO VARIABLE

expectedToVariable :: Int -> Pools -> Error.Expected Type -> IO Variable
expectedToVariable rank pools expectation =
  typeToVariable rank pools $
    case expectation of
      Error.NoExpectation tipe ->
        tipe
      Error.FromContext _ _ tipe ->
        tipe
      Error.FromAnnotation _ _ _ tipe ->
        tipe

patternExpectationToVariable :: Int -> Pools -> Error.PExpected Type -> IO Variable
patternExpectationToVariable rank pools expectation =
  typeToVariable rank pools $
    case expectation of
      Error.PNoExpectation tipe ->
        tipe
      Error.PFromContext _ _ tipe ->
        tipe

solveSimpleLet :: SolveConfig -> [Variable] -> Constraint -> IO State
solveSimpleLet config flexs headerCon = do
  introduce (config ^. solveRank) (config ^. solvePools) flexs
  solve config headerCon

solveEmptyLet :: SolveConfig -> Map Name.Name (A.Located Type) -> Constraint -> Constraint -> IO State
solveEmptyLet config header headerCon subCon = do
  state1 <- solve config headerCon
  locals <- traverse (A.traverse (typeToVariable (config ^. solveRank) (config ^. solvePools))) header
  let newEnv = Map.union (config ^. solveEnv) (Map.map A.toValue locals)
  let newConfig = config & solveEnv .~ newEnv & solveState .~ state1
  state2 <- solve newConfig subCon
  foldM occurs state2 (Map.toList locals)

solveFullLet :: SolveConfig -> [Variable] -> [Variable] -> Map Name.Name (A.Located Type) -> Constraint -> Constraint -> IO State
solveFullLet config rigids flexs header headerCon subCon = do
  nextPools <- prepareNextPools config
  let nextRank = (config ^. solveRank) + 1
  nextConfig <- introduceLetVariables config rigids flexs nextRank nextPools
  (locals, solvedState) <- solveHeaderInNextPool nextConfig header headerCon
  finalState <- finalizeLetSolving nextConfig locals solvedState rigids subCon nextRank nextPools
  foldM occurs finalState (Map.toList locals)

prepareNextPools :: SolveConfig -> IO Pools
prepareNextPools config = do
  let nextRank = (config ^. solveRank) + 1
  let poolsLength = MVector.length (config ^. solvePools)
  if nextRank < poolsLength
    then return (config ^. solvePools)
    else MVector.grow (config ^. solvePools) poolsLength

-- ERROR HELPERS

introduceLetVariables :: SolveConfig -> [Variable] -> [Variable] -> Int -> Pools -> IO SolveConfig
introduceLetVariables config rigids flexs nextRank nextPools = do
  let vars = rigids <> flexs
  for_ vars $ \var ->
    UF.modify var $ \(Descriptor content _ mark copy) ->
      Descriptor content nextRank mark copy
  MVector.write nextPools nextRank vars
  return $ config & solveRank .~ nextRank & solvePools .~ nextPools

solveHeaderInNextPool :: SolveConfig -> Map Name.Name (A.Located Type) -> Constraint -> IO (Map Name.Name (A.Located Variable), State)
solveHeaderInNextPool config header headerCon = do
  locals <- traverse (A.traverse (typeToVariable (config ^. solveRank) (config ^. solvePools))) header
  solvedState <- solve config headerCon
  return (locals, solvedState)

finalizeLetSolving :: SolveConfig -> Map Name.Name (A.Located Variable) -> State -> [Variable] -> Constraint -> Int -> Pools -> IO State
finalizeLetSolving config locals solvedState rigids subCon nextRank nextPools = do
  let (youngMark, visitMark, finalMark) = calculateMarks solvedState
  performGeneralization youngMark visitMark nextRank nextPools
  traverse_ isGeneric rigids
  let newEnv = Map.union (config ^. solveEnv) (Map.map A.toValue locals)
  let tempState = solvedState & stateMark .~ finalMark
  let finalConfig = config & solveEnv .~ newEnv & solveState .~ tempState & solveRank .~ (config ^. solveRank)
  solve finalConfig subCon

calculateMarks :: State -> (Mark, Mark, Mark)
calculateMarks state =
  let youngMark = state ^. stateMark
      visitMark = nextMark youngMark
      finalMark = nextMark visitMark
  in (youngMark, visitMark, finalMark)

performGeneralization :: Mark -> Mark -> Int -> Pools -> IO ()
performGeneralization youngMark visitMark nextRank nextPools = do
  generalize youngMark visitMark nextRank nextPools
  MVector.write nextPools nextRank []

addError :: State -> Error.Error -> State
addError state err = state & stateErrors %~ (err :)

-- OCCURS CHECK

occurs :: State -> (Name.Name, A.Located Variable) -> IO State
occurs state (name, A.At region variable) =
  do
    hasOccurred <- Occurs.occurs variable
    if hasOccurred
      then do
        errorType <- Type.toErrorType variable
        (Descriptor _ rank mark copy) <- UF.get variable
        UF.set variable (Descriptor Error rank mark copy)
        return $ addError state (Error.InfiniteType region name errorType)
      else return state

-- GENERALIZE

generalize :: Mark -> Mark -> Int -> Pools -> IO ()
generalize youngMark visitMark youngRank pools = do
  youngVars <- MVector.read pools youngRank
  rankTable <- poolToRankTable youngMark youngRank youngVars
  adjustAllRanks youngMark visitMark rankTable
  registerOldPoolVariables pools rankTable
  registerOrGeneralizeYoungVars pools youngRank rankTable

adjustAllRanks :: Mark -> Mark -> Vector.Vector [Variable] -> IO ()
adjustAllRanks youngMark visitMark rankTable =
  Vector.imapM_ (traverse_ . adjustRank youngMark visitMark) rankTable

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
  MVector.modify pools (var :) rank

registerOrGeneralizeYoungVars :: Pools -> Int -> Vector.Vector [Variable] -> IO ()
registerOrGeneralizeYoungVars pools youngRank rankTable =
  for_ (Vector.unsafeLast rankTable) $ \var -> do
    isRedundant <- UF.redundant var
    if isRedundant
      then return ()
      else registerOrGeneralizeVariable pools youngRank var

registerOrGeneralizeVariable :: Pools -> Int -> Variable -> IO ()
registerOrGeneralizeVariable pools youngRank var = do
  (Descriptor content rank mark copy) <- UF.get var
  if rank < youngRank
    then MVector.modify pools (var :) rank
    else UF.set var $ Descriptor content noRank mark copy

poolToRankTable :: Mark -> Int -> [Variable] -> IO (Vector.Vector [Variable])
poolToRankTable youngMark youngRank youngInhabitants =
  do
    mutableTable <- MVector.replicate (youngRank + 1) []

    -- Sort the youngPool variables into buckets by rank.
    for_ youngInhabitants $ \var ->
      do
        (Descriptor content rank _ copy) <- UF.get var
        UF.set var (Descriptor content rank youngMark copy)
        MVector.modify mutableTable (var :) rank

    Vector.unsafeFreeze mutableTable

-- ADJUST RANK

--
-- Adjust variable ranks such that ranks never increase as you move deeper.
-- This way the outermost rank is representative of the entire structure.
--
adjustRank :: Mark -> Mark -> Int -> Variable -> IO Int
adjustRank youngMark visitMark groupRank var =
  do
    (Descriptor content rank mark copy) <- UF.get var
    if mark == youngMark
      then do
        -- Set the variable as marked first because it may be cyclic.
        UF.set var $ Descriptor content rank visitMark copy
        maxRank <- adjustRankContent youngMark visitMark groupRank content
        UF.set var $ Descriptor content maxRank visitMark copy
        return maxRank
      else
        if mark == visitMark
          then return rank
          else do
            let minRank = min groupRank rank
            -- TODO how can minRank ever be groupRank?
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
    Alias _ _ args _ -> adjustRankAlias go args
    Error -> return groupRank

adjustRankStructure :: (Variable -> IO Int) -> FlatType -> IO Int
adjustRankStructure go flatType = case flatType of
  App1 _ _ args -> foldM (\rank arg -> max rank <$> go arg) outermostRank args
  Fun1 arg result -> max <$> go arg <*> go result
  EmptyRecord1 -> return outermostRank
  Record1 fields extension -> adjustRankRecord go fields extension
  Unit1 -> return outermostRank
  Tuple1 a b maybeC -> adjustRankTuple go a b maybeC

adjustRankRecord :: (Variable -> IO Int) -> Map.Map Name.Name Variable -> Variable -> IO Int
adjustRankRecord go fields extension = do
  extRank <- go extension
  foldM (\rank field -> max rank <$> go field) extRank fields

adjustRankTuple :: (Variable -> IO Int) -> Variable -> Variable -> Maybe Variable -> IO Int
adjustRankTuple go a b maybeC = do
  ma <- go a
  mb <- go b
  case maybeC of
    Nothing -> return (max ma mb)
    Just c -> max (max ma mb) <$> go c

adjustRankAlias :: (Variable -> IO Int) -> [(Name.Name, Variable)] -> IO Int
adjustRankAlias go args =
  foldM (\rank (_, argVar) -> max rank <$> go argVar) outermostRank args

-- REGISTER VARIABLES

introduce :: Int -> Pools -> [Variable] -> IO ()
introduce rank pools variables =
  do
    MVector.modify pools (variables ++) rank
    for_ variables $ \var ->
      UF.modify var $ \(Descriptor content _ mark copy) ->
        Descriptor content rank mark copy

-- TYPE TO VARIABLE

typeToVariable :: Int -> Pools -> Type -> IO Variable
typeToVariable rank pools = typeToVar rank pools Map.empty

-- PERF working with @mgriffith we noticed that a 784 line entry in a `let` was
-- causing a ~1.5 second slowdown. Moving it to the top-level to be a function
-- saved all that time. The slowdown seems to manifest in `typeToVar` and in
-- `register` in particular. Have not explored further yet. Top-level definitions
-- are recommended in cases like this anyway, so there is at least a safety
-- valve for now.
--
typeToVar :: Int -> Pools -> Map Name.Name Variable -> Type -> IO Variable
typeToVar rank pools aliasDict tipe =
  let go = typeToVar rank pools aliasDict
  in case tipe of
    VarN v -> return v
    AppN home name args -> convertAppType rank pools go home name args
    FunN a b -> convertFunType rank pools go a b
    AliasN home name args aliasType -> convertAliasType rank pools go home name args aliasType
    PlaceHolder name -> return (aliasDict ! name)
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

register :: Int -> Pools -> Content -> IO Variable
register rank pools content =
  do
    var <- UF.fresh (Descriptor content rank noMark Nothing)
    MVector.modify pools (var :) rank
    return var

{-# NOINLINE emptyRecord1 #-}
emptyRecord1 :: Content
emptyRecord1 =
  Structure EmptyRecord1

{-# NOINLINE unit1 #-}
unit1 :: Content
unit1 =
  Structure Unit1

-- SOURCE TYPE TO VARIABLE

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
        MVector.modify pools (Map.elems flexVars ++) rank
        srcTypeToVar rank pools flexVars srcType

srcTypeToVar :: Int -> Pools -> Map Name.Name Variable -> Can.Type -> IO Variable
srcTypeToVar rank pools flexVars srcType =
  let go = srcTypeToVar rank pools flexVars
  in case srcType of
    Can.TLambda argument result -> convertSrcLambdaType rank pools go argument result
    Can.TVar name -> return (flexVars ! name)
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
    Just ext -> return (flexVars ! ext)
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

-- COPY

makeCopy :: Int -> Pools -> Variable -> IO Variable
makeCopy rank pools var =
  do
    copy <- makeCopyHelp rank pools var
    restore var
    return copy

makeCopyHelp :: Int -> Pools -> Variable -> IO Variable
makeCopyHelp maxRank pools variable = do
  (Descriptor content rank _ maybeCopy) <- UF.get variable
  case maybeCopy of
    Just copy -> return copy
    Nothing -> handleNoCopy maxRank pools variable content rank

handleNoCopy :: Int -> Pools -> Variable -> Content -> Int -> IO Variable
handleNoCopy maxRank pools variable content rank
  | rank /= noRank = return variable
  | otherwise = createAndLinkCopy maxRank pools variable content rank

createFreshCopy :: Int -> Pools -> Content -> IO Variable
createFreshCopy maxRank pools content = do
  let makeDescriptor c = Descriptor c maxRank noMark Nothing
  copy <- UF.fresh $ makeDescriptor content
  MVector.modify pools (copy :) maxRank
  return copy

linkVariableToCopy :: Variable -> Content -> Int -> Variable -> IO ()
linkVariableToCopy variable content rank copy =
  UF.set variable $ Descriptor content rank noMark (Just copy)

processCopyContent :: Int -> Pools -> Variable -> Content -> IO Variable
processCopyContent maxRank pools copy content = do
  let makeDescriptor c = Descriptor c maxRank noMark Nothing
  case content of
    Structure term -> copyStructureContent maxRank pools copy makeDescriptor term
    FlexVar _ -> return copy
    FlexSuper _ _ -> return copy
    RigidVar name -> copyRigidVarContent copy makeDescriptor name
    RigidSuper super name -> copyRigidSuperContent copy makeDescriptor super name
    Alias home name args realType -> copyAliasContent maxRank pools copy makeDescriptor home name args realType
    Error -> return copy

copyStructureContent :: Int -> Pools -> Variable -> (Content -> Descriptor) -> FlatType -> IO Variable
copyStructureContent maxRank pools copy makeDescriptor term = do
  newTerm <- traverseFlatType (makeCopyHelp maxRank pools) term
  UF.set copy $ makeDescriptor (Structure newTerm)
  return copy

copyRigidVarContent :: Variable -> (Content -> Descriptor) -> Name.Name -> IO Variable
copyRigidVarContent copy makeDescriptor name = do
  UF.set copy . makeDescriptor $ FlexVar (Just name)
  return copy

copyRigidSuperContent :: Variable -> (Content -> Descriptor) -> SuperType -> Name.Name -> IO Variable
copyRigidSuperContent copy makeDescriptor super name = do
  UF.set copy . makeDescriptor $ FlexSuper super (Just name)
  return copy

copyAliasContent :: Int -> Pools -> Variable -> (Content -> Descriptor) -> ModuleName.Canonical -> Name.Name -> [(Name.Name, Variable)] -> Variable -> IO Variable
copyAliasContent maxRank pools copy makeDescriptor home name args realType = do
  newArgs <- traverse (traverse (makeCopyHelp maxRank pools)) args
  newRealType <- makeCopyHelp maxRank pools realType
  UF.set copy $ makeDescriptor (Alias home name newArgs newRealType)
  return copy

createAndLinkCopy :: Int -> Pools -> Variable -> Content -> Int -> IO Variable
createAndLinkCopy maxRank pools variable content rank = do
  copy <- createFreshCopy maxRank pools content
  linkVariableToCopy variable content rank copy
  processCopyContent maxRank pools copy content

-- RESTORE

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

traverseFlatType :: (Variable -> IO Variable) -> FlatType -> IO FlatType
traverseFlatType f flatType =
  case flatType of
    App1 home name args ->
      fmap (App1 home name) (traverse f args)
    Fun1 a b ->
      liftM2 Fun1 (f a) (f b)
    EmptyRecord1 ->
      pure EmptyRecord1
    Record1 fields ext ->
      liftM2 Record1 (traverse f fields) (f ext)
    Unit1 ->
      pure Unit1
    Tuple1 a b cs ->
      liftM3 Tuple1 (f a) (f b) (traverse f cs)
