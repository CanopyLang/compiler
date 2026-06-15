{-# LANGUAGE OverloadedStrings #-}

-- | End-to-end gate for @canopy make --target native@ (CMP-5).
--
-- == Why this exists
--
-- CMP-5 folds the native bundle assembly INTO the compiler: a new
-- @--target native@ flag drives 'Generate.JavaScript.NativeBundle' to emit the
-- self-contained Hermes/JSI bundle — the IIFE the web reuse path compiles, PLUS
-- the @__canopy_boot@ entry hook, ABI fallbacks, and the in-bundle source map —
-- replacing the brittle out-of-tree string-splice the native build tool used to
-- do. 'Unit.Generate.JavaScript.NativeBundleTest' pins the assembler in
-- isolation; this suite pins the WHOLE path END TO END by driving the real
-- @canopy@ binary on a sample app and then:
--
--   1. (golden) snapshots the STRUCTURE of the assembled bundle's native
--      trailer — the boot hook shape and the in-bundle map presence — which is
--      name-stable across runtime/kernel churn but moves the instant the
--      assembly changes;
--   2. (boot symbols) asserts the bundle carries @__canopy_boot@, the
--      @_Platform_export@ program export, the @Elm@ global, the inline
--      @globalThis.__canopy_sourcemap@, and the @sourceMappingURL@ comment;
--   3. (map alignment) asserts the in-bundle map JSON is byte-identical to the
--      standalone @.js.map@ the same build writes, and that the assembled JS
--      BEGINS with the IIFE (so no mapped line is shifted by the trailer — the
--      alignment property the hand-splice could not hold);
--   4. (prod) asserts @--optimize --target native@ still installs the boot hook
--      but emits NO map (no inline map, no @.map@ file, no @sourceMappingURL@);
--   5. (no free identifiers) evaluates the dev bundle under node and asserts no
--      @ReferenceError@ — the @F7 is not defined@ crash class — and that
--      @__canopy_boot@ is installed and bootable.
--
-- Requires @canopy@ (built via @stack build@) and @node@ on @PATH@, plus the
-- @canopy\/core@ + @canopy\/html@ packages in the cache — same prerequisite
-- policy as 'Integration.Native.CodegenSuiteTest': the test fails loudly if a
-- prerequisite is absent rather than silently passing.
--
-- @since 0.20.9
module Integration.Native.NativeBundleTargetTest (tests) where

import Data.List (isInfixOf, isPrefixOf)
import qualified Data.ByteString as BS
import qualified Generate.JavaScript.HermesContainer as HermesContainer
import qualified Generate.JavaScript.NativeDCE as NativeDCE
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Lazy.Char8 as LBS8
import qualified System.Directory as Dir
import qualified System.Exit as Exit
import System.FilePath ((</>))
import qualified System.IO.Temp as Temp
import qualified System.Process as Process
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Native.NativeBundleTarget (CMP-5)"
    [ structureGolden
    , bootSymbolTests
    , mapAlignmentTests
    , prodTests
    , bootabilityTests
    , browserGateTests
    , prodMapContentTests
    , containerTests
    ]

-- ---------------------------------------------------------------------------
-- SAMPLE APP
-- ---------------------------------------------------------------------------

-- | A small but real app: a recursive @fib@, a @Debug.log@ the boot path runs,
-- and an @Html@ view. Enough to exercise the IIFE + program export the boot hook
-- bridges to, while staying in the codegen that compiles + evaluates cleanly.
sampleSource :: String
sampleSource =
  unlines
    [ "module Main exposing (main)",
      "",
      "import Html exposing (Html, div, text)",
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
      "main : Html msg",
      "main =",
      "    let",
      "        _ =",
      "            Debug.log \"RESULT\" (String.fromInt (fib 7))",
      "    in",
      "    div [] [ text \"hi\" ]"
    ]

-- ---------------------------------------------------------------------------
-- 1. STRUCTURE GOLDEN
-- ---------------------------------------------------------------------------

-- | Snapshot the structure of the assembled native trailer.
--
-- The snapshot is a small set of name-stable predicates over the dev bundle:
-- the boot-hook marker line, the boot-hook signature, the ABI fallback, the
-- inline-map assignment, and the @sourceMappingURL@ comment. These do not move
-- with runtime/kernel changes (those add @_X_y@ / @$..$@ symbols, not these
-- markers) but move the instant the native assembly changes — which is exactly
-- the CMP-5 surface this guards.
--
-- Regenerate with @stack test --test-arguments=--accept@.
structureGolden :: TestTree
structureGolden =
  goldenVsString
    "native bundle trailer structure"
    "test/Golden/expected/NativeBundleTargetStructure.golden"
    trailerStructure

-- | Compile the sample with @--target native@ (dev) and reduce it to the
-- stable trailer-structure snapshot.
trailerStructure :: IO LBS.ByteString
trailerStructure = do
  ensurePrereqs
  (bundle, _map) <- compileNative sampleSource DevMode
  let has needle = if needle `isInfixOf` bundle then "yes" else "NO"
  pure . LBS8.pack . unlines $
    [ "boot-hook marker: " ++ has "GENERATED by canopy make --target native"
    , "boot-hook def: " ++ has "g.__canopy_boot = function (rootTag, flags)"
    , "abi fallback: " ++ has "(g.scope && g.scope.Elm)"
    , "mount call: " ++ has "elm.Main.init({ node: rootTag, flags: flags })"
    , "inline sourcemap: " ++ has "globalThis.__canopy_sourcemap = "
    , "sourceMappingURL: " ++ has "//# sourceMappingURL=canopy.bundle.js.map"
    ]

-- ---------------------------------------------------------------------------
-- 2. BOOT SYMBOLS
-- ---------------------------------------------------------------------------

bootSymbolTests :: TestTree
bootSymbolTests =
  testCase "dev native bundle carries boot hook, program export, Elm global, inline map" $ do
    ensurePrereqs
    (bundle, _map) <- compileNative sampleSource DevMode
    assertHas bundle "__canopy_boot" "native boot hook"
    assertHas bundle "_Platform_export(" "program-export call (CMP-1 root)"
    assertHas bundle "scope['Elm']" "Elm global the host boots from"
    assertHas bundle "globalThis.__canopy_sourcemap = " "in-bundle source map"
    assertHas bundle "//# sourceMappingURL=" "sourceMappingURL comment"

-- ---------------------------------------------------------------------------
-- 3. MAP ALIGNMENT
-- ---------------------------------------------------------------------------

mapAlignmentTests :: TestTree
mapAlignmentTests =
  testGroup
    "map alignment"
    [ testCase "assembled JS begins with the IIFE (trailer appended, map not shifted)" $ do
        ensurePrereqs
        (bundle, _) <- compileNative sampleSource DevMode
        assertBool
          "the native bundle must START with the IIFE header (the trailer is appended after it)"
          ("(function(scope)" `isPrefixOf` bundle)
        -- the boot hook must come AFTER the IIFE close, never before the program
        let afterIife = afterSubstr "}(typeof window" bundle
        assertBool
          "the boot hook must be emitted after the IIFE close"
          ("__canopy_boot" `isInfixOf` afterIife)
    , testCase "inline __canopy_sourcemap JSON equals the standalone .js.map" $ do
        ensurePrereqs
        (bundle, maybeMap) <- compileNative sampleSource DevMode
        case maybeMap of
          Nothing -> assertFailure "dev build must write a standalone .js.map"
          Just mapFile ->
            case inlinedMapJson bundle of
              Nothing -> assertFailure "could not find inline __canopy_sourcemap in the bundle"
              Just inlined ->
                assertBool
                  ( "the in-bundle map must be byte-identical to the sibling .map "
                      ++ "(so the host symbolicates identically from either)"
                  )
                  (inlined == mapFile)
    ]

-- ---------------------------------------------------------------------------
-- 4. PROD (map archived out-of-band — CMP-8b)
-- ---------------------------------------------------------------------------

-- | CMP-8b changed the @--optimize@ contract: the prod build no longer DROPS
-- the map (which left a release crash unsymbolicatable). It now ARCHIVES the map
-- out-of-band — a standalone @.js.map@ + a @sourceMappingURL@ comment — while
-- keeping the JSON OUT of the shipped bytes (the size budget). So under
-- @--optimize@:
--
--   * the boot hook is still installed (unchanged);
--   * a standalone @.js.map@ IS written (against the renamed names);
--   * the @sourceMappingURL@ comment IS present (a symbolication service finds
--     the sibling map);
--   * but the map is NOT inlined (@__canopy_sourcemap@ is absent), so the bundle
--     stays small.
prodTests :: TestTree
prodTests =
  testCase "optimized native bundle installs boot hook + archives the map out-of-band (CMP-8b)" $ do
    ensurePrereqs
    (bundle, maybeMap) <- compileNative sampleSource OptimizeMode
    assertHas bundle "__canopy_boot" "native boot hook (present under --optimize too)"
    assertBool
      "a standalone .js.map MUST be archived under --optimize (CMP-8b prod source map)"
      (maybeMap /= Nothing)
    assertBool
      "the archived prod map must be a valid Source Map V3 (version 3)"
      (maybe False ("\"version\":3" `isInfixOf`) maybeMap)
    assertBool
      "the map must NOT be inlined under --optimize (size budget — it is archived out-of-band)"
      (not ("__canopy_sourcemap" `isInfixOf` bundle))
    assertHas bundle "//# sourceMappingURL=" "sourceMappingURL comment (points at the sibling .map)"

-- ---------------------------------------------------------------------------
-- 5. BOOTABILITY  (no free identifiers)
-- ---------------------------------------------------------------------------

bootabilityTests :: TestTree
bootabilityTests =
  testCase "dev native bundle evaluates + boots under node with no ReferenceError" $ do
    ensurePrereqs
    output <- compileNativeAndBoot sampleSource
    let referenceErrors = filter isReferenceError (lines output)
    assertBool
      ( "the native bundle raised a free-identifier error (a runtime root or "
          ++ "symbol was tree-shaken / mis-mangled):\n  "
          ++ unlines referenceErrors
      )
      (null referenceErrors)
    assertBool
      ("expected __canopy_boot to be installed; node output was:\n" ++ output)
      ("__canopy_boot:function" `isInfixOf` filter (/= ' ') output)

isReferenceError :: String -> Bool
isReferenceError line =
  "ReferenceError" `isInfixOf` line || "is not defined" `isInfixOf` line

-- ---------------------------------------------------------------------------
-- 6. BROWSER-GLOBAL GATE (CMP-8b)
-- ---------------------------------------------------------------------------

-- | CMP-8b gates browser-only @window@/@document@ refs for Hermes via an
-- allowlist + a stub. These assertions hold the gate END TO END on the real
-- assembled bundle, in BOTH dev and @--optimize@:
--
--   * the browser-global STUB is spliced in (so the kernel's native-dead
--     @window.addEventListener@ / @document.body@ refs resolve on bare Hermes);
--   * the static GATE 'NativeDCE.unstubbedRefs' finds NO @window@/@document@
--     access outside the allowlist — i.e. every real browser reference the
--     bundle carries is one the stub provides. A new unguarded browser ref in
--     the kernel would surface here as a non-empty result and fail the gate.
browserGateTests :: TestTree
browserGateTests =
  testGroup
    "browser-global gate (CMP-8b)"
    [ testCase "dev bundle splices the browser-global stub and has no unstubbed refs" $ do
        ensurePrereqs
        (bundle, _) <- compileNative sampleSource DevMode
        assertHas bundle NativeDCE.stubMarkerName "browser-global stub marker"
        assertNoUnstubbed bundle
    , testCase "optimized bundle splices the stub and has no unstubbed refs" $ do
        ensurePrereqs
        (bundle, _) <- compileNative sampleSource OptimizeMode
        assertHas bundle NativeDCE.stubMarkerName "browser-global stub marker (prod)"
        assertNoUnstubbed bundle
    ]
  where
    assertNoUnstubbed bundle =
      case NativeDCE.unstubbedRefs bundle of
        [] -> pure ()
        refs ->
          assertFailure
            ( "the native bundle references browser globals the stub does NOT cover "
                ++ "(would crash on bare Hermes); extend the allowlist + stub or guard them:\n  "
                ++ show refs
            )

-- ---------------------------------------------------------------------------
-- 7. PROD SOURCE MAP CONTENT (CMP-8b)
-- ---------------------------------------------------------------------------

-- | The CMP-8b prod map is a real, archived Source Map V3 against the renamed
-- names: it carries @version 3@, names the @.can@ source modules, and has a
-- non-empty @mappings@ field — enough to turn a @canopy.bundle.js:LINE@ frame
-- into a @Module.can@ location on a release crash. It is written to the sibling
-- @.js.map@ (out-of-band), NOT inlined.
prodMapContentTests :: TestTree
prodMapContentTests =
  testCase "optimized native build archives a valid renamed-name source map (CMP-8b)" $ do
    ensurePrereqs
    (_bundle, maybeMap) <- compileNative sampleSource OptimizeMode
    case maybeMap of
      Nothing -> assertFailure "--optimize --target native must archive a standalone .js.map (CMP-8b)"
      Just mapJson -> do
        assertHas mapJson "\"version\":3" "Source Map V3 version field"
        assertHas mapJson ".can" "at least one .can source module in the map"
        assertBool
          "the prod map must carry a non-empty mappings field (it maps generated lines)"
          (nonEmptyMappings mapJson)
  where
    -- The mappings field is "mappings":"<vlq>" — assert it is present and not "".
    nonEmptyMappings j =
      case afterSubstr "\"mappings\":\"" j of
        [] -> False
        (c : _) -> c /= '"'

-- ---------------------------------------------------------------------------
-- 8. VERSIONED BUNDLE CONTAINER (CMP-8)
-- ---------------------------------------------------------------------------

-- | CMP-8 emits a versioned bundle container next to the native JS bundle:
-- @canopy.bundle.js.container@. With no @hermesc@ on this toolchain the payload
-- is the JS-source dev fallback — the SAME assembled bundle bytes — wrapped in
-- the magic + container/bytecode/ABI-version header the host validates. These
-- assertions hold that end-to-end on the REAL @canopy@ build:
--
--   * the container file is written;
--   * it parses with the host-mirror parser ('HermesContainer.parseContainer')
--     — magic, header CRC, and payload length all check out;
--   * its payload is byte-identical to the assembled @canopy.bundle.js@ (the
--     dev fallback wraps the exact bundle);
--   * its stamped ABI version is the host's, payload kind is JsSource; and
--   * it PASSES the host-mirror validation gate against the engine pin
--     (bytecode 96) and host ABI (1) — i.e. the host would accept it.
containerTests :: TestTree
containerTests =
  testGroup
    "versioned bundle container (CMP-8)"
    [ testCase "dev build writes a container that parses + wraps the exact bundle" $ do
        ensurePrereqs
        (bundleBytes, container) <- compileNativeWithContainer sampleSource DevMode
        case HermesContainer.parseContainer container of
          Left e -> assertFailure ("the emitted .container failed to parse: " ++ show e)
          Right (header, payload) -> do
            assertBool
              "the container payload must be the exact bytes of canopy.bundle.js (dev fallback)"
              (payload == bundleBytes)
            HermesContainer.chPayloadKind header @?= HermesContainer.JsSource
            HermesContainer.chAbiVersion header @?= HermesContainer.kCanopyAbiVersion
    , testCase "the emitted container PASSES the host-mirror validation gate" $ do
        ensurePrereqs
        (_bundle, container) <- compileNativeWithContainer sampleSource DevMode
        case HermesContainer.parseContainer container of
          Left e -> assertFailure ("parse failed: " ++ show e)
          Right (header, _) ->
            HermesContainer.validate
              HermesContainer.kCanopyContainerVersion
              HermesContainer.kCanopyEngineBytecodeVersion
              HermesContainer.kCanopyAbiVersion
              header
              @?= Right ()
    , testCase "optimized build also writes a parseable container" $ do
        ensurePrereqs
        (_bundle, container) <- compileNativeWithContainer sampleSource OptimizeMode
        assertBool
          "the optimized .container must parse (host would accept it)"
          (either (const False) (const True) (HermesContainer.parseContainer container))
    ]

-- ---------------------------------------------------------------------------
-- COMPILE PLUMBING
-- ---------------------------------------------------------------------------

data Mode = DevMode | OptimizeMode

modeFlags :: Mode -> [String]
modeFlags DevMode = []
modeFlags OptimizeMode = ["--optimize"]

-- | Compile the sample with @--target native@ and return the bundle text plus
-- the standalone @.js.map@ contents (Just in dev, Nothing in optimize).
compileNative :: String -> Mode -> IO (String, Maybe String)
compileNative source mode =
  Temp.withSystemTempDirectory "can-cmp5" $ \tmp -> do
    setupProject tmp source
    runCompileNative tmp mode
    bundle <- readFile (tmp </> "canopy.bundle.js")
    mapExists <- Dir.doesFileExist (tmp </> "canopy.bundle.js.map")
    maybeMap <-
      if mapExists
        then Just <$> readFile (tmp </> "canopy.bundle.js.map")
        else pure Nothing
    -- force the reads before the temp dir is removed
    length bundle `seq` maybe (pure ()) (\m -> length m `seq` pure ()) maybeMap
    pure (bundle, maybeMap)

-- | Compile the sample with @--target native@ and return the raw bytes of the
-- written @canopy.bundle.js@ plus the raw bytes of the emitted
-- @canopy.bundle.js.container@ (CMP-8). Fails the test if the container sidecar
-- was not written. Both are read as RAW bytes so the byte-identity check
-- (payload == bundle) is exact, independent of any text decoding.
compileNativeWithContainer :: String -> Mode -> IO (BS.ByteString, BS.ByteString)
compileNativeWithContainer source mode =
  Temp.withSystemTempDirectory "can-cmp8" $ \tmp -> do
    setupProject tmp source
    runCompileNative tmp mode
    bundle <- BS.readFile (tmp </> "canopy.bundle.js")
    let containerPath = tmp </> "canopy.bundle.js.container"
    containerExists <- Dir.doesFileExist containerPath
    if not containerExists
      then assertFailure "CMP-8: canopy make --target native must write canopy.bundle.js.container"
      else do
        container <- BS.readFile containerPath
        BS.length bundle `seq` BS.length container `seq` pure ()
        pure (bundle, container)

-- | Compile the sample with @--target native@, then evaluate + boot it under
-- node behind a minimal Fabric mock, returning combined stdout+stderr.
compileNativeAndBoot :: String -> IO String
compileNativeAndBoot source =
  Temp.withSystemTempDirectory "can-cmp5-boot" $ \tmp -> do
    setupProject tmp source
    runCompileNative tmp DevMode
    writeFile (tmp </> "boot.js") (bootHarness (tmp </> "canopy.bundle.js"))
    (_exit, out, err) <- Process.readProcessWithExitCode "node" [tmp </> "boot.js"] ""
    pure (out ++ "\n" ++ err)

-- | A node harness that mocks the Fabric host globals, evaluates the bundle,
-- prints whether @__canopy_boot@ is installed, then boots it. A
-- post-module-eval host/JSON FFI throw (no real DOM) is tolerated; only a
-- @ReferenceError@ matters here.
bootHarness :: FilePath -> String
bootHarness bundlePath =
  unlines
    [ "var fs = require('fs');",
      "var g = globalThis;",
      "['createView','updateProps','appendChild','insertChild','removeChild','setRoot']",
      "  .forEach(function(n){ g['__fabric_' + n] = function(){ return {}; }; });",
      "var code = fs.readFileSync(" ++ show bundlePath ++ ", 'utf8');",
      "try { (0, eval)(code); } catch (e) {",
      "  if (/ReferenceError|is not defined/.test(String(e))) { console.log(String(e)); }",
      "}",
      "console.log('__canopy_boot:' + (typeof g.__canopy_boot));",
      "try { if (typeof g.__canopy_boot === 'function') g.__canopy_boot(null, {}); }",
      "catch (e) { if (/ReferenceError|is not defined/.test(String(e))) console.log(String(e)); }"
    ]

-- | Set up a Canopy application project (matches the sibling CMP-4 suite).
setupProject :: FilePath -> String -> IO ()
setupProject root source = do
  Dir.createDirectoryIfMissing True (root </> "src")
  writeFile (root </> "canopy.json") canopyJson
  writeFile (root </> "src" </> "Main.can") source

-- | Compile @src/Main.can@ to @canopy.bundle.js@ with @--target native@.
runCompileNative :: FilePath -> Mode -> IO ()
runCompileNative projectDir mode = do
  canopyBin <- findCanopyBinary
  let args =
        ["make", "src/Main.can", "--output=canopy.bundle.js", "--target", "native"]
          ++ modeFlags mode
      cp = (Process.proc canopyBin args) {Process.cwd = Just projectDir}
  (exitCode, stdout, stderr) <- Process.readCreateProcessWithExitCode cp ""
  case exitCode of
    Exit.ExitSuccess -> pure ()
    Exit.ExitFailure code ->
      assertFailure
        ( "canopy make --target native failed with code "
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

ensurePrereqs :: IO ()
ensurePrereqs = do
  canopyOk <- checkCanopyAvailable
  nodeOk <- checkAvailable "node" ["--version"]
  if canopyOk && nodeOk
    then pure ()
    else
      assertFailure
        "Prerequisites not met: need both 'canopy' (stack build) and 'node' on PATH"

checkCanopyAvailable :: IO Bool
checkCanopyAvailable = do
  (exitCode, _, _) <-
    Process.readProcessWithExitCode "stack" ["exec", "--", "canopy", "--version"] ""
  pure (exitCode == Exit.ExitSuccess)

checkAvailable :: FilePath -> [String] -> IO Bool
checkAvailable cmd args = do
  (exitCode, _, _) <- Process.readProcessWithExitCode cmd args ""
  pure (exitCode == Exit.ExitSuccess)

-- ---------------------------------------------------------------------------
-- HELPERS
-- ---------------------------------------------------------------------------

assertHas :: String -> String -> String -> IO ()
assertHas haystack needle label =
  assertBool
    ("expected the native bundle to contain the " ++ label ++ " (" ++ show needle ++ ")")
    (needle `isInfixOf` haystack)

-- | The substring of @s@ that follows the first occurrence of @needle@.
afterSubstr :: String -> String -> String
afterSubstr _ [] = ""
afterSubstr needle s@(_ : rest)
  | needle `isPrefixOf` s = drop (length needle) s
  | otherwise = afterSubstr needle rest

-- | Recover the inlined map JSON from the bundle by un-escaping the
-- @globalThis.__canopy_sourcemap = "..."@ string literal — mirroring
-- @JSON.parse@ on the host — so it can be compared to the standalone @.map@.
inlinedMapJson :: String -> Maybe String
inlinedMapJson bundle =
  let body = afterSubstr "globalThis.__canopy_sourcemap = \"" bundle
   in if null body && not ("globalThis.__canopy_sourcemap = \"" `isInfixOf` bundle)
        then Nothing
        else Just (unescapeJsString body)

unescapeJsString :: String -> String
unescapeJsString [] = []
unescapeJsString ('"' : _) = []
unescapeJsString ('\\' : c : rest) =
  let ch = case c of
        'n' -> '\n'
        'r' -> '\r'
        't' -> '\t'
        '"' -> '"'
        '\\' -> '\\'
        other -> other
   in ch : unescapeJsString rest
unescapeJsString (c : rest) = c : unescapeJsString rest

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
