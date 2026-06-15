{-# LANGUAGE OverloadedStrings #-}

-- | Hermes stdlib-shim conformance suite (CMP-10).
--
-- == What this gate proves
--
-- The native target runs the SAME IIFE bundle the validated web path runs, but
-- under Hermes. Hermes's standard library diverges from Node/V8 in exactly the
-- three places the Canopy stdlib touches — @Intl@, @Date@ timezone, and
-- @RegExp@ — and every divergence is a SILENT correctness bug, not a crash
-- (see "Generate.JavaScript.HermesShim"). This suite is the gate that the
-- compiler-emitted Hermes shim closes those gaps:
--
--   1. (ships) the shim is present in the native (IIFE) bundle the host loads,
--      in both dev and @--optimize@ mode.
--   2. (no-op under a full engine) under Node — the conformance BASELINE — the
--      shim engages nothing: native @Intl@/@Date@ are left intact, so the
--      bundle behaves byte-for-byte as the web path does. A real Canopy program
--      that uses @canopy/time@ compiles and runs unchanged.
--   3. (closes the gap under Hermes) under a SIMULATED-Hermes sandbox (a Node
--      context with @Intl@ removed, @getTimezoneOffset@ forced to UTC, and the
--      @HermesInternal@ marker present — modelling Hermes's documented
--      divergences) the shim:
--        * answers the ONE scoped @Intl@ probe @canopy/time@ uses
--          (@DateTimeFormat().resolvedOptions().timeZone@) deterministically;
--        * throws an IDENTIFIABLE error ('HermesShim.unsupportedIntlSentinel')
--          for every out-of-scope @Intl@ use — never a wrong-but-plausible
--          value (the plan: "explicit unsupported-feature errors over silent
--          mismatch", "scope Intl to exactly what canopy/time exposes — error
--          on the rest");
--        * records the timezone-capability truth so the host can surface the
--          @Date@ divergence instead of silently shipping a UTC zone.
--   4. (regex gate, both engines) an unsupported @RegExp@ feature (lookbehind,
--      Unicode-property escape) is a LOUD error
--      ('HermesShim.unsupportedRegexSentinel') at construction on BOTH engines
--      — so an unsupported pattern fails in CI (Node) instead of only on a
--      device — while a legitimately-Hermes-supported pattern (named groups,
--      ordinary classes) is left alone.
--
-- == "Same program under node + headless Hermes"
--
-- The plan calls for running the same programs "under node + headless Hermes,
-- assert identical output." Node is driven directly here (the real engine,
-- the validated baseline). A real standalone @hermes@\/@hermesc@ CLI is NOT
-- present on the Linux CI box (only the vendored @libhermes.so@ + headers ship
-- — see open question (c) in plans/10), so the headless-Hermes leg is BEHAVIOUR
-- -MODELLED here (the simulated-Hermes sandbox above, which reproduces exactly
-- the @Intl@/@Date@ divergences Hermes exhibits) and additionally driven
-- against a real @hermes@ binary IFF one is on @PATH@ ('realHermesTests'), which
-- self-skips loudly otherwise rather than silently passing. On a device/Mac with
-- the matched @hermes@ the same assertions run against the true engine.
--
-- Requires @canopy@ (built via @stack build@) and @node@ on @PATH@, plus the
-- @canopy/core@ + @canopy/html@ + @canopy/time@ packages in the cache. Same
-- loud-fail prerequisite policy as 'Integration.Native.CodegenSuiteTest'.
--
-- @since 0.20.8
module Integration.Hermes.ConformanceTest (tests) where

import qualified Data.List as List
import qualified Generate.JavaScript.HermesShim as HermesShim
import qualified System.Directory as Dir
import qualified System.Exit as Exit
import System.FilePath ((</>))
import qualified System.IO.Temp as Temp
import qualified System.Process as Process
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase)

