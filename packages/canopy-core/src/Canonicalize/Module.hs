{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wall #-}

module Canonicalize.Module
  ( canonicalize,
    canonicalizeWithIO,
    loadFFIContent,
    loadFFIContentWithRoot,
  )
where

import qualified AST.Canonical as Can
import qualified AST.Source as Src
import qualified Canonicalize.Effects as Effects
import qualified Canonicalize.Environment as Env
import qualified Canonicalize.Environment.Dups as Dups
import qualified Canonicalize.Environment.Foreign as Foreign
import qualified Canonicalize.Environment.Local as Local
import qualified Canonicalize.Expression as Expr
import qualified Canonicalize.Pattern as Pattern
import qualified Canonicalize.Type as Type
import qualified Canopy.Interface as I
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.Graph as Graph
import qualified Data.Index as Index
import qualified Debug.Trace as Debug
import Data.List (isPrefixOf, isInfixOf)
import qualified Data.List as List
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Name as Name
import qualified Data.Text as Text
import qualified Foreign.FFI as FFI
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified Reporting.Warning as W
import Control.Exception (SomeException, catch)
import System.FilePath ((</>))

-- RESULT

type Result i w a =
  Result.Result i w Error.Error a

-- MODULES

-- | Canonicalize a source module with pre-loaded FFI content
--
-- This function now takes FFI content as a parameter to avoid threading issues
-- with unsafePerformIO. The FFI content should be read before canonicalization
-- in the IO monad and passed through the compilation pipeline.
--
-- @since 0.19.1
canonicalize :: Pkg.Name -> Map ModuleName.Raw I.Interface -> Map String String -> Src.Module -> Result i [W.Warning] Can.Module
canonicalize pkg ifaces ffiContentMap modul@(Src.Module _ exports docs imports foreignImports values _ _ binops effects) =
  do
    let home = ModuleName.Canonical pkg (Src.getName modul)
    let cbinops = Map.fromList (fmap canonicalizeBinop binops)
    let _ = Debug.trace ("DEBUG canonicalize home=" ++ show home ++ " pkg=" ++ show pkg) ()

    (env, cunions, caliases) <-
      Foreign.createInitialEnv home ifaces imports >>= Local.add modul

    -- Process FFI imports and add to environment using pre-loaded content
    envWithFFI <- addFFIToEnvPure env foreignImports ffiContentMap

    cvalues <- canonicalizeValues envWithFFI values
    ceffects <- Effects.canonicalize envWithFFI values cunions effects
    cexports <- canonicalizeExports values cunions caliases cbinops ceffects exports

    return $ Can.Module home cexports docs cvalues cunions caliases cbinops ceffects

-- | Legacy canonicalize function for backward compatibility
--
-- This function maintains the old signature for existing code but internally
-- handles FFI file reading. This should be replaced with the new signature
-- that takes pre-loaded FFI content.
--
-- @deprecated Use canonicalize with pre-loaded FFI content instead
canonicalizeWithIO :: Pkg.Name -> Map ModuleName.Raw I.Interface -> Src.Module -> IO (Result i [W.Warning] Can.Module)
canonicalizeWithIO pkg ifaces modul@(Src.Module _ _ _ _ foreignImports _ _ _ _ _) = do
  -- Pre-load FFI content
  ffiContentMap <- loadFFIContent foreignImports
  return $ canonicalize pkg ifaces ffiContentMap modul

-- CANONICALIZE BINOP

canonicalizeBinop :: A.Located Src.Infix -> (Name.Name, Can.Binop)
canonicalizeBinop (A.At _ (Src.Infix op associativity precedence func)) =
  (op, Can.Binop_ associativity precedence func)

-- DECLARATIONS / CYCLE DETECTION
--
-- There are two phases of cycle detection:
--
-- 1. Detect cycles using ALL dependencies => needed for type inference
-- 2. Detect cycles using DIRECT dependencies => nonterminating recursion
--

canonicalizeValues :: Env.Env -> [A.Located Src.Value] -> Result i [W.Warning] Can.Decls
canonicalizeValues env values =
  do
    nodes <- traverse (toNodeOne env) values
    detectCycles (Graph.stronglyConnComp nodes)

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
      error "The definition of Data.Graph.SCC should not allow empty CyclicSCC!"
    Graph.CyclicSCC (def : defs) ->
      let (A.At region name) = extractDefName def
          names = fmap (A.toValue . extractDefName) defs
       in Result.throw (Error.RecursiveDecl region name names)

extractDefName :: Can.Def -> A.Located Name.Name
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

toNodeOne :: Env.Env -> A.Located Src.Value -> Result i [W.Warning] NodeOne
toNodeOne env (A.At _ (Src.Value aname@(A.At _ name) srcArgs body maybeType)) =
  case maybeType of
    Nothing ->
      do
        (args, argBindings) <-
          Pattern.verify (Error.DPFuncArgs name) $
            traverse (Pattern.canonicalize env) srcArgs

        newEnv <-
          Env.addLocals argBindings env

        (cbody, freeLocals) <-
          Expr.verifyBindings W.Pattern argBindings (Expr.canonicalize newEnv body)

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
          Expr.verifyBindings W.Pattern argBindings (Expr.canonicalize newEnv body)

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
  [A.Located Src.Value] ->
  Map.Map Name.Name union ->
  Map.Map Name.Name alias ->
  Map.Map Name.Name binop ->
  Can.Effects ->
  A.Located Src.Exposing ->
  Result i w Can.Exports
canonicalizeExports values unions aliases binops effects (A.At region exposing) =
  case exposing of
    Src.Open ->
      Result.ok (Can.ExportEverything region)
    Src.Explicit exposeds ->
      do
        let names = Map.fromList (fmap valueToName values)
        infos <- traverse (checkExposed names unions aliases binops effects) exposeds
        Can.Export <$> Dups.detect Error.ExportDuplicate (Dups.unions infos)

valueToName :: A.Located Src.Value -> (Name.Name, ())
valueToName (A.At _ (Src.Value (A.At _ name) _ _ _)) =
  (name, ())

checkExposed ::
  Map Name.Name value ->
  Map Name.Name union ->
  Map Name.Name alias ->
  Map Name.Name binop ->
  Can.Effects ->
  Src.Exposed ->
  Result i w (Dups.Dict (A.Located Can.Export))
checkExposed values unions aliases binops effects exposed =
  case exposed of
    Src.Lower (A.At region name) ->
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
    Src.Upper (A.At region name) (Src.Public dotDotRegion) ->
      if Map.member name unions
        then ok name region Can.ExportUnionOpen
        else
          if Map.member name aliases
            then Result.throw $ Error.ExportOpenAlias dotDotRegion name
            else Result.throw . Error.ExportNotFound region Error.BadType name $ (Map.keys unions <> Map.keys aliases)
    Src.Upper (A.At region name) Src.Private ->
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

ok :: Name.Name -> A.Region -> Can.Export -> Result i w (Dups.Dict (A.Located Can.Export))
ok name region export =
  Result.ok $ Dups.one name region (A.At region export)

-- FFI SUPPORT

-- | Load FFI content from foreign imports in the IO monad
--
-- This function reads JavaScript files referenced in foreign imports
-- and returns a map of file paths to their content. This should be called
-- before canonicalization to avoid threading issues.
--
-- @since 0.19.1
loadFFIContent :: [Src.ForeignImport] -> IO (Map String String)
loadFFIContent = loadFFIContentWithRoot "."

-- | Load FFI content with explicit root directory for path resolution
loadFFIContentWithRoot :: FilePath -> [Src.ForeignImport] -> IO (Map String String)
loadFFIContentWithRoot rootDir foreignImports = do
  results <- traverse loadSingleFFI foreignImports
  return $ Map.fromList (concat results)
  where
    loadSingleFFI :: Src.ForeignImport -> IO [(String, String)]
    loadSingleFFI (Src.ForeignImport (FFI.JavaScriptFFI jsPath) _alias _region) = do
      let fullPath = rootDir </> jsPath
      result <- try (readFile fullPath)
      case result of
        Left (_ :: SomeException) -> return []
        Right content -> do
          -- FFI content is now passed directly through canonicalization pipeline
          -- No need for global storage which can cause threading issues
          return [(jsPath, content)]
    loadSingleFFI _ = return []

    try :: IO a -> IO (Either SomeException a)
    try action = (Right <$> action) `catch` (return . Left)

-- | Add FFI functions to environment using pre-loaded content (pure)
--
-- This is the pure version of addFFIToEnv that works with pre-loaded
-- FFI content instead of performing IO operations with unsafePerformIO.
--
-- @since 0.19.1
addFFIToEnvPure :: Env.Env -> [Src.ForeignImport] -> Map String String -> Result i [W.Warning] Env.Env
addFFIToEnvPure env foreignImports ffiContentMap =
  case foreignImports of
    [] ->
      Result.ok env
    [Src.ForeignImport (FFI.JavaScriptFFI jsPath) alias _region] ->
      let aliasName = A.toValue alias
          home = Env._home env
          ffiModuleName = ModuleName.Canonical (ModuleName._package home) aliasName
      in case Map.lookup jsPath ffiContentMap of
           Nothing -> Result.throw (Error.ImportNotFound A.one (Name.fromChars jsPath) [])
           Just jsContent ->
             case parseJavaScriptContentPure jsContent (Name.toChars aliasName) of
               Left _err -> Result.throw (Error.ImportNotFound A.one (Name.fromChars jsPath) [])
               Right functions -> addParsedFunctionsToEnv env ffiModuleName aliasName functions
    _fis ->
      -- Multiple foreign imports not yet supported
      Result.ok env

-- | Parse JavaScript content purely without IO operations
--
-- This replaces the problematic parseJavaScriptFile function that used
-- unsafePerformIO for file reading.
--
-- @since 0.19.1
parseJavaScriptContentPure :: String -> String -> Either String [(String, String)]
parseJavaScriptContentPure jsContent _alias =
  Right (extractFunctionsWithTypes (lines jsContent))


-- Extract functions with their @canopy-type annotations
-- Now properly handles JSDoc comments with @name and @canopy-type annotations
extractFunctionsWithTypes :: [String] -> [(String, String)]
extractFunctionsWithTypes [] = []
extractFunctionsWithTypes inputLines = extractFromJSDocBlocks inputLines

-- Extract functions from JSDoc comment blocks
extractFromJSDocBlocks :: [String] -> [(String, String)]
extractFromJSDocBlocks [] = []
extractFromJSDocBlocks (line:rest)
  | isJSDocStart line =
      let (commentBlock, remaining) = takeJSDocBlock (line:rest)
          mbFunction = parseJSDocBlock commentBlock
      in case mbFunction of
           Just func -> func : extractFromJSDocBlocks remaining
           Nothing -> extractFromJSDocBlocks remaining
  | otherwise = extractFromJSDocBlocks rest

-- Check if line starts a JSDoc comment
isJSDocStart :: String -> Bool
isJSDocStart line =
  let trimmed = dropWhile (`elem` (" \t" :: String)) line
  in "/**" `isPrefixOf` trimmed

-- Take a complete JSDoc comment block
takeJSDocBlock :: [String] -> ([String], [String])
takeJSDocBlock [] = ([], [])
takeJSDocBlock (line:rest) =
  if isJSDocEnd line
    then ([line], rest)
    else let (block, remaining) = takeJSDocBlock rest
         in (line:block, remaining)

-- Check if line ends a JSDoc comment
isJSDocEnd :: String -> Bool
isJSDocEnd line = "*/" `isInfixOf` line

-- Parse a JSDoc comment block to extract function name and type
parseJSDocBlock :: [String] -> Maybe (String, String)
parseJSDocBlock commentLines = do
  functionName <- findNameAnnotation commentLines
  canopyType <- findCanopyTypeAnnotation commentLines
  pure (functionName, canopyType)

-- Find @name annotation in JSDoc block
findNameAnnotation :: [String] -> Maybe String
findNameAnnotation [] = Nothing
findNameAnnotation (line:rest) =
  case parseNameAnnotation line of
    Just name -> Just name
    Nothing -> findNameAnnotation rest

-- Find @canopy-type annotation in JSDoc block
findCanopyTypeAnnotation :: [String] -> Maybe String
findCanopyTypeAnnotation [] = Nothing
findCanopyTypeAnnotation (line:rest) =
  case parseCanopyTypeAnnotation line of
    Just typeStr -> Just typeStr
    Nothing -> findCanopyTypeAnnotation rest

-- Parse @name annotation from a line
parseNameAnnotation :: String -> Maybe String
parseNameAnnotation line =
  let trimmed = dropWhile (`elem` (" *" :: String)) line
  in if ("@name " :: String) `isPrefixOf` trimmed
     then Just (strip (drop (length ("@name " :: String)) trimmed))
     else Nothing

-- Strip leading and trailing whitespace
strip :: String -> String
strip = dropWhileEnd (`elem` (" \t\n\r" :: String)) . dropWhile (`elem` (" \t\n\r" :: String))
  where
    dropWhileEnd predicate xs = foldr (\x acc -> if predicate x && null acc then [] else x:acc) [] xs

-- Parse @canopy-type annotation from a line
parseCanopyTypeAnnotation :: String -> Maybe String
parseCanopyTypeAnnotation line =
  let trimmed = dropWhile (`elem` (" *" :: String)) line
  in if ("@canopy-type " :: String) `isPrefixOf` trimmed
     then Just (drop (length ("@canopy-type " :: String)) trimmed)
     else Nothing


-- DYNAMIC FUNCTION ENVIRONMENT GENERATION
addParsedFunctionsToEnv :: Env.Env -> ModuleName.Canonical -> Name.Name -> [(String, String)] -> Result i [W.Warning] Env.Env
addParsedFunctionsToEnv env ffiModuleName aliasName functions = do
  -- Get the home module for type resolution
  let homeModuleName = Env._home env
  -- Dynamically process each parsed function
  processedFunctions <- traverse (processParsedFunction ffiModuleName homeModuleName) functions

  -- Build environment dynamically
  let (vars, qVars) = buildDynamicEnvironment aliasName processedFunctions
      newVars = List.foldl' (\acc (name, var) -> Map.insert name var acc) (Env._vars env) vars
      newQVars = Map.insertWith Map.union aliasName qVars (Env._q_vars env)
      newEnv = env { Env._vars = newVars, Env._q_vars = newQVars }

  Result.ok newEnv

-- Process a single parsed function (name, typeString) into Canopy types
processParsedFunction :: ModuleName.Canonical -> ModuleName.Canonical -> (String, String) -> Result i [W.Warning] (String, Can.Annotation, Env.Var)
processParsedFunction ffiModuleName homeModuleName (functionName, typeString) = do
  -- Parse the type string into actual Canopy types
  canopyType <- parseTypeStringWithHome homeModuleName typeString
  let annotation = Can.Forall Map.empty canopyType
      var = Env.Foreign ffiModuleName annotation
  Result.ok (functionName, annotation, var)

-- Build the dynamic environment from processed functions
buildDynamicEnvironment :: Name.Name -> [(String, Can.Annotation, Env.Var)] -> ([(Name.Name, Env.Var)], Map.Map Name.Name (Env.Info Can.Annotation))
buildDynamicEnvironment aliasName processedFunctions =
  let ffiModuleName = ModuleName.Canonical Pkg.dummyName aliasName

      -- Build vars with qualified names (Module.functionName)
      vars = List.map (\(fname, _, var) ->
               (Name.fromChars (Name.toChars aliasName ++ "." ++ fname), var)
             ) processedFunctions

      -- Build qualified vars (Module.functionName syntax)
      qVars = Map.fromList (List.map (\(fname, annotation, _) ->
                (Name.fromChars fname, Env.Specific ffiModuleName annotation)
              ) processedFunctions)

  in (vars, qVars)


-- Parse type string with home module context for custom type resolution
parseTypeStringWithHome :: ModuleName.Canonical -> String -> Result i [W.Warning] Can.Type
parseTypeStringWithHome homeModuleName typeStr =
  case parseTypeTokensWithHome homeModuleName (tokenizeCanopyType (Text.pack typeStr)) of
    Just canopyType -> Result.ok canopyType
    Nothing -> Result.throw (Error.ImportNotFound A.one (Name.fromChars typeStr) [])

-- Tokenize Canopy type string correctly, handling multi-word types
-- First split by arrows, then handle each segment as a potentially multi-word type
tokenizeCanopyType :: Text.Text -> [String]
tokenizeCanopyType typeText =
  let arrowSegments = Text.splitOn "->" typeText
      nonEmptySegments = filter (not . Text.null . Text.strip) arrowSegments
      processedSegments = map (Text.unpack . Text.strip) nonEmptySegments
  in case processedSegments of
       [] -> []
       [single] -> [single]  -- No arrows, just a single type
       multiple -> List.intercalate ["->"] (map (:[]) multiple)  -- Insert arrows between segments


-- Parse type tokens with home module context for custom type resolution
parseTypeTokensWithHome :: ModuleName.Canonical -> [String] -> Maybe Can.Type
parseTypeTokensWithHome homeModuleName tokens =
  case tokens of
    [] -> Nothing
    [typeName] -> Just (parseBasicTypeWithHome homeModuleName typeName)
    ["(", ")"] -> Just (Can.TType ModuleName.basics (Name.fromChars "Unit") [])
    (t1 : "->" : rest) ->
      case parseTypeTokensWithHome homeModuleName rest of
        Just restType -> Just (Can.TLambda (parseComplexTypeWithHome homeModuleName [t1]) restType)
        Nothing -> Nothing
    _ -> Just (parseComplexTypeWithHome homeModuleName tokens)


-- Parse complex types with home module context
parseComplexTypeWithHome :: ModuleName.Canonical -> [String] -> Can.Type
parseComplexTypeWithHome homeModuleName tokens =
  case tokens of
    [] -> Can.TType ModuleName.basics (Name.fromChars "Unit") []
    ["(", ")"] -> Can.TType ModuleName.basics (Name.fromChars "Unit") []
    [typeName] -> parseBasicTypeWithHome homeModuleName typeName
    ("Task" : errorType : resultType : _rest) ->
      -- Handle Task types: Task ErrorType ResultType -> Task is from Platform module, error/result types are resolved dynamically
      Can.TType ModuleName.platform (Name.fromChars "Task") [parseBasicTypeWithHome homeModuleName errorType, parseBasicTypeWithHome homeModuleName resultType]
    multiWordTokens ->
      -- Handle multi-word types like "Initialized AudioContext" as a single opaque type
      let typeName = unwords multiWordTokens
      in parseBasicTypeWithHome homeModuleName typeName


-- Parse basic type names with home module context for custom types
parseBasicTypeWithHome :: ModuleName.Canonical -> String -> Can.Type
parseBasicTypeWithHome homeModuleName typeName =
  case typeName of
    -- Core basic types from standard library
    "Int" -> Can.TType ModuleName.basics (Name.fromChars "Int") []
    "Float" -> Can.TType ModuleName.basics (Name.fromChars "Float") []
    "Bool" -> Can.TType ModuleName.basics (Name.fromChars "Bool") []
    "String" -> Can.TType ModuleName.string (Name.fromChars "String") []
    "()" -> Can.TType ModuleName.basics (Name.fromChars "Unit") []
    "Unit" -> Can.TType ModuleName.basics (Name.fromChars "Unit") []

    -- Capability types - resolve to core package for consistency
    "UserActivated" -> Can.TType ModuleName.capability (Name.fromChars "UserActivated") []
    "Initialized" -> Can.TType ModuleName.capability (Name.fromChars "Initialized") []
    "Permitted" -> Can.TType ModuleName.capability (Name.fromChars "Permitted") []
    "Available" -> Can.TType ModuleName.capability (Name.fromChars "Available") []
    "CapabilityError" -> Can.TType ModuleName.capability (Name.fromChars "CapabilityError") []

    -- Task type (from Platform module in core package)
    "Task" -> Can.TType ModuleName.platform (Name.fromChars "Task") []

    -- Type variables (single lowercase letters) - treat as opaque for now
    [ch] | ch >= 'a' && ch <= 'z' -> Can.TType homeModuleName (Name.fromChars typeName) []

    -- Custom opaque types (AudioContext, OscillatorNode, GainNode, etc.)
    -- These should resolve to the home module where they are defined
    customType -> Can.TType homeModuleName (Name.fromChars customType) []

{-
addSingleFFI :: Env.Env -> Src.ForeignImport -> Result i [W.Warning] Env.Env
addSingleFFI env (Src.ForeignImport target alias _region) =
  case target of
    FFI.JavaScriptFFI jsFilePath ->
      -- Parse the JavaScript file and add functions to environment
      case addFFIFunctions env alias jsFilePath of
        Left _errMsg -> Result.throw (Error.ImportNotFound A.one (Name.fromChars "FFI") []) -- TODO: Better error handling
        Right newEnv -> Result.ok newEnv
    FFI.WebAssemblyFFI _ ->
      -- WebAssembly not supported yet
      Result.ok env

-- NOTE: The old addFFIFunctions and readJavaScriptFile functions have been removed
-- because they used unsafePerformIO which caused MVar deadlocks during compilation.
-- All FFI processing now uses the safe addFFIToEnvPure approach with pre-loaded content.

addFFIFunctionsToEnv :: Env.Env -> ModuleName.Canonical -> Map.Map Text.Text FFI.FFIFunction -> Env.Env
addFFIFunctionsToEnv env ffiModuleName ffiFunctions =
  let aliasName = ModuleName._module ffiModuleName
      vars = Env._vars env
      qVars = Env._q_vars env

      -- Convert each FFI function to environment entries
      (newVars, newQVars) = Map.foldlWithKey (addFFIFunction aliasName ffiModuleName) (vars, qVars) ffiFunctions
  in env { Env._vars = newVars, Env._q_vars = newQVars }

addFFIFunction :: Name.Name -> ModuleName.Canonical -> (Map.Map Name.Name Env.Var, Env.Qualified Can.Annotation) -> Text.Text -> FFI.FFIFunction -> (Map.Map Name.Name Env.Var, Env.Qualified Can.Annotation)
addFFIFunction aliasName ffiModuleName (vars, qVars) funcNameText ffiFunc =
  let funcName = Name.fromChars (Text.unpack funcNameText)
      canType = ffiTypeToCanonicalType (FFI.ffiFuncOutputType ffiFunc) (FFI.ffiFuncInputTypes ffiFunc)
      annotation = Can.Forall Map.empty canType
      -- FFI functions should ONLY be registered in qualified vars map to avoid duplicate globals
      -- The qualified lookup in findVarQual will find them via qVars[aliasName][funcName]
      info = Env.Specific ffiModuleName annotation
      innerMap = Map.singleton funcName info
      newQVars = Map.insertWith Map.union aliasName innerMap qVars
  in (vars, newQVars)

ffiTypeToCanonicalType :: FFI.FFIType -> [FFI.FFIType] -> Can.Type
ffiTypeToCanonicalType returnType inputTypes =
  let canReturnType = ffiTypeToCanType returnType
      canInputTypes = map ffiTypeToCanType inputTypes
  in foldr Can.TLambda canReturnType canInputTypes

ffiTypeToCanType :: FFI.FFIType -> Can.Type
ffiTypeToCanType ffiType =
  case ffiType of
    FFI.FFIBasic "Int" -> Can.TType ModuleName.basics (Name.fromChars "Int") []
    FFI.FFIBasic "Float" -> Can.TType ModuleName.basics (Name.fromChars "Float") []
    FFI.FFIBasic "String" -> Can.TType ModuleName.string (Name.fromChars "String") []
    FFI.FFIBasic "Bool" -> Can.TType ModuleName.basics (Name.fromChars "Bool") []
    FFI.FFIBasic _ -> Can.TType ModuleName.string (Name.fromChars "String") [] -- Default to String for unknown basics
    FFI.FFIMaybe innerType ->
      Can.TType ModuleName.maybe (Name.fromChars "Maybe") [ffiTypeToCanType innerType]
    FFI.FFIList innerType ->
      Can.TType ModuleName.list (Name.fromChars "List") [ffiTypeToCanType innerType]
    _ -> Can.TType ModuleName.string (Name.fromChars "String") [] -- Default to String for unsupported types
-}
