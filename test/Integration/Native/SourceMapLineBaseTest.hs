{-# LANGUAGE OverloadedStrings #-}

-- | Integration test for the IIFE / native bundle source-map generated-line
-- base (CMP-6).
--
-- == The bug this pins
--
-- In dev mode the bundle is assembled as
--
-- @
-- (function(scope){...}     -- IIFE header
-- F2..F9 / A2..A9 helpers   -- arity helpers
-- <Canopy runtime>          -- thousands of lines
-- <FFI runtime>             -- embedded FFI
-- <inner preamble>          -- debugger stub, FFI content, perf note, ...
-- <traversal output>        -- the compiled .can defs   <-- mappings point here
-- ...
-- @
--
-- but @State.outputLine@ starts at 0 and counts only the traversal output, so
-- every recorded mapping's generated line was measured from the start of the
-- compiled defs — not from the top of the bundle. The dev red-box therefore
-- pointed at a line near the top of the file (off by the ENTIRE prepended
-- runtime), making symbolicated frames useless. CMP-6 seeds the generated-line
-- base with the newline count of everything emitted before the traversal
-- output.
--
-- == What this test asserts
--
-- Compile a small multi-def app to a dev IIFE (@--output-format=iife@), then for
-- a known top-level definition:
--
--   1. (line base applied) the source map resolves @Main.can:<defLine>@ to a
--      generated line that is DEEP in the bundle (past the runtime) — the
--      pre-fix bug put it within the first handful of lines.
--   2. (byte-accurate) that generated line in the emitted @.js@ actually
--      contains the definition's JS (@var $author$project$Main$<name> =@). This
--      is the end-to-end "a known .can line maps to the correct generated line"
--      gate the CMP-6 plan calls for, and it transitively exercises the V3
--      semicolon encoding (one separator per generated line, no off-by-one).
--
-- Requires @canopy@ on PATH (built via @stack build@) and the @canopy\/core@ +
-- @canopy\/html@ packages installed in the cache. The test self-skips with a
-- failure message if the prerequisites are absent (same policy as
-- 'Integration.JsExecutionTest').
--
-- @since 0.20.6
module Integration.Native.SourceMapLineBaseTest (tests) where

import qualified Data.Aeson as Aeson
import Data.Aeson ((.:))
import qualified Data.Bits as Bits
import qualified Data.ByteString.Lazy.Char8 as LBS8
import qualified Data.List as List
import qualified Data.Maybe as Maybe
import qualified System.Directory as Dir
import qualified System.Exit as Exit
import System.FilePath ((</>))
import qualified System.IO.Temp as Temp
import qualified System.Process as Process
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase)

-- | All native source-map line-base tests.
tests :: TestTree
tests =
  testGroup
    "Native.SourceMapLineBase (CMP-6)"
    [ testKnownDefMapsToByteAccurateLine,
      testLineBaseIsPastTheRuntime
    ]

-- A small multi-definition program. Each top-level def is on a distinct,
-- known .can line so its mapping can be looked up by source line.
--
-- Layout (1-based .can lines):
--   7  : greeting =
--   12 : doubler n =
--   16 : main =
sampleSource :: String
sampleSource =
  unlines
    [ "module Main exposing (main)", -- 1
      "", -- 2
      "import Html exposing (text)", -- 3
      "", -- 4
      "", -- 5
      "greeting : String", -- 6
      "greeting =", -- 7
      "    \"hello\"", -- 8
      "", -- 9
      "", -- 10
      "doubler : Int -> Int", -- 11
      "doubler n =", -- 12
      "    n * 2", -- 13
      "", -- 14
      "", -- 15
      "main =", -- 16
      "    let", -- 17
      "        _ = Debug.log \"RESULT\" (doubler 21)", -- 18
      "        _x = Debug.log \"GREET\" greeting", -- 19
      "    in", -- 20
      "    text \"\"" -- 21
    ]

-- | A known top-level def: its .can source line (1-based) and the JS identifier
-- the compiler emits for it.
data KnownDef = KnownDef
  { _kdSrcLine :: Int,
    _kdJsIdent :: String
  }

greetingDef :: KnownDef
greetingDef = KnownDef 7 "$author$project$Main$greeting"

doublerDef :: KnownDef
doublerDef = KnownDef 12 "$author$project$Main$doubler"

mainDef :: KnownDef
mainDef = KnownDef 16 "$author$project$Main$main"

-- TESTS

-- | The known-def mapping resolves to the generated line that actually defines
-- it — the byte-accurate, end-to-end gate for CMP-6.
testKnownDefMapsToByteAccurateLine :: TestTree
testKnownDefMapsToByteAccurateLine =
  testCase "known .can def lines map to their byte-accurate generated lines" $
    withPrereqs $ \(bundleLines, mappings) ->
      mapM_ (assertDefByteAccurate bundleLines mappings)
        [greetingDef, doublerDef, mainDef]

-- | The mapped generated line is DEEP in the bundle (past the prepended
-- runtime). Pre-fix, every mapping sat within the first few lines (base 0);
-- this is the direct regression guard for the line-base seed.
testLineBaseIsPastTheRuntime :: TestTree
testLineBaseIsPastTheRuntime =
  testCase "generated-line base is seeded past the runtime (not ~line 0)" $
    withPrereqs $ \(bundleLines, mappings) -> do
      genLine <- requireMapping mappings (_kdSrcLine doublerDef)
      let total = length bundleLines
      -- The runtime + helpers alone are thousands of lines; the user defs land
      -- near the END of the bundle. A correct base puts the mapping in the last
      -- 5% of the file. The pre-fix bug put it at line < 10.
      assertBool
        ( "expected the def's generated line ("
            ++ show genLine
            ++ ") to be deep in the "
            ++ show total
            ++ "-line bundle (past the runtime); a near-zero line means the "
            ++ "line-base seed regressed"
        )
        (genLine > total * 9 `div` 10)

-- | Assert that the source map resolves the def's .can line to a generated line
-- whose text in the bundle is the def's @var <ident> =@ declaration.
assertDefByteAccurate :: [String] -> [Mapping] -> KnownDef -> IO ()
assertDefByteAccurate bundleLines mappings (KnownDef srcLine ident) = do
  genLine <- requireMapping mappings srcLine
  let want = "var " ++ ident ++ " ="
  case lineAt bundleLines genLine of
    Nothing ->
      assertFailure
        ( "mapping for Main.can:"
            ++ show srcLine
            ++ " points at generated line "
            ++ show genLine
            ++ " which is out of range (bundle has "
            ++ show (length bundleLines)
            ++ " lines)"
        )
    Just lineText ->
      assertBool
        ( "mapping for Main.can:"
            ++ show srcLine
            ++ " should resolve to the def line containing "
            ++ show want
            ++ ", but generated line "
            ++ show genLine
            ++ " is:\n    "
            ++ lineText
        )
        (want `List.isInfixOf` lineText)

-- | Look up the (0-based) generated line a given 1-based Main.can source line
-- maps to, failing if no mapping references it.
requireMapping :: [Mapping] -> Int -> IO Int
requireMapping mappings srcLine1Based =
  case List.find (\m -> mSrcModule m == "Main.can" && mSrcLine m == srcLine1Based - 1) mappings of
    Just m -> pure (mGenLine m)
    Nothing ->
      assertFailure
        ( "no source-map mapping found for Main.can:"
            ++ show srcLine1Based
            ++ " (have: "
            ++ show
                 [ (mSrcModule m, mSrcLine m + 1)
                 | m <- mappings,
                   mSrcModule m == "Main.can"
                 ]
            ++ ")"
        )
        >> pure (-1)

-- | Safe (0-based) line indexing into the bundle.
lineAt :: [String] -> Int -> Maybe String
lineAt ls i
  | i < 0 || i >= length ls = Nothing
  | otherwise = Just (ls !! i)

-- PREREQUISITES + COMPILE

-- | Run the test body with the compiled bundle lines and decoded mappings, or
-- fail loudly if the canopy binary is unavailable.
withPrereqs :: (([String], [Mapping]) -> IO ()) -> IO ()
withPrereqs action = do
  canopyOk <- checkCanopyAvailable
  if not canopyOk
    then assertFailure "Prerequisite not met: need 'canopy' on PATH (stack build)"
    else do
      artifacts <- compileSample
      action artifacts

-- | Check whether the canopy binary is available via stack exec.
checkCanopyAvailable :: IO Bool
checkCanopyAvailable = do
  (exitCode, _, _) <-
    Process.readProcessWithExitCode "stack" ["exec", "--", "canopy", "--version"] ""
  pure (exitCode == Exit.ExitSuccess)

-- | Compile the sample app to a dev IIFE and return (bundle lines, decoded
-- source-map mappings).
compileSample :: IO ([String], [Mapping])
compileSample =
  Temp.withSystemTempDirectory "can-cmp6" $ \tmp -> do
    Dir.createDirectoryIfMissing True (tmp </> "src")
    writeFile (tmp </> "canopy.json") canopyJson
    writeFile (tmp </> "src" </> "Main.can") sampleSource
    compileProject tmp
    bundle <- readFile (tmp </> "elm.js")
    rawMap <- readFile (tmp </> "elm.js.map")
    mappings <- either failParse pure (decodeSourceMap rawMap)
    pure (lines bundle, mappings)
  where
    failParse err = assertFailure ("could not parse elm.js.map: " ++ err) >> pure []

-- | Compile @src/Main.can@ to @elm.js@ + @elm.js.map@ in dev IIFE mode.
compileProject :: FilePath -> IO ()
compileProject projectDir = do
  canopyBin <- findCanopyBinary
  let cp =
        (Process.proc canopyBin ["make", "src/Main.can", "--output=elm.js", "--output-format=iife"])
          { Process.cwd = Just projectDir }
  (exitCode, stdout, stderr) <- Process.readCreateProcessWithExitCode cp ""
  case exitCode of
    Exit.ExitSuccess -> pure ()
    Exit.ExitFailure code ->
      assertFailure
        ( "canopy make failed with code "
            ++ show code
            ++ "\nstdout: "
            ++ stdout
            ++ "\nstderr: "
            ++ stderr
        )

-- | Find the canopy binary via stack path, falling back to PATH.
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

-- | The canopy.json for an application project (matches JsExecutionTest).
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

-- SOURCE-MAP DECODING
--
-- A self-contained Source Map V3 decoder (so the test does not depend on node).
-- It mirrors the spec the compiler's encoder targets: @;@ separates generated
-- lines (line index = number of preceding @;@), @,@ separates segments, and
-- each segment is Base64-VLQ deltas [genCol, srcIndex, srcLine, srcCol(, name)].

-- | A decoded mapping: a generated (0-based) line, the source module it points
-- to, and the (0-based) source line within that module.
data Mapping = Mapping
  { mGenLine :: Int,
    mSrcModule :: String,
    mSrcLine :: Int
  }
  deriving (Show)

-- | The fields of a source-map JSON document we care about: the @sources@
-- array and the VLQ @mappings@ string.
data RawMap = RawMap [String] String

instance Aeson.FromJSON RawMap where
  parseJSON = Aeson.withObject "SourceMap" $ \o ->
    RawMap <$> o .: "sources" <*> o .: "mappings"

-- | Parse the .js.map JSON and decode its VLQ mappings into 'Mapping's.
decodeSourceMap :: String -> Either String [Mapping]
decodeSourceMap raw =
  case Aeson.eitherDecode (LBS8.pack raw) of
    Left err -> Left err
    Right (RawMap sources mappings) ->
      Right (decodeMappings sources mappings)

-- | Decode the @mappings@ string into 'Mapping's using running VLQ state.
--
-- Only the generated line, source index and source line are retained (genCol
-- and srcCol are not needed for line-level assertions). srcIndex and srcLine
-- carry across segments/lines per the V3 relative-delta scheme; genCol resets
-- at each generated line.
decodeMappings :: [String] -> String -> [Mapping]
decodeMappings sources mappingsStr =
  concat (go 0 0 0 (splitLines mappingsStr))
  where
    splitLines = foldr step [[]]
      where
        step ';' acc = [] : acc
        step c (cur : rest) = (cur ++ [c]) : rest
        step _ [] = [[]]
    go _ _ _ [] = []
    go genLine srcIdx srcLine (lineStr : rest) =
      let segs = splitSegs lineStr
          (decoded, srcIdx', srcLine') = decodeSegs genLine srcIdx srcLine segs
       in decoded : go (genLine + 1) srcIdx' srcLine' rest
    splitSegs = filter (not . null) . foldr step [[]]
      where
        step ',' acc = [] : acc
        step c (cur : r) = (cur ++ [c]) : r
        step _ [] = [[]]
    decodeSegs _ srcIdx srcLine [] = ([], srcIdx, srcLine)
    decodeSegs genLine srcIdx srcLine (seg : segs) =
      let fields = decodeVLQs seg
       in case fields of
            (_genCol : srcIdxD : srcLineD : _srcColD : _) ->
              let srcIdx' = srcIdx + srcIdxD
                  srcLine' = srcLine + srcLineD
                  modName = sourceAt sources srcIdx'
                  m = Mapping genLine modName srcLine'
                  (ms, fIdx, fLine) = decodeSegs genLine srcIdx' srcLine' segs
               in (m : ms, fIdx, fLine)
            _ ->
              -- A 1-field (genCol-only) segment carries no source position;
              -- skip it but keep running state.
              decodeSegs genLine srcIdx srcLine segs

-- | The source module name at a (sanitized) source index.
sourceAt :: [String] -> Int -> String
sourceAt sources i
  | i >= 0 && i < length sources = sources !! i
  | otherwise = "<out-of-range>"

-- | Decode all Base64-VLQ values packed in a segment string.
decodeVLQs :: String -> [Int]
decodeVLQs [] = []
decodeVLQs s =
  let (val, rest) = decodeOneVLQ s
   in val : decodeVLQs rest

-- | Decode one signed VLQ value, returning it and the unconsumed suffix.
decodeOneVLQ :: String -> (Int, String)
decodeOneVLQ = consume 0 0
  where
    consume shift acc (c : cs) =
      let digit = base64Index c
          acc' = acc Bits..|. ((digit Bits..&. 0x1F) `Bits.shiftL` shift)
          continues = digit Bits..&. 0x20 /= 0
       in if continues
            then consume (shift + 5) acc' cs
            else (fromVLQSigned acc', cs)
    consume _ acc [] = (fromVLQSigned acc, [])
    fromVLQSigned v =
      let magnitude = v `Bits.shiftR` 1
       in if v Bits..&. 1 == 1 then negate magnitude else magnitude

-- | Index of a character in the Base64 VLQ alphabet (-1 if absent).
base64Index :: Char -> Int
base64Index c = Maybe.fromMaybe 0 (List.elemIndex c base64Alphabet)

base64Alphabet :: String
base64Alphabet =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