-- | All Hermes-conformance gate tests.
tests :: TestTree
tests =
  testGroup
    "Hermes.Conformance (CMP-10)"
    [ shipsTests,
      nodeBaselineTests,
      simulatedHermesTests,
      regexGateTests,
      realHermesTests
    ]

-- ---------------------------------------------------------------------------
-- 1. THE SHIM SHIPS IN THE NATIVE BUNDLE
-- ---------------------------------------------------------------------------

-- | The native (IIFE) bundle the Hermes host loads carries the shim, in both
-- modes. (The web path uses the separate ESM emitter, which is unaffected.)
shipsTests :: TestTree
shipsTests =
  testGroup
    "shim ships in the native bundle"
    [ testCase "dev IIFE contains the Hermes shim marker + sentinels" $
        assertShimPresent DevMode,
      testCase "optimized IIFE contains the Hermes shim marker + sentinels" $
        assertShimPresent OptimizeMode
    ]

assertShimPresent :: Mode -> IO ()
assertShimPresent mode = do
  ensurePrereqs
  bundle <- compileSample timeSample mode
  let text = unlines bundle
  assertBool
    ("native " ++ show mode ++ " bundle is missing the Hermes shim marker '" ++ HermesShim.shimMarkerName ++ "'")
    (HermesShim.shimMarkerName `List.isInfixOf` text)
  assertBool
    ("native " ++ show mode ++ " bundle is missing the unsupported-Intl sentinel")
    (HermesShim.unsupportedIntlSentinel `List.isInfixOf` text)
  assertBool
    ("native " ++ show mode ++ " bundle is missing the unsupported-RegExp sentinel")
    (HermesShim.unsupportedRegexSentinel `List.isInfixOf` text)

-- ---------------------------------------------------------------------------
-- 2. NODE BASELINE — the shim is a no-op under a full engine
-- ---------------------------------------------------------------------------

-- | Under Node (the conformance baseline) a real @canopy/time@ program runs
-- unchanged and the shim engages nothing (native @Intl@ left intact).
nodeBaselineTests :: TestTree
nodeBaselineTests =
  testGroup
    "node baseline (shim is a no-op under a full engine)"
    [ testCase "a canopy/time program compiles + runs under node, no ReferenceError" $ do
        ensurePrereqs
        output <- compileAndCapture timeSample DevMode
        let refErrs = filter isReferenceError (lines output)
        assertBool
          ("the canopy/time bundle raised a free-identifier error:\n  " ++ List.intercalate "\n  " refErrs)
          (null refErrs)
        assertBool
          ("expected RESULT: \"ok\" in node output, got:\n" ++ output)
          ("RESULT: \"ok\"" `List.isInfixOf` output),
      testCase "under node the shim leaves native Intl intact (engine=full, shimmedIntl=false)" $ do
        ensurePrereqs
        shim <- extractShim
        out <- runShimProbe shim fullEngineProbe
        assertProbe out "engine=full"
        assertProbe out "shimmedIntl=false"
        assertProbe out "nativeIntlUsed=true"
    ]

-- ---------------------------------------------------------------------------
-- 3. SIMULATED HERMES — the shim closes the gap
-- ---------------------------------------------------------------------------

-- | Under a simulated-Hermes sandbox the shim supplies the scoped @Intl@ probe
-- and errors loudly out of scope.
simulatedHermesTests :: TestTree
simulatedHermesTests =
  testGroup
    "simulated Hermes (shim closes the Intl/Date gap)"
    [ testCase "Intl installed; scoped timeZone probe answers deterministically (UTC)" $ do
        ensurePrereqs
        shim <- extractShim
        out <- runShimProbe shim hermesScopedProbe
        assertProbe out "engine=hermes"
        assertProbe out "shimmedIntl=true"
        assertProbe out "intlDefined=true"
        assertProbe out "timeZone=UTC",
      testCase "out-of-scope Intl (NumberFormat) throws the identifiable sentinel" $ do
        ensurePrereqs
        shim <- extractShim
        out <- runShimProbe shim hermesNumberFormatProbe
        assertProbe out "numberFormatThrew=true"
        assertProbe out ("sentinelMatched=true"),
      testCase "out-of-scope Intl (DateTimeFormat with options) throws the sentinel" $ do
        ensurePrereqs
        shim <- extractShim
        out <- runShimProbe shim hermesDtfOptionsProbe
        assertProbe out "dtfOptionsThrew=true"
        assertProbe out "sentinelMatched=true",
      testCase "Date timezone divergence is recorded (hasLocalTimeZone=false on Hermes)" $ do
        ensurePrereqs
        shim <- extractShim
        out <- runShimProbe shim hermesScopedProbe
        assertProbe out "hasLocalTimeZone=false"
    ]

