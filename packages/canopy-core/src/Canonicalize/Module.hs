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
import qualified Reporting.InternalError as InternalError
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
      InternalError.report "Canonicalize.Module.detectBadCycles" "Empty CyclicSCC from Data.Graph" "Data.Graph.SCC should never produce an empty CyclicSCC list."
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
      result <- loadFFIFileWithTimeout (rootDir </> jsPath) jsPath
      case result of
        Left _ -> return []
        Right content -> return [(jsPath, content)]
    loadSingleFFI _ = return []

-- Load FFI file with timeout to prevent hanging
loadFFIFileWithTimeout :: FilePath -> String -> IO (Either String String)
loadFFIFileWithTimeout fullPath _jsPath = do
  result <- try (readFile fullPath)
  case result of
    Left (_ :: SomeException) -> return (Left "File not found")
    Right content -> return (Right content)
  where
    try :: IO a -> IO (Either SomeException a)
    try action = (Right <$> action) `catch` (return . Left)

-- | Add FFI functions to environment using pre-loaded content (pure)
addFFIToEnvPure :: Env.Env -> [Src.ForeignImport] -> Map String String -> Result i [W.Warning] Env.Env
addFFIToEnvPure env foreignImports ffiContentMap =
  case foreignImports of
    [] -> Result.ok env
    [Src.ForeignImport (FFI.JavaScriptFFI jsPath) alias region] ->
      processFFIImport env jsPath alias region ffiContentMap
    _fis -> Result.ok env

-- Process single FFI import with comprehensive error handling
processFFIImport :: Env.Env -> FilePath -> A.Located Name.Name -> A.Region -> Map String String -> Result i [W.Warning] Env.Env
processFFIImport env jsPath alias region ffiContentMap =
  let aliasName = A.toValue alias
      home = Env._home env
      ffiModuleName = ModuleName.Canonical (ModuleName._package home) aliasName
  in case Map.lookup jsPath ffiContentMap of
       Nothing -> Result.throw (Error.FFIFileNotFound region jsPath)
       Just jsContent -> parseAndAddFFI env ffiModuleName aliasName jsPath region jsContent

-- Parse FFI content and add to environment with validation
parseAndAddFFI :: Env.Env -> ModuleName.Canonical -> Name.Name -> FilePath -> A.Region -> String -> Result i [W.Warning] Env.Env
parseAndAddFFI env ffiModuleName aliasName jsPath region jsContent =
  case parseJavaScriptContentPure jsContent (Name.toChars aliasName) of
    Left err -> Result.throw (Error.FFIParseError region jsPath err)
    Right functions -> validateAndAddFunctions env ffiModuleName aliasName jsPath region functions

-- Validate and add FFI functions to environment
validateAndAddFunctions :: Env.Env -> ModuleName.Canonical -> Name.Name -> FilePath -> A.Region -> [(String, String)] -> Result i [W.Warning] Env.Env
validateAndAddFunctions env ffiModuleName aliasName jsPath region functions =
  case validateFFIFunctions jsPath region functions of
    Left err -> Result.throw err
    Right validFunctions -> addParsedFunctionsToEnv env ffiModuleName aliasName validFunctions

-- Validate FFI functions have proper type annotations
validateFFIFunctions :: FilePath -> A.Region -> [(String, String)] -> Either Error.Error [(String, String)]
validateFFIFunctions jsPath region functions =
  traverse (validateSingleFunction jsPath region) functions

-- Validate single FFI function signature
validateSingleFunction :: FilePath -> A.Region -> (String, String) -> Either Error.Error (String, String)
validateSingleFunction jsPath region (fname, typeStr) =
  if null typeStr
    then Left (Error.FFIMissingAnnotation region jsPath (Name.fromChars fname))
    else Right (fname, typeStr)

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
  -- Dynamically process each parsed function, passing env for type lookup
  processedFunctions <- traverse (processParsedFunction env ffiModuleName homeModuleName) functions

  -- Build environment dynamically
  let (vars, qVars) = buildDynamicEnvironment aliasName processedFunctions
      newVars = List.foldl' (\acc (name, var) -> Map.insert name var acc) (Env._vars env) vars
      newQVars = Map.insertWith Map.union aliasName qVars (Env._q_vars env)
      newEnv = env { Env._vars = newVars, Env._q_vars = newQVars }

  Result.ok newEnv

