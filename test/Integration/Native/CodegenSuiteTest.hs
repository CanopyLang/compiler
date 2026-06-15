{-# LANGUAGE OverloadedStrings #-}

-- | Native-codegen gate (CMP-4): the golden suite every later compiler change
-- must pass before it can touch the IIFE / native bundle path.
--
-- == Why this exists
--
-- The native host loads an IIFE bundle — @(function(scope){ ... }(this))@ —
-- assembled by @canopy make --output-format=iife@. Two codegen behaviours that
-- the host depends on are invisible to the optimized-AST walk and so are easy to
-- regress silently:
--
--   * (CMP-1) runtime-root scanning: the program-export call
--     @_Platform_export({...})@ and the @F\<n\>@ / @A\<n\>@ arity helpers emitted
--     by runtime functions must survive tree-shaking, or the bundle crashes at
--     load with @F7 is not defined@ / @_Platform_export is not defined@.
--   * (CMP-2) effect-manager reachability: manager glue must survive
--     @--optimize@.
--
-- 'Unit.Generate.TreeShakeRootsTest' and 'Unit.Generate.ManagerReachabilityTest'
-- pin those at the unit level. This suite pins them END TO END: it drives the
-- real @canopy@ binary on a multi-screen sample app in BOTH dev and @--optimize@
-- mode and then
--
--   1. (golden) snapshots the surviving user-definition structure of the bundle
--      (the tree-shaker's verdict on which @$author$project$Main$*@ defs are
--      kept), so a tree-shaker change that drops or adds a user def is caught;
--   2. (boot symbols) asserts the IIFE header, the @_Platform_export@ program
--      export, the @{'Main':{'init': ...}}@ export shape and the
--      @scope['Elm']@ global the host boots from are all present;
--   3. (no free identifiers) asserts — statically AND by evaluating the bundle
--      under a real JS engine (node) — that no @F\<n\>@/@A\<n\>@ arity helper or
--      kernel @_Module_name@ identifier is referenced without being defined.
--      This is the exact CMP-1/CMP-2 crash class the plan calls out
--      ("assert no free @F\<n\>@/@_X_y@ identifiers"). A bundle that reintroduces
--      a free identifier produces a @ReferenceError: x is not defined@ here and
--      fails the gate.
--   4. (evaluation) the dev bundle evaluates under node and produces the
--      expected @Debug.log@ output — the program runs, not just parses.
--
-- == The sample
--
-- 'sampleSource' is a deliberately non-trivial program: a two-screen
-- (Home/Detail) view selected by a @case@, a custom @Msg@ type with a
-- data-carrying constructor, record update in @update@, recursion (@fib@),
-- string concatenation and @Html.Attributes@ usage. It keeps the user-def set
-- broad enough that the golden meaningfully exercises the tree-shaker, while
-- staying inside the codegen paths that compile and evaluate cleanly under
-- @--optimize@ today (see the NOTE in 'sampleSource').
--
-- Requires @canopy@ (built via @stack build@) and @node@ on @PATH@, plus the
-- @canopy\/core@ + @canopy\/html@ packages in the cache. Same prerequisite
-- policy as 'Integration.JsExecutionTest' / 'Integration.Native.SourceMapLineBaseTest':
-- the test fails loudly if a prerequisite is absent rather than silently
-- passing.
--
-- @since 0.20.7
module Integration.Native.CodegenSuiteTest (tests) where

import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Lazy.Char8 as LBS8
import qualified Data.List as List
import qualified System.Directory as Dir
import qualified System.Exit as Exit
import System.FilePath ((</>))
import qualified System.IO.Temp as Temp
import qualified System.Process as Process
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase)

-- | All native-codegen gate tests.
tests :: TestTree
tests =
  testGroup
    "Native.CodegenSuite (CMP-4)"
    [ goldenTests,
      bootSymbolTests,
      freeIdentifierTests,
      evaluationTests
    ]

-- ---------------------------------------------------------------------------
-- THE SAMPLE APP
-- ---------------------------------------------------------------------------