-- ---------------------------------------------------------------------------
-- 4. REGEX FEATURE GATE — loud error on both engines
-- ---------------------------------------------------------------------------

regexGateTests :: TestTree
regexGateTests =
  testGroup
    "RegExp feature gate (loud on both engines)"
    [ testCase "lookbehind (?<=...) is blocked with the identifiable sentinel" $ do
        ensurePrereqs
        shim <- extractShim
        out <- runShimProbe shim (regexProbe "(/(?<=a)b/).source")
        assertProbe out "blocked=true"
        assertProbe out "sentinelMatched=true",
      testCase "negative lookbehind (?<!...) is blocked" $ do
        ensurePrereqs
        shim <- extractShim
        out <- runShimProbe shim (regexProbe "(/(?<!a)b/).source")
        assertProbe out "blocked=true",
      testCase "Unicode property escape \\p{...} is blocked" $ do
        ensurePrereqs
        shim <- extractShim
        out <- runShimProbe shim (regexProbe "(/\\p{L}/u).source")
        assertProbe out "blocked=true",
      testCase "named group (?<name>...) is ALLOWED (not confused with lookbehind)" $ do
        ensurePrereqs
        shim <- extractShim
        out <- runShimProbe shim (regexProbe "(/(?<yr>\\d+)/).source")
        assertProbe out "blocked=false",
      testCase "an ordinary pattern is ALLOWED" $ do
        ensurePrereqs
        shim <- extractShim
        out <- runShimProbe shim (regexProbe "(/ab+c\\d*/).source")
        assertProbe out "blocked=false",
      testCase "new RegExp(...) with lookbehind is blocked at construction" $ do
        ensurePrereqs
        shim <- extractShim
        out <- runShimProbe shim newRegexProbe
        assertProbe out "ctorThrew=true"
        assertProbe out "sentinelMatched=true"
    ]

-- ---------------------------------------------------------------------------
-- 5. REAL HEADLESS HERMES — gated, self-skips loudly when absent
-- ---------------------------------------------------------------------------

-- | If a real @hermes@ CLI is on @PATH@ (a Mac/device dev box, or a CI image
-- that vendors a runnable @hermes@), run the scoped probe against the TRUE
-- engine and assert the same conformance. Otherwise self-skip with a visible
-- note — never silently pass. (The Linux CI box ships @libhermes.so@ + headers
-- but no standalone @hermes@ binary; see plans/10 open question (c).)
realHermesTests :: TestTree
realHermesTests =
  testGroup
    "real headless Hermes (gated)"
    [ testCase "scoped probe under a real hermes binary (skips if absent)" $ do
        mHermes <- findHermesBinary
        case mHermes of
          Nothing ->
            -- Visible skip: a no-op assertion plus a note on stderr-equivalent.
            -- We assert True so the gate is green, but print the skip reason so
            -- it is never mistaken for a real pass.
            putStrLn
              "  [skip] no standalone 'hermes' binary on PATH — real headless-Hermes leg deferred to a device/Mac CI image (Linux box ships libhermes.so only)."
          Just hermesBin -> do
            ensurePrereqs
            shim <- extractShim
            out <- runShimProbeUnder hermesBin shim hermesScopedRealProbe
            -- On a real Hermes WITHOUT intl, the shim installs Intl and answers
            -- the scoped probe. On a Hermes built WITH intl, the native Intl is
            -- used. Either way the scoped timeZone probe must succeed (not throw)
            -- and the marker must be present.
            assertProbe out "markerPresent=true"
            assertProbe out "timeZoneOk=true"
    ]