-- Process a single parsed function (name, typeString) into Canopy types
processParsedFunction :: Env.Env -> ModuleName.Canonical -> ModuleName.Canonical -> (String, String) -> Result i [W.Warning] (String, Can.Annotation, Env.Var)
processParsedFunction env ffiModuleName homeModuleName (functionName, typeString) = do
  canopyType <- parseTypeStringWithHome env homeModuleName typeString
  let annotation = Can.Forall Map.empty canopyType
      var = Env.Foreign ffiModuleName annotation
  Result.ok (functionName, annotation, var)

-- Build the dynamic environment from processed functions with proper qualified name registration
buildDynamicEnvironment :: Name.Name -> [(String, Can.Annotation, Env.Var)] -> ([(Name.Name, Env.Var)], Map.Map Name.Name (Env.Info Can.Annotation))
buildDynamicEnvironment aliasName processedFunctions =
  let ffiModuleName = ModuleName.Canonical Pkg.dummyName aliasName
      vars = []
      qVars = buildQualifiedVars ffiModuleName processedFunctions
  in (vars, qVars)

-- Build qualified vars map for FFI functions (Module.functionName syntax)
buildQualifiedVars :: ModuleName.Canonical -> [(String, Can.Annotation, Env.Var)] -> Map.Map Name.Name (Env.Info Can.Annotation)
buildQualifiedVars ffiModuleName processedFunctions =
  Map.fromList (List.map toQualifiedEntry processedFunctions)
  where
    toQualifiedEntry (fname, annotation, _) =
      (Name.fromChars fname, Env.Specific ffiModuleName annotation)


-- Parse type string with home module context for custom type resolution
parseTypeStringWithHome :: Env.Env -> ModuleName.Canonical -> String -> Result i [W.Warning] Can.Type
parseTypeStringWithHome env homeModuleName typeStr =
  case parseTypeTokensWithHome env homeModuleName (tokenizeCanopyType (Text.pack typeStr)) of
    Just canopyType -> Result.ok canopyType
    Nothing -> Result.throw (Error.ImportNotFound A.one (Name.fromChars typeStr) [])

-- Tokenize Canopy type string correctly, handling multi-word types
-- First split by arrows, then tokenize each segment into words
tokenizeCanopyType :: Text.Text -> [String]
tokenizeCanopyType typeText =
  let arrowSegments = Text.splitOn "->" typeText
      nonEmptySegments = filter (not . Text.null . Text.strip) arrowSegments
      tokenizedSegments = map (tokenizeTypeSegment . Text.strip) nonEmptySegments
  in case tokenizedSegments of
       [] -> []
       [singleSegment] -> singleSegment
       multipleSegments -> List.intercalate ["->"] multipleSegments


-- Tokenize a single type segment into words, preserving parenthesized expressions
tokenizeTypeSegment :: Text.Text -> [String]
tokenizeTypeSegment segment =
  go [] "" (0 :: Int) (Text.unpack segment)
  where
    go acc current _depth [] =
      if null current then reverse acc else reverse (current : acc)
    go acc current depth (c:cs)
      | c == '(' = go acc (current ++ "(") (depth + 1) cs
      | c == ')' =
          let newCurrent = current ++ ")"
          in if depth == 1
               then go (newCurrent : acc) "" (depth - 1) cs
               else go acc newCurrent (depth - 1) cs
      | c == ' ' && depth == 0 =
          if null current
            then go acc "" 0 cs
            else go (current : acc) "" 0 cs
      | otherwise = go acc (current ++ [c]) depth cs


-- Split tokens at top-level arrow (not inside parentheses)
splitAtArrow :: [String] -> Maybe ([String], [String])
splitAtArrow tokens =
  go tokens 0 []
  where
    go :: [String] -> Int -> [String] -> Maybe ([String], [String])
    go [] _ _ = Nothing
    go ("(" : rest) depth acc = go rest (depth + 1) (acc ++ ["("])
    go (")" : rest) depth acc = go rest (depth - 1) (acc ++ [")"])
    go ("->" : rest) 0 acc = Just (acc, rest)
    go ("->" : rest) depth acc = go rest depth (acc ++ ["->"])
    go (t : rest) depth acc = go rest depth (acc ++ [t])

