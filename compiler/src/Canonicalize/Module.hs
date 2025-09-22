{-# LANGUAGE BangPatterns #-}
{-# OPTIONS_GHC -Wall #-}

module Canonicalize.Module
  ( canonicalize,
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
import Data.List (isPrefixOf)
import qualified Data.List as List
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Name as Name
import qualified Data.Text as Text
import qualified Foreign.FFI as FFI
import qualified FFI.Storage as FFIStorage
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified System.IO.Unsafe
import qualified Reporting.Warning as W
import Control.Exception (SomeException, catch)

-- RESULT

type Result i w a =
  Result.Result i w Error.Error a

-- MODULES

canonicalize :: Pkg.Name -> Map ModuleName.Raw I.Interface -> Src.Module -> Result i [W.Warning] Can.Module
canonicalize pkg ifaces modul@(Src.Module _ exports docs imports foreignImports values _ _ binops effects) =
  do
    let home = ModuleName.Canonical pkg (Src.getName modul)
    let cbinops = Map.fromList (fmap canonicalizeBinop binops)

    (env, cunions, caliases) <-
      Foreign.createInitialEnv home ifaces imports >>= Local.add modul

    -- Process FFI imports and add to environment
    envWithFFI <- addFFIToEnv env foreignImports

    cvalues <- canonicalizeValues envWithFFI values
    ceffects <- Effects.canonicalize envWithFFI values cunions effects
    cexports <- canonicalizeExports values cunions caliases cbinops ceffects exports

    return $ Can.Module home cexports docs cvalues cunions caliases cbinops ceffects

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
    Can.Manager {} ->
      Just []

ok :: Name.Name -> A.Region -> Can.Export -> Result i w (Dups.Dict (A.Located Can.Export))
ok name region export =
  Result.ok $ Dups.one name region (A.At region export)

-- FFI SUPPORT

addFFIToEnv :: Env.Env -> [Src.ForeignImport] -> Result i [W.Warning] Env.Env
addFFIToEnv env foreignImports =
  case foreignImports of
    [] ->
      Result.ok env
    [Src.ForeignImport (FFI.JavaScriptFFI jsPath) alias _region] ->
      let aliasName = A.toValue alias
          home = Env._home env
          ffiModuleName = ModuleName.Canonical (ModuleName._package home) aliasName
      in case parseJavaScriptFile jsPath (Name.toChars aliasName) of
           Left _err -> Result.throw (Error.ImportNotFound A.one (Name.fromChars jsPath) [])
           Right functions -> addParsedFunctionsToEnv env ffiModuleName aliasName functions
    _fis ->
      -- Multiple foreign imports not yet supported
      Result.ok env

-- PROPER JAVASCRIPT FILE PARSING IMPLEMENTATION
parseJavaScriptFile :: String -> String -> Either String [(String, String)] -- [(functionName, canopyType)]
parseJavaScriptFile jsPath alias = do
  -- Step 1: Read the actual JavaScript file from filesystem
  jsContent <- readJavaScriptFileIO jsPath alias
  -- Step 2: Parse JSDoc comments and function declarations
  parseJavaScriptContent jsContent

-- Read JavaScript file from filesystem
readJavaScriptFileIO :: String -> String -> Either String String
readJavaScriptFileIO jsPath alias =
  -- PERMANENT RULE: NO HARDCODING OF FFI PATHS - read from foreign import statements
  -- Use ONLY the exact path specified in the foreign import statement
  let paths = [jsPath]
  in case System.IO.Unsafe.unsafePerformIO (tryPaths paths) of
    Left err -> Left err
    Right (actualPath, content) ->
      let !_ = System.IO.Unsafe.unsafePerformIO (FFIStorage.storeFFIInfo actualPath content alias)
      in Right content
  where
    tryPaths :: [String] -> IO (Either String (String, String))
    tryPaths [] = return (Left ("Cannot read JavaScript file: " ++ jsPath ++ ". Ensure the file exists relative to your project root."))
    tryPaths (path:rest) = do
      result <- try (readFile path)
      case result of
        Left (_ :: SomeException) -> tryPaths rest
        Right content -> return (Right (path, content))

    try :: IO a -> IO (Either SomeException a)
    try action = (Right <$> action) `catch` (return . Left)


-- Parse JavaScript content to extract functions and their types
parseJavaScriptContent :: String -> Either String [(String, String)]
parseJavaScriptContent jsContent =
  Right (extractFunctionsWithTypes (lines jsContent))

-- Extract functions with their @canopy-type annotations
extractFunctionsWithTypes :: [String] -> [(String, String)]
extractFunctionsWithTypes [] = []
extractFunctionsWithTypes (line:rest) =
  case parseCanopyTypeAnnotation line of
    Just canopyType ->
      case findNextFunctionDeclaration rest of
        Just functionName -> (functionName, canopyType) : extractFunctionsWithTypes rest
        Nothing -> extractFunctionsWithTypes rest
    Nothing -> extractFunctionsWithTypes rest

-- Parse @canopy-type annotation from a line
parseCanopyTypeAnnotation :: String -> Maybe String
parseCanopyTypeAnnotation line =
  let trimmed = dropWhile (`elem` (" *" :: String)) line
  in if ("@canopy-type " :: String) `isPrefixOf` trimmed
     then Just (drop (length ("@canopy-type " :: String)) trimmed)
     else Nothing

-- Find the next function declaration after type annotation
findNextFunctionDeclaration :: [String] -> Maybe String
findNextFunctionDeclaration [] = Nothing
findNextFunctionDeclaration (line:rest) =
  case extractFunctionName line of
    Just name -> Just name
    Nothing -> findNextFunctionDeclaration rest

-- Extract function name from a JavaScript function declaration
extractFunctionName :: String -> Maybe String
extractFunctionName line =
  let trimmed = dropWhile (`elem` (" */" :: String)) line
  in if ("function " :: String) `isPrefixOf` trimmed
     then let afterFunction = drop (length ("function " :: String)) trimmed
              nameEnd = takeWhile (\c -> c /= '(' && c /= ' ') afterFunction
          in if null nameEnd then Nothing else Just nameEnd
     else Nothing

-- DYNAMIC FUNCTION ENVIRONMENT GENERATION
addParsedFunctionsToEnv :: Env.Env -> ModuleName.Canonical -> Name.Name -> [(String, String)] -> Result i [W.Warning] Env.Env
addParsedFunctionsToEnv env ffiModuleName aliasName functions = do
  -- Dynamically process each parsed function
  processedFunctions <- traverse (processParsedFunction ffiModuleName) functions

  -- Build environment dynamically
  let (vars, qVars) = buildDynamicEnvironment aliasName processedFunctions
      newVars = List.foldl' (\acc (name, var) -> Map.insert name var acc) (Env._vars env) vars
      newQVars = Map.insertWith Map.union aliasName qVars (Env._q_vars env)
      newEnv = env { Env._vars = newVars, Env._q_vars = newQVars }

  Result.ok newEnv

-- Process a single parsed function (name, typeString) into Canopy types
processParsedFunction :: ModuleName.Canonical -> (String, String) -> Result i [W.Warning] (String, Can.Annotation, Env.Var)
processParsedFunction ffiModuleName (functionName, typeString) = do
  -- Parse the type string into actual Canopy types
  canopyType <- parseTypeString typeString
  let annotation = Can.Forall Map.empty canopyType
      var = Env.Foreign ffiModuleName annotation
  Result.ok (functionName, annotation, var)

-- Build the dynamic environment from processed functions
buildDynamicEnvironment :: Name.Name -> [(String, Can.Annotation, Env.Var)] -> ([(Name.Name, Env.Var)], Map.Map Name.Name (Env.Info Can.Annotation))
buildDynamicEnvironment aliasName processedFunctions =
  let -- Build vars with qualified names (Module.functionName)
      vars = List.map (\(fname, _, var) ->
               (Name.fromChars (Name.toChars aliasName ++ "." ++ fname), var)
             ) processedFunctions

      -- Build qualified vars (Module.functionName syntax)
      qVars = Map.fromList (List.map (\(fname, annotation, _) ->
                (Name.fromChars fname, Env.Specific ffiModuleName annotation)
              ) processedFunctions)
              where ffiModuleName = ModuleName.Canonical (Pkg.dummyName) aliasName

  in (vars, qVars)

-- Parse type string like "Int -> Int -> Int" into Canopy types
parseTypeString :: String -> Result i [W.Warning] Can.Type
parseTypeString typeStr =
  case parseTypeTokens (tokenizeCanopyType (Text.pack typeStr)) of
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

-- Parse type tokens into Canopy types
parseTypeTokens :: [String] -> Maybe Can.Type
parseTypeTokens tokens =
  case tokens of
    [] -> Nothing
    [typeName] -> Just (parseBasicType typeName)
    ["(", ")"] -> Just (Can.TType ModuleName.basics (Name.fromChars "Unit") [])
    (t1 : "->" : rest) ->
      case parseTypeTokens rest of
        Just restType -> Just (Can.TLambda (parseComplexType [t1]) restType)
        Nothing -> Nothing
    _ -> Just (parseComplexType tokens)

-- Parse complex types that may have multiple words
parseComplexType :: [String] -> Can.Type
parseComplexType tokens =
  case tokens of
    [] -> Can.TType ModuleName.basics (Name.fromChars "Unit") []
    ["(", ")"] -> Can.TType ModuleName.basics (Name.fromChars "Unit") []
    [typeName] -> parseBasicType typeName
    ("Task" : errorType : resultType : _rest) ->
      -- Handle Task types: Task ErrorType ResultType -> use Task module from core
      Can.TType (ModuleName.Canonical Pkg.core (Name.fromChars "Task")) (Name.fromChars "Task")
        [parseBasicType errorType, parseBasicType resultType]
    multiWordTokens ->
      -- Handle multi-word types like "Initialized AudioContext" as a single opaque type
      let typeName = unwords multiWordTokens
      in parseBasicType typeName

-- Parse basic type names
parseBasicType :: String -> Can.Type
parseBasicType typeName =
  case typeName of
    "Int" -> Can.TType ModuleName.basics (Name.fromChars "Int") []
    "Float" -> Can.TType ModuleName.basics (Name.fromChars "Float") []
    "Bool" -> Can.TType ModuleName.basics (Name.fromChars "Bool") []
    "String" -> Can.TType ModuleName.string (Name.fromChars "String") []
    "()" -> Can.TType ModuleName.basics (Name.fromChars "Unit") []
    -- Handle complex types like "AudioContext", "OscillatorNode", etc.
    _ -> Can.TType ModuleName.basics (Name.fromChars typeName) []

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

addFFIFunctions :: Env.Env -> A.Located Name.Name -> String -> Either Text.Text Env.Env
addFFIFunctions env alias jsFilePath = do
  -- Read the JavaScript file
  jsContent <- case readJavaScriptFile jsFilePath of
    Left err -> Left err
    Right content -> Right content

  -- Parse the JavaScript file to extract FFI functions
  ffiFunctions <- FFI.parseJavaScriptFile jsFilePath jsContent

  -- Add each function to the environment
  let aliasName = A.toValue alias
      home = Env._home env
      ffiModuleName = ModuleName.Canonical (ModuleName._package home) aliasName

  Right (addFFIFunctionsToEnv env ffiModuleName ffiFunctions)

readJavaScriptFile :: String -> Either Text.Text Text.Text
readJavaScriptFile jsFilePath =
  -- PERMANENT RULE: NO HARDCODING OF FFI PATHS - read from foreign import statements
  -- Read ANY JavaScript file path specified in the foreign import statement
  case System.IO.Unsafe.unsafePerformIO (tryReadFile jsFilePath) of
    Left err -> Left ("Cannot read file: " <> Text.pack err)
    Right content -> Right (Text.pack content)
  where
    tryReadFile :: String -> IO (Either String String)
    tryReadFile path = do
      result <- try (readFile path)
      case result of
        Left (_ :: SomeException) -> return (Left ("File not found or cannot be read: " ++ path))
        Right content -> return (Right content)

    try :: IO a -> IO (Either SomeException a)
    try action = (Right <$> action) `catch` (return . Left)

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
      var = Env.Foreign ffiModuleName annotation
      qualifiedName = Name.fromChars (Name.toChars aliasName ++ "." ++ Text.unpack funcNameText)
      newVars = Map.insert qualifiedName var vars
      -- For qualified vars, we need to update the nested map structure
      info = Env.Specific ffiModuleName annotation
      innerMap = Map.singleton funcName info
      newQVars = Map.insertWith Map.union aliasName innerMap qVars
  in (newVars, newQVars)

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
