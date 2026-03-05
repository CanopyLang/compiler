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
    canonicalizeWithIO,
    loadFFIContent,
    loadFFIContentWithRoot,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import Data.Foldable (traverse_)
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

-- | Canonicalize a source module with pre-loaded FFI content
--
-- This function now takes FFI content as a parameter to avoid threading issues
-- with unsafePerformIO. The FFI content should be read before canonicalization
-- in the IO monad and passed through the compilation pipeline.
--
-- @since 0.19.1
canonicalize :: Pkg.Name -> ProjectType -> Map ModuleName.Raw Interface.Interface -> Map JsSourcePath JsSource -> Src.Module -> Result i [Warning.Warning] Can.Module
canonicalize pkg projectType ifaces ffiContentMap modul@(Src.Module _ exports docs imports foreignImports values _ _ binops effects _) =
  do
    let home = ModuleName.Canonical pkg (Src.getName modul)
    let cbinops = Map.fromList (fmap canonicalizeBinop binops)

    -- Validate lazy imports before environment creation (they are excluded
    -- from Foreign.createInitialEnv to avoid spurious ImportNotFound errors)
    lazySet <- validateAndCollectLazyImports pkg projectType home ifaces imports

    let eagerImports = filter (not . Src._importLazy) imports

    (env, cunions, caliases) <-
      Foreign.createInitialEnv home ifaces eagerImports >>= Local.add modul

    -- Process FFI imports and add to environment using pre-loaded content
    envWithFFI <- FFI.addFFIToEnvPure env foreignImports ffiContentMap

    -- Emit capability warnings for FFI functions with @capability annotations
    let capWarnings = concatMap (emitCapabilityWarnings ffiContentMap) foreignImports
    traverse_ Result.warn capWarnings

    cvalues <- canonicalizeValues envWithFFI values
    ceffects <- Effects.canonicalize envWithFFI values cunions effects
    let derivedNames = collectDerivedFunctionNames cunions caliases
    cexports <- canonicalizeExports values derivedNames cunions caliases cbinops ceffects exports
    cguards <- canonicalizeGuards envWithFFI values

    return $ Can.Module home cexports docs cvalues cunions caliases cbinops ceffects lazySet cguards

-- | Legacy canonicalize function for backward compatibility
--
-- This function maintains the old signature for existing code but internally
-- handles FFI file reading. This should be replaced with the new signature
-- that takes pre-loaded FFI content.
--
-- @deprecated Use canonicalize with pre-loaded FFI content instead
canonicalizeWithIO :: Pkg.Name -> Map ModuleName.Raw Interface.Interface -> Src.Module -> IO (Result i [Warning.Warning] Can.Module)
canonicalizeWithIO pkg ifaces modul@(Src.Module _ _ _ _ foreignImports _ _ _ _ _ _) = do
  -- Pre-load FFI content
  ffiContentMap <- FFI.loadFFIContent foreignImports
  return $ canonicalize pkg Application ifaces ffiContentMap modul

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
validateAndCollectLazyImports ::
  Pkg.Name ->
  ProjectType ->
  ModuleName.Canonical ->
  Map ModuleName.Raw Interface.Interface ->
  [Src.Import] ->
  Result i w (Set ModuleName.Canonical)
validateAndCollectLazyImports pkg projectType home ifaces imports =
  fmap Set.fromList (traverse (validateOneLazy pkg projectType home ifaces) lazyImports)
  where
    lazyImports = filter Src._importLazy imports

-- | Validate a single lazy import and resolve to its canonical name.
validateOneLazy ::
  Pkg.Name ->
  ProjectType ->
  ModuleName.Canonical ->
  Map ModuleName.Raw Interface.Interface ->
  Src.Import ->
  Result i w ModuleName.Canonical
validateOneLazy pkg projectType home ifaces (Src.Import (Ann.At region name) _ _ _) =
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
detectCycles sccs =
  case sccs of
    [] ->
      Result.ok Can.SaveTheEnvironment
    scc : otherSccs ->
      case scc of
        Graph.AcyclicSCC (def, _, _) ->
          Can.Declare def <$> detectCycles otherSccs
        Graph.CyclicSCC subNodes ->
          do
            defs <- traverse detectBadCycles (Graph.stronglyConnComp subNodes)
            case defs of
              [] -> detectCycles otherSccs
              d : ds -> Can.DeclareRec d ds <$> detectCycles otherSccs

detectBadCycles :: Graph.SCC Can.Def -> Result i w Can.Def
detectBadCycles scc =
  case scc of
    Graph.AcyclicSCC def ->
      Result.ok def
    Graph.CyclicSCC [] ->
      InternalError.report "Canonicalize.Module.detectBadCycles" "Empty CyclicSCC from Data.Graph" "Data.Graph.SCC should never produce an empty CyclicSCC list."
    Graph.CyclicSCC (def : defs) ->
      let (Ann.At region name) = extractDefName def
          names = fmap (Ann.toValue . extractDefName) defs
       in Result.throw (Error.RecursiveDecl region name names)

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