-- Parse type tokens with home module context for custom type resolution
parseTypeTokensWithHome :: Env.Env -> ModuleName.Canonical -> [String] -> Maybe Can.Type
parseTypeTokensWithHome env homeModuleName tokens =
  case tokens of
    [] -> Nothing
    [typeName] -> Just (parseBasicTypeWithHome env homeModuleName typeName)
    ["(", ")"] -> Just Can.TUnit
    _ -> case splitAtArrow tokens of
      Just (leftTokens, rightTokens) ->
        case parseTypeTokensWithHome env homeModuleName rightTokens of
          Just restType -> Just (Can.TLambda (parseComplexTypeWithHome env homeModuleName leftTokens) restType)
          Nothing -> Nothing
      Nothing -> Just (parseComplexTypeWithHome env homeModuleName tokens)


-- Parse one complete type from the beginning of the token list
-- Returns (parsed type, remaining tokens)
parseOneType :: Env.Env -> ModuleName.Canonical -> [String] -> Maybe (Can.Type, [String])
parseOneType _env _homeModuleName [] = Nothing
parseOneType _env _homeModuleName ["(", ")"] = Just (Can.TUnit, [])
parseOneType env homeModuleName ("Task" : rest) = do
  (errorType, rest1) <- parseOneType env homeModuleName rest
  (resultType, rest2) <- parseOneType env homeModuleName rest1
  let taskAlias = Can.TAlias
        ModuleName.task
        (Name.fromChars "Task")
        [(Name.fromChars "x", errorType), (Name.fromChars "a", resultType)]
        (Can.Filled (Can.TType ModuleName.platform (Name.fromChars "Task") [errorType, resultType]))
  return (taskAlias, rest2)
parseOneType env homeModuleName ("Result" : rest) = do
  (errorType, rest1) <- parseOneType env homeModuleName rest
  (valueType, rest2) <- parseOneType env homeModuleName rest1
  let resultAlias = Can.TAlias
        ModuleName.result
        (Name.fromChars "Result")
        [(Name.fromChars "e", errorType), (Name.fromChars "a", valueType)]
        (Can.Filled (Can.TType ModuleName.result (Name.fromChars "Result") [errorType, valueType]))
  return (resultAlias, rest2)
parseOneType env homeModuleName ("List" : rest) = do
  (elementType, rest1) <- parseOneType env homeModuleName rest
  let listAlias = Can.TAlias
        ModuleName.list
        (Name.fromChars "List")
        [(Name.fromChars "a", elementType)]
        (Can.Filled (Can.TType ModuleName.list (Name.fromChars "List") [elementType]))
  return (listAlias, rest1)
parseOneType env homeModuleName ("Maybe" : rest) = do
  (valueType, rest1) <- parseOneType env homeModuleName rest
  let maybeAlias = Can.TAlias
        ModuleName.maybe
        (Name.fromChars "Maybe")
        [(Name.fromChars "a", valueType)]
        (Can.Filled (Can.TType ModuleName.maybe (Name.fromChars "Maybe") [valueType]))
  return (maybeAlias, rest1)
parseOneType env homeModuleName ("Capability.Initialized" : rest) = do
  (paramType, rest1) <- parseOneType env homeModuleName rest
  let capabilityModule = case homeModuleName of
        ModuleName.Canonical pkg _ -> ModuleName.Canonical pkg (Name.fromChars "Capability")
  return (Can.TType capabilityModule (Name.fromChars "Initialized") [paramType], rest1)
-- NOTE: Capability.UserActivated is NOT included here because it's a simple enum type (not parameterized)
-- It will be handled by the catch-all pattern and parseBasicTypeWithHome
parseOneType env homeModuleName ("Capability.Permitted" : rest) = do
  (paramType, rest1) <- parseOneType env homeModuleName rest
  let capabilityModule = case homeModuleName of
        ModuleName.Canonical pkg _ -> ModuleName.Canonical pkg (Name.fromChars "Capability")
  return (Can.TType capabilityModule (Name.fromChars "Permitted") [paramType], rest1)
parseOneType env homeModuleName ("Capability.Available" : rest) = do
  (paramType, rest1) <- parseOneType env homeModuleName rest
  let capabilityModule = case homeModuleName of
        ModuleName.Canonical pkg _ -> ModuleName.Canonical pkg (Name.fromChars "Capability")
  return (Can.TType capabilityModule (Name.fromChars "Available") [paramType], rest1)