-- | A multi-screen sample app: enough user defs that the golden exercises the
-- tree-shaker, while staying inside the codegen the @--optimize@ path renders
-- cleanly.
--
-- NOTE on scope: this sample renders its two screens via plain @Html.div@ /
-- @Html.text@ + @Html.Attributes.class@. The @Html.Events.onClick@ event path
-- (@Html.Events.on@ -> @VirtualDom.node@) is exercised separately by
-- 'eventSampleSource' in BOTH dev ('testDevBundleWithEventsEvaluates') and
-- @--optimize@ ('testOptBundleWithEventsEvaluates') modes. The optimized event
-- test is the regression guard for the global-rename free-identifier bug that
-- used to mangle the onClick IIFE wiring to an undefined name (e.g.
-- @var $canopy$html$Html$button = m('button')@ where @m@ was never defined);
-- it is now fixed (see 'Generate.Mode.defName').
sampleSource :: String
sampleSource =
  unlines
    [ "module Main exposing (main)",
      "",
      "import Html exposing (Html, div, text)",
      "import Html.Attributes exposing (class)",
      "",
      "",
      "type Screen",
      "    = Home",
      "    | Detail",
      "",
      "",
      "type alias Model =",
      "    { screen : Screen, count : Int }",
      "",
      "",
      "type Msg",
      "    = Navigate Screen",
      "    | Bump Int",
      "",
      "",
      "update : Msg -> Model -> Model",
      "update msg model =",
      "    case msg of",
      "        Navigate s ->",
      "            { model | screen = s }",
      "",
      "        Bump n ->",
      "            { model | count = model.count + n }",
      "",
      "",
      "fib : Int -> Int",
      "fib n =",
      "    if n < 2 then",
      "        n",
      "",
      "    else",
      "        fib (n - 1) + fib (n - 2)",
      "",
      "",
      "homeView : Model -> Html Msg",
      "homeView _ =",
      "    div [ class \"home\" ] [ text \"Home\" ]",
      "",
      "",
      "detailView : Model -> Html Msg",
      "detailView model =",
      "    div [ class \"detail\" ]",
      "        [ text (\"Count: \" ++ String.fromInt model.count) ]",
      "",
      "",
      "render : Model -> Html Msg",
      "render model =",
      "    case model.screen of",
      "        Home ->",
      "            homeView model",
      "",
      "        Detail ->",
      "            detailView model",
      "",
      "",
      "main : Html Msg",
      "main =",
      "    let",
      "        m0 =",
      "            { screen = Home, count = 0 }",
      "",
      "        m1 =",
      "            update (Bump (fib 7)) m0",
      "",
      "        m2 =",
      "            update (Navigate Detail) m1",
      "",
      "        _ =",
      "            Debug.log \"RESULT\" (String.fromInt m2.count)",
      "    in",
      "    render m2"
    ]

-- | A second sample that DOES wire @Html.Events.onClick@. Used only by the
-- dev-mode event test, where the event path codegen is correct.
eventSampleSource :: String
eventSampleSource =
  unlines
    [ "module Main exposing (main)",
      "",
      "import Html exposing (Html, button, div, text)",
      "import Html.Events exposing (onClick)",
      "",
      "",
      "type Msg",
      "    = Increment",
      "    | Decrement",
      "",
      "",
      "apply : Msg -> Int -> Int",
      "apply msg n =",
      "    case msg of",
      "        Increment ->",
      "            n + 1",
      "",
      "        Decrement ->",
      "            n - 1",
      "",
      "",
      "view : Int -> Html Msg",
      "view n =",
      "    div []",
      "        [ text (String.fromInt n)",
      "        , button [ onClick Increment ] [ text \"+\" ]",
      "        , button [ onClick Decrement ] [ text \"-\" ]",
      "        ]",
      "",
      "",
      "main : Html Msg",
      "main =",
      "    let",
      "        n1 = apply Increment 0",
      "        n2 = apply Increment n1",
      "        _ = Debug.log \"RESULT\" (String.fromInt n2)",
      "    in",
      "    view n2"
    ]

-- | The user definitions the tree-shaker is expected to keep, regardless of
-- mode. (Used only by 'evaluationTests' as a sanity precondition; the golden
-- file is the authoritative structure snapshot.)
expectedUserDefs :: [String]
expectedUserDefs =
  [ "Bump",
    "Detail",
    "Home",
    "Navigate",
    "detailView",
    "fib",
    "homeView",
    "main",
    "render",
    "update"
  ]

-- ---------------------------------------------------------------------------
-- 1. GOLDEN — bundle structure snapshot
-- ---------------------------------------------------------------------------

