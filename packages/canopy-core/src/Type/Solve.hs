{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Type.Solve
  ( run,
  )
where

import qualified AST.Canonical as Can
import qualified Canopy.ModuleName as ModuleName
import Control.Lens (makeLenses, (^.), (.~), (&), (%~))
import Control.Monad (filterM, foldM, forM, liftM2, liftM3, when)
import Data.Foldable (for_, traverse_, maximumBy)
import Data.Map.Strict (Map)
import qualified Data.Text as Text
import qualified Reporting.InternalError as InternalError
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Data.Set as Set
import Canopy.Data.NonEmptyList (List)
import qualified Canopy.Data.NonEmptyList as NE
import qualified Data.Vector as Vector
import qualified Data.Vector.Mutable as MVector
import Data.IORef
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Type as Error
import qualified Reporting.Render.Type as RT
import qualified Reporting.Render.Type.Localizer as Localizer
import qualified Type.Error as ET
import qualified Type.Occurs as Occurs
import Type.Type as Type
import qualified Type.Unify as Unify
import qualified Type.UnionFind as UF
import Logging.Event (LogEvent (..), ConstraintKind (..))
import qualified Logging.Logger as Log

-- TYPES

type Env = Map Name.Name Variable

type Pools = IORef (MVector.IOVector [Variable])

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
    _solveDeferAllGeneralization :: !Bool
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

run :: Constraint -> IO (Either (List Error.Error) (Map Name.Name Can.Annotation))
run constraint = do
  poolsVec <- MVector.replicate 8 []
  pools <- newIORef poolsVec
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
  , _solveAmbientRigids = []
  , _solveDeferAllGeneralization = False
  }

-- SOLVER

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
      -- Case branches are solved sequentially, matching Elm's proven type solver
      -- behavior. Each branch's unification results flow into subsequent branches.
      foldM (solve . updateSolveState config) (config ^. solveState) constraints
    CLet [] flexs _ headerCon CTrue _ ->
      solveSimpleLet config flexs headerCon
    CLet [] [] header headerCon subCon _ ->
      solveEmptyLet config header headerCon subCon
    CLet rigids flexs header headerCon subCon expectedType ->
      solveFullLet config rigids flexs header headerCon subCon expectedType

-- | Reset a rigid variable to noRank after generalization
-- IMPORTANT: Reset BOTH RigidVar and RigidSuper!
-- RigidSuper represents constrained type variables (comparable, number, etc.) that must be
-- generalized so they can be instantiated independently for each use
resetRigidToNoRank :: Variable -> IO ()
resetRigidToNoRank var = do
  (Descriptor content _ mark copy) <- UF.get var
  case content of
    RigidVar _ ->
      UF.set var (Descriptor content noRank mark copy)
    RigidSuper _ _ ->
      UF.set var (Descriptor content noRank mark copy)  -- MUST reset RigidSuper for generalization
    _ -> UF.set var (Descriptor content noRank mark copy)  -- Reset other content types

-- | Recursively generalize a variable and all nested variables to rank 0
-- This ensures that when makeCopy is called, all parts of the type structure
-- are properly instantiated with fresh variables
--
-- IMPORTANT: Generalize FlexVar, FlexSuper, RigidSuper, and Structure content. NEVER generalize:
-- - Error: Error markers should NEVER be generalized or modified
-- - RigidVar: Rigid type parameters from explicit annotations should maintain their ranks
--
-- NOTE: RigidSuper (constrained type variables like 'number') MUST be generalized!
-- They represent polymorphic constraints that need fresh instantiation for each use
generalizeRecursively :: Variable -> IO ()
generalizeRecursively var = do
  (Descriptor content rank mark copy) <- UF.get var
  -- Check for Error content FIRST, before rank check
  case content of
    Error -> return ()  -- NEVER generalize Error variables
    -- Only generalize if not already at rank 0 to avoid infinite loops
    _ | rank == noRank -> return ()
      | otherwise -> case content of
          -- Only generalize flex variables and structures
          FlexVar _ -> do
            UF.set var (Descriptor content noRank mark copy)
          FlexSuper _ _ -> do
            UF.set var (Descriptor content noRank mark copy)
          Structure flatType -> do
            -- Set this variable to rank 0 first (prevents infinite recursion)
            UF.set var (Descriptor content noRank mark copy)
            -- Recursively generalize nested variables in structure
            generalizeStructure flatType
          Alias _ _ args realVar -> do
            -- Set this variable to rank 0 first
            UF.set var (Descriptor content noRank mark copy)
            -- Recursively generalize alias arguments and real variable
            traverse_ (generalizeRecursively . snd) args
            generalizeRecursively realVar
          -- CRITICAL FIX: MUST generalize RigidSuper variables!
          -- RigidSuper represents constrained type variables (number, comparable, etc.)
          -- These MUST be generalized to rank 0 so makeCopy can instantiate them properly
          -- Previously we were NOT generalizing them, causing them to stay at rank 2
          RigidSuper _ _ -> do
            UF.set var (Descriptor content noRank mark copy)
          -- NEVER generalize regular rigid variables (type parameters from annotations)
          RigidVar _ -> return ()

