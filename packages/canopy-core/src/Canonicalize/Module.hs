{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Canonicalize.Module - Module canonicalization
--
-- This module takes a parsed source module and resolves all names,
-- producing a canonical AST with fully-qualified module names.
-- FFI processing is handled in "Canonicalize.Module.FFI".
--
-- @since 0.19.1
module Canonicalize.Module
  ( canonicalize,
    CanonConfig (..),
    canonicalizeWithIO,
    loadFFIContent,
    loadFFIContentWithRoot,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import Data.Foldable (traverse_)
import qualified Canonicalize.Ability as Ability
import qualified Canonicalize.Effects as Effects
import qualified Canonicalize.Environment as Env
import qualified Canonicalize.Environment.Dups as Dups
import qualified Canonicalize.Environment.Foreign as Foreign
import qualified Canonicalize.Environment.Local as Local
import qualified Canonicalize.Expression as Expr
import qualified Canonicalize.Module.FFI as FFI
import qualified Canonicalize.Pattern as Pattern
import FFI.Types (JsSourcePath, JsSource)
import qualified Canonicalize.Type as Type
import qualified Canopy.Compiler.Imports as Imports
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Parse.Module (ProjectType (..))
import qualified Data.Graph as Graph
import qualified Canopy.Data.Index as Index
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Canopy.Data.Name as Name
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified Reporting.InternalError as InternalError
import qualified Reporting.Warning as Warning

-- RESULT

type Result i w a =
  Result.Result i w Error.Error a

-- RE-EXPORTS from sub-modules

-- | Load FFI content from foreign imports in the IO monad.
--
-- @since 0.19.1
loadFFIContent :: [Src.ForeignImport] -> IO (Map JsSourcePath JsSource)
loadFFIContent = FFI.loadFFIContent

-- | Load FFI content with explicit root directory for path resolution.
loadFFIContentWithRoot :: FilePath -> [Src.ForeignImport] -> IO (Map JsSourcePath JsSource)
loadFFIContentWithRoot = FFI.loadFFIContentWithRoot

-- MODULES

-- | Groups the three immutable compilation inputs needed by 'canonicalize'.
--
-- Bundles the package name, project type, and dependency interface map
-- so they can be passed as one argument instead of three.
data CanonConfig = CanonConfig
  { _ccPkg :: !Pkg.Name
  , _ccProjectType :: !ProjectType
  , _ccIfaces :: !(Map ModuleName.Raw Interface.Interface)
  }

-- | Canonicalize a source module with pre-loaded FFI content.
--
-- The 'CanonConfig' bundles the package name, project type, and interface
-- map so they can be passed as one argument.  The FFI content map and the
-- source module are passed separately because they vary per-file while the
-- config is constant across all files in a build.
--
-- @since 0.19.1
canonicalize :: CanonConfig -> Map JsSourcePath JsSource -> Src.Module -> Result i [Warning.Warning] Can.Module
canonicalize = canonicalizeWithConfig

-- | Implementation of canonicalize using a 'CanonConfig'.
canonicalizeWithConfig :: CanonConfig -> Map JsSourcePath JsSource -> Src.Module -> Result i [Warning.Warning] Can.Module
canonicalizeWithConfig cc ffiContentMap modul@(Src.Module _ exports docs imports foreignImports values _ _ binops effects _ srcAbilities srcImpls) =
  do
    let home = ModuleName.Canonical (_ccPkg cc) (Src.getName modul)
    let cbinops = Map.fromList (fmap canonicalizeBinop binops)
    lazySet <- validateAndCollectLazyImports (_ccPkg cc) (_ccProjectType cc) home (_ccIfaces cc) imports
    let eagerImports = filter (not . Src._importLazy) imports
    (env, cunions, caliases) <-
      Foreign.createInitialEnv home (_ccIfaces cc) eagerImports >>= Local.add modul
    envWithFFI <- canonicalizeFFIEnv env foreignImports ffiContentMap
    envWithAbilities <- canonicalizeAbilityEnv home envWithFFI srcAbilities
    cabilities <- Ability.canonicalizeAbilities envWithFFI srcAbilities
    cimpls <- Ability.canonicalizeImpls envWithFFI home cabilities srcImpls
    (cvalues, ceffects, cexports, cguards) <-
      canonicalizeModuleBody envWithAbilities (ModuleBodyArgs values cunions caliases cbinops effects exports)
    return $ Can.Module home cexports docs cvalues cunions caliases cbinops ceffects lazySet cguards cabilities cimpls

-- | Add FFI bindings to the environment and emit capability warnings.
canonicalizeFFIEnv :: Env.Env -> [Src.ForeignImport] -> Map JsSourcePath JsSource -> Result i [Warning.Warning] Env.Env
canonicalizeFFIEnv env foreignImports ffiContentMap = do
  let capWarnings = concatMap (emitCapabilityWarnings ffiContentMap) foreignImports
  traverse_ Result.warn capWarnings
  FFI.addFFIToEnvPure env foreignImports ffiContentMap Map.empty

-- | Canonicalize abilities and extend the environment with ability methods.
canonicalizeAbilityEnv :: ModuleName.Canonical -> Env.Env -> [Ann.Located Src.AbilityDecl] -> Result i [Warning.Warning] Env.Env
canonicalizeAbilityEnv home envWithFFI srcAbilities = do
  cabilities <- Ability.canonicalizeAbilities envWithFFI srcAbilities
  return (addAbilityMethodsToEnv home envWithFFI cabilities)

-- | Groups the declarations needed by 'canonicalizeModuleBody'.
data ModuleBodyArgs = ModuleBodyArgs
  { _mbaValues :: ![Ann.Located Src.Value]
  , _mbaCUnions :: !(Map Name.Name Can.Union)
  , _mbaCaliases :: !(Map Name.Name Can.Alias)
  , _mbaCBinops :: !(Map Name.Name Can.Binop)
  , _mbaEffects :: !Src.Effects
  , _mbaExports :: !(Ann.Located Src.Exposing)
  }

-- | Canonicalize the main module body: values, effects, exports, and guards.
canonicalizeModuleBody :: Env.Env -> ModuleBodyArgs -> Result i [Warning.Warning] (Can.Decls, Can.Effects, Can.Exports, Map Name.Name Can.GuardInfo)
canonicalizeModuleBody env mba = do
  cvalues <- canonicalizeValues env (_mbaValues mba)
  ceffects <- Effects.canonicalize env (_mbaValues mba) (_mbaCUnions mba) (_mbaEffects mba)
  let derivedNames = collectDerivedFunctionNames (_mbaCUnions mba) (_mbaCaliases mba)
  cexports <- canonicalizeExports (_mbaValues mba) derivedNames (_mbaCUnions mba) (_mbaCaliases mba) (_mbaCBinops mba) ceffects (_mbaExports mba)
  cguards <- canonicalizeGuards env (_mbaValues mba)
  return (cvalues, ceffects, cexports, cguards)

-- | Legacy canonicalize function for backward compatibility
--
-- This function maintains the old signature for existing code but internally
-- handles FFI file reading. This should be replaced with the new signature
-- that takes pre-loaded FFI content.
--
-- @deprecated Use canonicalize with pre-loaded FFI content instead
canonicalizeWithIO :: Pkg.Name -> Map ModuleName.Raw Interface.Interface -> Src.Module -> IO (Result i [Warning.Warning] Can.Module)
canonicalizeWithIO pkg ifaces modul@(Src.Module _ _ _ _ foreignImports _ _ _ _ _ _ _ _) = do
  -- Pre-load FFI content
  ffiContentMap <- FFI.loadFFIContent foreignImports
  return $ canonicalize (CanonConfig pkg Application ifaces) ffiContentMap modul

-- LAZY IMPORT VALIDATION

-- | Validate and collect lazy imports from source imports.
--
-- Each lazy import is checked against five rules:
--
--   1. Must not be inside a package (code splitting is app-only)
--   2. Must not be a self-import
--   3. Must not target a kernel package module
--   4. Must not target a core/stdlib default import
--   5. Must exist in the available interfaces
--
-- Returns the set of validated canonical lazy module names, or
-- throws errors for each invalid lazy import encountered.
--
-- @since 0.19.2
-- | Context for lazy import validation, grouping the three values that never
-- change across imports within a single module.
type LazyCtx = (Pkg.Name, ProjectType, ModuleName.Canonical)

validateAndCollectLazyImports ::
  Pkg.Name ->
  ProjectType ->
  ModuleName.Canonical ->
  Map ModuleName.Raw Interface.Interface ->
  [Src.Import] ->
  Result i w (Set ModuleName.Canonical)
validateAndCollectLazyImports pkg projectType home ifaces imports =
  fmap Set.fromList (traverse (validateOneLazy (pkg, projectType, home) ifaces) lazyImports)
  where
    lazyImports = filter Src._importLazy imports

-- | Validate a single lazy import and resolve to its canonical name.
validateOneLazy ::
  LazyCtx ->
  Map ModuleName.Raw Interface.Interface ->
  Src.Import ->
  Result i w ModuleName.Canonical
validateOneLazy (pkg, projectType, home) ifaces (Src.Import (Ann.At region name) _ _ _) =
  checkNotPackage region name projectType
    >> checkNotSelf region name home
    >> checkNotKernel region name
    >> checkNotCore region name
    >> checkExists region name ifaces
    >> Result.ok (ModuleName.Canonical pkg name)

-- | Reject lazy imports in package context.
checkNotPackage :: Ann.Region -> Name.Name -> ProjectType -> Result i w ()
checkNotPackage region name projectType =
  case projectType of
    Package _ -> Result.throw (Error.LazyImportInPackage region name)
    Application -> Result.ok ()

-- | Reject a module lazily importing itself.
checkNotSelf :: Ann.Region -> Name.Name -> ModuleName.Canonical -> Result i w ()
checkNotSelf region name (ModuleName.Canonical _ selfName)
  | name == selfName = Result.throw (Error.LazyImportSelf region name)
  | otherwise = Result.ok ()

-- | Reject lazy imports of internal kernel modules.
checkNotKernel :: Ann.Region -> Name.Name -> Result i w ()
checkNotKernel region name
  | Name.isKernel name = Result.throw (Error.LazyImportKernel region name)
  | otherwise = Result.ok ()

-- | Reject lazy imports of core/stdlib default modules.
checkNotCore :: Ann.Region -> Name.Name -> Result i w ()
checkNotCore region name
  | Set.member name coreModuleNames =
      Result.throw (Error.LazyImportCoreModule region name)
  | otherwise = Result.ok ()

-- | Reject lazy imports of modules not found in available interfaces.
checkExists :: Ann.Region -> Name.Name -> Map ModuleName.Raw Interface.Interface -> Result i w ()
checkExists region name ifaces
  | Map.member name ifaces = Result.ok ()
  | otherwise =
      Result.throw (Error.LazyImportNotFound region name (Map.keys ifaces))

-- | The set of module names that are default core imports.
--
-- Derived from 'Imports.defaults' so it stays in sync automatically.
coreModuleNames :: Set Name.Name
coreModuleNames =
  Set.fromList (fmap Src.getImportName Imports.defaults)

-- CAPABILITY WARNINGS

-- | Emit capability warnings for a single foreign import.
emitCapabilityWarnings :: Map JsSourcePath JsSource -> Src.ForeignImport -> [Warning.Warning]
emitCapabilityWarnings ffiContentMap (Src.ForeignImport _ (Ann.At _ aliasName) _) =
  FFI.extractCapabilityWarnings aliasName ffiContentMap

-- ADD ABILITY METHODS TO ENV

addAbilityMethodsToEnv ::
  ModuleName.Canonical ->
  Env.Env ->
  Map Name.Name Can.Ability ->
  Env.Env
addAbilityMethodsToEnv home (Env.Env h vs ts cs bs qvs qts qcs) abilities =
  let methodVars = Map.foldlWithKey' (addAbilityMethods home) Map.empty abilities
  in Env.Env h (Map.union methodVars vs) ts cs bs qvs qts qcs

addAbilityMethods ::
  ModuleName.Canonical ->
  Map Name.Name Env.Var ->
  Name.Name ->
  Can.Ability ->
  Map Name.Name Env.Var
addAbilityMethods home acc abilityName (Can.Ability _ _ _ methods) =
  Map.foldlWithKey' (addOneMethod home abilityName) acc methods

addOneMethod ::
  ModuleName.Canonical ->
  Name.Name ->
  Map Name.Name Env.Var ->
  Name.Name ->
  Can.Type ->
  Map Name.Name Env.Var
addOneMethod home abilityName acc methodName methodType =
  Map.insert methodName (Env.AbilityMethod home abilityName (Can.Forall Map.empty methodType)) acc

-- CANONICALIZE BINOP

canonicalizeBinop :: Ann.Located Src.Infix -> (Name.Name, Can.Binop)
canonicalizeBinop (Ann.At _ (Src.Infix op associativity precedence func)) =
  (op, Can.Binop_ associativity precedence func)

-- DECLARATIONS / CYCLE DETECTION
--
-- There are two phases of cycle detection:
--
-- 1. Detect cycles using ALL dependencies => needed for type inference
-- 2. Detect cycles using DIRECT dependencies => nonterminating recursion
--

canonicalizeValues :: Env.Env -> [Ann.Located Src.Value] -> Result i [Warning.Warning] Can.Decls
canonicalizeValues env values =
  do
    nodes <- traverse (toNodeOne env) values
    detectCycles (Graph.stronglyConnComp nodes)

-- | Canonicalize guard annotations from source values.
--
-- For each value that has a @guards@ annotation, the narrow type is
-- canonicalized and stored in a map keyed by the function name.
--
-- @since 0.20.0
canonicalizeGuards :: Env.Env -> [Ann.Located Src.Value] -> Result i [Warning.Warning] (Map Name.Name Can.GuardInfo)
canonicalizeGuards env values =
  Map.fromList <$> traverse (canonicalizeOneGuard env) guardedValues
  where
    guardedValues = [(name, ga) | Ann.At _ (Src.Value (Ann.At _ name) _ _ _ (Just ga)) <- values]

-- | Canonicalize a single guard annotation.
--
-- @since 0.20.0
canonicalizeOneGuard :: Env.Env -> (Name.Name, Src.GuardAnnotation) -> Result i [Warning.Warning] (Name.Name, Can.GuardInfo)
canonicalizeOneGuard env (name, Src.GuardAnnotation argIdx srcNarrowType) =
  do
    (Can.Forall _ canNarrowType) <- Type.toAnnotation env srcNarrowType
    Result.ok (name, Can.GuardInfo argIdx canNarrowType)

detectCycles :: [Graph.SCC NodeTwo] -> Result i w Can.Decls
detectCycles [] = Result.ok Can.SaveTheEnvironment
detectCycles (scc : otherSccs) = detectOneSCC scc otherSccs

detectOneSCC :: Graph.SCC NodeTwo -> [Graph.SCC NodeTwo] -> Result i w Can.Decls
detectOneSCC (Graph.AcyclicSCC (def, _, _)) otherSccs =
  Can.Declare def <$> detectCycles otherSccs
detectOneSCC (Graph.CyclicSCC subNodes) otherSccs =
  traverse detectBadCycles (Graph.stronglyConnComp subNodes)
    >>= assembleCyclicDecls otherSccs

assembleCyclicDecls :: [Graph.SCC NodeTwo] -> [Can.Def] -> Result i w Can.Decls
assembleCyclicDecls otherSccs [] = detectCycles otherSccs
assembleCyclicDecls otherSccs (d : ds) = Can.DeclareRec d ds <$> detectCycles otherSccs

detectBadCycles :: Graph.SCC Can.Def -> Result i w Can.Def
detectBadCycles (Graph.AcyclicSCC def) = Result.ok def
detectBadCycles (Graph.CyclicSCC []) =
  InternalError.report "Canonicalize.Module.detectBadCycles" "Empty CyclicSCC from Data.Graph" "Data.Graph.SCC should never produce an empty CyclicSCC list."
detectBadCycles (Graph.CyclicSCC (def : defs)) =
  Result.throw (Error.RecursiveDecl region name names)
  where
    (Ann.At region name) = extractDefName def
    names = fmap (Ann.toValue . extractDefName) defs

extractDefName :: Can.Def -> Ann.Located Name.Name
extractDefName def =
  case def of
    Can.Def name _ _ -> name
    Can.TypedDef name _ _ _ _ -> name

-- DECLARATIONS / CYCLE DETECTION SETUP
--
-- toNodeOne and toNodeTwo set up nodes for the two cycle detection phases.
--

-- Phase one nodes track ALL dependencies.
-- This allows us to find cyclic values for type inference.
type NodeOne =
  (NodeTwo, Name.Name, [Name.Name])

-- Phase two nodes track DIRECT dependencies.
-- This allows us to detect cycles that definitely do not terminate.
type NodeTwo =
  (Can.Def, Name.Name, [Name.Name])

-- | Groups the definition-level fields needed by 'toNodeOne' helpers.
data DefSpec = DefSpec
  { _dsAname :: !(Ann.Located Name.Name)
  , _dsName :: !Name.Name
  , _dsSrcArgs :: ![Src.Pattern]
  , _dsBody :: !Src.Expr
  }

toNodeOne :: Env.Env -> Ann.Located Src.Value -> Result i [Warning.Warning] NodeOne
toNodeOne env (Ann.At _ (Src.Value aname@(Ann.At _ name) srcArgs body maybeType _maybeGuard)) =
  maybe
    (toNodeOneUntyped env (DefSpec aname name srcArgs body))
    (toNodeOneTyped env (DefSpec aname name srcArgs body))
    maybeType

toNodeOneUntyped :: Env.Env -> DefSpec -> Result i [Warning.Warning] NodeOne
toNodeOneUntyped env ds = do
  (args, argBindings) <-
    Pattern.verify (Error.DPFuncArgs (_dsName ds)) $
      traverse (Pattern.canonicalize env) (_dsSrcArgs ds)
  newEnv <- Env.addLocals argBindings env
  (cbody, freeLocals) <-
    Expr.verifyBindings Warning.Pattern argBindings (Expr.canonicalize newEnv (_dsBody ds))
  let def = Can.Def (_dsAname ds) args cbody
  return (toNodeTwo (_dsName ds) (_dsSrcArgs ds) def freeLocals, _dsName ds, Map.keys freeLocals)

toNodeOneTyped :: Env.Env -> DefSpec -> Src.Type -> Result i [Warning.Warning] NodeOne
toNodeOneTyped env ds srcType = do
  (Can.Forall freeVars tipe) <- Type.toAnnotation env srcType
  ((args, resultType), argBindings) <-
    Pattern.verify (Error.DPFuncArgs (_dsName ds)) $
      Expr.gatherTypedArgs env (_dsName ds) (_dsSrcArgs ds) tipe (Index.first, [])
  newEnv <- Env.addLocals argBindings env
  (cbody, freeLocals) <-
    Expr.verifyBindings Warning.Pattern argBindings (Expr.canonicalize newEnv (_dsBody ds))
  let def = Can.TypedDef (_dsAname ds) freeVars args cbody resultType
  return (toNodeTwo (_dsName ds) (_dsSrcArgs ds) def freeLocals, _dsName ds, Map.keys freeLocals)

toNodeTwo :: Name.Name -> [arg] -> Can.Def -> Expr.FreeLocals -> NodeTwo
toNodeTwo name args def freeLocals =
  case args of
    [] ->
      (def, name, Map.foldrWithKey addDirects [] freeLocals)
    _ ->
      (def, name, [])

addDirects :: Name.Name -> Expr.Uses -> [Name.Name] -> [Name.Name]
addDirects name (Expr.Uses directUses _) directDeps =
  if directUses > 0
    then name : directDeps
    else directDeps

-- CANONICALIZE EXPORTS

canonicalizeExports ::
  [Ann.Located Src.Value] ->
  Map.Map Name.Name () ->
  Map.Map Name.Name Can.Union ->
  Map.Map Name.Name Can.Alias ->
  Map.Map Name.Name Can.Binop ->
  Can.Effects ->
  Ann.Located Src.Exposing ->
  Result i w Can.Exports
canonicalizeExports values derivedNames unions aliases binops effects (Ann.At region exposing) =
  case exposing of
    Src.Open ->
      Result.ok (Can.ExportEverything region)
    Src.Explicit exposeds ->
      let names = Map.union (Map.fromList (fmap valueToName values)) derivedNames
          ctx = ExposedCtx names unions aliases binops
      in canonicalizeExplicitExports ctx effects exposeds

-- | Canonicalize a list of explicitly exported names into a 'Can.Export' map.
canonicalizeExplicitExports :: ExposedCtx -> Can.Effects -> [Src.Exposed] -> Result i w Can.Exports
canonicalizeExplicitExports ctx effects exposeds = do
  infos <- traverse (checkExposed ctx effects) exposeds
  Can.Export <$> Dups.detect Error.ExportDuplicate (Dups.unions infos)

valueToName :: Ann.Located Src.Value -> (Name.Name, ())
valueToName (Ann.At _ (Src.Value (Ann.At _ name) _ _ _ _)) =
  (name, ())

-- | Groups the four declaration maps needed during export checking.
data ExposedCtx = ExposedCtx
  { _ecValues :: !(Map Name.Name ())
  , _ecUnions :: !(Map Name.Name Can.Union)
  , _ecAliases :: !(Map Name.Name Can.Alias)
  , _ecBinops :: !(Map Name.Name Can.Binop)
  }

checkExposed ::
  ExposedCtx ->
  Can.Effects ->
  Src.Exposed ->
  Result i w (Dups.Dict (Ann.Located Can.Export))
checkExposed ctx effects exposed =
  case exposed of
    Src.Lower (Ann.At region name) ->
      checkExposedLower ctx effects region name
    Src.Operator region name ->
      checkExposedOp (_ecBinops ctx) region name
    Src.Upper (Ann.At region name) (Src.Public dotDotRegion) ->
      checkExposedUpperOpen (_ecUnions ctx) (_ecAliases ctx) region name dotDotRegion
    Src.Upper (Ann.At region name) Src.Private ->
      checkExposedUpperClosed (_ecUnions ctx) (_ecAliases ctx) region name

checkExposedLower ::
  ExposedCtx ->
  Can.Effects ->
  Ann.Region ->
  Name.Name ->
  Result i w (Dups.Dict (Ann.Located Can.Export))
checkExposedLower ctx effects region name
  | Map.member name (_ecValues ctx) = ok name region Can.ExportValue
  | otherwise = checkExposedLowerPort ctx effects region name

checkExposedLowerPort ::
  ExposedCtx ->
  Can.Effects ->
  Ann.Region ->
  Name.Name ->
  Result i w (Dups.Dict (Ann.Located Can.Export))
checkExposedLowerPort ctx effects region name =
  maybe
    (ok name region Can.ExportPort)
    (\ports -> Result.throw (Error.ExportNotFound region Error.BadVar name (ports <> Map.keys (_ecValues ctx))))
    (checkPorts effects name)

checkExposedOp :: Map Name.Name binop -> Ann.Region -> Name.Name -> Result i w (Dups.Dict (Ann.Located Can.Export))
checkExposedOp binops region name
  | Map.member name binops = ok name region Can.ExportBinop
  | otherwise = Result.throw (Error.ExportNotFound region Error.BadOp name (Map.keys binops))

checkExposedUpperOpen ::
  Map Name.Name union ->
  Map Name.Name alias ->
  Ann.Region ->
  Name.Name ->
  Ann.Region ->
  Result i w (Dups.Dict (Ann.Located Can.Export))
checkExposedUpperOpen unions aliases region name dotDotRegion
  | Map.member name unions = ok name region Can.ExportUnionOpen
  | Map.member name aliases = Result.throw (Error.ExportOpenAlias dotDotRegion name)
  | otherwise = Result.throw (Error.ExportNotFound region Error.BadType name (Map.keys unions <> Map.keys aliases))

checkExposedUpperClosed ::
  Map Name.Name union ->
  Map Name.Name alias ->
  Ann.Region ->
  Name.Name ->
  Result i w (Dups.Dict (Ann.Located Can.Export))
checkExposedUpperClosed unions aliases region name
  | Map.member name unions = ok name region Can.ExportUnionClosed
  | Map.member name aliases = ok name region Can.ExportAlias
  | otherwise = Result.throw (Error.ExportNotFound region Error.BadType name (Map.keys unions <> Map.keys aliases))

checkPorts :: Can.Effects -> Name.Name -> Maybe [Name.Name]
checkPorts effects name =
  case effects of
    Can.NoEffects ->
      Just []
    Can.Ports ports ->
      if Map.member name ports then Nothing else Just (Map.keys ports)
    Can.FFI ->
      Just []
    Can.Manager {} ->
      Just []

ok :: Name.Name -> Ann.Region -> Can.Export -> Result i w (Dups.Dict (Ann.Located Can.Export))
ok name region export =
  Result.ok $ Dups.one name region (Ann.At region export)

-- | Collect function names generated by @deriving@ clauses.
--
-- Returns a map of derived function names for export and name resolution.
-- Each deriving clause generates a specific function name:
--
--   * @Show@ → @showTypeName@
--   * @Parse@ → @parseTypeName@
--   * @Json.Encode@ → @encodeTypeName@
--   * @Json.Decode@ → @typeNameDecoder@
--   * @Ord@ → (no function generated)
--
-- @since 0.20.0
collectDerivedFunctionNames ::
  Map.Map Name.Name Can.Union ->
  Map.Map Name.Name Can.Alias ->
  Map.Map Name.Name ()
collectDerivedFunctionNames unions aliases =
  Map.union
    (Map.foldlWithKey' addUnionDerived Map.empty unions)
    (Map.foldlWithKey' addAliasDerived Map.empty aliases)

addUnionDerived :: Map.Map Name.Name () -> Name.Name -> Can.Union -> Map.Map Name.Name ()
addUnionDerived acc typeName (Can.Union _ _ _ _ _ clauses) =
  foldl (addDerivedName typeName) acc clauses

addAliasDerived :: Map.Map Name.Name () -> Name.Name -> Can.Alias -> Map.Map Name.Name ()
addAliasDerived acc typeName (Can.Alias _ _ _ _ clauses) =
  foldl (addDerivedName typeName) acc clauses

addDerivedName :: Name.Name -> Map.Map Name.Name () -> Can.DerivingClause -> Map.Map Name.Name ()
addDerivedName typeName acc clause =
  let nameChars = Name.toChars typeName
   in case clause of
        Can.DeriveOrd ->
          acc
        Can.DeriveEncode _ ->
          Map.insert (Name.fromChars ("encode" ++ nameChars)) () acc
        Can.DeriveDecode _ ->
          Map.insert (Name.fromChars (lowerFirst nameChars ++ "Decoder")) () acc
        Can.DeriveEnum ->
          Map.insert (Name.fromChars ("all" ++ nameChars)) () acc

lowerFirst :: String -> String
lowerFirst [] = []
lowerFirst (c : cs) = toLower c : cs
  where
    toLower ch
      | ch >= 'A' && ch <= 'Z' = toEnum (fromEnum ch + 32)
      | otherwise = ch