-- | Find a standalone @hermes@ binary on PATH (not @hermesc@; we want the VM).
findHermesBinary :: IO (Maybe FilePath)
findHermesBinary = Dir.findExecutable "hermes"

-- ---------------------------------------------------------------------------
-- THE SHIM-PROBE HARNESS
-- ---------------------------------------------------------------------------

-- | A probe is a JS snippet that, given a context where the shim has already
-- run, prints @key=value@ lines this suite asserts on. The harness:
--
--   * extracts the shim IIFE from a freshly-compiled native bundle,
--   * (optionally) mutates the engine to model Hermes BEFORE the shim runs,
--   * runs the shim, then the probe,
--   * captures stdout.
--
-- Running the shim against the COMPILED bundle's own shim text (not a copy)
-- guarantees we test exactly what ships.

-- | Build the full JS the engine evaluates: optional pre-shim engine mutation,
-- then the (real, compiled) shim, then the probe.
buildProbeScript :: String -> Probe -> String
buildProbeScript shimSrc (Probe preMutation probeBody) =
  unlines
    [ "(function () {",
      preMutation,
      shimSrc,
      "var __h = (typeof globalThis !== 'undefined' ? globalThis : this).__canopy_hermes;",
      probeBody,
      "}());"
    ]

-- | A probe: JS run BEFORE the shim (to model the engine) and JS run AFTER.
data Probe = Probe
  { _preMutation :: String,
    _probeBody :: String
  }

-- | Run a probe under @node@ and return stdout.
runShimProbe :: String -> Probe -> IO String
runShimProbe = runShimProbeUnder "node"

-- | Run a probe under the given JS engine binary and return stdout.
runShimProbeUnder :: FilePath -> String -> Probe -> IO String
runShimProbeUnder engineBin shimSrc probe =
  Temp.withSystemTempDirectory "can-cmp10-probe" $ \tmp -> do
    let scriptPath = tmp </> "probe.js"
    writeFile scriptPath (buildProbeScript shimSrc probe)
    (_exit, out, err) <- Process.readProcessWithExitCode engineBin [scriptPath] ""
    pure (out ++ err)

-- | Assert a @key=value@ line is present in probe output.
assertProbe :: String -> String -> IO ()
assertProbe output kv =
  assertBool
    ("expected probe output to contain '" ++ kv ++ "', full output:\n" ++ output)
    (kv `List.isInfixOf` output)

-- ---- the probes -----------------------------------------------------------

-- | Full-engine (Node) probe: assert the shim is a no-op and native Intl wins.
fullEngineProbe :: Probe
fullEngineProbe =
  Probe
    ""
    ( unlines
        [ "console.log('engine=' + __h.engine);",
          "console.log('shimmedIntl=' + __h.shimmedIntl);",
          -- Native Intl must still produce a real (non-UTC-fallback would also be",
          -- fine, but on this box it is a real zone) timeZone, proving it wasn't",
          -- replaced by the shim's UTC stub.
          "var tz = Intl.DateTimeFormat().resolvedOptions().timeZone;",
          "console.log('nativeIntlUsed=' + (typeof tz === 'string' && tz.length > 0));"
        ]
    )

-- | Pre-shim mutation that models Hermes: remove Intl, force tz=UTC, mark engine.
hermesMutation :: String
hermesMutation =
  unlines
    [ "HermesInternal = {};",
      "try { delete this.Intl; } catch (e) {}",
      "Intl = undefined;",
      "Date.prototype.getTimezoneOffset = function () { return 0; };"
    ]