-- | Generalize all nested variables in a structure
-- This is called by generalizeRecursively after setting the structure itself to rank 0
-- Note: generalizeRecursively will skip RigidVar/Error but WILL generalize RigidSuper
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

-- | Emit a TRACE event for the constraint kind being solved.
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

solveEqual :: SolveConfig -> Ann.Region -> Error.Category -> Type -> Error.Expected Type -> IO State
solveEqual config region category tipe expectation = do
  actual <- typeToVariable (config ^. solveRank) (config ^. solvePools) tipe
  expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
  handleUnifyResult config actual expected (createEqualError region category expectation)

solveLocal :: SolveConfig -> Ann.Region -> Name.Name -> Error.Expected Type -> IO State
solveLocal config region name expectation = do
  -- CRITICAL FIX: solveEnv ALWAYS takes precedence over monoEnv!
  -- Parameters and local bindings in solveEnv should NEVER be shadowed by stale monoEnv entries.
  -- Only check monoEnv if the variable is NOT in solveEnv at all.
  case Map.lookup name (config ^. solveEnv) of
    Just envType -> do
      -- Variable found in solveEnv - use it regardless of rank
      -- IMPORTANT: Follow repr chain to get actual current descriptor
      actualEnvType <- UF.repr envType
      descriptor <- UF.get actualEnvType
      let envRank = case descriptor of
            Descriptor _ r _ _ -> r
      let _descContent = case descriptor of
            Descriptor c _ _ _ -> case c of
              FlexVar _ -> ("FlexVar" :: String)
              FlexSuper _ _ -> ("FlexSuper" :: String)
              RigidVar _ -> ("RigidVar" :: String)
              RigidSuper _ _ -> ("RigidSuper" :: String)
              Structure _ -> ("Structure" :: String)
              Alias _ _ _ _ -> ("Alias" :: String)
              Error -> ("Error" :: String)
      if envRank == noRank
        then do
          -- Variable is generalized (polymorphic), instantiate it with makeCopy
          actual <- makeCopy (config ^. solveRank) (config ^. solvePools) (config ^. solveAmbientRigids) actualEnvType
          expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
          handleUnifyResult config actual expected (createLocalError region name expectation)
        else do
          -- Variable is at non-zero rank (local/parameter), use directly without instantiation
          expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
          handleUnifyResult config actualEnvType expected (createLocalError region name expectation)
    Nothing -> do
      -- Not in solveEnv, check monoEnv
      let currentMonoEnv = (config ^. solveState . stateMonoEnv)
      case Map.lookup name currentMonoEnv of
        Just monoType -> do
          -- Check if the variable was generalized (rank 0)
          -- CRITICAL FIX: DO NOT call UF.repr! The variable in monoEnv is the pristine
          -- generalized type. If we call UF.repr, it might follow union-find Links created
          -- during previous instantiations, returning an already-unified type instead of
          -- the pristine generalized type. This causes phantom type bugs where the first
          -- use constrains subsequent uses.
          (Descriptor _content monoRank _ _) <- UF.get monoType
          if monoRank == noRank
            then do
              -- Variable was generalized, instantiate it
              -- IMPORTANT: Use empty ambient rigids list! Generalized type variables should
              -- become fresh FlexVars, not unify with ambient rigids that happen to share names.
              -- Type variables in generalized types are QUANTIFIED and independent of outer scope.
              actual <- makeCopy (config ^. solveRank) (config ^. solvePools) (config ^. solveAmbientRigids) monoType
              expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
              handleUnifyResult config actual expected (createLocalError region name expectation)
            else do
              -- Use monomorphic variable directly without makeCopy
              expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
              handleUnifyResult config monoType expected (createLocalError region name expectation)
        Nothing -> do
          -- Not found anywhere, create placeholder
          actual <- register Type.noRank (config ^. solvePools) (FlexVar Nothing)
          expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
          handleUnifyResult config actual expected (createLocalError region name expectation)

solveForeign :: SolveConfig -> Ann.Region -> Name.Name -> Can.Annotation -> Error.Expected Type -> IO State
solveForeign config region name (Can.Forall freeVars srcType) expectation = do
  actual <- srcTypeToVariable (config ^. solveRank) (config ^. solvePools) freeVars srcType
  expected <- expectedToVariable (config ^. solveRank) (config ^. solvePools) expectation
  handleUnifyResult config actual expected (createForeignError region name expectation)

