{-# LANGUAGE OverloadedStrings #-}

module Canonicalize.Environment.Local
  ( add,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified AST.Utils.Type as TypeUtils
import qualified Canonicalize.Environment as Env
import qualified Canonicalize.Environment.Dups as Dups
import qualified Canonicalize.Type as Type
import qualified Canopy.ModuleName as ModuleName
import Control.Monad (foldM)
import Data.Foldable (traverse_)
import qualified Data.Graph as Graph
import qualified Canopy.Data.Index as Index
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified Type.Variance as Variance

-- RESULT

type Result i w a =
  Result.Result i w Error.Error a

type Unions = Map.Map Name.Name Can.Union

type Aliases = Map.Map Name.Name Can.Alias

add :: Src.Module -> Env.Env -> Result i w (Env.Env, Unions, Aliases)
add module_ env =
  (addTypes module_ env >>= addVars module_) >>= addCtors module_

-- ADD VARS

addVars :: Src.Module -> Env.Env -> Result i w Env.Env
addVars module_ (Env.Env home vs ts cs bs qvs qts qcs) =
  do
    topLevelVars <- collectVars module_
    let vs2 = Map.union topLevelVars vs
    Result.ok $ Env.Env home vs2 ts cs bs qvs qts qcs

collectVars :: Src.Module -> Result i w (Map.Map Name.Name Env.Var)
collectVars (Src.Module _ _ _ _ _foreignImports values unions aliases _ effects _) =
  let addDecl dict (Ann.At _ (Src.Value (Ann.At region name) _ _ _ _)) =
        Dups.insert name region (Env.TopLevel region) dict
      derivedDups = collectDerivedNames unions aliases
   in Dups.detect Error.DuplicateDecl $
        Dups.union derivedDups (List.foldl' addDecl (toEffectDups effects) values)

-- | Collect derived function names from union and alias type declarations.
--
-- For each type with @deriving@ clauses, generates the corresponding
-- function names and registers them as top-level variables.
--
-- @since 0.20.0
collectDerivedNames :: [Ann.Located Src.Union] -> [Ann.Located Src.Alias] -> Dups.Dict Env.Var
collectDerivedNames unions aliases =
  let unionDups = List.foldl' collectUnionDerived Dups.none unions
      aliasDups = List.foldl' collectAliasDerived Dups.none aliases
   in Dups.union unionDups aliasDups

collectUnionDerived :: Dups.Dict Env.Var -> Ann.Located Src.Union -> Dups.Dict Env.Var
collectUnionDerived dups (Ann.At _ (Src.Union (Ann.At region name) _ _ _ clauses)) =
  List.foldl' (addDerivedName region name) dups clauses

collectAliasDerived :: Dups.Dict Env.Var -> Ann.Located Src.Alias -> Dups.Dict Env.Var
collectAliasDerived dups (Ann.At _ (Src.Alias (Ann.At region name) _ _ _ _ clauses)) =
  List.foldl' (addDerivedName region name) dups clauses

addDerivedName :: Ann.Region -> Name.Name -> Dups.Dict Env.Var -> Src.DerivingClause -> Dups.Dict Env.Var
addDerivedName region typeName dups clause =
  let nameChars = Name.toChars typeName
   in case clause of
        Src.DeriveOrd ->
          dups
        Src.DeriveEncode _ ->
          Dups.insert (Name.fromChars ("encode" ++ nameChars)) region (Env.TopLevel region) dups
        Src.DeriveDecode _ ->
          Dups.insert (Name.fromChars (lowerFirst nameChars ++ "Decoder")) region (Env.TopLevel region) dups
        Src.DeriveEnum ->
          Dups.insert (Name.fromChars ("all" ++ nameChars)) region (Env.TopLevel region) dups

lowerFirst :: String -> String
lowerFirst [] = []
lowerFirst (c : cs) = toLower c : cs
  where
    toLower ch
      | ch >= 'A' && ch <= 'Z' = toEnum (fromEnum ch + 32)
      | otherwise = ch

toEffectDups :: Src.Effects -> Dups.Dict Env.Var
toEffectDups effects =
  case effects of
    Src.NoEffects ->
      Dups.none
    Src.Ports ports ->
      let addPort dict (Src.Port (Ann.At region name) _) =
            Dups.insert name region (Env.TopLevel region) dict
       in List.foldl' addPort Dups.none ports
    Src.FFI _ ->
      Dups.none
    Src.Manager _ manager ->
      case manager of
        Src.Cmd (Ann.At region _) ->
          Dups.one "command" region (Env.TopLevel region)
        Src.Sub (Ann.At region _) ->
          Dups.one "subscription" region (Env.TopLevel region)
        Src.Fx (Ann.At regionCmd _) (Ann.At regionSub _) ->
          Dups.union
            (Dups.one "command" regionCmd (Env.TopLevel regionCmd))
            (Dups.one "subscription" regionSub (Env.TopLevel regionSub))

-- ADD TYPES

addTypes :: Src.Module -> Env.Env -> Result i w Env.Env
addTypes (Src.Module _ _ _ _ _ _ unions aliases _ _ _) (Env.Env home vs ts cs bs qvs qts qcs) =
  let addAliasDups dups (Ann.At _ (Src.Alias (Ann.At region name) _ _ _ _ _)) = Dups.insert name region () dups
      addUnionDups dups (Ann.At _ (Src.Union (Ann.At region name) _ _ _ _)) = Dups.insert name region () dups
      typeNameDups =
        List.foldl' addUnionDups (List.foldl' addAliasDups Dups.none aliases) unions
   in do
        _ <- Dups.detect Error.DuplicateType typeNameDups
        ts1 <- foldM (addUnion home) ts unions
        addAliases aliases (Env.Env home vs ts1 cs bs qvs qts qcs)

addUnion :: ModuleName.Canonical -> Env.Exposed Env.Type -> Ann.Located Src.Union -> Result i w (Env.Exposed Env.Type)
addUnion home types union@(Ann.At _ (Src.Union (Ann.At _ name) _ _ _ _)) =
  do
    arity <- checkUnionFreeVars union
    let one = Env.Specific home (Env.Union arity home)
    Result.ok $ Map.insert name one types

-- ADD TYPE ALIASES

addAliases :: [Ann.Located Src.Alias] -> Env.Env -> Result i w Env.Env
addAliases aliases env =
  let nodes = fmap toNode aliases
      sccs = Graph.stronglyConnComp nodes
   in foldM addAlias env sccs

addAlias :: Env.Env -> Graph.SCC (Ann.Located Src.Alias) -> Result i w Env.Env
addAlias env@(Env.Env home vs ts cs bs qvs qts qcs) scc =
  case scc of
    Graph.AcyclicSCC alias@(Ann.At _ (Src.Alias (Ann.At _ name) _ _ tipe _ _)) ->
      do
        args <- checkAliasFreeVars alias
        ctype <- Type.canonicalize env tipe
        let one = Env.Specific home (Env.Alias (length args) home args ctype)
        let ts1 = Map.insert name one ts
        Result.ok $ Env.Env home vs ts1 cs bs qvs qts qcs
    Graph.CyclicSCC [] ->
      Result.ok env
    Graph.CyclicSCC (alias@(Ann.At _ (Src.Alias (Ann.At region name1) _ _ tipe _ _)) : others) ->
      do
        args <- checkAliasFreeVars alias
        let toName (Ann.At _ (Src.Alias (Ann.At _ name) _ _ _ _ _)) = name
        Result.throw (Error.RecursiveAlias region name1 args tipe (fmap toName others))

-- DETECT TYPE ALIAS CYCLES

toNode :: Ann.Located Src.Alias -> (Ann.Located Src.Alias, Name.Name, [Name.Name])
toNode alias@(Ann.At _ (Src.Alias (Ann.At _ name) _ _ tipe _ _)) =
  (alias, name, getEdges [] tipe)

getEdges :: [Name.Name] -> Src.Type -> [Name.Name]
getEdges edges (Ann.At _ tipe) =
  case tipe of
    Src.TLambda arg result ->
      getEdges (getEdges edges arg) result
    Src.TVar _ ->
      edges
    Src.TType _ name args ->
      List.foldl' getEdges (name : edges) args
    Src.TTypeQual _ _ _ args ->
      List.foldl' getEdges edges args
    Src.TRecord fields _ ->
      List.foldl' (\es (_, t) -> getEdges es t) edges fields
    Src.TUnit ->
      edges
    Src.TTuple a b cs ->
      List.foldl' getEdges (getEdges (getEdges edges a) b) cs

-- CHECK FREE VARIABLES

checkUnionFreeVars :: Ann.Located Src.Union -> Result i w Int
checkUnionFreeVars (Ann.At unionRegion (Src.Union (Ann.At _ name) args _ ctors _)) =
  let addCtorFreeVars (_, tipes) freeVars =
        List.foldl' addFreeVars freeVars tipes

      addArg (Ann.At region arg) = Dups.insert arg region region
   in do
        boundVars <- Dups.detect (Error.DuplicateUnionArg name) (foldr addArg Dups.none args)
        let freeVars = foldr addCtorFreeVars Map.empty ctors
        case Map.toList (Map.difference freeVars boundVars) of
          [] ->
            Result.ok (length args)
          unbound : unbounds ->
            Result.throw $
              Error.TypeVarsUnboundInUnion unionRegion name (fmap Ann.toValue args) unbound unbounds

checkAliasFreeVars :: Ann.Located Src.Alias -> Result i w [Name.Name]
checkAliasFreeVars (Ann.At aliasRegion (Src.Alias (Ann.At _ name) args _ tipe _ _)) =
  let addArg (Ann.At region arg) = Dups.insert arg region region
   in do
        boundVars <- Dups.detect (Error.DuplicateAliasArg name) (foldr addArg Dups.none args)
        let freeVars = addFreeVars Map.empty tipe
        let overlap = Map.size (Map.intersection boundVars freeVars)
        if Map.size boundVars == overlap && Map.size freeVars == overlap
          then Result.ok (fmap Ann.toValue args)
          else
            Result.throw $
              Error.TypeVarsMessedUpInAlias
                aliasRegion
                name
                (fmap Ann.toValue args)
                (Map.toList (Map.difference boundVars freeVars))
                (Map.toList (Map.difference freeVars boundVars))

addFreeVars :: Map.Map Name.Name Ann.Region -> Src.Type -> Map.Map Name.Name Ann.Region
addFreeVars freeVars (Ann.At region tipe) =
  case tipe of
    Src.TLambda arg result ->
      addFreeVars (addFreeVars freeVars arg) result
    Src.TVar name ->
      Map.insert name region freeVars
    Src.TType _ _ args ->
      List.foldl' addFreeVars freeVars args
    Src.TTypeQual _ _ _ args ->
      List.foldl' addFreeVars freeVars args
    Src.TRecord fields maybeExt ->
      let extFreeVars =
            case maybeExt of
              Nothing ->
                freeVars
              Just (Ann.At extRegion ext) ->
                Map.insert ext extRegion freeVars
       in List.foldl' (\fvs (_, t) -> addFreeVars fvs t) extFreeVars fields
    Src.TUnit ->
      freeVars
    Src.TTuple a b cs ->
      List.foldl' addFreeVars (addFreeVars (addFreeVars freeVars a) b) cs

-- ADD CTORS

addCtors :: Src.Module -> Env.Env -> Result i w (Env.Env, Unions, Aliases)
addCtors (Src.Module _ _ _ _ _ _ unions aliases _ _ _) env@(Env.Env home vs ts cs bs qvs qts qcs) =
  do
    unionInfo <- traverse (canonicalizeUnion env) unions
    aliasInfo <- traverse (canonicalizeAlias env) aliases

    ctors <-
      Dups.detect Error.DuplicateCtor $
        Dups.union
          (Dups.unions (fmap snd unionInfo))
          (Dups.unions (fmap snd aliasInfo))

    let cs2 = Map.union ctors cs

    Result.ok
      ( Env.Env home vs ts cs2 bs qvs qts qcs,
        Map.fromList (fmap fst unionInfo),
        Map.fromList (fmap fst aliasInfo)
      )

type CtorDups = Dups.Dict (Env.Info Env.Ctor)

-- CANONICALIZE ALIAS

canonicalizeAlias :: Env.Env -> Ann.Located Src.Alias -> Result i w ((Name.Name, Can.Alias), CtorDups)
canonicalizeAlias env@(Env.Env home _ _ _ _ _ _ _) (Ann.At _ (Src.Alias (Ann.At region name) args srcVariances tipe maybeBound srcDeriving)) =
  do
    let vars = fmap Ann.toValue args
    ctipe <- Type.canonicalize env tipe
    let canVariances = fmap canonicalizeVariance srcVariances
    let canDeriving = fmap canonicalizeDerivingClause srcDeriving
    let canBound = mergeDeriveOrd (fmap canonicalizeBound maybeBound) canDeriving
    Variance.checkAliasVariance region name vars canVariances ctipe
    validateDerivingForType region name ctipe canDeriving
    Result.ok
      ( (name, Can.Alias vars canVariances ctipe canBound canDeriving),
        case ctipe of
          Can.TRecord fields Nothing ->
            Dups.one name region (Env.Specific home (toRecordCtor home name vars fields))
          _ ->
            Dups.none
      )

-- | Merge @deriving (Ord)@ into the alias bound.
--
-- If no explicit bound exists and @DeriveOrd@ is present, set @ComparableBound@.
mergeDeriveOrd :: Maybe Can.SupertypeBound -> [Can.DerivingClause] -> Maybe Can.SupertypeBound
mergeDeriveOrd (Just bound) _ = Just bound
mergeDeriveOrd Nothing clauses
  | any isOrd clauses = Just Can.ComparableBound
  | otherwise = Nothing
  where
    isOrd Can.DeriveOrd = True
    isOrd _ = False

-- | Convert a source supertype bound to its canonical representation.
canonicalizeBound :: Src.SupertypeBound -> Can.SupertypeBound
canonicalizeBound Src.ComparableBound = Can.ComparableBound
canonicalizeBound Src.AppendableBound = Can.AppendableBound
canonicalizeBound Src.NumberBound = Can.NumberBound
canonicalizeBound Src.CompAppendBound = Can.CompAppendBound

-- | Convert a source variance annotation to its canonical representation.
canonicalizeVariance :: Src.Variance -> Can.Variance
canonicalizeVariance Src.Covariant = Can.Covariant
canonicalizeVariance Src.Contravariant = Can.Contravariant
canonicalizeVariance Src.Invariant = Can.Invariant

-- | Convert a source deriving clause to its canonical representation.
canonicalizeDerivingClause :: Src.DerivingClause -> Can.DerivingClause
canonicalizeDerivingClause Src.DeriveOrd = Can.DeriveOrd
canonicalizeDerivingClause (Src.DeriveEncode opts) = Can.DeriveEncode (fmap canonicalizeJsonOptions opts)
canonicalizeDerivingClause (Src.DeriveDecode opts) = Can.DeriveDecode (fmap canonicalizeJsonOptions opts)
canonicalizeDerivingClause Src.DeriveEnum = Can.DeriveEnum

-- | Convert source JSON options to canonical representation.
canonicalizeJsonOptions :: Src.JsonOptions -> Can.JsonOptions
canonicalizeJsonOptions (Src.JsonOptions fn tf cf on mn us) =
  Can.JsonOptions (fmap canonicalizeNaming fn) tf cf on mn us

-- | Convert source naming strategy to canonical representation.
canonicalizeNaming :: Src.NamingStrategy -> Can.NamingStrategy
canonicalizeNaming Src.IdentityNaming = Can.IdentityNaming
canonicalizeNaming Src.SnakeCase = Can.SnakeCase
canonicalizeNaming Src.CamelCase = Can.CamelCase
canonicalizeNaming Src.KebabCase = Can.KebabCase

toRecordCtor :: ModuleName.Canonical -> Name.Name -> [Name.Name] -> Map.Map Name.Name Can.FieldType -> Env.Ctor
toRecordCtor home name vars fields =
  let avars = fmap (\var -> (var, Can.TVar var)) vars
      alias =
        foldr
          (\(_, t1) t2 -> Can.TLambda t1 t2)
          (Can.TAlias home name avars (Can.Filled (Can.TRecord fields Nothing)))
          (Can.fieldsToList fields)
   in Env.RecordCtor home vars alias

-- CANONICALIZE UNION

canonicalizeUnion :: Env.Env -> Ann.Located Src.Union -> Result i w ((Name.Name, Can.Union), CtorDups)
canonicalizeUnion env@(Env.Env home _ _ _ _ _ _ _) (Ann.At _ (Src.Union (Ann.At region name) avars srcVariances ctors srcDeriving)) =
  do
    cctors <- Index.indexedTraverse (canonicalizeCtor env) ctors
    let vars = fmap Ann.toValue avars
    let alts = fmap Ann.toValue cctors
    let canVariances = fmap canonicalizeVariance srcVariances
    let canDeriving = fmap canonicalizeDerivingClause srcDeriving
    Variance.checkUnionVariance region name vars canVariances alts
    validateDerivingForUnion region name alts canDeriving
    let union = Can.Union vars canVariances alts (length alts) (toOpts ctors) canDeriving
    Result.ok
      ( (name, union),
        Dups.unions $ fmap (toCtor home name union) cctors
      )

canonicalizeCtor :: Env.Env -> Index.ZeroBased -> (Ann.Located Name.Name, [Src.Type]) -> Result i w (Ann.Located Can.Ctor)
canonicalizeCtor env index (Ann.At region ctor, tipes) =
  do
    ctipes <- traverse (Type.canonicalize env) tipes
    Result.ok . Ann.At region $ Can.Ctor ctor index (length ctipes) ctipes

toOpts :: [(Ann.Located Name.Name, [Src.Type])] -> Can.CtorOpts
toOpts ctors =
  case ctors of
    [(_, [_])] ->
      Can.Unbox
    _ ->
      if all (null . snd) ctors then Can.Enum else Can.Normal

toCtor :: ModuleName.Canonical -> Name.Name -> Can.Union -> Ann.Located Can.Ctor -> CtorDups
toCtor home typeName union (Ann.At region (Can.Ctor name index _ args)) =
  Dups.one name region . Env.Specific home $ Env.Ctor home typeName union index args

-- DERIVING VALIDATION

-- | Validate that all deriving clauses are compatible with the alias type.
validateDerivingForType ::
  Ann.Region -> Name.Name -> Can.Type -> [Can.DerivingClause] -> Result i w ()
validateDerivingForType region name tipe clauses =
  traverse_ (validateOneAliasClause region name tipe) clauses

-- | Validate that all deriving clauses are compatible with the union constructors.
validateDerivingForUnion ::
  Ann.Region -> Name.Name -> [Can.Ctor] -> [Can.DerivingClause] -> Result i w ()
validateDerivingForUnion region name ctors clauses =
  let allArgTypes = concatMap (\(Can.Ctor _ _ _ argTypes) -> argTypes) ctors
      syntheticType = Can.TRecord (toFieldMap allArgTypes) Nothing
   in traverse_ (validateOneUnionClause region name ctors syntheticType) clauses
  where
    toFieldMap types =
      Map.fromList (zip (fmap indexToName [0..]) (fmap (Can.FieldType 0) types))
    indexToName i = Name.fromChars [toEnum (fromEnum 'a' + i)]

-- | Validate a single union deriving clause, handling Enum specially.
validateOneUnionClause ::
  Ann.Region -> Name.Name -> [Can.Ctor] -> Can.Type -> Can.DerivingClause -> Result i w ()
validateOneUnionClause region name ctors syntheticType clause =
  case clause of
    Can.DeriveEnum -> validateEnumForUnion region name ctors
    _ -> validateOneClause region name syntheticType clause

-- | Validate a single deriving clause against a type.
-- | Validate a single alias deriving clause against a type.
validateOneAliasClause ::
  Ann.Region -> Name.Name -> Can.Type -> Can.DerivingClause -> Result i w ()
validateOneAliasClause region name tipe clause =
  case clause of
    Can.DeriveOrd ->
      Result.throw (Error.DerivingInvalid region name (Name.fromChars "Ord") (Error.DerivingOrdNotOnUnion name))
    Can.DeriveEncode _ -> validateJsonType region name (derivingClauseName clause) tipe
    Can.DeriveDecode _ -> validateJsonType region name (derivingClauseName clause) tipe
    Can.DeriveEnum -> Result.ok ()

-- | Validate a single union deriving clause against a type.
validateOneClause ::
  Ann.Region -> Name.Name -> Can.Type -> Can.DerivingClause -> Result i w ()
validateOneClause region name tipe clause =
  case clause of
    Can.DeriveOrd -> validateOrdType region name tipe
    Can.DeriveEncode _ -> validateJsonType region name (derivingClauseName clause) tipe
    Can.DeriveDecode _ -> validateJsonType region name (derivingClauseName clause) tipe
    Can.DeriveEnum -> Result.ok ()

-- | Get a display name for a deriving clause.
derivingClauseName :: Can.DerivingClause -> Name.Name
derivingClauseName Can.DeriveOrd = Name.fromChars "Ord"
derivingClauseName (Can.DeriveEncode _) = Name.fromChars "Encode"
derivingClauseName (Can.DeriveDecode _) = Name.fromChars "Decode"
derivingClauseName Can.DeriveEnum = Name.fromChars "Enum"

-- | Check that a type can be JSON encoded/decoded.
validateJsonType ::
  Ann.Region -> Name.Name -> Name.Name -> Can.Type -> Result i w ()
validateJsonType region typeName clauseName tipe =
  case checkJsonCompatible tipe of
    Nothing -> Result.ok ()
    Just problem -> Result.throw (Error.DerivingInvalid region typeName clauseName problem)

-- | Check if a type is JSON-compatible. Returns 'Nothing' if valid,
-- or 'Just problem' describing why it is not.
checkJsonCompatible :: Can.Type -> Maybe Error.DerivingProblem
checkJsonCompatible tipe =
  case tipe of
    Can.TLambda _ _ -> Just Error.DerivingHasFunction
    Can.TVar _ -> Nothing
    Can.TUnit -> Nothing
    Can.TTuple a b c ->
      checkJsonCompatible a
        `orElse` checkJsonCompatible b
        `orElse` maybe Nothing checkJsonCompatible c
    Can.TType _ name args ->
      case args of
        [] | isJsonPrimitive name -> Nothing
        [arg] | isJsonContainer name -> checkJsonCompatible arg
        _ -> Just (Error.DerivingHasUnsupportedType name)
    Can.TRecord _ (Just _) -> Just Error.DerivingHasExtensibleRecord
    Can.TRecord fields Nothing ->
      foldr (\(Can.FieldType _ ft) acc -> checkJsonCompatible ft `orElse` acc) Nothing (Map.elems fields)
    Can.TAlias _ _ args alias ->
      checkJsonCompatible (TypeUtils.dealias args alias)

-- | Short-circuit 'Maybe' combination.
orElse :: Maybe a -> Maybe a -> Maybe a
orElse (Just x) _ = Just x
orElse Nothing y = y

-- | Check if a type name is a JSON-encodable primitive.
isJsonPrimitive :: Name.Name -> Bool
isJsonPrimitive name =
  name == Name.float
    || name == Name.int
    || name == Name.bool
    || name == Name.string
    || name == Name.value

-- | Check if a type name is a JSON-encodable container (takes one type arg).
isJsonContainer :: Name.Name -> Bool
isJsonContainer name =
  name == Name.maybe
    || name == Name.list
    || name == Name.array

-- ORD VALIDATION

-- | Validate that a type is comparable for @deriving (Ord)@.
validateOrdType :: Ann.Region -> Name.Name -> Can.Type -> Result i w ()
validateOrdType region typeName tipe =
  case checkOrdCompatible tipe of
    Nothing -> Result.ok ()
    Just problem -> Result.throw (Error.DerivingInvalid region typeName (Name.fromChars "Ord") problem)

-- | Check if a type is comparable. Returns 'Nothing' if valid.
checkOrdCompatible :: Can.Type -> Maybe Error.DerivingProblem
checkOrdCompatible tipe =
  case tipe of
    Can.TLambda _ _ -> Just Error.DerivingHasFunction
    Can.TVar _ -> Nothing
    Can.TUnit -> Nothing
    Can.TTuple a b c ->
      checkOrdCompatible a
        `orElse` checkOrdCompatible b
        `orElse` maybe Nothing checkOrdCompatible c
    Can.TType _ name args ->
      case args of
        [] | isOrdPrimitive name -> Nothing
        [arg] | isOrdContainer name -> checkOrdCompatible arg
        _ -> Nothing
    Can.TRecord _ _ -> Just Error.DerivingHasExtensibleRecord
    Can.TAlias _ _ args alias ->
      checkOrdCompatible (TypeUtils.dealias args alias)

-- | Check if a type name is a comparable primitive.
isOrdPrimitive :: Name.Name -> Bool
isOrdPrimitive name =
  name == Name.int
    || name == Name.float
    || name == Name.string
    || name == Name.char

-- | Check if a type name is a comparable container.
isOrdContainer :: Name.Name -> Bool
isOrdContainer name =
  name == Name.list

-- ENUM VALIDATION

-- | Validate @deriving (Enum)@ — all constructors must be nullary.
validateEnumForUnion :: Ann.Region -> Name.Name -> [Can.Ctor] -> Result i w ()
validateEnumForUnion region typeName ctors =
  case List.find hasArgs ctors of
    Nothing -> Result.ok ()
    Just (Can.Ctor ctorName _ _ _) ->
      Result.throw (Error.DerivingInvalid region typeName (Name.fromChars "Enum") (Error.DerivingHasConstructorArgs ctorName))
  where
    hasArgs (Can.Ctor _ _ numArgs _) = numArgs > 0