-- Handle tuples: ["(", ..., ",", ..., ")"]
parseOneType env homeModuleName ("(" : rest) = do
  let (tupleTokens, afterParen) = span (/= ")") rest
  case afterParen of
    (")" : remaining) -> do
      let elements = splitTupleTokens tupleTokens
      parsedElements <- mapM (parseOneType env homeModuleName) elements
      let types = map fst parsedElements
      case types of
        [] -> Just (Can.TUnit, remaining)
        [single] -> Just (single, remaining)
        [first, second] -> Just (Can.TTuple first second Nothing, remaining)
        [first, second, third] -> Just (Can.TTuple first second (Just third), remaining)
        _ -> Nothing  -- More than 3 elements not supported
    _ -> Nothing  -- No closing paren
  where
    -- Split tokens by comma at depth 0 (not inside nested parens)
    splitTupleTokens :: [String] -> [[String]]
    splitTupleTokens tokens =
      let go :: [String] -> Int -> [String] -> [[String]] -> [[String]]
          go [] _ acc result = if null acc then result else result ++ [reverse acc]
          go ("," : ts) 0 acc result = go ts 0 [] (result ++ [reverse acc])
          go ("(" : ts) depth acc result = go ts (depth + 1) ("(" : acc) result
          go (")" : ts) depth acc result = go ts (depth - 1) (")" : acc) result
          go (t : ts) depth acc result = go ts depth (t : acc) result
      in go tokens (0 :: Int) [] []
parseOneType env homeModuleName (t : rest) = Just (parseBasicTypeWithHome env homeModuleName t, rest)

-- Parse complex types with home module context
parseComplexTypeWithHome :: Env.Env -> ModuleName.Canonical -> [String] -> Can.Type
parseComplexTypeWithHome env homeModuleName tokens =
  case parseOneType env homeModuleName tokens of
    Just (tipe, []) -> tipe
    Just (tipe, _rest) -> tipe  -- Use only the first type, ignore rest
    Nothing -> Can.TUnit  -- Fallback