solvePattern :: SolveConfig -> Ann.Region -> Error.PCategory -> Type -> Error.PExpected Type -> IO State
solvePattern config region category tipe expectation = do
  actual <- typeToVariable (config ^. solveRank) (config ^. solvePools) tipe
  expected <- patternExpectationToVariable (config ^. solveRank) (config ^. solvePools) expectation
  handlePatternUnifyResult config actual expected (createPatternError region category expectation)

handleUnifyResult :: SolveConfig -> Variable -> Variable -> (ET.Type -> ET.Type -> Error.Error) -> IO State
handleUnifyResult config actual expected errorFunc = do
  answer <- Unify.unify actual expected
  case answer of
    Unify.Ok vars -> do
      enabled <- Log.isEnabled
      when enabled (Log.logEvent (TypeUnified "solver" "actual" "expected"))
      introduce (config ^. solveRank) (config ^. solvePools) vars
      return (config ^. solveState)
    Unify.Err vars actualType expectedType -> do
      enabled <- Log.isEnabled
      when enabled (Log.logEvent (TypeUnifyFailed "solver" (Text.pack (show actualType)) (Text.pack (show expectedType))))
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

-- CASE BRANCH ISOLATION
--
-- This section implements proper isolation of case branch environments to prevent
-- cross-branch type pollution through union-find Links. Each case branch gets a
-- completely independent deep clone of polymorphic environment variables, preventing
-- unification in one branch from affecting other branches.
--
-- This fixes the polymorphism bug where:
--   case page of
--     Branch1 -> polymorphicFn concrete1
--     Branch2 -> polymorphicFn concrete2  -- Must get fresh polymorphic types
--
-- Without isolation, Branch 1 unification creates permanent union-find Links in nested
-- type variables (e.g., inside Fun1 structures). When Branch 2 calls makeCopy on the
-- same environment variable, makeCopyHelp follows these Links and gets Branch 1's
-- specialized types instead of fresh polymorphic variables.
--
-- Deep cloning creates completely independent variable structures without any shared
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

solveEmptyLet :: SolveConfig -> Map Name.Name (Ann.Located Type) -> Constraint -> Constraint -> IO State
solveEmptyLet config header headerCon subCon = do
  -- CRITICAL FIX: Create locals and add to environment BEFORE solving headerCon
  -- This ensures parameters shadow any previous bindings with the same name
  locals <- traverse (Ann.traverse (typeToVariable (config ^. solveRank) (config ^. solvePools))) header
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
  (locals, solvedState) <- solveHeaderInNextPool nextConfig header headerCon rigids
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

-- ERROR HELPERS

introduceLetVariables :: SolveConfig -> [Variable] -> [Variable] -> Int -> Pools -> IO SolveConfig
introduceLetVariables config rigids flexs nextRank nextPools = do
  let vars = rigids <> flexs
  for_ vars $ \var ->
    UF.modify var $ \(Descriptor content _ mark copy) ->
      Descriptor content nextRank mark copy
  currentPools <- readIORef nextPools
  MVector.write currentPools nextRank vars
  -- Filter out any Error variables from rigids before adding to ambient rigids
  -- Error variables should never be treated as ambient rigids
  validRigids <- filterM (\rigid -> do
    (Descriptor content _ _ _) <- UF.get rigid
    return (case content of
      Error -> False
      _ -> True)
    ) rigids
  let rankedRigids = [(nextRank, rigid) | rigid <- validRigids]
  let newAmbientRigids = (config ^. solveAmbientRigids) <> rankedRigids
  return $ config
    & solveRank .~ nextRank
    & solvePools .~ nextPools
    & solveAmbientRigids .~ newAmbientRigids