-- | Simulated-Hermes scoped probe: the one Intl surface canopy/time uses.
hermesScopedProbe :: Probe
hermesScopedProbe =
  Probe
    hermesMutation
    ( unlines
        [ "console.log('engine=' + __h.engine);",
          "console.log('shimmedIntl=' + __h.shimmedIntl);",
          "console.log('intlDefined=' + (typeof Intl !== 'undefined'));",
          "console.log('hasLocalTimeZone=' + __h.hasLocalTimeZone);",
          "var tz = Intl.DateTimeFormat().resolvedOptions().timeZone;",
          "console.log('timeZone=' + tz);"
        ]
    )

-- | Out-of-scope: Intl.NumberFormat must throw the identifiable sentinel.
hermesNumberFormatProbe :: Probe
hermesNumberFormatProbe =
  Probe
    hermesMutation
    (sentinelCatch "Intl.NumberFormat()" "numberFormatThrew" HermesShim.unsupportedIntlSentinel)

-- | Out-of-scope: Intl.DateTimeFormat WITH options must throw the sentinel.
hermesDtfOptionsProbe :: Probe
hermesDtfOptionsProbe =
  Probe
    hermesMutation
    (sentinelCatch "Intl.DateTimeFormat([], { hour: '2-digit' })" "dtfOptionsThrew" HermesShim.unsupportedIntlSentinel)

-- | RegExp gate probe: checkRegex on the given JS source expression.
regexProbe :: String -> Probe
regexProbe sourceExpr =
  Probe
    ""
    ( unlines
        [ "var blocked = false; var msg = '';",
          "try { __h.checkRegex(" ++ sourceExpr ++ "); }",
          "catch (e) { blocked = true; msg = String(e.message); }",
          "console.log('blocked=' + blocked);",
          "console.log('sentinelMatched=' + (msg.indexOf(" ++ jsString HermesShim.unsupportedRegexSentinel ++ ") === 0));"
        ]
    )

-- | new RegExp(...) construction with an unsupported feature must throw.
newRegexProbe :: Probe
newRegexProbe =
  Probe
    ""
    ( unlines
        [ "var threw = false; var msg = '';",
          "try { new RegExp('(?<=a)b'); }",
          "catch (e) { threw = true; msg = String(e.message); }",
          "console.log('ctorThrew=' + threw);",
          "console.log('sentinelMatched=' + (msg.indexOf(" ++ jsString HermesShim.unsupportedRegexSentinel ++ ") === 0));"
        ]
    )

-- | Real-Hermes scoped probe: tolerant of a Hermes built WITH intl (native Intl
-- used) or WITHOUT (shim used). Asserts the marker is present and the scoped
-- timeZone probe does not throw.
hermesScopedRealProbe :: Probe
hermesScopedRealProbe =
  Probe
    ""
    ( unlines
        [ "console.log('markerPresent=' + (!!__h));",
          "var ok = false;",
          "try { var tz = Intl.DateTimeFormat().resolvedOptions().timeZone; ok = (typeof tz === 'string' && tz.length > 0); }",
          "catch (e) { ok = false; }",
          "console.log('timeZoneOk=' + ok);"
        ]
    )

-- | Emit a try/catch that sets @<flag>=true@ and @sentinelMatched=<bool>@ when
-- @expr@ throws an error whose message starts with @sentinel@.
sentinelCatch :: String -> String -> String -> String
sentinelCatch expr flag sentinel =
  unlines
    [ "var threw = false; var msg = '';",
      "try { " ++ expr ++ "; }",
      "catch (e) { threw = true; msg = String(e.message); }",
      "console.log('" ++ flag ++ "=' + threw);",
      "console.log('sentinelMatched=' + (msg.indexOf(" ++ jsString sentinel ++ ") === 0));"
    ]

-- | Quote a Haskell String as a JS single-quoted literal (sentinels are ASCII).
jsString :: String -> String
jsString s = "'" ++ concatMap esc s ++ "'"
  where
    esc '\'' = "\\'"
    esc '\\' = "\\\\"
    esc c = [c]

