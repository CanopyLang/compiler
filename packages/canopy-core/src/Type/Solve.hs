{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Type.Solve - Hindley-Milner constraint solver
--
-- This module implements the core constraint-solving loop of the Canopy type
-- checker.  It takes a 'Constraint' produced by 'Type.Constrain.*' and returns
-- either a map of inferred 'Can.Annotation' values (one per top-level binding)
-- or a non-empty list of type errors.
--
-- == Architecture
--
-- The solver is split across two modules to keep each file manageable:
--
--   * This module contains the high-level solver logic: the 'SolveConfig' and
--     'State' types, the 'run' entry point, the 'solve' dispatch loop, and all
--     constraint-specific handlers.
--   * "Type.Solve.Pool" contains the lower-level infrastructure: pool
--     management, type-to-variable conversion, generalisation, and the copy\/
--     restore machinery.
--
-- == Let-polymorphism
--
-- The solver implements Hindley-Milner let-polymorphism via a two-pool scheme.
-- When a @CLet@ constraint is encountered the solver creates a new rank-@n+1@
-- pool, solves the binding at that rank, and then generalises variables that
-- did not escape into the outer scope (rank ≤ @n@).  Generalised variables are
-- set to @rank = noRank@ (generic) so 'makeCopy' can instantiate them freshly
-- at each use site.
module Type.Solve
  ( run,
    runWithBounds,
    extractBoundsFromAliases,
    extractAllInterfaceBounds,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Data.Name as Name
import Control.Lens (makeLenses, (%~), (&), (.~), (^.))
import Control.Monad (filterM, foldM, forM, when)
import Data.Foldable (for_, traverse_)
import Data.IORef
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Vector.Mutable as MVector
import Canopy.Data.NonEmptyList (List)
import qualified Canopy.Data.NonEmptyList as NE
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Type as Error
import qualified Reporting.InternalError as InternalError
import qualified Reporting.Render.Type as RT
import qualified Reporting.Render.Type.Localizer as Localizer
import qualified Type.Error as ET
import qualified Type.Occurs as Occurs
import Type.Solve.Pool (Pools)
import qualified Type.Solve.Pool as Pool
import Type.Type as Type
import qualified Type.Unify as Unify
import qualified Type.UnionFind as UF
import Logging.Event (ConstraintKind (..), LogEvent (..))
import qualified Logging.Logger as Log

-- TYPES

type Env = Map Name.Name Variable

data State = State
  { _stateEnv :: !Env,
    _stateMark :: !Mark,
    _stateErrors :: ![Error.Error],
    _stateMonoEnv :: !Env
  }

makeLenses ''State

data SolveConfig = SolveConfig
  { _solveEnv :: !Env,
    _solveRank :: !Int,
    _solvePools :: !Pools,
    _solveState :: !State,
    _solveAmbientRigids :: ![(Int, Variable)],
    _solveDeferAllGeneralization :: !Bool,
    _solveBounds :: !Unify.BoundsMap
  }

makeLenses ''SolveConfig

{-# NOINLINE emptyState #-}
emptyState :: State
emptyState = State
  { _stateEnv = Map.empty
  , _stateMark = nextMark noMark
  , _stateErrors = []
  , _stateMonoEnv = Map.empty
  }

-- RUN SOLVER

-- | Run the constraint solver on the top-level 'Constraint'.
--
-- Creates an initial pool vector and 'SolveConfig', then calls 'solve'.
-- Returns either the inferred annotations or the accumulated type errors.
run :: Constraint -> IO (Either (List Error.Error) (Map Name.Name Can.Annotation))
run = runWithBounds Map.empty

-- | Run the constraint solver with opaque alias bounds registered.
--
-- The bounds map tells the unifier which nominal types satisfy which
-- super type constraints (e.g., an opaque @UserId@ type satisfying
-- @comparable@). This enables opaque bounded aliases to be used in
-- constrained contexts like @Set@ keys or @Dict@ keys.
runWithBounds ::
  Map (ModuleName.Canonical, Name.Name) SuperType ->
  Constraint ->
  IO (Either (List Error.Error) (Map Name.Name Can.Annotation))
runWithBounds bounds constraint = do
  poolsVec <- MVector.replicate 8 []
  pools <- newIORef poolsVec
  let config = createSolveConfig Map.empty outermostRank pools emptyState bounds
  finalState <- solve config constraint
  case finalState ^. stateErrors of
    [] -> Right <$> traverse Type.toAnnotation (finalState ^. stateEnv)
    e : es -> return $ Left (NE.List e es)

-- | Extract supertype bounds from a map of interface aliases.
--
-- Scans all public/opaque aliases in an interface map and returns a bounds
-- map suitable for 'runWithBounds'. Only aliases with a 'Just' supertype
-- bound are included.
extractBoundsFromAliases ::
  ModuleName.Canonical ->
  Map Name.Name Can.Alias ->
  Map (ModuleName.Canonical, Name.Name) SuperType
extractBoundsFromAliases home =
  Map.foldlWithKey' collectBound Map.empty
  where
    collectBound acc name (Can.Alias _ _ _ maybeBound) =
      maybe acc (\bound -> Map.insert (home, name) (convertBound bound) acc) maybeBound

-- | Convert a canonical 'SupertypeBound' to the solver's 'SuperType'.
convertBound :: Can.SupertypeBound -> SuperType
convertBound Can.ComparableBound = Comparable
convertBound Can.AppendableBound = Appendable
convertBound Can.NumberBound = Number
convertBound Can.CompAppendBound = CompAppend

-- | Extract all supertype bounds from a full dependency interface map.
--
-- Iterates over every interface, constructs the canonical module name from
-- each interface's home package and the raw module name key, then collects
-- bounds from all aliases that declare a supertype bound.
extractAllInterfaceBounds ::
  Map ModuleName.Raw Interface.Interface ->
  Map (ModuleName.Canonical, Name.Name) SuperType
extractAllInterfaceBounds =
  Map.foldlWithKey' collectFromInterface Map.empty
  where
    collectFromInterface acc rawName iface =
      Map.union acc (extractBoundsFromAliases canonical aliasMap)
      where
        canonical = ModuleName.Canonical (Interface._home iface) rawName
        aliasMap = Map.map Interface.extractAlias (Interface._aliases iface)

createSolveConfig :: Env -> Int -> Pools -> State -> Unify.BoundsMap -> SolveConfig
createSolveConfig env rank pools state bounds = SolveConfig
  { _solveEnv = env
  , _solveRank = rank
  , _solvePools = pools
  , _solveState = state
  , _solveAmbientRigids = []
  , _solveDeferAllGeneralization = False
  , _solveBounds = bounds
  }

-- SOLVER

-- | Dispatch a single 'Constraint' to its specific handler.
--
-- Each constraint variant maps to one of the @solve*@ helpers below.
solve :: SolveConfig -> Constraint -> IO State
solve config constraint = do
  enabled <- Log.isEnabled
  when enabled (logConstraintKind constraint)
  case constraint of
    CTrue -> return (config ^. solveState)
    CSaveTheEnvironment -> return $ config ^. solveState & stateEnv .~ (config ^. solveEnv)
    CEqual region category tipe expectation ->
      solveEqual config region category tipe expectation
    CLocal region name expectation ->
      solveLocal config region name expectation
    CForeign region name forAll expectation ->
      solveForeign config region name forAll expectation
    CPattern region category tipe expectation ->
      solvePattern config region category tipe expectation
    CAnd constraints ->
      foldM (solve . updateSolveState config) (config ^. solveState) constraints
    CCaseBranchesIsolated constraints ->
      foldM (solve . updateSolveState config) (config ^. solveState) constraints
    CLet [] flexs _ headerCon CTrue _ ->
      solveSimpleLet config flexs headerCon
    CLet [] [] header headerCon subCon _ ->
      solveEmptyLet config header headerCon subCon
    CLet rigids flexs header headerCon subCon expectedType ->
      solveFullLet config rigids flexs header headerCon subCon expectedType

-- | Reset a rigid variable to 'noRank' after generalisation.
--
-- Both 'RigidVar' and 'RigidSuper' are reset; 'RigidSuper' represents
-- constrained type variables (@comparable@, @number@, etc.) that must be
-- generalised so they can be instantiated independently at each call site.
resetRigidToNoRank :: Variable -> IO ()
resetRigidToNoRank var = do
  (Descriptor content _ mark copy) <- UF.get var
  UF.set var (Descriptor content noRank mark copy)

-- | Recursively generalise a variable and all nested variables to rank 0.
--
-- Ensures that when 'makeCopy' is called, all parts of the type structure are
-- properly instantiated with fresh variables.
--
-- 'Error' and 'RigidVar' are never generalised; 'RigidSuper' must be
-- generalised so polymorphic constraints get fresh instantiations.
generalizeRecursively :: Variable -> IO ()
generalizeRecursively var = do
  (Descriptor content rank mark copy) <- UF.get var
  case content of
    Error -> return ()
    _ | rank == noRank -> return ()
      | otherwise -> case content of
          FlexVar _ ->
            UF.set var (Descriptor content noRank mark copy)
          FlexSuper _ _ ->
            UF.set var (Descriptor content noRank mark copy)
          Structure flatType -> do
            UF.set var (Descriptor content noRank mark copy)
            generalizeStructure flatType
          Alias _ _ args realVar -> do
            UF.set var (Descriptor content noRank mark copy)
            traverse_ (generalizeRecursively . snd) args
            generalizeRecursively realVar
          RigidSuper _ _ ->
            UF.set var (Descriptor content noRank mark copy)
          RigidVar _ -> return ()

-- | Generalise all nested variables in a 'FlatType'.
generalizeStructure :: FlatType -> IO ()
generalizeStructure flatType = case flatType of
  App1 _ _ args -> traverse_ generalizeRecursively args
  Fun1 arg result -> do
    generalizeRecursively arg
    generalizeRecursively result
  EmptyRecord1 -> return ()
  Record1 fields ext -> do
    traverse_ generalizeRecursively fields
    generalizeRecursively ext
  Unit1 -> return ()
  Tuple1 a b maybeC -> do
    generalizeRecursively a
    generalizeRecursively b
    traverse_ generalizeRecursively maybeC

-- | Assert that a variable is generic (rank = 'noRank').
--
-- Reports an internal error if the variable still has a non-zero rank,
-- indicating a bug in the constraint solver.
isGeneric :: Variable -> IO ()
isGeneric var = do
  (Descriptor _ rank _ _) <- UF.get var
  if rank == noRank
    then return ()
    else do
      tipe <- Type.toErrorType var
      InternalError.report
        "Type.Solve.isGeneric"
        (Text.pack ("Non-generic type variable at rank " <> show rank <> ": " <> show (ET.toDoc Localizer.empty RT.None tipe)))
        "A type variable was expected to be generalized (rank=noRank) but still has a concrete rank. This indicates a bug in the constraint solver."

-- | Emit a TRACE log event for the constraint kind being solved.
logConstraintKind :: Constraint -> IO ()
logConstraintKind = \case
  CTrue -> pure ()
  CSaveTheEnvironment -> pure ()
  CEqual {} -> Log.logEvent (TypeConstraintSolved "solver" CKEqual)
  CLocal {} -> Log.logEvent (TypeConstraintSolved "solver" CKLocal)
  CForeign {} -> Log.logEvent (TypeConstraintSolved "solver" CKForeign)
  CPattern {} -> Log.logEvent (TypeConstraintSolved "solver" CKPattern)
  CLet {} -> Log.logEvent (TypeConstraintSolved "solver" CKLet)
  CAnd {} -> Log.logEvent (TypeConstraintSolved "solver" CKAnd)
  CCaseBranchesIsolated {} -> Log.logEvent (TypeConstraintSolved "solver" CKCase)

updateSolveState :: SolveConfig -> State -> SolveConfig
updateSolveState config newState = config & solveState .~ newState

-- CONSTRAINT HANDLERS

solveEqual :: SolveConfig -> Ann.Region -> Error.Category -> Type -> Error.Expected Type -> IO State
solveEqual config region category tipe expectation = do
  actual <- Pool.typeToVariable (config ^. solveRank) (config ^. solvePools) tipe
  expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
  handleUnifyResult config actual expected (createEqualError region category expectation)

solveLocal :: SolveConfig -> Ann.Region -> Name.Name -> Error.Expected Type -> IO State
solveLocal config region name expectation =
  case Map.lookup name (config ^. solveEnv) of
    Just envType -> solveLocalFromEnv config region name expectation envType
    Nothing -> solveLocalFromMonoEnv config region name expectation

-- | Solve a local variable found in 'solveEnv'.
--
-- 'solveEnv' always takes precedence over 'monoEnv'.  Generalised variables
-- (rank = 'noRank') are instantiated via 'makeCopy'; monomorphic variables are
-- used directly.
solveLocalFromEnv :: SolveConfig -> Ann.Region -> Name.Name -> Error.Expected Type -> Variable -> IO State
solveLocalFromEnv config region name expectation envType = do
  actualEnvType <- UF.repr envType
  (Descriptor _ envRank _ _) <- UF.get actualEnvType
  if envRank == noRank
    then do
      actual <- Pool.makeCopy (config ^. solveRank) (config ^. solvePools) (config ^. solveAmbientRigids) actualEnvType
      expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
      handleUnifyResult config actual expected (createLocalError region name expectation)
    else do
      expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
      handleUnifyResult config actualEnvType expected (createLocalError region name expectation)

-- | Solve a local variable found in 'stateMonoEnv' (or create a placeholder).
--
-- Monomorphic variables (rank > 0) are used directly; generalised ones (rank 0)
-- are instantiated via 'makeCopy'.
solveLocalFromMonoEnv :: SolveConfig -> Ann.Region -> Name.Name -> Error.Expected Type -> IO State
solveLocalFromMonoEnv config region name expectation = do
  let currentMonoEnv = config ^. solveState . stateMonoEnv
  case Map.lookup name currentMonoEnv of
    Just monoType -> do
      (Descriptor _ monoRank _ _) <- UF.get monoType
      if monoRank == noRank
        then do
          actual <- Pool.makeCopy (config ^. solveRank) (config ^. solvePools) (config ^. solveAmbientRigids) monoType
          expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
          handleUnifyResult config actual expected (createLocalError region name expectation)
        else do
          expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
          handleUnifyResult config monoType expected (createLocalError region name expectation)
    Nothing -> do
      actual <- Pool.register Type.noRank (config ^. solvePools) (FlexVar Nothing)
      expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
      handleUnifyResult config actual expected (createLocalError region name expectation)

solveForeign :: SolveConfig -> Ann.Region -> Name.Name -> Can.Annotation -> Error.Expected Type -> IO State
solveForeign config region name (Can.Forall freeVars srcType) expectation = do
  actual <- Pool.srcTypeToVariable (config ^. solveRank) (config ^. solvePools) freeVars srcType
  expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
  handleUnifyResult config actual expected (createForeignError region name expectation)

solvePattern :: SolveConfig -> Ann.Region -> Error.PCategory -> Type -> Error.PExpected Type -> IO State
solvePattern config region category tipe expectation = do
  actual <- Pool.typeToVariable (config ^. solveRank) (config ^. solvePools) tipe
  expected <- patternExpectationToVariable (config ^. solveRank) (config ^. solvePools) expectation
  handlePatternUnifyResult config actual expected (createPatternError region category expectation)

handleUnifyResult :: SolveConfig -> Variable -> Variable -> (ET.Type -> ET.Type -> Error.Error) -> IO State
handleUnifyResult config actual expected errorFunc = do
  answer <- Unify.unify (config ^. solveBounds) actual expected
  case answer of
    Unify.Ok vars -> do
      enabled <- Log.isEnabled
      when enabled (Log.logEvent (TypeUnified "solver" "actual" "expected"))
      Pool.introduce (config ^. solveRank) (config ^. solvePools) vars
      return (config ^. solveState)
    Unify.Err vars actualType expectedType -> do
      enabled <- Log.isEnabled
      when enabled (Log.logEvent (TypeUnifyFailed "solver" (Text.pack (show actualType)) (Text.pack (show expectedType))))
      Pool.introduce (config ^. solveRank) (config ^. solvePools) vars
      return $ addError (config ^. solveState) (errorFunc actualType expectedType)

handlePatternUnifyResult :: SolveConfig -> Variable -> Variable -> (ET.Type -> ET.Type -> Error.Error) -> IO State
handlePatternUnifyResult config actual expected errorFunc = do
  answer <- Unify.unify (config ^. solveBounds) actual expected
  case answer of
    Unify.Ok vars -> do
      Pool.introduce (config ^. solveRank) (config ^. solvePools) vars
      return (config ^. solveState)
    Unify.Err vars actualType expectedType -> do
      Pool.introduce (config ^. solveRank) (config ^. solvePools) vars
      return $ addError (config ^. solveState) (errorFunc actualType expectedType)

createEqualError :: Ann.Region -> Error.Category -> Error.Expected Type -> ET.Type -> ET.Type -> Error.Error
createEqualError region category expectation actualType expectedType =
  let expectedET = convertExpectedToET expectation expectedType
  in Error.BadExpr region category actualType expectedET

createLocalError :: Ann.Region -> Name.Name -> Error.Expected Type -> ET.Type -> ET.Type -> Error.Error
createLocalError region name expectation actualType expectedType =
  let expectedET = convertExpectedToET expectation expectedType
  in Error.BadExpr region (Error.Local name) actualType expectedET

createForeignError :: Ann.Region -> Name.Name -> Error.Expected Type -> ET.Type -> ET.Type -> Error.Error
createForeignError region name expectation actualType expectedType =
  let expectedET = convertExpectedToET expectation expectedType
  in Error.BadExpr region (Error.Foreign name) actualType expectedET

createPatternError :: Ann.Region -> Error.PCategory -> Error.PExpected Type -> ET.Type -> ET.Type -> Error.Error
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
  Pool.typeToVariable rank pools $
    case expectation of
      Error.NoExpectation tipe -> tipe
      Error.FromContext _ _ tipe -> tipe
      Error.FromAnnotation _ _ _ tipe -> tipe

patternExpectationToVariable :: Int -> Pools -> Error.PExpected Type -> IO Variable
patternExpectationToVariable rank pools expectation =
  Pool.typeToVariable rank pools $
    case expectation of
      Error.PNoExpectation tipe -> tipe
      Error.PFromContext _ _ tipe -> tipe

-- LET SOLVING

solveSimpleLet :: SolveConfig -> [Variable] -> Constraint -> IO State
solveSimpleLet config flexs headerCon = do
  Pool.introduce (config ^. solveRank) (config ^. solvePools) flexs
  solve config headerCon

solveEmptyLet :: SolveConfig -> Map Name.Name (Ann.Located Type) -> Constraint -> Constraint -> IO State
solveEmptyLet config header headerCon subCon = do
  locals <- traverse (Ann.traverse (Pool.typeToVariable (config ^. solveRank) (config ^. solvePools))) header
  let localsEnv = Map.fromList [(name, var) | (name, Ann.At _ var) <- Map.toList locals]
  let configWithLocals = config & solveEnv .~ Map.union localsEnv (config ^. solveEnv)
  state1 <- solve configWithLocals headerCon
  let newEnv = Map.union (config ^. solveEnv) (Map.map Ann.toValue locals)
  let newConfig = config & solveEnv .~ newEnv & solveState .~ state1
  state2 <- solve newConfig subCon
  foldM occurs state2 (Map.toList locals)

solveFullLet :: SolveConfig -> [Variable] -> [Variable] -> Map Name.Name (Ann.Located Type) -> Constraint -> Constraint -> Maybe Type -> IO State
solveFullLet config rigids flexs header headerCon subCon expectedType = do
  enabled <- Log.isEnabled
  when enabled (Log.logEvent (TypeLetGeneralized "solver" "let-binding" (length flexs)))
  nextPools <- prepareNextPools config
  let nextRank = (config ^. solveRank) + 1
  nextConfig <- introduceLetVariables config rigids flexs nextRank nextPools
  (locals, solvedState) <- solveHeaderInNextPool nextConfig header headerCon
  finalState <- finalizeLetSolving nextConfig locals solvedState rigids subCon nextRank nextPools expectedType
  foldM occurs finalState (Map.toList locals)

prepareNextPools :: SolveConfig -> IO Pools
prepareNextPools config = do
  let nextRank = (config ^. solveRank) + 1
  currentPools <- readIORef (config ^. solvePools)
  let poolsLength = MVector.length currentPools
  if nextRank < poolsLength
    then return (config ^. solvePools)
    else do
      newPools <- MVector.grow currentPools poolsLength
      newPoolsRef <- newIORef newPools
      return newPoolsRef

introduceLetVariables :: SolveConfig -> [Variable] -> [Variable] -> Int -> Pools -> IO SolveConfig
introduceLetVariables config rigids flexs nextRank nextPools = do
  let vars = rigids <> flexs
  for_ vars $ \var ->
    UF.modify var $ \(Descriptor content _ mark copy) ->
      Descriptor content nextRank mark copy
  currentPools <- readIORef nextPools
  MVector.write currentPools nextRank vars
  validRigids <- filterM isNotError rigids
  let rankedRigids = [(nextRank, rigid) | rigid <- validRigids]
  let newAmbientRigids = (config ^. solveAmbientRigids) <> rankedRigids
  return $ config
    & solveRank .~ nextRank
    & solvePools .~ nextPools
    & solveAmbientRigids .~ newAmbientRigids

isNotError :: Variable -> IO Bool
isNotError rigid = do
  (Descriptor content _ _ _) <- UF.get rigid
  return (case content of
    Error -> False
    _ -> True)

solveHeaderInNextPool :: SolveConfig -> Map Name.Name (Ann.Located Type) -> Constraint -> IO (Map Name.Name (Ann.Located Variable), State)
solveHeaderInNextPool config header headerCon = do
  locals <- traverse (Ann.traverse (Pool.typeToVariable (config ^. solveRank) (config ^. solvePools))) header
  let localsEnv = Map.fromList [(name, var) | (name, Ann.At _ var) <- Map.toList locals]
  let configWithLocals = config & solveEnv .~ Map.union localsEnv (config ^. solveEnv)
  solvedState <- solve configWithLocals headerCon
  return (locals, solvedState)

finalizeLetSolving :: SolveConfig -> Map Name.Name (Ann.Located Variable) -> State -> [Variable] -> Constraint -> Int -> Pools -> Maybe Type -> IO State
finalizeLetSolving config locals solvedState rigids subCon nextRank nextPools expectedType = do
  let ambientRigids = config ^. solveAmbientRigids
  let hasAmbientRigids = not (null ambientRigids)
  let hasExpectedType = maybe False (const True) expectedType
  let shouldDefer = (config ^. solveDeferAllGeneralization) || hasAmbientRigids || hasExpectedType
  if shouldDefer
    then finalizeDeferredLet config locals solvedState rigids subCon nextRank ambientRigids
    else finalizeStandardLet config locals solvedState rigids subCon nextRank nextPools ambientRigids

-- | Finalise a let-binding when generalisation must be deferred.
--
-- Adds bindings to 'monoEnv', solves the body, then checks which variables
-- unified with outer scope and can be retroactively generalised.
finalizeDeferredLet :: SolveConfig -> Map Name.Name (Ann.Located Variable) -> State -> [Variable] -> Constraint -> Int -> [(Int, Variable)] -> IO State
finalizeDeferredLet config locals solvedState rigids subCon nextRank ambientRigids = do
  let hasOwnRigids = not (null rigids)
  let isAtModuleLevel = null ambientRigids
  let hasLocals = not (Map.null locals)
  let isOriginalDefer = hasOwnRigids || isAtModuleLevel || hasLocals
  let currentMonoEnv = solvedState ^. stateMonoEnv
  let newMonoEnv = Map.union (Map.map Ann.toValue locals) currentMonoEnv
  let newVarsThisLevel = Map.keysSet (Map.map Ann.toValue locals)
  let tempState = solvedState & stateMonoEnv .~ newMonoEnv
  let shouldGeneralizeEarly = isOriginalDefer
  tempState2 <- if shouldGeneralizeEarly
    then do
      for_ (Map.toList locals) $ \(_name, Ann.At _ var) -> do
        actualVar <- UF.repr var
        generalizeRecursively actualVar
      traverse_ resetRigidToNoRank rigids
      return tempState
    else return tempState
  let currentAmbientRigids =
        if shouldGeneralizeEarly
        then [(rank, var) | (rank, var) <- config ^. solveAmbientRigids, rank /= nextRank]
        else config ^. solveAmbientRigids
  let bodyConfig = config
        & solveState .~ tempState2
        & solveRank .~ (config ^. solveRank)
        & solveAmbientRigids .~ currentAmbientRigids
        & solveDeferAllGeneralization .~ True
  bodyState <- solve bodyConfig subCon
  if shouldGeneralizeEarly
    then finalizeEarlyGeneralized bodyState locals ambientRigids
    else if isOriginalDefer
      then finalizeOriginalDeferred bodyState config locals ambientRigids rigids nextRank newVarsThisLevel
      else return bodyState

finalizeEarlyGeneralized :: State -> Map Name.Name (Ann.Located Variable) -> [(Int, Variable)] -> IO State
finalizeEarlyGeneralized bodyState locals _ambientRigids = do
  let (_, _, finalMark) = calculateMarks bodyState
  let polyEnv = Map.fromList [(name, var) | (name, Ann.At _ var) <- Map.toList locals]
  let finalEnv = Map.union (bodyState ^. stateEnv) polyEnv
  return $ bodyState
    & stateMark .~ finalMark
    & stateEnv .~ finalEnv
    & stateMonoEnv .~ Map.empty

finalizeOriginalDeferred :: State -> SolveConfig -> Map Name.Name (Ann.Located Variable) -> [(Int, Variable)] -> [Variable] -> Int -> Set.Set Name.Name -> IO State
finalizeOriginalDeferred bodyState config locals ambientRigids rigids nextRank newVarsThisLevel = do
  let parentRank = nextRank - 1
  let finalMonoEnv = bodyState ^. stateMonoEnv
  let outerRigids = [(rank, var) | (rank, var) <- ambientRigids, rank < nextRank]
  let dummyPos = Ann.Position 0 0
  varsFromMonoEnv <- forM (Map.toList finalMonoEnv) $ \(name, var) ->
    if Set.member name newVarsThisLevel
      then do
        actualVar <- UF.repr var
        (Descriptor _ actualRank _ _) <- UF.get actualVar
        if actualRank >= parentRank
          then return (Just (name, Ann.At (Ann.Region dummyPos dummyPos) var))
          else return Nothing
      else return Nothing
  let varsFromMonoEnvFiltered = [x | Just x <- varsFromMonoEnv]
  let localsToCheck = [(name, locatedVar) | (name, locatedVar) <- Map.toList locals]
  let varsToCheckFiltered = varsFromMonoEnvFiltered <> localsToCheck
  monoToPolyVars <- foldM (checkAndGeneralizeWithParent nextRank parentRank outerRigids locals) [] varsToCheckFiltered
  let polyEnv = Map.fromList [(name, var) | (name, var) <- monoToPolyVars]
  let finalEnv = Map.union (config ^. solveEnv) polyEnv
  remainingMonoVars <- foldM (retainOuterMonoVar polyEnv parentRank) Map.empty
    [(name, var) | (name, Ann.At _ var) <- varsToCheckFiltered]
  let (_, _, finalMark) = calculateMarks bodyState
  traverse_ resetRigidToNoRank rigids
  traverse_ isGeneric rigids
  return $ bodyState
    & stateMark .~ finalMark
    & stateEnv .~ finalEnv
    & stateMonoEnv .~ remainingMonoVars

retainOuterMonoVar :: Map Name.Name Variable -> Int -> Map Name.Name Variable -> (Name.Name, Variable) -> IO (Map Name.Name Variable)
retainOuterMonoVar polyEnv parentRank acc (name, var) =
  if Map.member name polyEnv
    then return acc
    else do
      actualVar <- UF.repr var
      (Descriptor _ actualRank _ _) <- UF.get actualVar
      if actualRank < parentRank
        then return (Map.insert name var acc)
        else return acc

-- | Finalise a let-binding using the standard generalisation path.
--
-- No ambient rigids: run the full pool-based generalisation, reset rigids, and
-- solve the body constraint.
finalizeStandardLet :: SolveConfig -> Map Name.Name (Ann.Located Variable) -> State -> [Variable] -> Constraint -> Int -> Pools -> [(Int, Variable)] -> IO State
finalizeStandardLet config locals solvedState rigids subCon nextRank nextPools ambientRigids = do
  let (youngMark, visitMark, finalMark) = calculateMarks solvedState
  let ambientRigidVars = fmap snd ambientRigids
  Pool.performGeneralization youngMark visitMark nextRank nextPools ambientRigidVars
  traverse_ resetRigidToNoRank rigids
  traverse_ isGeneric rigids
  let newEnv = Map.union (config ^. solveEnv) (Map.map Ann.toValue locals)
  let tempState = solvedState & stateMark .~ finalMark
  let finalConfig = config & solveEnv .~ newEnv & solveState .~ tempState & solveRank .~ (config ^. solveRank)
  solve finalConfig subCon

-- GENERALIZATION HELPERS

-- | Extract immediate child variables from a 'FlatType' (non-recursive).
extractVarsFromFlatType :: FlatType -> [Variable]
extractVarsFromFlatType flatType = case flatType of
  App1 _ _ vars -> vars
  Fun1 arg result -> [arg, result]
  EmptyRecord1 -> []
  Record1 fields ext -> Map.elems fields <> [ext]
  Unit1 -> []
  Tuple1 a b maybeC -> [a, b] <> maybe [] pure maybeC

-- | Recursively extract all variables from a unified type by following union-find links.
extractVarsFromUnifiedType :: Variable -> IO [Variable]
extractVarsFromUnifiedType var = do
  actualVar <- UF.repr var
  (Descriptor content _ _ _) <- UF.get actualVar
  case content of
    Structure flatType -> do
      let childVars = extractVarsFromFlatType flatType
      nestedVars <- concat <$> traverse extractVarsFromUnifiedType childVars
      return (childVars <> nestedVars)
    FlexVar _ -> return [actualVar]
    FlexSuper _ _ -> return [actualVar]
    RigidVar _ -> return [actualVar]
    RigidSuper _ _ -> return [actualVar]
    Alias _ _ args realVar -> do
      argVars <- concat <$> traverse (extractVarsFromUnifiedType . snd) args
      realVars <- extractVarsFromUnifiedType realVar
      return (argVars <> realVars)
    Error -> return []

-- | Check whether a monomorphic variable can be retroactively generalised.
--
-- Variables that unified with the outer scope (rank <= parentRank) or with
-- ambient rigids remain monomorphic.  Variables that stayed local (rank >
-- parentRank) are generalised via 'generalizeRecursively'.
checkAndGeneralizeWithParent :: Int -> Int -> [(Int, Variable)] -> Map Name.Name (Ann.Located Variable) -> [(Name.Name, Variable)] -> (Name.Name, Ann.Located Variable) -> IO [(Name.Name, Variable)]
checkAndGeneralizeWithParent youngRank parentRank outerRigids locals acc (name, Ann.At _ var) = do
  actualVar <- UF.repr var
  (Descriptor _ actualRank _ _) <- UF.get actualVar
  allVarsInType <- extractVarsFromUnifiedType var
  let isLocal = Map.member name locals
  let rigidRankThreshold = if isLocal then parentRank else actualRank
  let strictlyOuterRigids = [(r, v) | (r, v) <- outerRigids, r < rigidRankThreshold]
  let rigidsToCheck = fmap snd strictlyOuterRigids
  equivalences <- forM allVarsInType $ \typeVar ->
    forM rigidsToCheck $ \rigidVar ->
      UF.equivalent typeVar rigidVar
  let isUnifiedWithRigid = any id (concat equivalences)
  let hasOuterRigids = not (null outerRigids)
  let isModuleLevel = isLocal
  if actualRank == noRank
    then return ((name, var) : acc)
    else if isUnifiedWithRigid && not isModuleLevel
      then return acc
    else if actualRank <= parentRank
      then return acc
    else if hasOuterRigids && actualRank /= youngRank && not isModuleLevel
      then return acc
      else do
        generalizeRecursively actualVar
        return ((name, var) : acc)

calculateMarks :: State -> (Mark, Mark, Mark)
calculateMarks state =
  let youngMark = state ^. stateMark
      visitMark = nextMark youngMark
      finalMark = nextMark visitMark
  in (youngMark, visitMark, finalMark)

addError :: State -> Error.Error -> State
addError state err = state & stateErrors %~ (err :)

-- OCCURS CHECK

occurs :: State -> (Name.Name, Ann.Located Variable) -> IO State
occurs state (name, Ann.At region variable) = do
  hasOccurred <- Occurs.occurs variable
  if hasOccurred
    then do
      errorType <- Type.toErrorType variable
      (Descriptor _ rank mark copy) <- UF.get variable
      UF.set variable (Descriptor Error rank mark copy)
      return $ addError state (Error.InfiniteType region name errorType)
    else return state