solveHeaderInNextPool :: SolveConfig -> Map Name.Name (Ann.Located Type) -> Constraint -> [Variable] -> IO (Map Name.Name (Ann.Located Variable), State)
solveHeaderInNextPool config header headerCon _rigids = do
  locals <- traverse (Ann.traverse (typeToVariable (config ^. solveRank) (config ^. solvePools))) header
  -- DON'T filter THIS function's rigids from ambient rigids!
  -- The function body NEEDS access to these rigids for proper type variable instantiation
  -- When the body instantiates polymorphic functions, makeCopy looks for matching rigids
  -- If we filter out the current function's rigids, instantiation will find wrong rigids
  -- from outer scopes, breaking type identity for types with 3+ parameters
  -- CRITICAL FIX: Add locals to environment BEFORE solving headerCon
  -- This ensures that when the body references parameters, it finds the NEW bindings, not stale ones from monoEnv
  -- Parameters should shadow any previous bindings with the same name
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
    then do
      -- MONOMORPHIC PATH: Add let bindings to monoEnv, solve body, then check generalization
      -- isOriginalDefer: Check generalization if:
      --   1. Has own rigids (explicit type annotation), OR
      --   2. At module level (no ambient rigids), OR
      --   3. Let-bound function (should enable let-polymorphism)
      -- The key insight: ALL let-bound functions should be checked for generalization
      -- to enable Hindley-Milner let-polymorphism
      let hasOwnRigids = not (null rigids)
      let isAtModuleLevel = null ambientRigids
      let hasLocals = not (Map.null locals)
      -- CRITICAL FIX: ALL let-bound functions should attempt generalization (let-polymorphism)
      -- Not just those with explicit type annotations (hasOwnRigids)
      let isOriginalDefer = hasOwnRigids || isAtModuleLevel || hasLocals

      -- Add locals to monoEnv (NOT main env) - these are constrained by outer scope
      -- IMPORTANT: Use Map.union with locals FIRST so new variables shadow old ones with same name
      -- This prevents parameter name collisions across different functions
      let currentMonoEnv = solvedState ^. stateMonoEnv
      let newMonoEnv = Map.union (Map.map Ann.toValue locals) currentMonoEnv
      -- Track which variables are NEW at this level (not from outer scope)
      let newVarsThisLevel = Map.keysSet (Map.map Ann.toValue locals)
      let tempState = solvedState
            & stateMark .~ (solvedState ^. stateMark)
            & stateMonoEnv .~ newMonoEnv
      -- FOR TYPED DEFS: Generalize immediately BEFORE solving body
      -- This allows subsequent functions to use this one polymorphically
      -- Any function with explicit type annotation (isOriginalDefer) can be generalized early
      let _parentRank = nextRank - 1
      let shouldGeneralizeEarly = isOriginalDefer  -- All TypedDefs, not just module-level
      tempState2 <- if shouldGeneralizeEarly
        then do
          -- Recursively generalize the locals immediately
          -- This ensures ALL nested variables (including Structure variables and nested RigidVars)
          -- are set to rank 0, not just the top-level variable
          for_ (Map.toList locals) $ \(_name, Ann.At _ var) -> do
            actualVar <- UF.repr var
            generalizeRecursively actualVar
          -- Reset THIS function's rigids to rank 0 (they are the function's type parameters)
          -- This allows them to be properly instantiated when the function is called
          traverse_ resetRigidToNoRank rigids
          return tempState
        else
          return tempState

      -- CRITICAL FIX: After generalizing, remove THIS function's rigids from ambient rigids
      -- When a function is generalized to rank 0, its type parameters are no longer "ambient"
      -- to subsequent code - they're quantified variables of the generalized function.
      -- If we keep them in ambient rigids, later instantiations will incorrectly unify with them.
      let currentAmbientRigids =
            if shouldGeneralizeEarly
            then
              -- Remove rigids that belong to THIS function (nextRank)
              -- These rigids are now generalized and should not be in ambient rigids for subsequent code
              [(rank, var) | (rank, var) <- config ^. solveAmbientRigids, rank /= nextRank]
            else
              config ^. solveAmbientRigids

      let bodyConfig = config
            & solveState .~ tempState2
            & solveRank .~ (config ^. solveRank)
            & solveAmbientRigids .~ currentAmbientRigids  -- Use filtered ambient rigids (generalized rigids removed)
            & solveDeferAllGeneralization .~ True  -- Nested lets in body should also defer

      -- Solve body - monomorphic variables will be used directly (no makeCopy)
      -- This establishes unifications with outer scope
      bodyState <- solve bodyConfig subCon

      -- Only do generalization check if this is the ORIGINAL deferred let (first one with ambient rigids)
      -- Nested lets inherit the defer flag but should NOT generalize
      -- Skip if we already generalized early for TypedDefs
      if shouldGeneralizeEarly
        then do
          -- MODULE LEVEL: Already generalized, just update environment
          let (_, _, finalMark) = calculateMarks bodyState
          let polyEnv = Map.fromList [(name, var) | (name, Ann.At _ var) <- Map.toList locals]
          -- FIXED: Use bodyState's stateEnv (accumulated) instead of config's solveEnv (original)
          -- This ensures that module-level definitions accumulate across multiple top-level lets
          let finalEnv = Map.union (bodyState ^. stateEnv) polyEnv
          return $ bodyState
            & stateMark .~ finalMark
            & stateEnv .~ finalEnv
            & stateMonoEnv .~ Map.empty  -- No remaining mono vars at module level
        else if isOriginalDefer
          then do
          -- Now check which variables unified with OUTER scope (not current let)
          -- Use the PARENT rank (nextRank - 1) to detect unifications with truly outer scope
          -- IMPORTANT: Only check NEWLY ADDED variables at this level, not outer scope variables
          let parentRank = nextRank - 1
          -- Get the FINAL monoEnv from bodyState (includes all nested let additions)
          let finalMonoEnv = bodyState ^. stateMonoEnv
          -- Check variables at THIS level and DEEPER (rank >= parentRank)
          -- Exclude variables from OUTER scope (rank < parentRank)
          -- IMPORTANT: Also check locals being defined at this level!
          let dummyPos = Ann.Position 0 0
          -- FIXED: Only check variables that are NEW at this level or defined at this level
          -- Don't check variables inherited from outer scopes that happen to be in monoEnv
          varsFromMonoEnv <- forM (Map.toList finalMonoEnv) $ \(name, var) -> do
            -- Only include if this variable was added at THIS level (in newVarsThisLevel)
            if Set.member name newVarsThisLevel
              then do
                actualVar <- UF.repr var
                (Descriptor _ actualRank _ _) <- UF.get actualVar
                -- Include if at current level or deeper
                if actualRank >= parentRank
                  then return (Just (name, Ann.At (Ann.Region dummyPos dummyPos) var))
                  else return Nothing
              else return Nothing  -- Variable from outer scope, skip it
          let varsFromMonoEnvFiltered = [x | Just x <- varsFromMonoEnv]
          -- Add locals to the check (they are being defined at THIS level)
          let localsToCheck = [(name, locatedVar) | (name, locatedVar) <- Map.toList locals]
          let varsToCheckFiltered = varsFromMonoEnvFiltered <> localsToCheck

          -- Check against AMBIENT RIGIDS from OUTER levels only (rank < nextRank)
          -- Filter to exclude rigids from current level - only check against truly outer rigids
          let outerRigids = [(rank, var) | (rank, var) <- ambientRigids, rank < nextRank]
          monoToPolyVars <- foldM (checkAndGeneralizeWithParent nextRank parentRank outerRigids locals) [] varsToCheckFiltered

          -- Add ALL variables to environment:
          -- - Generalized variables (from monoToPolyVars) go to main env
          -- - Monomorphic variables stay in monoEnv but need to remain accessible
          let polyEnv = Map.fromList [(name, var) | (name, var) <- monoToPolyVars]
          let finalEnv = Map.union (config ^. solveEnv) polyEnv

          -- Keep only mono variables from OUTER scopes (rank < nextRank), not locals
          -- Locals either got generalized (in polyEnv) or are scoped to this level only
          remainingMonoVars <- foldM (\acc (name, var) ->
            if Map.member name polyEnv
              then return acc  -- Already generalized
              else do
                actualVar <- UF.repr var
                (Descriptor _ actualRank _ _) <- UF.get actualVar
                -- Only keep if from outer scope (rank < parentRank)
                if actualRank < parentRank
                  then return (Map.insert name var acc)
                  else return acc  -- Local variable, scoped to this level
            ) Map.empty [(name, var) | (name, Ann.At _ var) <- varsToCheckFiltered]

          -- Reset THIS function's rigids to rank 0 (they are the function's type parameters)
          let (_, _, finalMark) = calculateMarks bodyState
          traverse_ resetRigidToNoRank rigids
          traverse_ isGeneric rigids

          return $ bodyState
            & stateMark .~ finalMark
            & stateEnv .~ finalEnv
            & stateMonoEnv .~ remainingMonoVars  -- Keep mono variables for outer scopes
        else do
          -- Nested let: add locals to monoEnv in the returned state
          -- These variables stay monomorphic (not added to main env)

          -- The monoEnv is lost when we return State, so we need to keep track of it differently
          -- For now, add non-generalized locals back to state's monoEnv tracking
          -- Actually, the parent's monoEnv already has these from bodyConfig, so just return
          return bodyState

    else do
      -- STANDARD PATH: No ambient rigids, use normal generalization
      let (youngMark, visitMark, finalMark) = calculateMarks solvedState
      let ambientRigidVars = fmap snd ambientRigids
      performGeneralization youngMark visitMark nextRank nextPools ambientRigidVars
      -- Reset THIS function's rigids to rank 0 (they are the function's type parameters)
      traverse_ resetRigidToNoRank rigids
      traverse_ isGeneric rigids
      let newEnv = Map.union (config ^. solveEnv) (Map.map Ann.toValue locals)
      let tempState = solvedState & stateMark .~ finalMark
      let finalConfig = config & solveEnv .~ newEnv & solveState .~ tempState & solveRank .~ (config ^. solveRank)
      solve finalConfig subCon