-- | Extract the shim IIFE from a freshly-compiled dev bundle, so we test the
-- EXACT text that ships (not a hand-copied snippet).
extractShim :: IO String
extractShim = do
  bundle <- compileSample timeSample DevMode
  let text = unlines bundle
  case sliceShim text of
    Just s -> pure s
    Nothing -> assertFailure "could not locate the Hermes shim IIFE in the compiled bundle" >> pure ""

-- | Slice the shim IIFE out of the bundle text. The shim opens with the unique
-- @(function () {@ + global-resolution prologue 'HermesShim.hermesShimSource'
-- emits, and closes with @}());@.
sliceShim :: String -> Maybe String
sliceShim text =
  let marker = "(function () {\n  var g = (typeof globalThis"
   in case breakOn marker text of
        Nothing -> Nothing
        Just (_, fromStart) ->
          case breakOn "}());" fromStart of
            Nothing -> Nothing
            Just (body, _) -> Just (body ++ "}());")

-- | First @(prefix, suffix-from-needle)@ split at @needle@; Nothing if absent.
breakOn :: String -> String -> Maybe (String, String)
breakOn needle haystack = go "" haystack
  where
    go _ [] = Nothing
    go acc s@(c : cs)
      | needle `List.isPrefixOf` s = Just (reverse acc, s)
      | otherwise = go (c : acc) cs

-- ---------------------------------------------------------------------------
-- THE SAMPLE PROGRAM (exercises canopy/time -> the scoped Intl/Date surface)
-- ---------------------------------------------------------------------------

-- | A program that imports @Time@ so the @canopy/time@ FFI (the only stdlib FFI
-- touching @Intl@/@Date@) is in the dependency graph. Keeps a @Debug.log@ so
-- the node-baseline run has an observable @RESULT@.
timeSample :: String
timeSample =
  unlines
    [ "module Main exposing (main)",
      "",
      "import Html exposing (Html, div, text)",
      "import Time",
      "",
      "",
      "main : Html msg",
      "main =",
      "    let",
      "        _ =",
      "            Debug.log \"RESULT\" \"ok\"",
      "    in",
      "    div [] [ text \"hello\" ]"
    ]

-- ---------------------------------------------------------------------------
-- COMPILE + RUN PLUMBING  (mirrors Integration.Native.CodegenSuiteTest)
-- ---------------------------------------------------------------------------

data Mode = DevMode | OptimizeMode

instance Show Mode where
  show DevMode = "dev"
  show OptimizeMode = "optimize"

modeFlags :: Mode -> [String]
modeFlags DevMode = []
modeFlags OptimizeMode = ["--optimize"]

-- | Compile the sample to an IIFE bundle and return its lines.
compileSample :: String -> Mode -> IO [String]
compileSample source mode =
  Temp.withSystemTempDirectory "can-cmp10" $ \tmp -> do
    setupProject tmp source
    runCompile tmp mode
    bundle <- readFile (tmp </> "elm.js")
    pure (lines bundle)

-- | Compile the sample and run it under node, returning stdout+stderr.
compileAndCapture :: String -> Mode -> IO String
compileAndCapture source mode =
  Temp.withSystemTempDirectory "can-cmp10-run" $ \tmp -> do
    setupProject tmp source
    runCompile tmp mode
    (_exit, out, err) <- Process.readProcessWithExitCode "node" [tmp </> "elm.js"] ""
    pure (out ++ "\n" ++ err)

setupProject :: FilePath -> String -> IO ()
setupProject root source = do
  Dir.createDirectoryIfMissing True (root </> "src")
  writeFile (root </> "canopy.json") canopyJson
  writeFile (root </> "src" </> "Main.can") source

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

isReferenceError :: String -> Bool
isReferenceError line =
  "ReferenceError" `List.isInfixOf` line
    || "is not defined" `List.isInfixOf` line

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

-- | The canopy.json for an application project that depends on @canopy/time@.
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
      "          \"canopy/html\": \"1.0.1\",",
      "          \"canopy/time\": \"1.0.0\"",
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