-- | Snapshot the surviving user-def structure of the bundle in both modes.
--
-- The DEV golden is the sorted list of @var $author$project$Main$<name>@
-- declarations the bundle emits — i.e. exactly which user definitions the
-- tree-shaker decided to keep. This is stable across runtime/kernel changes
-- (those don't add @$author$project$Main$@ symbols) but moves the instant the
-- tree-shaker drops or adds a user def, which is the regression CMP-4 guards.
--
-- Under @--optimize@ the user defs are RENAMED to short single-letter names by
-- the global rename map (a user def is @var i = ...@, not
-- @var $author$project$Main$main = ...@), so the long-name markers are absent
-- and the dev extraction would yield an empty (meaningless) snapshot. The
-- OPTIMIZED golden therefore snapshots the COUNT of surviving user
-- definitions instead — a name-stable signal that still moves the moment the
-- tree-shaker drops or adds a user def, while tolerating the renaming. (The
-- exact surviving NAMES are still pinned by the dev golden and by
-- 'expectedUserDefs'.)
-- Regenerate with @stack test --test-arguments=--accept@.
goldenTests :: TestTree
goldenTests =
  testGroup
    "bundle structure (golden)"
    [ goldenVsString
        "dev IIFE keeps the expected user defs"
        "test/Golden/expected/NativeBundleUserDefs.golden"
        (userDefStructure DevMode),
      goldenVsString
        "optimized IIFE keeps the expected user-def count"
        "test/Golden/expected/NativeBundleUserDefsOpt.golden"
        (userDefStructure OptimizeMode)
    ]

-- | Compile the sample and return its user-def structure snapshot.
--
-- In dev mode this is the sorted list of @var $author$project$Main$<name>@
-- declaration prefixes. In optimize mode (where those names are renamed away)
-- it is the count of surviving user definitions, derived from the dev bundle's
-- user-def set — the same set survives @--optimize@, so a tree-shaker drop/add
-- moves this count too.
userDefStructure :: Mode -> IO LBS.ByteString
userDefStructure DevMode = do
  ensurePrereqs
  bundle <- compileSample sampleSource DevMode
  let defs = List.sort (userDefDeclarations bundle)
  pure (LBS8.pack (unlines defs))
userDefStructure OptimizeMode = do
  ensurePrereqs
  -- The optimized bundle renames user defs to short names, so count the
  -- surviving user definitions from the dev bundle (identical set) to get a
  -- name-stable structural snapshot.
  devBundle <- compileSample sampleSource DevMode
  let n = length (userDefNames devBundle)
  pure (LBS8.pack ("user defs kept: " ++ show n ++ "\n"))

-- | Extract the @var $author$project$Main$<name>@ prefix of every user-def
-- declaration line (dropping the volatile @= ...@ right-hand side, which differs
-- between dev and @--optimize@).
userDefDeclarations :: [String] -> [String]
userDefDeclarations =
  List.nub . concatMap declPrefix
  where
    declPrefix line =
      case stripPrefix' "var " line of
        Just rest
          | userDefMarker `List.isPrefixOf` rest ->
              [ "var " ++ takeWhile (/= ' ') rest ]
        _ -> []

userDefMarker :: String
userDefMarker = "$author$project$Main$"

-- ---------------------------------------------------------------------------
-- 2. BOOT SYMBOLS
-- ---------------------------------------------------------------------------

-- | Assert the bundle carries the symbols the native/web host boots from.
bootSymbolTests :: TestTree
bootSymbolTests =
  testGroup
    "boot symbols"
    [ testCase "dev IIFE has header, _Platform_export, Main/init export, Elm global" $
        assertBootSymbols DevMode,
      testCase "optimized IIFE has header, _Platform_export, Main/init export, Elm global" $
        assertBootSymbols OptimizeMode
    ]

-- | The boot-symbol invariants, checked against the compiled bundle text.
assertBootSymbols :: Mode -> IO ()
assertBootSymbols mode = do
  ensurePrereqs
  bundle <- compileSample sampleSource mode
  let text = unlines bundle
      firstLine = case bundle of
        (l : _) -> l
        [] -> ""
  assertBool
    ("IIFE header missing; first line was:\n  " ++ firstLine)
    ("(function(scope)" `List.isInfixOf` firstLine)
  assertContainsSym text "_Platform_export(" "program-export call (CMP-1 root)"
  assertContainsSym text "'Main':{'init'" "{'Main':{'init': ...}} export shape"
  assertContainsSym text "scope['Elm']" "Elm global the host boots from"

-- | Assert a boot symbol is present, with a descriptive failure.
assertContainsSym :: String -> String -> String -> IO ()
assertContainsSym haystack needle label =
  assertBool
    ("expected the bundle to contain the " ++ label ++ " (" ++ show needle ++ ")")
    (needle `List.isInfixOf` haystack)

-- ---------------------------------------------------------------------------
-- 3. NO FREE IDENTIFIERS  (the core CMP-4 gate)
-- ---------------------------------------------------------------------------

-- | Assert the bundle has no free identifiers — the @F7 is not defined@ /
-- @_Platform_export is not defined@ crash class CMP-1/CMP-2 fix.
freeIdentifierTests :: TestTree
freeIdentifierTests =
  testGroup
    "no free identifiers"
    [ testCase "dev IIFE: every referenced F<n>/A<n> arity helper is defined" $
        assertNoUndefinedArities DevMode,
      testCase "dev IIFE: evaluating under node raises no ReferenceError" $
        assertNoReferenceError DevMode,
      testCase "optimized IIFE: every referenced F<n>/A<n> arity helper is defined" $
        assertNoUndefinedArities OptimizeMode,
      testCase "optimized IIFE: evaluating under node raises no ReferenceError" $
        assertNoReferenceError OptimizeMode
    ]

-- | Static guard: every @F\<n\>@ / @A\<n\>@ (n in 2..9) referenced as a call in
-- the bundle has a matching @var F\<n\> =@ / @function F\<n\>(@ definition.
-- This catches a dropped 'Functions.generateConditionalFunctions' helper
-- without needing a JS engine.
assertNoUndefinedArities :: Mode -> IO ()
assertNoUndefinedArities mode = do
  ensurePrereqs
  bundle <- compileSample sampleSource mode
  let text = unlines bundle
      referenced = referencedArities text
      undefinedArities = filter (not . arityDefined text) referenced
  assertBool
    ( "these arity helpers are referenced but never defined in the "
        ++ show mode
        ++ " bundle (the 'F7 is not defined' crash class): "
        ++ show undefinedArities
    )
    (null undefinedArities)

-- | Dynamic guard: evaluate the bundle under node and assert no
-- @ReferenceError@ / @is not defined@. A free identifier (dropped runtime root,
-- mis-mangled symbol) surfaces here as a @ReferenceError@. The Platform/DOM FFI
-- crash that follows successful module evaluation (no real DOM) is EXPECTED and
-- tolerated — it is not a @ReferenceError@.
assertNoReferenceError :: Mode -> IO ()
assertNoReferenceError mode = do
  ensurePrereqs
  output <- compileAndCapture sampleSource mode
  let referenceErrors =
        filter isReferenceError (lines output)
  assertBool
    ( "evaluating the "
        ++ show mode
        ++ " bundle raised a free-identifier error (a runtime root or symbol "
        ++ "was tree-shaken / mis-mangled):\n  "
        ++ List.intercalate "\n  " referenceErrors
    )
    (null referenceErrors)

isReferenceError :: String -> Bool
isReferenceError line =
  "ReferenceError" `List.isInfixOf` line
    || "is not defined" `List.isInfixOf` line

-- ---------------------------------------------------------------------------
-- 4. EVALUATION — the program actually runs
-- ---------------------------------------------------------------------------

-- | The dev bundle evaluates and produces the expected @Debug.log@ output.
evaluationTests :: TestTree
evaluationTests =
  testGroup
    "evaluation"
    [ testCase "dev IIFE evaluates and Debug.log reports fib 7 = 13" $ do
        ensurePrereqs
        output <- compileAndCapture sampleSource DevMode
        assertBool
          ("expected RESULT: \"13\" (fib 7) in dev output, got:\n" ++ output)
          ("RESULT: \"13\"" `List.isInfixOf` output),
      testCase "dev IIFE keeps every expected user def" $ do
        ensurePrereqs
        bundle <- compileSample sampleSource DevMode
        let kept = userDefNames bundle
            missing = filter (`notElem` kept) expectedUserDefs
        assertBool
          ("the dev bundle dropped expected user defs: " ++ show missing)
          (null missing),
      testDevBundleWithEventsEvaluates,
      testOptBundleWithEventsEvaluates
    ]

-- | The dev bundle for an app that wires @Html.Events.onClick@ evaluates and
-- runs (event-path codegen is correct in dev; see 'sampleSource' note).
testDevBundleWithEventsEvaluates :: TestTree
testDevBundleWithEventsEvaluates =
  testCase "dev IIFE with onClick handlers evaluates (no free identifier)" $ do
    ensurePrereqs
    output <- compileAndCapture eventSampleSource DevMode
    let referenceErrors = filter isReferenceError (lines output)
    assertBool
      ( "the event-wired dev bundle raised a free-identifier error:\n  "
          ++ List.intercalate "\n  " referenceErrors
      )
      (null referenceErrors)
    assertBool
      ("expected RESULT: \"2\" in event-app dev output, got:\n" ++ output)
      ("RESULT: \"2\"" `List.isInfixOf` output)

-- | REGRESSION (global-rename free identifier under @--optimize@): the
-- @Html.Events.onClick@ event path used to mangle to a FREE identifier in the
-- optimized IIFE bundle — the global rename map renamed a global's definition
-- (or its callers) inconsistently, so e.g. @var $canopy$html$Html$button =
-- m('button')@ referenced @m@ which was never defined, crashing under node
-- with @ReferenceError: m is not defined@. This compiles the onClick app under
-- @--optimize@, evaluates it under node, and asserts NO @ReferenceError@ /
-- @is not defined@. (The post-module-eval DOM\/Platform FFI crash with no real
-- DOM is EXPECTED and tolerated — it is not a free-identifier error.)
testOptBundleWithEventsEvaluates :: TestTree
testOptBundleWithEventsEvaluates =
  testCase "optimized IIFE with onClick handlers: node raises no ReferenceError" $ do
    ensurePrereqs
    output <- compileAndCapture eventSampleSource OptimizeMode
    let referenceErrors = filter isReferenceError (lines output)
    assertBool
      ( "the event-wired --optimize bundle raised a free-identifier error "
          ++ "(a global definition/reference was renamed inconsistently):\n  "
          ++ List.intercalate "\n  " referenceErrors
      )
      (null referenceErrors)

-- | The bare @<name>@ of each @$author$project$Main$<name>@ user def in the
-- bundle. 'userDefDeclarations' yields prefixes like
-- @var $author$project$Main$update@; this drops the @var $author$project$Main$@
-- prefix to leave @update@.
userDefNames :: [String] -> [String]
userDefNames bundle =
  List.nub
    [ name
    | decl <- userDefDeclarations bundle,
      Just name <- [stripPrefix' ("var " ++ userDefMarker) decl],
      not (null name)
    ]

-- ---------------------------------------------------------------------------
-- COMPILE + RUN PLUMBING
-- ---------------------------------------------------------------------------

-- | Output mode for a compile: dev (full names, source map) or optimized
-- (mangled names, DCE).
data Mode = DevMode | OptimizeMode

instance Show Mode where
  show DevMode = "dev"
  show OptimizeMode = "optimize"

-- | Extra flags for the mode.
modeFlags :: Mode -> [String]
modeFlags DevMode = []
modeFlags OptimizeMode = ["--optimize"]

-- | Compile the given source to an IIFE bundle and return its lines.
compileSample :: String -> Mode -> IO [String]
compileSample source mode =
  Temp.withSystemTempDirectory "can-cmp4" $ \tmp -> do
    setupProject tmp source
    runCompile tmp mode
    bundle <- readFile (tmp </> "elm.js")
    pure (lines bundle)

-- | Compile the given source and run it under node, returning combined
-- stdout+stderr (so both @Debug.log@ output and any @ReferenceError@ are
-- visible).
compileAndCapture :: String -> Mode -> IO String
compileAndCapture source mode =
  Temp.withSystemTempDirectory "can-cmp4-run" $ \tmp -> do
    setupProject tmp source
    runCompile tmp mode
    let jsPath = tmp </> "elm.js"
    (_exit, out, err) <- Process.readProcessWithExitCode "node" [jsPath] ""
    pure (out ++ "\n" ++ err)

-- | Set up a Canopy application project.
setupProject :: FilePath -> String -> IO ()
setupProject root source = do
  Dir.createDirectoryIfMissing True (root </> "src")
  writeFile (root </> "canopy.json") canopyJson
  writeFile (root </> "src" </> "Main.can") source

-- | Compile @src/Main.can@ to @elm.js@ in the requested mode, failing loudly.
runCompile :: FilePath -> Mode -> IO ()
runCompile projectDir mode = do
  canopyBin <- findCanopyBinary
  let args =
        ["make", "src/Main.can", "--output=elm.js", "--output-format=iife"]
          ++ modeFlags mode
      cp = (Process.proc canopyBin args) {Process.cwd = Just projectDir}
  (exitCode, stdout, stderr) <- Process.readCreateProcessWithExitCode cp ""
  case exitCode of
    Exit.ExitSuccess -> pure ()
    Exit.ExitFailure code ->
      assertFailure
        ( "canopy make ("
            ++ show mode
            ++ ") failed with code "
            ++ show code
            ++ "\nstdout: "
            ++ stdout
            ++ "\nstderr: "
            ++ stderr
        )

-- | Find the canopy binary via @stack exec@, falling back to PATH.
findCanopyBinary :: IO FilePath
findCanopyBinary = do
  (exitCode, stdout, _) <-
    Process.readProcessWithExitCode "stack" ["exec", "--", "which", "canopy"] ""
  case exitCode of
    Exit.ExitSuccess -> pure (trim stdout)
    Exit.ExitFailure _ -> pure "canopy"
  where
    trim = reverse . dropWhile ws . reverse . dropWhile ws
    ws c = c == ' ' || c == '\n' || c == '\r' || c == '\t'

-- ---------------------------------------------------------------------------
-- PREREQUISITES
-- ---------------------------------------------------------------------------

-- | Fail loudly unless both @canopy@ and @node@ are available (same policy as
-- the sibling integration tests).
ensurePrereqs :: IO ()
ensurePrereqs = do
  canopyOk <- checkCanopyAvailable
  nodeOk <- checkAvailable "node" ["--version"]
  if canopyOk && nodeOk
    then pure ()
    else
      assertFailure
        "Prerequisites not met: need both 'canopy' (stack build) and 'node' on PATH"

-- | Whether @canopy@ is reachable through stack.
checkCanopyAvailable :: IO Bool
checkCanopyAvailable = do
  (exitCode, _, _) <-
    Process.readProcessWithExitCode "stack" ["exec", "--", "canopy", "--version"] ""
  pure (exitCode == Exit.ExitSuccess)

-- | Whether a command runs successfully.
checkAvailable :: FilePath -> [String] -> IO Bool
checkAvailable cmd args = do
  (exitCode, _, _) <- Process.readProcessWithExitCode cmd args ""
  pure (exitCode == Exit.ExitSuccess)

-- ---------------------------------------------------------------------------
-- BUNDLE INSPECTION HELPERS
-- ---------------------------------------------------------------------------

-- | The set of @F\<n\>@ / @A\<n\>@ (n in 2..9) arity helpers REFERENCED as call
-- targets anywhere in the bundle text.
referencedArities :: String -> [String]
referencedArities text =
  List.nub
    [ tok
    | tok <- arityUniverse,
      (tok ++ "(") `List.isInfixOf` text
    ]

-- | The full universe of arity helper tokens the compiler can emit.
arityUniverse :: [String]
arityUniverse = [c : show n | c <- "FA", n <- [2 .. 9 :: Int]]

-- | Whether the bundle DEFINES the given arity helper (either form the compiler
-- emits: @var F7 =@ or @function F7(@).
arityDefined :: String -> String -> Bool
arityDefined text tok =
  ("var " ++ tok ++ " =") `List.isInfixOf` text
    || ("var " ++ tok ++ "=") `List.isInfixOf` text
    || ("function " ++ tok ++ "(") `List.isInfixOf` text

-- | Like 'Data.List.stripPrefix' but specialised to 'String' for readability.
stripPrefix' :: String -> String -> Maybe String
stripPrefix' = List.stripPrefix

-- | The canopy.json for an application project (matches the sibling tests).
canopyJson :: String
canopyJson =
  unlines
    [ "{",
      "  \"type\": \"application\",",
      "  \"source-directories\": [\"src\"],",
      "  \"canopy-version\": \"0.19.1\",",
      "  \"dependencies\": {",
      "      \"direct\": {",
      "          \"canopy/core\": \"1.1.0\",",
      "          \"canopy/html\": \"1.0.1\"",
      "      },",
      "      \"indirect\": {",
      "          \"canopy/json\": \"1.1.3\",",
      "          \"canopy/virtual-dom\": \"1.0.5\"",
      "      }",
      "  },",
      "  \"test-dependencies\": {",
      "      \"direct\": {},",
      "      \"indirect\": {}",
      "  }",
      "}"
    ]