-- Extract all type variables from a Type.
-- Uses traverse + concat for O(n) total instead of foldM with (<>) which is O(n^2).
extractTypeVars :: Type -> IO [Variable]
extractTypeVars tipe = case tipe of
  VarN v -> return [v]
  AppN _ _ args -> concat <$> traverse extractTypeVars args
  FunN arg result -> liftM2 (<>) (extractTypeVars arg) (extractTypeVars result)
  AliasN _ _ args realType -> do
    argVars <- concat <$> traverse (extractTypeVars . snd) args
    realVars <- extractTypeVars realType
    return (argVars <> realVars)
  RecordN fields ext -> do
    fieldVars <- concat <$> traverse extractTypeVars (Map.elems fields)
    extVars <- extractTypeVars ext
    return (fieldVars <> extVars)
  EmptyRecordN -> return []
  UnitN -> return []
  TupleN a b maybeC -> do
    aVars <- extractTypeVars a
    bVars <- extractTypeVars b
    cVars <- maybe (return []) extractTypeVars maybeC
    return (aVars <> bVars <> cVars)
  PlaceHolder _ -> return []

-- Extract all variables from a FlatType (non-recursive, returns immediate child variables)
extractVarsFromFlatType :: FlatType -> [Variable]
extractVarsFromFlatType flatType = case flatType of
  App1 _ _ vars -> vars
  Fun1 arg result -> [arg, result]
  EmptyRecord1 -> []
  Record1 fields ext -> Map.elems fields <> [ext]
  Unit1 -> []
  Tuple1 a b maybeC -> [a, b] <> maybe [] pure maybeC

