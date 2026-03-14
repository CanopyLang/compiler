{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Rank2Types #-}

-- | Type.Unify — Structural type unification for the Hindley-Milner type checker.
--
-- Implements the classic union-find–based unification algorithm extended
-- with:
--
-- * Flexible and rigid type variables (for let-polymorphism and type
--   annotations).
-- * Super-type constraints (@number@, @comparable@, @appendable@,
--   @compappend@) that restrict which concrete types a variable may
--   unify with.
-- * Opaque alias bounds: a 'BoundsMap' records which nominal alias types
--   satisfy which super-type constraints, enabling bounded opaque types
--   to be used as 'Dict' keys or 'Set' members.
--
-- The internal 'Unify' monad is CPS over @IO@ so that the success and
-- failure continuations can be differentiated without intermediate
-- allocations.
--
-- @since 0.19.1
module Type.Unify
  ( Answer (..),
    BoundsMap,
    unify,
  )
where

import qualified Canopy.ModuleName as ModuleName
import Data.Foldable (forM_)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Type.Error as Error
import qualified Type.Occurs as Occurs
import Type.Type as Type
import qualified Type.UnionFind as UF

-- | Map from qualified type names to their declared supertype bounds.
--
-- Passed through the unification system so that opaque bounded alias types
-- (e.g. @UserId@ declared @comparable@) can be checked against super type
-- constraints without any global mutable state.
type BoundsMap = Map (ModuleName.Canonical, Name.Name) SuperType

-- UNIFY

-- | Result of a unification attempt.
--
-- 'Ok' carries any freshly-created variables that may need to be added
-- to the current pool for generalisation.  'Err' additionally provides
-- the two type error terms for error reporting.
--
-- @since 0.19.1
data Answer
  = Ok [Variable]
  | Err [Variable] Error.Type Error.Type

-- | Unify two type variables, using the provided bounds map to resolve
-- opaque alias super type constraints.
unify :: BoundsMap -> Variable -> Variable -> IO Answer
unify bounds v1 v2 =
  case guardedUnify bounds v1 v2 of
    Unify k ->
      k [] onSuccess $ \vars () ->
        do
          t1 <- Type.toErrorType v1
          t2 <- Type.toErrorType v2
          -- CRITICAL FIX: DO NOT mutate variables to Error!
          -- The error types have already been extracted above.
          -- Mutating variables to Error/rank 0 breaks subsequent type checking
          -- when the same variable is used again (e.g., dict parameter used twice).
          -- Previously: UF.union v1 v2 errorDescriptor
          return (Err vars t1 t2)

onSuccess :: [Variable] -> () -> IO Answer
onSuccess vars () =
  return (Ok vars)

-- CPS UNIFIER

newtype Unify a
  = Unify
      ( forall r.
        [Variable] ->
        ([Variable] -> a -> IO r) ->
        ([Variable] -> () -> IO r) ->
        IO r
      )

instance Functor Unify where
  fmap func (Unify kv) =
    Unify $ \vars ok err ->
      let ok1 vars1 value =
            ok vars1 (func value)
       in kv vars ok1 err

instance Applicative Unify where
  pure a =
    Unify $ \vars ok _ ->
      ok vars a

  (<*>) (Unify kf) (Unify kv) =
    Unify $ \vars ok err ->
      let ok1 vars1 func =
            let ok2 vars2 value =
                  ok vars2 (func value)
             in kv vars1 ok2 err
       in kf vars ok1 err

instance Monad Unify where
  (>>=) (Unify ka) callback =
    Unify $ \vars ok err ->
      let ok1 vars1 a =
            case callback a of
              Unify kb -> kb vars1 ok err
       in ka vars ok1 err

register :: IO Variable -> Unify Variable
register mkVar =
  Unify $ \vars ok _ ->
    do
      var <- mkVar
      ok (var : vars) var

mismatch :: Unify a
mismatch =
  Unify $ \vars _ err ->
    err vars ()

-- UNIFICATION HELPERS

data Context = Context
  { _first :: Variable,
    _firstDesc :: Descriptor,
    _second :: Variable,
    _secondDesc :: Descriptor,
    _contextBounds :: !BoundsMap
  }

reorient :: Context -> Context
reorient (Context var1 desc1 var2 desc2 bounds) =
  Context var2 desc2 var1 desc1 bounds

-- MERGE

merge :: Context -> Content -> Unify ()
merge (Context var1 (Descriptor _ rank1 _ _) var2 (Descriptor _ rank2 _ _) _) content =
  Unify $ \vars ok _ ->
    UF.union var1 var2 (Descriptor content (min rank1 rank2) noMark Nothing) >>= ok vars

fresh :: Context -> Content -> Unify Variable
fresh (Context _ (Descriptor _ rank1 _ _) _ (Descriptor _ rank2 _ _) _) content =
  register . UF.fresh $ Descriptor content (min rank1 rank2) noMark Nothing

-- ACTUALLY UNIFY THINGS

guardedUnify :: BoundsMap -> Variable -> Variable -> Unify ()
guardedUnify bounds left right =
  Unify $ \vars ok err ->
    do
      -- It might be possible to actually just do == instead of >. This is
      -- because it might be the case that if a variable is not infinite
      -- right now, it won't ever be infinite during this particular unify
      -- call. But I haven't really thought that through enough to be
      -- confident putting it in.
      --
      -- Note that we ultimately decided against doing a recursion depth check
      -- as detailed in
      -- https://github.com/Zokka-Dev/zokka-compiler/pull/20#issuecomment-2234089482
      -- This is because we didn't want to have an unpredictable performance
      -- profile (i.e. mysterious immediate slowdown).
      -- If we see slowdown we want to know soon so that we can think about a
      -- better fix. So far benchmarks seem to show that this causes minimal slowdown.
      occursLeft <- Occurs.occurs left
      occursRight <- Occurs.occurs right
      equivalent <- UF.equivalent left right
      if occursLeft || occursRight
        then err vars ()
        else
          if equivalent
            then ok vars ()
            else do
              leftDesc <- UF.get left
              rightDesc <- UF.get right
              case actuallyUnify (Context left leftDesc right rightDesc bounds) of
                Unify k ->
                  k vars ok err

subUnify :: BoundsMap -> Variable -> Variable -> Unify ()
subUnify = guardedUnify

actuallyUnify :: Context -> Unify ()
actuallyUnify context@(Context _ (Descriptor firstContent _ _ _) _ (Descriptor secondContent _ _ _) _) =
  case firstContent of
    FlexVar _ ->
      unifyFlex context firstContent secondContent
    FlexSuper super _ ->
      unifyFlexSuper context super firstContent secondContent
    RigidVar _ ->
      unifyRigid context Nothing firstContent secondContent
    RigidSuper super _ ->
      unifyRigid context (Just super) firstContent secondContent
    Alias home name args realVar ->
      unifyAlias context home name args realVar secondContent
    Structure flatType ->
      unifyStructure context flatType firstContent secondContent
    Error ->
      -- If there was an error, just pretend it is okay. This lets us avoid
      -- "cascading" errors where one problem manifests as multiple message.
      merge context Error

-- UNIFY FLEXIBLE VARIABLES

unifyFlex :: Context -> Content -> Content -> Unify ()
unifyFlex context content otherContent =
  case otherContent of
    Error ->
      merge context Error
    FlexVar maybeName ->
      merge context (maybe content (const otherContent) maybeName)
    FlexSuper _ _ ->
      merge context otherContent
    RigidVar _ ->
      merge context otherContent
    RigidSuper _ _ ->
      merge context otherContent
    Alias {} ->
      merge context otherContent
    Structure _ ->
      merge context otherContent

-- UNIFY RIGID VARIABLES

unifyRigid :: Context -> Maybe SuperType -> Content -> Content -> Unify ()
unifyRigid context maybeSuper content otherContent =
  case otherContent of
    FlexVar _ ->
      merge context content
    FlexSuper otherSuper _ ->
      maybe mismatch (mergeIfCompatible context content otherSuper) maybeSuper
    RigidVar _ ->
      -- Rigid variables only unify with themselves (same union-find node).
      -- Two distinct rigid vars with the same name from different CLet scopes
      -- must NOT unify -- doing so violates Hindley-Milner parametricity.
      -- Within a single CLet scope, all occurrences of the same rigid name
      -- share the same physical node (via Map.traverseWithKey in
      -- constrainAnnotatedDef), so identity-based unification is correct.
      mismatch
    RigidSuper _ _ ->
      mismatch
    Alias {} ->
      mismatch
    Structure flatType ->
      maybe mismatch (unifyStructureRigidSuper (reorient context) flatType) maybeSuper
    Error ->
      merge context Error

-- | Merge content if the rigid super type is compatible with the other super type.
mergeIfCompatible :: Context -> Content -> SuperType -> SuperType -> Unify ()
mergeIfCompatible context content otherSuper super
  | combineRigidSupers super otherSuper = merge context content
  | otherwise = mismatch

-- UNIFY SUPER VARIABLES

unifyFlexSuper :: Context -> SuperType -> Content -> Content -> Unify ()
unifyFlexSuper context super content otherContent =
  case otherContent of
    Structure flatType ->
      unifyFlexSuperStructure context super flatType
    RigidVar _ ->
      mismatch
    RigidSuper otherSuper _ ->
      if combineRigidSupers otherSuper super
        then merge context otherContent
        else mismatch
    FlexVar _ ->
      merge context content
    FlexSuper otherSuper _ ->
      unifyFlexSupers context content otherContent super otherSuper
    Alias _ _ _ realVar ->
      subUnify (_contextBounds context) (_first context) realVar
    Error ->
      merge context Error

-- | Unify two flexible super type variables.
--
-- Resolves the compatibility between two super type constraints,
-- choosing the most specific super type that satisfies both.
-- For example, Number + Comparable -> Number (more specific).
--
-- @since 0.19.2
unifyFlexSupers :: Context -> Content -> Content -> SuperType -> SuperType -> Unify ()
unifyFlexSupers context content otherContent super otherSuper =
  case flexSuperResult super otherSuper of
    FlexFirst -> merge context content
    FlexSecond -> merge context otherContent
    FlexCompAppend -> merge context (Type.unnamedFlexSuper CompAppend)
    FlexMismatch -> mismatch

-- | Outcome of combining two flex super types.
data FlexSuperResult
  = FlexFirst
  | FlexSecond
  | FlexCompAppend
  | FlexMismatch

-- | Determine how to combine two flexible super types.
--
-- Returns which content to keep or whether they are incompatible.
flexSuperResult :: SuperType -> SuperType -> FlexSuperResult
flexSuperResult Number Number = FlexFirst
flexSuperResult Number Comparable = FlexFirst
flexSuperResult Number Appendable = FlexMismatch
flexSuperResult Number CompAppend = FlexMismatch
flexSuperResult Comparable Comparable = FlexSecond
flexSuperResult Comparable Number = FlexSecond
flexSuperResult Comparable Appendable = FlexCompAppend
flexSuperResult Comparable CompAppend = FlexSecond
flexSuperResult Appendable Appendable = FlexSecond
flexSuperResult Appendable Comparable = FlexCompAppend
flexSuperResult Appendable CompAppend = FlexSecond
flexSuperResult Appendable Number = FlexMismatch
flexSuperResult CompAppend Comparable = FlexFirst
flexSuperResult CompAppend Appendable = FlexFirst
flexSuperResult CompAppend CompAppend = FlexFirst
flexSuperResult CompAppend Number = FlexMismatch

combineRigidSupers :: SuperType -> SuperType -> Bool
combineRigidSupers rigid flex =
  rigid == flex
    || (rigid == Number && flex == Comparable)
    || (rigid == CompAppend && (flex == Comparable || flex == Appendable))

atomMatchesSuper :: SuperType -> ModuleName.Canonical -> Name.Name -> Bool
atomMatchesSuper super home name =
  case super of
    Number ->
      isNumber home name
    Comparable ->
      isNumber home name
        || Error.isString home name
        || Error.isChar home name
    Appendable ->
      Error.isString home name
    CompAppend ->
      Error.isString home name

isNumber :: ModuleName.Canonical -> Name.Name -> Bool
isNumber home name =
  home == ModuleName.basics
    && (name == Name.int || name == Name.float)

unifyFlexSuperStructure :: Context -> SuperType -> FlatType -> Unify ()
unifyFlexSuperStructure context super flatType =
  case flatType of
    App1 home name [] ->
      if atomMatchesSuper super home name
        then merge context (Structure flatType)
        else checkBoundedAlias context super flatType home name
    App1 home name [variable] | home == ModuleName.list && name == Name.list ->
      unifyListWithSuper context flatType super variable
    Tuple1 a b maybeC ->
      unifyTupleWithSuper context flatType super a b maybeC
    _ ->
      mismatch

-- | Check if a type is an opaque alias with a bound satisfying the super constraint.
--
-- Reads the bounds directly from the context rather than a global IORef,
-- making this function pure within the Unify CPS monad.
checkBoundedAlias :: Context -> SuperType -> FlatType -> ModuleName.Canonical -> Name.Name -> Unify ()
checkBoundedAlias context super flatType home name =
  case Map.lookup (home, name) (_contextBounds context) of
    Just bound | boundSatisfiesSuper bound super ->
      merge context (Structure flatType)
    _ ->
      mismatch

-- | Check if a declared bound satisfies the required super type constraint.
--
-- A bound satisfies a constraint when it is equal to or more specific than
-- the constraint. For example, @Number@ satisfies @Comparable@ because all
-- numbers are comparable.
boundSatisfiesSuper :: SuperType -> SuperType -> Bool
boundSatisfiesSuper bound required =
  bound == required
    || (bound == Number && required == Comparable)
    || (bound == CompAppend && (required == Comparable || required == Appendable))

-- | Unify a List type with a super type constraint.
--
-- Lists are Appendable and Comparable (if their element type is Comparable),
-- but not Number.
--
-- @since 0.19.2
unifyListWithSuper :: Context -> FlatType -> SuperType -> Variable -> Unify ()
unifyListWithSuper context flatType super variable =
  case super of
    Number ->
      mismatch
    Appendable ->
      merge context (Structure flatType)
    Comparable ->
      do
        comparableOccursCheck context
        unifyComparableRecursive (_contextBounds context) variable
        merge context (Structure flatType)
    CompAppend ->
      do
        comparableOccursCheck context
        unifyComparableRecursive (_contextBounds context) variable
        merge context (Structure flatType)

-- | Unify a Tuple type with a super type constraint.
--
-- Tuples are Comparable (if all elements are Comparable),
-- but not Number or Appendable.
--
-- @since 0.19.2
unifyTupleWithSuper :: Context -> FlatType -> SuperType -> Variable -> Variable -> Maybe Variable -> Unify ()
unifyTupleWithSuper context flatType super a b maybeC =
  case super of
    Number ->
      mismatch
    Appendable ->
      mismatch
    Comparable ->
      do
        comparableOccursCheck context
        unifyComparableRecursive (_contextBounds context) a
        unifyComparableRecursive (_contextBounds context) b
        forM_ maybeC (unifyComparableRecursive (_contextBounds context))
        merge context (Structure flatType)
    CompAppend ->
      mismatch

-- Occurs check for comparable types is needed to prevent infinite types.
-- Type classes with ordering constraints require this check.
comparableOccursCheck :: Context -> Unify ()
comparableOccursCheck (Context _ _ var _ _) =
  Unify $ \vars ok err ->
    do
      hasOccurred <- Occurs.occurs var
      if hasOccurred
        then err vars ()
        else ok vars ()

unifyComparableRecursive :: BoundsMap -> Variable -> Unify ()
unifyComparableRecursive bounds var =
  do
    compVar <- register $
      do
        (Descriptor _ rank _ _) <- UF.get var
        UF.fresh $ Descriptor (Type.unnamedFlexSuper Comparable) rank noMark Nothing
    guardedUnify bounds compVar var

-- UNIFY STRUCTURE WITH RIGID SUPER
--
-- When a concrete type (Structure) meets a rigid super type variable,
-- we need to check if the concrete type satisfies the super type constraint.
-- For example, Int should unify with a rigid "number" type variable.
unifyStructureRigidSuper :: Context -> FlatType -> SuperType -> Unify ()
unifyStructureRigidSuper context flatType super =
  case flatType of
    App1 home name [] ->
      if atomMatchesSuper super home name
        then merge context (Structure flatType)
        else checkBoundedAlias context super flatType home name
    App1 home name [variable] | home == ModuleName.list && name == Name.list ->
      unifyListWithSuper context flatType super variable
    Tuple1 a b maybeC ->
      unifyTupleWithSuper context flatType super a b maybeC
    _ ->
      mismatch

-- UNIFY ALIASES

unifyAlias :: Context -> ModuleName.Canonical -> Name.Name -> [(Name.Name, Variable)] -> Variable -> Content -> Unify ()
unifyAlias context home name args realVar otherContent =
  case otherContent of
    FlexVar _ ->
      merge context (Alias home name args realVar)
    FlexSuper _ _ ->
      subUnify (_contextBounds context) realVar (_second context)
    RigidVar _ ->
      subUnify (_contextBounds context) realVar (_second context)
    RigidSuper _ _ ->
      subUnify (_contextBounds context) realVar (_second context)
    Alias otherHome otherName otherArgs otherRealVar ->
      if name == otherName && home == otherHome
        then Unify $ \vars ok err ->
          let ok1 vars1 () =
                let (Unify k) = merge context otherContent
                 in k vars1 ok err
           in unifyAliasArgs vars context args otherArgs ok1 err
        else subUnify (_contextBounds context) realVar otherRealVar
    Structure _ ->
      subUnify (_contextBounds context) realVar (_second context)
    Error ->
      merge context Error

unifyAliasArgs :: [Variable] -> Context -> [(Name.Name, Variable)] -> [(Name.Name, Variable)] -> ([Variable] -> () -> IO r) -> ([Variable] -> () -> IO r) -> IO r
unifyAliasArgs vars _context [] [] ok _err = ok vars ()
unifyAliasArgs vars _context [] _ _ok err = err vars ()
unifyAliasArgs vars _context _ [] _ok err = err vars ()
unifyAliasArgs vars context ((_, arg1) : others1) ((_, arg2) : others2) ok err =
  unifyOneAliasArg vars context arg1 arg2 others1 others2 ok err

-- | Unify a single pair of alias arguments and continue with the rest.
--
-- @since 0.19.2
unifyOneAliasArg :: [Variable] -> Context -> Variable -> Variable -> [(Name.Name, Variable)] -> [(Name.Name, Variable)] -> ([Variable] -> () -> IO r) -> ([Variable] -> () -> IO r) -> IO r
unifyOneAliasArg vars context arg1 arg2 rest1 rest2 ok err =
  let (Unify k) = subUnify (_contextBounds context) arg1 arg2
   in k
        vars
        (\vs () -> unifyAliasArgs vs context rest1 rest2 ok err)
        (\vs () -> unifyAliasArgs vs context rest1 rest2 err err)

-- UNIFY STRUCTURES

unifyStructure :: Context -> FlatType -> Content -> Content -> Unify ()
unifyStructure context flatType content otherContent =
  case otherContent of
    FlexVar _ ->
      merge context content
    FlexSuper super _ ->
      unifyFlexSuperStructure (reorient context) super flatType
    RigidVar _ ->
      mismatch
    RigidSuper super _ ->
      unifyStructureRigidSuper context flatType super
    Alias _ _ _ realVar ->
      subUnify (_contextBounds context) (_first context) realVar
    Structure otherFlatType ->
      unifyFlatTypes context flatType otherFlatType otherContent
    Error ->
      merge context Error

-- | Unify two flat type structures, handling each structural pair.
--
-- @since 0.19.2
unifyFlatTypes :: Context -> FlatType -> FlatType -> Content -> Unify ()
unifyFlatTypes context flatType otherFlatType otherContent =
  case (flatType, otherFlatType) of
    (App1 home name args, App1 otherHome otherName otherArgs) | home == otherHome && name == otherName ->
      Unify $ \vars ok err ->
        let ok1 vars1 () =
              let (Unify k) = merge context otherContent
               in k vars1 ok err
         in unifyArgs vars context args otherArgs ok1 err
    (Fun1 arg1 res1, Fun1 arg2 res2) ->
      do
        subUnify (_contextBounds context) arg1 arg2
        subUnify (_contextBounds context) res1 res2
        merge context otherContent
    (EmptyRecord1, EmptyRecord1) ->
      merge context otherContent
    (Record1 fields ext, EmptyRecord1)
      | Map.null fields ->
        subUnify (_contextBounds context) ext (_second context)
    (EmptyRecord1, Record1 fields ext)
      | Map.null fields ->
        subUnify (_contextBounds context) (_first context) ext
    (Record1 fields1 ext1, Record1 fields2 ext2) ->
      unifyRecordFields context fields1 ext1 fields2 ext2
    (Tuple1 a b Nothing, Tuple1 x y Nothing) ->
      do
        subUnify (_contextBounds context) a x
        subUnify (_contextBounds context) b y
        merge context otherContent
    (Tuple1 a b (Just c), Tuple1 x y (Just z)) ->
      do
        subUnify (_contextBounds context) a x
        subUnify (_contextBounds context) b y
        subUnify (_contextBounds context) c z
        merge context otherContent
    (Unit1, Unit1) ->
      merge context otherContent
    _ ->
      mismatch

-- UNIFY ARGS

unifyArgs :: [Variable] -> Context -> [Variable] -> [Variable] -> ([Variable] -> () -> IO r) -> ([Variable] -> () -> IO r) -> IO r
unifyArgs vars _context [] [] ok _err = ok vars ()
unifyArgs vars _context [] _ _ok err = err vars ()
unifyArgs vars _context _ [] _ok err = err vars ()
unifyArgs vars context (arg1 : others1) (arg2 : others2) ok err =
  unifyOneArg vars context arg1 arg2 others1 others2 ok err

-- | Unify a single pair of arguments and continue with the rest.
--
-- @since 0.19.2
unifyOneArg :: [Variable] -> Context -> Variable -> Variable -> [Variable] -> [Variable] -> ([Variable] -> () -> IO r) -> ([Variable] -> () -> IO r) -> IO r
unifyOneArg vars context arg1 arg2 rest1 rest2 ok err =
  let (Unify k) = subUnify (_contextBounds context) arg1 arg2
   in k
        vars
        (\vs () -> unifyArgs vs context rest1 rest2 ok err)
        (\vs () -> unifyArgs vs context rest1 rest2 err err)

-- UNIFY RECORDS

-- | Gather record fields from both sides and unify the resulting structures.
--
-- This eliminates a nested case expression by wrapping the IO field-gathering
-- step and the CPS unification into a single helper.
--
-- @since 0.19.2
unifyRecordFields :: Context -> Map Name.Name Variable -> Variable -> Map Name.Name Variable -> Variable -> Unify ()
unifyRecordFields context fields1 ext1 fields2 ext2 =
  Unify $ \vars ok err ->
    do
      structure1 <- gatherFields fields1 ext1
      structure2 <- gatherFields fields2 ext2
      let (Unify k) = unifyRecord context structure1 structure2
      k vars ok err

unifyRecord :: Context -> RecordStructure -> RecordStructure -> Unify ()
unifyRecord context (RecordStructure fields1 ext1) (RecordStructure fields2 ext2) =
  let sharedFields = Map.intersectionWith (,) fields1 fields2
      uniqueFields1 = Map.difference fields1 fields2
      uniqueFields2 = Map.difference fields2 fields1
   in if Map.null uniqueFields1
        then
          if Map.null uniqueFields2
            then do
              subUnify (_contextBounds context) ext1 ext2
              unifySharedFields context sharedFields Map.empty ext1
            else do
              subRecord <- fresh context (Structure (Record1 uniqueFields2 ext2))
              subUnify (_contextBounds context) ext1 subRecord
              unifySharedFields context sharedFields Map.empty subRecord
        else
          if Map.null uniqueFields2
            then do
              subRecord <- fresh context (Structure (Record1 uniqueFields1 ext1))
              subUnify (_contextBounds context) subRecord ext2
              unifySharedFields context sharedFields Map.empty subRecord
            else do
              let otherFields = Map.union uniqueFields1 uniqueFields2
              ext <- fresh context Type.unnamedFlexVar
              sub1 <- fresh context (Structure (Record1 uniqueFields1 ext))
              sub2 <- fresh context (Structure (Record1 uniqueFields2 ext))
              subUnify (_contextBounds context) ext1 sub2
              subUnify (_contextBounds context) sub1 ext2
              unifySharedFields context sharedFields otherFields ext

unifySharedFields :: Context -> Map Name.Name (Variable, Variable) -> Map Name.Name Variable -> Variable -> Unify ()
unifySharedFields context sharedFields otherFields ext =
  do
    matchingFields <- Map.traverseMaybeWithKey (unifyField (_contextBounds context)) sharedFields
    if Map.size sharedFields == Map.size matchingFields
      then merge context (Structure (Record1 (Map.union matchingFields otherFields) ext))
      else mismatch

unifyField :: BoundsMap -> Name.Name -> (Variable, Variable) -> Unify (Maybe Variable)
unifyField bounds _ (actual, expected) =
  Unify $ \vars ok _ ->
    case subUnify bounds actual expected of
      Unify k ->
        k
          vars
          (\vs () -> ok vs (Just actual))
          (\vs () -> ok vs Nothing)

-- GATHER RECORD STRUCTURE

data RecordStructure = RecordStructure
  { _fields :: Map Name.Name Variable,
    _extension :: Variable
  }

gatherFields :: Map Name.Name Variable -> Variable -> IO RecordStructure
gatherFields fields variable =
  do
    (Descriptor content _ _ _) <- UF.get variable
    case content of
      Structure (Record1 subFields subExt) ->
        gatherFields (Map.union fields subFields) subExt
      Alias _ _ _ var ->
        -- Alias info is discarded here since record unification only needs
        -- the underlying structure. Alias names are preserved elsewhere.
        gatherFields fields var
      _ ->
        return (RecordStructure fields variable)