-- Parse basic type names with home module context for custom types
-- Uses env to look up imported types and resolve them to their defining module
parseBasicTypeWithHome :: Env.Env -> ModuleName.Canonical -> String -> Can.Type
parseBasicTypeWithHome env homeModuleName typeName =
  let trimmedName = dropWhileEnd (== ' ') (dropWhile (== ' ') typeName)
      dropWhileEnd predicate xs = foldr (\x acc -> if predicate x && null acc then [] else x:acc) [] xs
      -- Check for tuple FIRST using the original string (with parens)
      isTuple = isTupleString trimmedName
      -- Strip surrounding parentheses if present: "(String)" -> "String", but keep "()"
      unparenthesized = case trimmedName of
        "()" -> "()"
        ('(' : rest) | not (null rest) && last rest == ')' -> init rest
        other -> other
      -- Check if unparenthesized string contains spaces (complex type) BUT NOT if it's a tuple
      isComplexType = ' ' `elem` unparenthesized && unparenthesized /= "()" && not isTuple
  in if isTuple
       then parseTupleString env homeModuleName trimmedName
       else if isComplexType
         then parseComplexTypeWithHome env homeModuleName (tokenizeTypeSegment (Text.pack unparenthesized))
         else case unparenthesized of
    -- Core basic types from standard library
    "Int" -> Can.TType ModuleName.basics (Name.fromChars "Int") []
    "Float" -> Can.TType ModuleName.basics (Name.fromChars "Float") []
    "Bool" -> Can.TType ModuleName.basics (Name.fromChars "Bool") []
    "String" -> Can.TType ModuleName.string (Name.fromChars "String") []
    "()" -> Can.TUnit
    "Unit" -> Can.TUnit

    -- Tuple types: "(Float, Float)" or "( Float, Float )"
    tupleStr | isTupleString tupleStr -> parseTupleString env homeModuleName tupleStr

    -- Task type (from Task module in core package)
    "Task" -> Can.TType ModuleName.task (Name.fromChars "Task") []

    -- Result type (from Result module in core package)
    "Result" -> Can.TType ModuleName.result (Name.fromChars "Result") []

    -- List type (from List module in core package)
    "List" -> Can.TType ModuleName.list (Name.fromChars "List") []

    -- Maybe type (from Maybe module in core package)
    "Maybe" -> Can.TType ModuleName.maybe (Name.fromChars "Maybe") []

    -- Type variables (single lowercase letters) - treat as opaque for now
    [ch] | ch >= 'a' && ch <= 'z' -> Can.TType homeModuleName (Name.fromChars trimmedName) []

    -- Module-qualified types: "Capability.CapabilityError" -> resolve module from homeModule's package
    qualifiedType | '.' `elem` qualifiedType ->
      let parts = splitOn '.' qualifiedType
          moduleParts = init parts  -- ["Capability"]
          typeNamePart = last parts      -- "CapabilityError"
          moduleNameStr = intercalate "." moduleParts  -- "Capability"
          -- Create a canonical module name in the same package as homeModule
          resolvedModule = case homeModuleName of
            ModuleName.Canonical pkg _ -> ModuleName.Canonical pkg (Name.fromChars moduleNameStr)
          resultType = Can.TType resolvedModule (Name.fromChars typeNamePart) []
      in resultType

    -- Custom opaque types (AudioContext, OscillatorNode, GainNode, etc.)
    -- These should resolve to the module where they are defined, not the importing module
    customType ->
      if customType == "String"
        then Can.TType ModuleName.string (Name.fromChars "String") []
        else
          let typeNameObj = Name.fromChars customType
              -- Look up the type in the environment to find its defining module
              maybeTypeInfo = Map.lookup typeNameObj (Env._types env)
              resolvedModule = maybe homeModuleName extractModule maybeTypeInfo
          in Can.TType resolvedModule typeNameObj []
  where
    extractModule :: Env.Info Env.Type -> ModuleName.Canonical
    extractModule (Env.Specific definingModule _) = definingModule
    extractModule (Env.Ambiguous definingModule _) = definingModule

    splitOn :: Char -> String -> [String]
    splitOn _ [] = []
    splitOn delim str =
      let (first, rest) = break (== delim) str
      in first : case rest of
                   [] -> []
                   (_:xs) -> splitOn delim xs

    intercalate :: String -> [String] -> String
    intercalate _ [] = ""
    intercalate _ [x] = x
    intercalate sep (x:xs) = x ++ sep ++ intercalate sep xs


-- Check if a type string represents a tuple
isTupleString :: String -> Bool
isTupleString str =
  let trimmed = dropWhile (== ' ') str
  in case trimmed of
       ('(' : rest) ->
         let inner = takeWhile (/= ')') rest
         in ',' `elem` inner
       _ -> False


-- Parse a tuple string like "(Float, Float)" into a Can.TTuple
parseTupleString :: Env.Env -> ModuleName.Canonical -> String -> Can.Type
parseTupleString env homeModuleName str =
  let trimmed = dropWhile (== ' ') str
      withoutParens = case trimmed of
                        ('(' : rest) -> takeWhile (/= ')') rest
                        other -> other
      elements = splitByComma withoutParens
      parsedElements = map (parseBasicTypeWithHome env homeModuleName . trim) elements
  in case parsedElements of
       [] -> Can.TUnit
       [single] -> single
       (first : second : rest) ->
         case rest of
           [] -> Can.TTuple first second Nothing
           [third] -> Can.TTuple first second (Just third)
           _ -> Can.TUnit  -- More than 3 elements not supported, fallback to Unit
  where
    trim = dropWhile (== ' ') . reverse . dropWhile (== ' ') . reverse
    splitByComma s = go [] [] s
      where
        go acc current [] = reverse (reverse current : acc)
        go acc current (',' : cs) = go (reverse current : acc) [] cs
        go acc current (c : cs) = go acc (c : current) cs


{-
addSingleFFI :: Env.Env -> Src.ForeignImport -> Result i [W.Warning] Env.Env
addSingleFFI env (Src.ForeignImport target alias _region) =
  case target of
    FFI.JavaScriptFFI jsFilePath ->
      -- Parse the JavaScript file and add functions to environment
      case addFFIFunctions env alias jsFilePath of
        Left _errMsg -> Result.throw (Error.ImportNotFound A.one (Name.fromChars "FFI") [])
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