-- Extract all variables from a variable's unified Type by following union-find links RECURSIVELY.
-- Uses traverse + concat for O(n) total instead of foldM with (<>) which is O(n^2).
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

-- Check if a monomorphic variable can be generalized
-- If rank <= parentRank, it unified with OUTER scope (not just current let) - keep monomorphic
-- If any nested variable is equivalent to an outer rigid (rank < parentRank for locals) - keep monomorphic
-- If rank == youngRank, it's still local to current let - generalize it
-- If parentRank < rank < youngRank, it unified within current let only - generalize it
-- IMPORTANT: For variables in locals (being defined at this level), only check rigids < parentRank
--            to avoid false positives from peer module-level functions
checkAndGeneralizeWithParent :: Int -> Int -> [(Int, Variable)] -> Map Name.Name (Ann.Located Variable) -> [(Name.Name, Variable)] -> (Name.Name, Ann.Located Variable) -> IO [(Name.Name, Variable)]
checkAndGeneralizeWithParent youngRank parentRank outerRigids locals acc (name, Ann.At _ var) = do
  (Descriptor _ _rank _ _) <- UF.get var
  -- Follow links to get the representative variable
  actualVar <- UF.repr var
  (Descriptor _ actualRank _ _) <- UF.get actualVar

  -- Extract ALL variables from the unified type structure
  allVarsInType <- extractVarsFromUnifiedType var

  -- Check if ANY of the nested variables are equivalent to TRULY OUTER rigids
  -- For variables in locals (being defined at this level), only check rigids < parentRank
  -- This prevents false positives from peer module-level functions at the same conceptual level
  -- For nested variables (not in locals), check rigids < actualRank as before
  let isLocal = Map.member name locals
  let rigidRankThreshold = if isLocal then parentRank else actualRank
  let strictlyOuterRigids = [(r, v) | (r, v) <- outerRigids, r < rigidRankThreshold]
  let rigidsToCheck = fmap snd strictlyOuterRigids
  equivalences <- forM allVarsInType $ \typeVar -> do
    results <- forM rigidsToCheck $ \rigidVar -> do
      UF.equivalent typeVar rigidVar
    return (any id results)
  let isUnifiedWithRigid = any id equivalences

  let hasOuterRigids = not (null outerRigids)
  -- Module level: variable is being defined as a local (has type annotation at module level)
  -- This is more accurate than checking rank, since module-level functions can have various ranks due to dependency order
  let isModuleLevel = isLocal

  let finalRank = actualRank
  if finalRank == noRank
    then do
      -- Already generalized by nested let - this is OK, it's polymorphic
      return ((name, var) : acc)
    else if isUnifiedWithRigid && not isModuleLevel
      then do
        -- Unified with an OUTER rigid in NESTED context - stays monomorphic!
        -- But at module level, always generalize regardless of rigid unification
        return acc
    else if finalRank <= parentRank
      then do
        -- Unified with OUTER scope (parent or higher) - stays monomorphic
        return acc
    else if hasOuterRigids && finalRank /= youngRank && not isModuleLevel
      then do
        -- When outer rigids present in NESTED context, be VERY conservative: only generalize variables exactly at youngRank
        -- But at module level, generalize regardless of rank mismatch
        return acc
      else do
        -- rank > parentRank and (no outer rigids OR rank == youngRank OR module level)
        -- Recursively generalize to ensure ALL nested variables are at rank 0
        generalizeRecursively actualVar
        return ((name, var) : acc)

-- Helper for checking if any element satisfies predicate
anyM :: (Monad m) => (a -> m Bool) -> [a] -> m Bool
anyM _ [] = return False
anyM p (x:xs) = do
  result <- p x
  if result
    then return True
    else anyM p xs

