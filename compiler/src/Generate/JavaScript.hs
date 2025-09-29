{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | JavaScript generation for the Canopy compiler
--
-- ⚠️  CRITICAL RULE: NO HARDCODING OF FFI FILE PATHS! ⚠️
-- All FFI file paths MUST come from the actual foreign import statements
-- in the source code, NOT hardcoded values. This allows the FFI system
-- to work with ANY project structure and ANY file paths.
--
-- @since 0.19.1
module Generate.JavaScript
  ( generate,
    generateForRepl,
    generateForReplEndpoint,
    FFIInfo(..),
  )
where

import qualified AST.Canonical as Can
import qualified AST.Optimized as Opt
import qualified Canopy.Kernel as K
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import Control.Exception (Exception, throw)
import qualified Debug.Trace as Debug
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as B
import qualified Data.Index as Index
import qualified Data.List as List
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Maybe
import qualified Data.Name as Name
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Utf8 as Utf8
import Debug.Trace (trace)
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Expression as Expr
import qualified Generate.JavaScript.Functions as Functions
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.Mode as Mode
import qualified Reporting.Doc as D
import qualified Reporting.Render.Type as RT
import qualified Reporting.Render.Type.Localizer as L
import Prelude hiding (cycle, print)
-- import Text.RawString.QQ (r)  -- Removed: no longer using raw strings

-- GENERATE

type Graph = Map Opt.Global Opt.Node

type Mains = Map ModuleName.Canonical Opt.Main

-- | FFI information for JavaScript generation
--
-- This type contains the information needed to generate FFI JavaScript code
-- without relying on global storage.
data FFIInfo = FFIInfo
  { ffiFilePath :: !String    -- ^ Path to the JavaScript file
  , ffiContent  :: !String    -- ^ Content of the JavaScript file
  , ffiAlias    :: !String    -- ^ Alias used in the import statement
  } deriving (Eq, Show)

-- | Generate FFI JavaScript content to include in bundle
--
-- This function now receives FFI information directly through the compilation
-- pipeline instead of using global storage, eliminating MVar deadlock issues.
generateFFIContent :: Graph -> Map String FFIInfo -> Builder
generateFFIContent graph ffiInfos =
  if Map.null ffiInfos
     then mempty
     else mconcat . map B.stringUtf8 $
            [ "\n// FFI JavaScript content from external files\n" ] ++
            Map.foldrWithKey formatFFIFileFromInfo [] ffiInfos ++
            [ "\n// FFI function bindings\n" ] ++
            Map.foldrWithKey (generateFFIBindingsFromInfo graph) [] ffiInfos

-- Format FFI file content for inclusion using FFIInfo
formatFFIFileFromInfo :: String -> FFIInfo -> [String] -> [String]
formatFFIFileFromInfo _key ffiInfo acc =
  let filePath = ffiFilePath ffiInfo
      content = ffiContent ffiInfo
  in [ "\n// From " ++ filePath ++ "\n"
     , content
     , "\n"
     ] ++ acc

-- Generate JavaScript variable bindings for FFI functions using FFIInfo with proper aliases
generateFFIBindingsFromInfo :: Graph -> String -> FFIInfo -> [String] -> [String]
generateFFIBindingsFromInfo graph _key ffiInfo acc =
  let filePath = ffiFilePath ffiInfo
      content = ffiContent ffiInfo
      alias = ffiAlias ffiInfo
  in case extractFFIFunctionBindings graph filePath content alias of
    [] -> acc
    bindings -> ("\n// Bindings for " ++ filePath ++ "\n") : ("var " ++ alias ++ " = " ++ alias ++ " || {};\n") : (map (++ "\n") bindings) ++ ["\n"] ++ acc

-- Extract and generate bindings for FFI functions from JavaScript content
extractFFIFunctionBindings :: Graph -> String -> String -> String -> [String]
extractFFIFunctionBindings graph filePath content alias =
  let contentLines = lines content
      functions = extractCanopyTypeFunctions contentLines
  in concatMap (generateFunctionBinding graph filePath alias) functions

-- Extract functions that have @canopy-type annotations
extractCanopyTypeFunctions :: [String] -> [(String, String)]  -- [(functionName, canopyType)]
extractCanopyTypeFunctions [] = []
extractCanopyTypeFunctions (line:rest) =
  case extractCanopyType line of
    Just canopyType ->
      case findFunctionName rest of
        Just funcName -> (funcName, canopyType) : extractCanopyTypeFunctions rest
        Nothing -> extractCanopyTypeFunctions rest
    Nothing -> extractCanopyTypeFunctions rest

-- Extract @canopy-type annotation from a line
extractCanopyType :: String -> Maybe String
extractCanopyType line =
  if " * @canopy-type " `isInfixOf` line
    then case dropWhile (/= '@') line of
      ('@':'c':'a':'n':'o':'p':'y':'-':'t':'y':'p':'e':' ':typeStr) -> Just (trim typeStr)
      _ -> Nothing
    else Nothing

-- Find the function name in the following lines
findFunctionName :: [String] -> Maybe String
findFunctionName [] = Nothing
findFunctionName (line:rest) =
  if "function " `isPrefixOf` trim line
    then case dropWhile (/= ' ') (trim line) of
      (' ':rest') -> case takeWhile (\c -> c /= '(' && c /= ' ') (trim rest') of
        "" -> findFunctionName rest
        name -> Just name
      _ -> findFunctionName rest
    else if "*/" `isInfixOf` line
      then findFunctionName rest  -- Continue past comment end
      else findFunctionName rest

-- Generate JavaScript binding for a single function
generateFunctionBinding :: Graph -> String -> String -> (String, String) -> [String]
generateFunctionBinding _graph _filePath alias (funcName, canopyType) =
  let arity = countArrows canopyType
      wrapper = if arity <= 1 then "" else "F" ++ show arity ++ "("
      closing = if arity <= 1 then "" else ")"
      -- Use the actual alias from the import statement instead of hardcoded "Math"
      jsVarName = "$author$project$" ++ alias ++ "$" ++ funcName
      -- Create namespace object using the correct alias
      namespaceBinding = alias ++ "." ++ funcName ++ " = " ++ wrapper ++ funcName ++ closing ++ ";"
  in ["var " ++ jsVarName ++ " = " ++ wrapper ++ funcName ++ closing ++ ";", namespaceBinding]

-- Count arrows in a type signature to determine arity (only function parameter arrows)
-- Uses the same tokenization logic as the FFI parser to handle multi-word types correctly
countArrows :: String -> Int
countArrows typeStr =
  let tokens = tokenizeCanopyType (Text.pack typeStr)
      result = countFunctionArrows tokens
  in result
  where
    -- Tokenize the same way as the FFI parser to handle multi-word types
    tokenizeCanopyType :: Text.Text -> [Text.Text]
    tokenizeCanopyType typeText = filter (not . Text.null) (go [] "" typeText)
      where
        go :: [Text.Text] -> Text.Text -> Text.Text -> [Text.Text]
        go acc current text
          | Text.null text = if Text.null current then acc else acc ++ [current]
          | Text.head text == '(' =
              let newAcc = if Text.null current then acc else acc ++ [current]
              in go (newAcc ++ ["("]) "" (Text.tail text)
          | Text.head text == ')' =
              let newAcc = if Text.null current then acc else acc ++ [current]
              in go (newAcc ++ [")"]) "" (Text.tail text)
          | Text.head text == ' ' =
              if Text.null current
                then go acc "" (Text.tail text)
                else go (acc ++ [current]) "" (Text.tail text)
          | otherwise =
              go acc (current <> Text.take 1 text) (Text.tail text)

    -- Count arrows that represent function parameters (not arrows inside types)
    countFunctionArrows :: [Text.Text] -> Int
    countFunctionArrows tokens = go tokens (0 :: Int) (0 :: Int)
      where
        go [] _parenCount arrowCount = arrowCount
        go (token:rest) parenCount arrowCount
          | token == "(" = go rest (parenCount + 1) arrowCount
          | token == ")" = go rest (parenCount - 1) arrowCount
          | token == "->" && parenCount == 0 = go rest parenCount (arrowCount + 1)
          | otherwise = go rest parenCount arrowCount

-- Utility function to trim whitespace
trim :: String -> String
trim = dropWhile isSpace . dropWhileEnd isSpace
  where
    isSpace c = c `elem` [' ', '\t', '\n', '\r']
    dropWhileEnd p = reverse . dropWhile p . reverse

-- Check if a string contains a substring
isInfixOf :: String -> String -> Bool
isInfixOf needle haystack = any (isPrefixOf needle) (tails haystack)

-- Check if a string is a prefix of another
isPrefixOf :: String -> String -> Bool
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (x:xs) (y:ys) = x == y && isPrefixOf xs ys

-- Get all suffixes of a list
tails :: [a] -> [[a]]
tails [] = [[]]
tails xs@(_:ys) = xs : tails ys

generate :: Mode.Mode -> Opt.GlobalGraph -> Mains -> Map String FFIInfo -> Builder
generate mode (Opt.GlobalGraph graph _) mains ffiInfos =
  let _ = Debug.trace ("GLOBAL-GRAPH-DEBUG: Total globals: " <> show (Map.size graph)) ()
      allGlobals = Map.keys graph
      listGlobals = filter (\(Opt.Global home name) ->
        let modName = ModuleName._module home
            pkgName = ModuleName._package home
        in "List" `isInfixOf` Name.toChars modName || "List" `isInfixOf` Name.toChars name) allGlobals
      elmCoreGlobals = filter (\(Opt.Global home _) ->
        let pkg = ModuleName._package home
        in Pkg._author pkg == Pkg.elm && Pkg._project pkg == Pkg._project Pkg.core) allGlobals
      dollarGlobals = filter (\(Opt.Global _ name) -> Name.toChars name == "$") allGlobals
      _ = Debug.trace ("GLOBAL-GRAPH-DEBUG: List-related globals: " <> show listGlobals) ()
      _ = Debug.trace ("GLOBAL-GRAPH-DEBUG: elm/core globals count: " <> show (length elmCoreGlobals)) ()
      _ = Debug.trace ("GLOBAL-GRAPH-DEBUG: $ globals: " <> show dollarGlobals) ()
      _ = Debug.trace ("GLOBAL-GRAPH-DEBUG: First 20 globals: " <> show (take 20 allGlobals)) ()
      baseState = Map.foldrWithKey (addMain mode graph) emptyState mains
      state = baseState  -- For now, we'll focus on fixing the core issue
      header = if Mode.isElmCompatible mode
               then "(function(scope){\n'use strict';\n"
               else "(function(scope){'use strict';\n"
   in header
        <> generateFFIContent graph ffiInfos
        <> Functions.functions
        <> perfNote mode
        <> mempty  -- comprehensiveRuntime mode DISABLED to debug dependency inclusion
        <> stateToBuilder state
        <> toMainExports mode mains
        <> "\n}(this));"


addMain :: Mode.Mode -> Graph -> ModuleName.Canonical -> Opt.Main -> State -> State
addMain mode graph home _ state =
  addGlobal mode graph state (Opt.Global home "main")

perfNote :: Mode.Mode -> Builder
perfNote mode =
  case mode of
    Mode.Prod _ _ ->
      mempty
    Mode.Dev Nothing elmCompatible ->
      -- Always include console.warn in dev mode to match Elm behavior
      -- Use explicit semicolon annotation to ensure semicolon is added
      let optimizeUrl = if elmCompatible
                        then "https://elm-lang.org/0.19.1/optimize"
                        else D.makeNakedLink "optimize"
      in JS.stmtToBuilder $
           JS.ExprStmtWithSemi $
             JS.Call
               (JS.Access (JS.Ref (JsName.fromLocal "console")) (JsName.fromLocal "warn"))
               [ JS.String $
                   "Compiled in DEV mode. Follow the advice at "
                     <> B.stringUtf8 optimizeUrl
                     <> " for better performance and smaller assets."
               ]
    Mode.Dev (Just _) elmCompatible ->
      -- Always include console.warn in dev mode to match Elm behavior
      -- Use explicit semicolon annotation to ensure semicolon is added
      let optimizeUrl = if elmCompatible
                        then "https://elm-lang.org/0.19.1/optimize"
                        else D.makeNakedLink "optimize"
      in JS.stmtToBuilder $
           JS.ExprStmtWithSemi $
             JS.Call
               (JS.Access (JS.Ref (JsName.fromLocal "console")) (JsName.fromLocal "warn"))
               [ JS.String $
                   "Compiled in DEBUG mode. Follow the advice at "
                     <> B.stringUtf8 optimizeUrl
                     <> " for better performance and smaller assets."
               ]

-- Note: Comprehensive runtime functions removed due to unused warnings.
-- These can be re-added when actually needed for Elm compatibility.

-- GENERATE FOR REPL
generateForRepl :: Bool -> L.Localizer -> Opt.GlobalGraph -> ModuleName.Canonical -> Name.Name -> Can.Annotation -> Builder
generateForRepl ansi localizer (Opt.GlobalGraph graph _) home name (Can.Forall _ tipe) =
  let mode = Mode.Dev Nothing True  -- Default to elm-compatible for REPL
      debugState = addGlobal mode graph emptyState (Opt.Global ModuleName.debug "toString")
      evalState = addGlobal mode graph debugState (Opt.Global home name)
      processExceptionHandler = JS.stmtToBuilder $
        JS.ExprStmt $
          JS.Call
            (JS.Access (JS.Ref (JsName.fromLocal "process")) (JsName.fromLocal "on"))
            [ JS.String "uncaughtException",
              JS.Function Nothing [JsName.fromLocal "err"] [
                JS.ExprStmt $ JS.Call
                  (JS.Access
                    (JS.Access (JS.Ref (JsName.fromLocal "process")) (JsName.fromLocal "stderr"))
                    (JsName.fromLocal "write"))
                  [ JS.Infix JS.OpAdd
                      (JS.Call
                        (JS.Access (JS.Ref (JsName.fromLocal "err")) (JsName.fromLocal "toString"))
                        [])
                      (JS.String "\\n")
                  ],
                JS.ExprStmt $ JS.Call
                  (JS.Access (JS.Ref (JsName.fromLocal "process")) (JsName.fromLocal "exit"))
                  [JS.Int 1]
              ]
            ]
   in processExceptionHandler
        <> Functions.functions
        <> stateToBuilder evalState
        <> print ansi localizer home name tipe

print :: Bool -> L.Localizer -> ModuleName.Canonical -> Name.Name -> Can.Type -> Builder
print ansi localizer home name tipe =
  let value = JS.Ref (JsName.fromGlobal home name)
      toString = JS.Ref (JsName.fromKernel Name.debug "toAnsiString")
      tipeDoc = RT.canToDoc localizer RT.None tipe
      boolValue = if ansi then JS.Bool True else JS.Bool False

      -- var _value = toString(bool, value);
      valueVar = JS.Var (JsName.fromLocal "_value") $
        JS.Call toString [boolValue, value]

      -- var _type = "type string";
      typeVar = JS.Var (JsName.fromLocal "_type") $
        JS.String $ B.stringUtf8 (show (D.toString tipeDoc))

      -- function _print(t) { console.log(_value + (ansi ? '\x1b[90m' + t + '\x1b[0m' : t)); }
      printFunc = JS.FunctionStmt (JsName.fromLocal "_print") [JsName.fromLocal "t"] [
        JS.ExprStmt $ JS.Call
          (JS.Access (JS.Ref (JsName.fromLocal "console")) (JsName.fromLocal "log"))
          [ JS.Infix JS.OpAdd
              (JS.Ref (JsName.fromLocal "_value"))
              (JS.If boolValue
                (JS.Infix JS.OpAdd
                  (JS.Infix JS.OpAdd (JS.String "\\x1b[90m") (JS.Ref (JsName.fromLocal "t")))
                  (JS.String "\\x1b[0m"))
                (JS.Ref (JsName.fromLocal "t")))
          ]
        ]

      -- Condition: _value.length + 3 + _type.length >= 80 || _type.indexOf('\n') >= 0
      lengthCondition = JS.Infix JS.OpGe
        (JS.Infix JS.OpAdd
          (JS.Infix JS.OpAdd
            (JS.Access (JS.Ref (JsName.fromLocal "_value")) (JsName.fromLocal "length"))
            (JS.Int 3))
          (JS.Access (JS.Ref (JsName.fromLocal "_type")) (JsName.fromLocal "length")))
        (JS.Int 80)

      newlineCondition = JS.Infix JS.OpGe
        (JS.Call
          (JS.Access (JS.Ref (JsName.fromLocal "_type")) (JsName.fromLocal "indexOf"))
          [JS.String "\\n"])
        (JS.Int 0)

      condition = JS.Infix JS.OpOr lengthCondition newlineCondition

      -- if/else statement
      ifStmt = JS.IfStmt condition
        -- _print('\n    : ' + _type.split('\n').join('\n      '));
        (JS.ExprStmt $ JS.Call
          (JS.Ref (JsName.fromLocal "_print"))
          [ JS.Infix JS.OpAdd
              (JS.String "\\n    : ")
              (JS.Call
                (JS.Access
                  (JS.Call
                    (JS.Access (JS.Ref (JsName.fromLocal "_type")) (JsName.fromLocal "split"))
                    [JS.String "\\n"])
                  (JsName.fromLocal "join"))
                [JS.String "\\n      "])
          ])
        -- _print(' : ' + _type);
        (JS.ExprStmt $ JS.Call
          (JS.Ref (JsName.fromLocal "_print"))
          [ JS.Infix JS.OpAdd (JS.String " : ") (JS.Ref (JsName.fromLocal "_type")) ]
        )
   in JS.stmtToBuilder $ JS.Block [valueVar, typeVar, printFunc, ifStmt]

-- GENERATE FOR REPL ENDPOINT

generateForReplEndpoint :: L.Localizer -> Opt.GlobalGraph -> ModuleName.Canonical -> Maybe Name.Name -> Can.Annotation -> Builder
generateForReplEndpoint localizer (Opt.GlobalGraph graph _) home maybeName (Can.Forall _ tipe) =
  let name = Data.Maybe.fromMaybe Name.replValueToPrint maybeName
      mode = Mode.Dev Nothing True  -- Default to elm-compatible for REPL
      debugState = addGlobal mode graph emptyState (Opt.Global ModuleName.debug "toString")
      evalState = addGlobal mode graph debugState (Opt.Global home name)
   in Functions.functions
        <> stateToBuilder evalState
        <> postMessage localizer home maybeName tipe

postMessage :: L.Localizer -> ModuleName.Canonical -> Maybe Name.Name -> Can.Type -> Builder
postMessage localizer home maybeName tipe =
  let name = Data.Maybe.fromMaybe Name.replValueToPrint maybeName
      value = JS.Ref (JsName.fromGlobal home name)
      toString = JS.Ref (JsName.fromKernel Name.debug "toAnsiString")
      tipeDoc = RT.canToDoc localizer RT.None tipe

      nameField = case maybeName of
        Nothing -> JS.Null
        Just n -> JS.String (Name.toBuilder n)

      messageObj = JS.Object
        [ (JsName.fromLocal "name", nameField),
          (JsName.fromLocal "value", JS.Call toString [JS.Bool True, value]),
          (JsName.fromLocal "type", JS.String $ B.stringUtf8 (show (D.toString tipeDoc)))
        ]

      postMessageCall = JS.ExprStmt $
        JS.Call
          (JS.Access (JS.Ref (JsName.fromLocal "self")) (JsName.fromLocal "postMessage"))
          [messageObj]

   in JS.stmtToBuilder postMessageCall

-- GRAPH TRAVERSAL STATE

data State = State
  { _revKernels :: [Builder],
    _revBuilders :: [Builder],
    _seenGlobals :: Set Opt.Global
  }

emptyState :: State
emptyState =
  State mempty [] Set.empty

stateToBuilder :: State -> Builder
stateToBuilder (State revKernels revBuilders _) =
  prependBuilders revKernels (prependBuilders revBuilders mempty)

prependBuilders :: [Builder] -> Builder -> Builder
prependBuilders revBuilders monolith =
  List.foldl' (flip (<>)) monolith revBuilders

-- ADD DEPENDENCIES

addGlobal :: Mode.Mode -> Graph -> State -> Opt.Global -> State
addGlobal mode graph state@(State revKernels builders seen) global =
  if Set.member global seen
    then state
    else
      -- Skip FFI functions - they should be handled by expression generation
      let Opt.Global globalHome _globalName = global
          moduleName = ModuleName._module globalHome
      in if Name.toChars moduleName == "Math"
         then state  -- Skip FFI functions entirely
         else
           addGlobalHelp mode graph global $
             State revKernels builders (Set.insert global seen)

data MyException = MyException String
  deriving (Show)

instance Exception MyException

-- | Filter dependencies to only include essential ones that match Elm's inclusion strategy
filterEssentialDeps :: Mode.Mode -> Set Opt.Global -> Set Opt.Global
filterEssentialDeps _mode deps =
  Set.filter isEssentialDependency deps
  where
    isEssentialDependency (Opt.Global modName funcName) =
      let pkgName = ModuleName._package modName
          moduleName = ModuleName._module modName
      in case (Pkg.toChars pkgName, Name.toChars moduleName) of
        -- Always include user project functions
        ("author/project", _) -> True
        -- Always include platform/kernel functions (essential runtime)
        (pkg, _) | "elm/" `List.isPrefixOf` pkg && isKernelFunction funcName -> True
        -- Include core elm/core functions that Elm includes
        ("elm/core", "Basics") -> True  -- Include all Basics functions
        ("elm/core", "String") -> True  -- Include String functions
        ("elm/core", "List") -> True    -- Include List functions
        ("elm/core", "Array") -> True   -- Include Array functions
        ("elm/core", "Dict") -> True    -- Include Dict functions
        ("elm/core", "Set") -> True     -- Include Set functions
        ("elm/core", "Result") -> True  -- Include Result functions
        ("elm/core", "Platform") -> True -- Include Platform functions
        ("elm/core", "VirtualDom") -> True -- Include VirtualDom functions
        ("elm/core", "Html") -> True     -- Include Html functions
        ("elm/core", "Json.Decode") -> True -- Include Json.Decode functions
        ("elm/core", "Json.Encode") -> True -- Include Json.Encode functions
        ("elm/core", "Elm.JsArray") -> True -- Include JsArray functions
        ("elm/core", "Tuple") -> True    -- Include Tuple functions
        -- Skip larger modules that might not be essential
        ("elm/core", _) -> False
        -- Include everything else (non-elm/core dependencies)
        _ -> True

    isKernelFunction name = "_" `List.isPrefixOf` Name.toChars name


addGlobalHelp :: Mode.Mode -> Graph -> Opt.Global -> State -> State
addGlobalHelp mode graph currentGlobal state =
  let _ = trace ("DEBUG GLOBAL: Processing global " ++ show currentGlobal) ()
  in
  let addDeps deps someState =
        let filteredDeps = filterEssentialDeps mode deps
        in Set.foldl' (addGlobal mode graph) someState filteredDeps
      globalInGraph = case Map.lookup currentGlobal graph of
        Just x -> x
        Nothing ->
          -- Try alternative package name (canopy/kernel vs elm/kernel)
          let Opt.Global globalHome globalName = currentGlobal
              currentPkg = ModuleName._package globalHome
              _ = trace ("DEBUG PACKAGE MAPPING: currentPkg=" ++ show currentPkg ++ ", module=" ++ show (ModuleName._module globalHome)) ()
              altPkg = if Pkg._author currentPkg == Pkg.canopy
                      then -- Map canopy packages: kernel->core for standard modules, others stay the same
                           if Pkg._project currentPkg == Pkg._project Pkg.kernel
                           then Pkg.core  -- canopy/kernel -> elm/core (for List, String, etc.)
                           else Pkg.Name Pkg.elm (Pkg._project currentPkg)  -- canopy/other -> elm/other
                      else if Pkg._author currentPkg == Pkg.elm && Pkg._project currentPkg == Pkg._project Pkg.kernel
                      then -- Map elm/kernel back to canopy/kernel as fallback
                           Pkg.kernel
                      else -- No mapping needed
                           currentPkg
              altGlobalHome = globalHome { ModuleName._package = altPkg }
              altGlobal = Opt.Global altGlobalHome globalName
              _ = trace ("DEBUG PACKAGE MAPPING: trying altPkg=" ++ show altPkg) ()
              moduleName = ModuleName._module globalHome
          in case Map.lookup altGlobal graph of
               Just x -> x
               Nothing ->
                 if Name.toChars moduleName == "Math"
                 then error "FFI function found - this should be handled by expression generation"
                 else let allKeys = Map.keys graph
                          listRelated = filter (\(Opt.Global home name) ->
                            let modName = ModuleName._module home
                            in "List" `isInfixOf` Name.toChars modName || "List" `isInfixOf` Name.toChars name) allKeys
                          dollarKeys = filter (\(Opt.Global _ name) -> Name.toChars name == "$") allKeys
                          elmCoreKeys = filter (\(Opt.Global home _) ->
                            let pkg = ModuleName._package home
                            in Pkg._author pkg == Pkg.elm && Pkg._project pkg == Pkg._project Pkg.core) allKeys
                          errorMsg = "\n=== GLOBALHELP DEBUG ===\n" <>
                                   "Missing: " <> show currentGlobal <> "\n" <>
                                   "Also tried: " <> show altGlobal <> "\n" <>
                                   "Total keys: " <> show (length allKeys) <> "\n" <>
                                   "List-related: " <> show listRelated <> "\n" <>
                                   "$ globals: " <> show dollarKeys <> "\n" <>
                                   "elm/core count: " <> show (length elmCoreKeys) <> "\n" <>
                                   "First 20: " <> show (take 20 allKeys) <> "\n" <>
                                   "========================"
                      in error errorMsg
   in case globalInGraph of
        Opt.Define expr deps ->
          addStmt
            (addDeps deps state)
            ( var currentGlobal (Expr.generate mode expr)
            )
        Opt.DefineTailFunc argNames body deps ->
          addStmt
            (addDeps deps state)
            ( let (Opt.Global _ name) = currentGlobal
               in JS.Var (JsName.fromGlobal (case currentGlobal of Opt.Global home _ -> home) name) (Expr.generateTailDefExpr mode name argNames body)
            )
        Opt.Ctor index arity ->
          addStmt
            state
            ( var currentGlobal (Expr.generateCtor mode currentGlobal index arity)
            )
        Opt.Link linkedGlobal ->
          addGlobal mode graph state linkedGlobal
        Opt.Cycle names values functions deps ->
          let cycleStmt = generateCycle mode currentGlobal names values functions
              baseState = addDeps deps state
          in case cycleStmt of
               JS.Block stmts -> List.foldl' addStmt baseState stmts
               stmt -> addStmt baseState stmt
        Opt.Manager effectsType ->
          generateManager mode graph currentGlobal effectsType state
        Opt.Kernel chunks deps ->
          if isDebugger currentGlobal && not (Mode.isDebug mode)
            then state
            else addKernel (addDeps deps state) (generateKernel mode chunks)
        Opt.Enum index ->
          addStmt
            state
            ( generateEnum mode currentGlobal index
            )
        Opt.Box ->
          addStmt
            (addGlobal mode graph state identity)
            ( generateBox mode currentGlobal
            )
        Opt.PortIncoming decoder deps ->
          addStmt
            (addDeps deps state)
            ( generatePort mode currentGlobal "incomingPort" decoder
            )
        Opt.PortOutgoing encoder deps ->
          addStmt
            (addDeps deps state)
            ( generatePort mode currentGlobal "outgoingPort" encoder
            )

addStmt :: State -> JS.Stmt -> State
addStmt state stmt =
  addBuilder state (JS.stmtToBuilder stmt)

addBuilder :: State -> Builder -> State
addBuilder (State revKernels revBuilders seen) builder =
  State revKernels (builder : revBuilders) seen

addKernel :: State -> Builder -> State
addKernel (State revKernels revBuilders seen) kernel =
  State (kernel : revKernels) revBuilders seen

var :: Opt.Global -> Expr.Code -> JS.Stmt
var (Opt.Global home name) code =
  JS.Var (JsName.fromGlobal home name) (Expr.codeToExpr code)

isDebugger :: Opt.Global -> Bool
isDebugger (Opt.Global (ModuleName.Canonical _ home) _) =
  home == Name.debugger

-- GENERATE CYCLES

generateCycle :: Mode.Mode -> Opt.Global -> [Name.Name] -> [(Name.Name, Opt.Expr)] -> [Opt.Def] -> JS.Stmt
generateCycle mode (Opt.Global home _) names values functions =
  let functionStmts = fmap (generateCycleFunc mode home) functions
      safeStmts = fmap (generateSafeCycle mode home) values
      realStmts = case fmap (generateRealCycle home) values of
        [] -> []
        realBlock@(_ : _) ->
          case mode of
            Mode.Prod _ _ ->
              realBlock
            Mode.Dev _ _ ->
              [(JS.Try (JS.Block realBlock) JsName.dollar . JS.Throw) . JS.String $
                ( "Some top-level definitions from `" <> Name.toBuilder (ModuleName._module home) <> "` are causing infinite recursion:\\n"
                    <> drawCycle names
                    <> "\\n\\nThese errors are very tricky, so read "
                    <> B.stringUtf8 (D.makeNakedLink "bad-recursion")
                    <> " to learn how to fix it!"
                )]
      allStmts = functionStmts ++ safeStmts ++ realStmts
  in case allStmts of
       [singleStmt] -> singleStmt
       _ -> JS.Block allStmts

generateCycleFunc :: Mode.Mode -> ModuleName.Canonical -> Opt.Def -> JS.Stmt
generateCycleFunc mode home def =
  case def of
    Opt.Def name expr ->
      JS.Var (JsName.fromGlobal home name) (Expr.codeToExpr (Expr.generate mode expr))
    Opt.TailDef name args expr ->
      JS.Var (JsName.fromGlobal home name) (Expr.generateTailDefExpr mode name args expr)

generateSafeCycle :: Mode.Mode -> ModuleName.Canonical -> (Name.Name, Opt.Expr) -> JS.Stmt
generateSafeCycle mode home (name, expr) =
  JS.FunctionStmt (JsName.fromCycle home name) [] $
    Expr.codeToStmtList (Expr.generate mode expr)

generateRealCycle :: ModuleName.Canonical -> (Name.Name, expr) -> JS.Stmt
generateRealCycle home (name, _) =
  let safeName = JsName.fromCycle home name
      realName = JsName.fromGlobal home name
   in JS.Block
        [ JS.Var realName (JS.Call (JS.Ref safeName) []),
          JS.ExprStmt . JS.Assign (JS.LRef safeName) $ JS.Function Nothing [] [JS.Return (JS.Ref realName)]
        ]

drawCycle :: [Name.Name] -> Builder
drawCycle names =
  let topLine = "\\n  ┌─────┐"
      nameLine name = "\\n  │    " <> Name.toBuilder name
      midLine = "\\n  │     ↓"
      bottomLine = "\\n  └─────┘"
   in mconcat (topLine : (List.intersperse midLine (fmap nameLine names) <> [bottomLine]))

-- GENERATE KERNEL

generateKernel :: Mode.Mode -> [K.Chunk] -> Builder
generateKernel mode = List.foldr (addChunk mode) mempty

addChunk :: Mode.Mode -> K.Chunk -> Builder -> Builder
addChunk mode chunk builder =
  case chunk of
    K.JS javascript ->
      B.byteString javascript <> builder
    K.CanopyVar home name ->
      JsName.toBuilder (JsName.fromGlobal home name) <> builder
    K.JsVar home name ->
      JsName.toBuilder (JsName.fromKernel home name) <> builder
    K.CanopyField name ->
      JsName.toBuilder (Expr.generateField mode name) <> builder
    K.JsField int ->
      JsName.toBuilder (JsName.fromInt int) <> builder
    K.JsEnum int ->
      B.intDec int <> builder
    K.Debug ->
      case mode of
        Mode.Dev _ elmCompatible ->
          if elmCompatible
            then builder               -- Elm dev: debug functions are used (clean)
            else builder               -- Canopy dev: use debug functions
        Mode.Prod _ _ ->
          "_UNUSED" <> builder
    K.Prod ->
      case mode of
        Mode.Dev _ elmCompatible ->
          if elmCompatible
            then "_UNUSED" <> builder  -- Elm dev: prod functions marked unused
            else "_UNUSED" <> builder  -- Canopy dev: prod functions marked unused
        Mode.Prod _ _ ->
          builder

-- GENERATE ENUM

generateEnum :: Mode.Mode -> Opt.Global -> Index.ZeroBased -> JS.Stmt
generateEnum mode global@(Opt.Global home name) index =
  JS.Var (JsName.fromGlobal home name) $
    case mode of
      Mode.Dev _ _ ->
        Expr.codeToExpr (Expr.generateCtor mode global index 0)
      Mode.Prod _ _ ->
        JS.Int (Index.toMachine index)

-- GENERATE BOX

generateBox :: Mode.Mode -> Opt.Global -> JS.Stmt
generateBox mode global@(Opt.Global home name) =
  JS.Var (JsName.fromGlobal home name) $
    case mode of
      Mode.Dev _ _ ->
        Expr.codeToExpr (Expr.generateCtor mode global Index.first 1)
      Mode.Prod _ _ ->
        JS.Ref (JsName.fromGlobal ModuleName.basics Name.identity)

{-# NOINLINE identity #-}
identity :: Opt.Global
identity =
  Opt.Global ModuleName.basics Name.identity

-- GENERATE PORTS

generatePort :: Mode.Mode -> Opt.Global -> Name.Name -> Opt.Expr -> JS.Stmt
generatePort mode (Opt.Global home name) makePort converter =
  JS.Var (JsName.fromGlobal home name) $
    JS.Call
      (JS.Ref (JsName.fromKernel Name.platform makePort))
      [ JS.String (Name.toBuilder name),
        Expr.codeToExpr (Expr.generate mode converter)
      ]

-- GENERATE MANAGER

generateManager :: Mode.Mode -> Graph -> Opt.Global -> Opt.EffectsType -> State -> State
generateManager mode graph (Opt.Global home@(ModuleName.Canonical _ moduleName) _) effectsType state =
  let managerLVar =
        JS.LBracket
          (JS.Ref (JsName.fromKernel Name.platform "effectManagers"))
          (JS.String (Name.toBuilder moduleName))

      (deps, args, stmts) =
        generateManagerHelp home effectsType

      createManager =
        (JS.ExprStmt . JS.Assign managerLVar $ JS.Call (JS.Ref (JsName.fromKernel Name.platform "createManager")) args)
   in List.foldl' addStmt (List.foldl' (addGlobal mode graph) state deps) (createManager : stmts)

generateLeaf :: ModuleName.Canonical -> Name.Name -> JS.Stmt
generateLeaf home@(ModuleName.Canonical _ moduleName) name =
  JS.Var (JsName.fromGlobal home name) $
    JS.Call leaf [JS.String (Name.toBuilder moduleName)]

{-# NOINLINE leaf #-}
leaf :: JS.Expr
leaf =
  JS.Ref (JsName.fromKernel Name.platform "leaf")

generateManagerHelp :: ModuleName.Canonical -> Opt.EffectsType -> ([Opt.Global], [JS.Expr], [JS.Stmt])
generateManagerHelp home effectsType =
  let ref name = JS.Ref (JsName.fromGlobal home name)
      dep = Opt.Global home
   in case effectsType of
        Opt.Cmd ->
          ( [dep "init", dep "onEffects", dep "onSelfMsg", dep "cmdMap"],
            [ref "init", ref "onEffects", ref "onSelfMsg", ref "cmdMap"],
            [generateLeaf home "command"]
          )
        Opt.Sub ->
          ( [dep "init", dep "onEffects", dep "onSelfMsg", dep "subMap"],
            [ref "init", ref "onEffects", ref "onSelfMsg", JS.Int 0, ref "subMap"],
            [generateLeaf home "subscription"]
          )
        Opt.Fx ->
          ( [dep "init", dep "onEffects", dep "onSelfMsg", dep "cmdMap", dep "subMap"],
            [ref "init", ref "onEffects", ref "onSelfMsg", ref "cmdMap", ref "subMap"],
            [ generateLeaf home "command",
              generateLeaf home "subscription"
            ]
          )

-- MAIN EXPORTS

toMainExports :: Mode.Mode -> Mains -> Builder
toMainExports mode mains =
  let export = JsName.fromKernel Name.platform "export"
      exports = generateExports mode (Map.foldrWithKey addToTrie emptyTrie mains)
   in JsName.toBuilder export <> "(" <> exports <> ");"
        <> "scope['Canopy'] = scope['Elm'];"

generateExports :: Mode.Mode -> Trie -> Builder
generateExports mode (Trie maybeMain subs) =
  let starter end =
        case maybeMain of
          Nothing ->
            "{"
          Just (home, main) ->
            "{'init':"
              <> JS.exprToBuilder (Expr.generateMain mode home main)
              <> end
   in case Map.toList subs of
        [] ->
          starter "" <> "}"
        (name, subTrie) : otherSubTries ->
          starter ","
            <> "'"
            <> Utf8.toBuilder name
            <> "':"
            <> generateExports mode subTrie
            <> List.foldl' (addSubTrie mode) "}" otherSubTries

addSubTrie :: Mode.Mode -> Builder -> (Name.Name, Trie) -> Builder
addSubTrie mode end (name, trie) =
  ",'" <> Utf8.toBuilder name <> "':" <> generateExports mode trie <> end

-- BUILD TRIES

data Trie = Trie
  { _main :: Maybe (ModuleName.Canonical, Opt.Main),
    _subs :: Map Name.Name Trie
  }

emptyTrie :: Trie
emptyTrie =
  Trie Nothing Map.empty

addToTrie :: ModuleName.Canonical -> Opt.Main -> Trie -> Trie
addToTrie home@(ModuleName.Canonical _ moduleName) main trie =
  merge trie $ segmentsToTrie home (Name.splitDots moduleName) main

segmentsToTrie :: ModuleName.Canonical -> [Name.Name] -> Opt.Main -> Trie
segmentsToTrie home segments main =
  case segments of
    [] ->
      Trie (Just (home, main)) Map.empty
    segment : otherSegments ->
      Trie Nothing (Map.singleton segment (segmentsToTrie home otherSegments main))

merge :: Trie -> Trie -> Trie
merge (Trie main1 subs1) (Trie main2 subs2) =
  Trie
    (checkedMerge main1 main2)
    (Map.unionWith merge subs1 subs2)

checkedMerge :: Maybe a -> Maybe a -> Maybe a
checkedMerge a b =
  case (a, b) of
    (Nothing, main) ->
      main
    (main, Nothing) ->
      main
    (Just _, Just _) ->
      error "cannot have two modules with the same name"