toNodeOne :: Env.Env -> Ann.Located Src.Value -> Result i [Warning.Warning] NodeOne
toNodeOne env (Ann.At _ (Src.Value aname@(Ann.At _ name) srcArgs body maybeType _maybeGuard)) =
  case maybeType of
    Nothing ->
      do
        (args, argBindings) <-
          Pattern.verify (Error.DPFuncArgs name) $
            traverse (Pattern.canonicalize env) srcArgs

        newEnv <-
          Env.addLocals argBindings env

        (cbody, freeLocals) <-
          Expr.verifyBindings Warning.Pattern argBindings (Expr.canonicalize newEnv body)

        let def = Can.Def aname args cbody
        return
          ( toNodeTwo name srcArgs def freeLocals,
            name,
            Map.keys freeLocals
          )
    Just srcType ->
      do
        (Can.Forall freeVars tipe) <- Type.toAnnotation env srcType

        ((args, resultType), argBindings) <-
          Pattern.verify (Error.DPFuncArgs name) $
            Expr.gatherTypedArgs env name srcArgs tipe Index.first []

        newEnv <-
          Env.addLocals argBindings env

        (cbody, freeLocals) <-
          Expr.verifyBindings Warning.Pattern argBindings (Expr.canonicalize newEnv body)

        let def = Can.TypedDef aname freeVars args cbody resultType
        return
          ( toNodeTwo name srcArgs def freeLocals,
            name,
            Map.keys freeLocals
          )

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
  Map.Map Name.Name union ->
  Map.Map Name.Name alias ->
  Map.Map Name.Name binop ->
  Can.Effects ->
  Ann.Located Src.Exposing ->
  Result i w Can.Exports
canonicalizeExports values derivedNames unions aliases binops effects (Ann.At region exposing) =
  case exposing of
    Src.Open ->
      Result.ok (Can.ExportEverything region)
    Src.Explicit exposeds ->
      do
        let names = Map.union (Map.fromList (fmap valueToName values)) derivedNames
        infos <- traverse (checkExposed names unions aliases binops effects) exposeds
        Can.Export <$> Dups.detect Error.ExportDuplicate (Dups.unions infos)

valueToName :: Ann.Located Src.Value -> (Name.Name, ())
valueToName (Ann.At _ (Src.Value (Ann.At _ name) _ _ _ _)) =
  (name, ())

checkExposed ::
  Map Name.Name value ->
  Map Name.Name union ->
  Map Name.Name alias ->
  Map Name.Name binop ->
  Can.Effects ->
  Src.Exposed ->
  Result i w (Dups.Dict (Ann.Located Can.Export))
checkExposed values unions aliases binops effects exposed =
  case exposed of
    Src.Lower (Ann.At region name) ->
      if Map.member name values
        then ok name region Can.ExportValue
        else case checkPorts effects name of
          Nothing ->
            ok name region Can.ExportPort
          Just ports ->
            Result.throw . Error.ExportNotFound region Error.BadVar name $ (ports <> Map.keys values)
    Src.Operator region name ->
      if Map.member name binops
        then ok name region Can.ExportBinop
        else Result.throw . Error.ExportNotFound region Error.BadOp name $ Map.keys binops
    Src.Upper (Ann.At region name) (Src.Public dotDotRegion) ->
      if Map.member name unions
        then ok name region Can.ExportUnionOpen
        else
          if Map.member name aliases
            then Result.throw $ Error.ExportOpenAlias dotDotRegion name
            else Result.throw . Error.ExportNotFound region Error.BadType name $ (Map.keys unions <> Map.keys aliases)
    Src.Upper (Ann.At region name) Src.Private ->
      if Map.member name unions
        then ok name region Can.ExportUnionClosed
        else
          if Map.member name aliases
            then ok name region Can.ExportAlias
            else Result.throw . Error.ExportNotFound region Error.BadType name $ (Map.keys unions <> Map.keys aliases)

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
        Can.DeriveShow ->
          Map.insert (Name.fromChars ("show" ++ nameChars)) () acc
        Can.DeriveOrd ->
          acc
        Can.DeriveJsonEncode _ ->
          Map.insert (Name.fromChars ("encode" ++ nameChars)) () acc
        Can.DeriveJsonDecode _ ->
          Map.insert (Name.fromChars (lowerFirst nameChars ++ "Decoder")) () acc

lowerFirst :: String -> String
lowerFirst [] = []
lowerFirst (c : cs) = toLower c : cs
  where
    toLower ch
      | ch >= 'A' && ch <= 'Z' = toEnum (fromEnum ch + 32)
      | otherwise = ch