calculateMarks :: State -> (Mark, Mark, Mark)
calculateMarks state =
  let youngMark = state ^. stateMark
      visitMark = nextMark youngMark
      finalMark = nextMark visitMark
  in (youngMark, visitMark, finalMark)

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
            foldM go (var : visited) termVars
          _ ->
            return (var : visited)
  foldM go [] ambientRigids
  where
    getTermVariables term = case term of
      App1 _ _ args -> return args
      Fun1 arg result -> return [arg, result]
      EmptyRecord1 -> return []
      Record1 fields ext -> return (Map.elems fields <> [ext])
      Unit1 -> return []
      Tuple1 a b maybeC -> return ([a, b] <> maybe [] pure maybeC)

performGeneralization :: Mark -> Mark -> Int -> Pools -> [Variable] -> IO ()
performGeneralization youngMark visitMark nextRank nextPools ambientRigids = do
  ambientVars <- collectAmbientVariables ambientRigids
  generalize youngMark visitMark nextRank nextPools ambientVars
  currentPools <- readIORef nextPools
  MVector.write currentPools nextRank []

addError :: State -> Error.Error -> State
addError state err = state & stateErrors %~ (err :)

-- OCCURS CHECK

occurs :: State -> (Name.Name, Ann.Located Variable) -> IO State
occurs state (name, Ann.At region variable) =
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

generalize :: Mark -> Mark -> Int -> Pools -> [Variable] -> IO ()
generalize youngMark visitMark youngRank pools ambientVars = do
  currentPools <- readIORef pools
  youngVars <- MVector.read currentPools youngRank
  rankTable <- poolToRankTable youngMark youngRank youngVars
  adjustAllRanks youngMark visitMark rankTable
  registerOldPoolVariables pools rankTable
  registerOrGeneralizeYoungVars pools youngRank rankTable ambientVars

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
  ensurePoolSize rank pools
  currentPools <- readIORef pools
  MVector.modify currentPools (var :) rank

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

poolToRankTable :: Mark -> Int -> [Variable] -> IO (Vector.Vector [Variable])
poolToRankTable youngMark youngRank youngInhabitants =
  do
    -- First pass: find the maximum rank to ensure table is large enough
    maxRank <- foldM (\acc var -> do
      (Descriptor _ rank _ _) <- UF.get var
      return (max acc rank)) youngRank youngInhabitants

    mutableTable <- MVector.replicate (maxRank + 1) []

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
            -- minRank equals groupRank when a variable was already at or below the
            -- group's rank, meaning it doesn't need further adjustment.
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
introduce rank pools variables = do
  ensurePoolSize rank pools
  currentPools <- readIORef pools
  MVector.modify currentPools (variables ++) rank
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
    PlaceHolder name ->
      maybe
        (InternalError.report "Type.Solve.typeToVar" (Text.pack ("Unknown placeholder: " <> show name)) "Alias dictionary missing expected type variable.")
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

-- | Ensure pools vector is large enough to accommodate the given rank
-- FIXED: Properly grow pools vector when accessing indices beyond current size
ensurePoolSize :: Int -> Pools -> IO ()
ensurePoolSize rank poolsRef = do
  currentPools <- readIORef poolsRef
  let currentSize = MVector.length currentPools
  if rank < currentSize
    then return ()
    else do
      let newSize = rank + 1
      newPools <- MVector.grow currentPools (newSize - currentSize)
      -- Initialize new slots with empty lists
      for_ [currentSize .. newSize - 1] $ \i ->
        MVector.write newPools i []
      writeIORef poolsRef newPools

register :: Int -> Pools -> Content -> IO Variable
register rank pools content = do
  var <- UF.fresh (Descriptor content rank noMark Nothing)
  ensurePoolSize rank pools
  currentPools <- readIORef pools
  MVector.modify currentPools (var :) rank
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
        (InternalError.report "Type.Solve.srcTypeToVar" (Text.pack ("Unknown type variable: " <> show name)) "Flex vars dictionary missing expected variable.")
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
        (InternalError.report "Type.Solve.convertSrcRecordType" (Text.pack ("Unknown record extension: " <> show ext)) "Flex vars dictionary missing record extension variable.")
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

-- COPY

makeCopy :: Int -> Pools -> [(Int, Variable)] -> Variable -> IO Variable
makeCopy rank pools ambientRigids var =
  do
    copy <- makeCopyHelp rank pools ambientRigids var
    restore var
    return copy

makeCopyHelp :: Int -> Pools -> [(Int, Variable)] -> Variable -> IO Variable
makeCopyHelp maxRank pools ambientRigids variable = do
  (Descriptor content rank _ maybeCopy) <- UF.get variable

  -- Check for Error content BEFORE checking hasCopy
  -- Error variables should NEVER be instantiated, regardless of their copy field
  case content of
    Error ->
      return variable  -- Return Error variables unchanged
    _ -> case maybeCopy of
      Just copy ->
        return copy
      Nothing -> handleNoCopy maxRank pools ambientRigids variable content rank

showContentType :: Content -> String
showContentType (FlexVar _) = "FlexVar"
showContentType (FlexSuper _ _) = "FlexSuper"
showContentType (RigidVar _) = "RigidVar"
showContentType (RigidSuper _ _) = "RigidSuper"
showContentType (Structure _) = "Structure"
showContentType (Alias _ _ _ _) = "Alias"
showContentType Error = "Error"

showSuperType :: SuperType -> String
showSuperType Number = "Number"
showSuperType Comparable = "Comparable"
showSuperType Appendable = "Appendable"
showSuperType CompAppend = "CompAppend"

handleNoCopy :: Int -> Pools -> [(Int, Variable)] -> Variable -> Content -> Int -> IO Variable
handleNoCopy maxRank pools ambientRigids variable content rank
  | rank /= noRank =
      -- Check if this is a rigid that might have a higher-rank version in ambient rigids
      case content of
        RigidVar name -> do
          checkForHigherRankRigid name variable rank ambientRigids
        RigidSuper super name -> checkForHigherRankRigidSuper name super variable rank ambientRigids
        _ -> return variable
  | otherwise =
      createAndLinkCopy maxRank pools ambientRigids variable content rank

-- | Check if there's a higher-rank version of a RigidVar in ambient rigids
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

-- | Check if there's a higher-rank version of a RigidSuper in ambient rigids
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

-- | Copy a RigidVar by converting it to FlexVar, but check if it should unify with ambient rigids
-- When instantiating a polymorphic function, rigid type variables become flexible
-- But if there are ambient rigids with the same name, the fresh flex should unify with them
copyRigidVarContent :: [(Int, Variable)] -> Variable -> (Content -> Descriptor) -> Name.Name -> Int -> IO Variable
copyRigidVarContent ambientRigids copy makeDescriptor name originalRank = do
  -- CRITICAL: Only check ambient rigids if originalRank != 0
  -- Generalized variables (rank 0) should ALWAYS become FlexVars, never unify with ambient rigids
  if originalRank == noRank
    then do
      -- Generalized rigid: convert to FlexVar without checking ambient rigids
      UF.set copy . makeDescriptor $ FlexVar (Just name)
      return copy
    else do
      -- Non-generalized rigid: check for matching ambient rigid
      matchingRigid <- findMatchingRigid name ambientRigids
      case matchingRigid of
        Just rigidVar -> do
          -- Unify the copy with the ambient rigid
          -- The copy will now point to the same variable as the rigid
          UF.union copy rigidVar (makeDescriptor (RigidVar name))
          return copy
        Nothing -> do
          -- No matching rigid, create a regular FlexVar
          UF.set copy . makeDescriptor $ FlexVar (Just name)
          return copy

-- | Find an ambient rigid variable with matching name
-- Prefers the HIGHEST rank (most local scope) when multiple matches exist
findMatchingRigid :: Name.Name -> [(Int, Variable)] -> IO (Maybe Variable)
findMatchingRigid targetName rigids = do
  -- Collect all matching rigids with their ranks
  matches <- collectMatches rigids
  case matches of
    [] -> return Nothing
    _ -> do
      -- Select the highest rank (most local)
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

copyRigidSuperContent :: [(Int, Variable)] -> Variable -> (Content -> Descriptor) -> SuperType -> Name.Name -> Int -> IO Variable
copyRigidSuperContent ambientRigids copy makeDescriptor super name originalRank = do
  -- CRITICAL: Only check ambient rigids if originalRank != 0
  -- Generalized variables (rank 0) should ALWAYS become FlexSupers, never unify with ambient rigids
  if originalRank == noRank
    then do
      -- Generalized rigid super: convert to FlexSuper without checking ambient rigids
      UF.set copy . makeDescriptor $ FlexSuper super (Just name)
      return copy
    else do
      -- Non-generalized rigid super: check for matching ambient rigid
      matchingRigid <- findMatchingRigidSuper name super ambientRigids
      case matchingRigid of
        Just rigidVar -> do
          -- Unify the copy with the ambient rigid
          UF.union copy rigidVar (makeDescriptor (RigidSuper super name))
          return copy
        Nothing -> do
          -- No matching rigid, create a regular FlexSuper
          UF.set copy . makeDescriptor $ FlexSuper super (Just name)
          return copy

-- | Find an ambient rigid super variable with matching name and compatible supertype
-- | Find a matching RigidSuper in ambient rigids
-- Prefers the HIGHEST rank (most local scope) when multiple matches exist
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
          -- RigidVar can match any supertype
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
