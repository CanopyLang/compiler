{-# LANGUAGE OverloadedStrings #-}

-- | Integration test for def-level generated-column precision (CMP-7A).
--
-- == What CMP-7A adds on top of CMP-6
--
-- CMP-6 seeded the source map's generated-LINE base so a dev red-box pointed at
-- the right line of the bundle. CMP-7A makes each def's mapping carry a precise
-- generated COLUMN instead of the hard-coded @0@: the byte offset, within the
-- def's generated line, at which the def's emitted name begins. Because every
-- emitted statement is newline-terminated, a def's @var \<name\> = ...@ statement
-- always starts at column 0 of its generated line, so the def-distinguishing
-- column is the offset of the NAME within that statement — i.e. exactly past the
-- @"var "@ prefix (4 columns). A symbolicated frame then resolves to the right
-- def + column, not merely the right line.
--
-- == What this test asserts (end-to-end)
--
-- Compile a small multi-def app to a dev IIFE (@--output-format=iife@), decode
-- the real V3 source map, and for each known top-level def:
--
--   1. (non-zero, byte-accurate genCol) the decoded generated column is NOT 0
--      (the pre-CMP-7A value) and the bundle's generated line, sliced at exactly
--      that column, begins with the def's JS identifier (@$author$project$Main$<name>@).
--      This is the direct "the column points at the def name" gate.
--   2. (source column preserved) the mapping's source column resolves to the
--      def's start column in the @.can@ file (column 1, 1-based) — confirming the
--      @Ann.Region@ start column still flows into @_mSrcCol@ unchanged.
--
-- Requires @canopy@ on PATH (built via @stack build@) and the @canopy\/core@ +
-- @canopy\/html@ packages installed in the cache. Self-fails with a clear message
-- if the prerequisites are absent (same policy as 'Integration.Native.SourceMapLineBaseTest').
--
-- @since 0.20.9
module Integration.Native.SourceMapColumnTest (tests) where

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

-- | All native source-map column-precision tests.
tests :: TestTree
tests =
  testGroup
    "Native.SourceMapColumn (CMP-7A)"
    [ testDefColumnsAreByteAccurate,
      testDefColumnsAreNonZero
    ]

-- A small multi-definition program. Each top-level def is on a distinct, known
-- .can line (and starts at .can column 1) so its mapping can be looked up.
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

knownDefs :: [KnownDef]
knownDefs = [greetingDef, doublerDef, mainDef]

-- TESTS

-- | Each known def's generated column is byte-accurate: slicing the def's
-- generated bundle line at the mapping's column yields the def's JS identifier.
-- This is the end-to-end "the column points at the def name" gate for CMP-7A.
testDefColumnsAreByteAccurate :: TestTree
testDefColumnsAreByteAccurate =
  testCase "known def columns slice exactly onto the def's JS identifier" $
    withPrereqs $ \(bundleLines, mappings) ->
      mapM_ (assertDefColumnByteAccurate bundleLines mappings) knownDefs

-- | Every known def's generated column is non-zero — the direct regression
-- guard against the pre-CMP-7A hard-coded @_mGenCol = 0@. (A @var \<name\>@
-- statement places the name at column 4, after the @"var "@ prefix.)
testDefColumnsAreNonZero :: TestTree
testDefColumnsAreNonZero =
  testCase "known def columns are non-zero (not the pre-CMP-7A 0)" $
    withPrereqs $ \(_bundleLines, mappings) ->
      mapM_ (assertDefColumnNonZero mappings) knownDefs

-- | Assert the def's mapping column slices exactly onto its JS identifier, and
-- that its source column is the def's .can start column (1).
assertDefColumnByteAccurate :: [String] -> [Mapping] -> KnownDef -> IO ()
assertDefColumnByteAccurate bundleLines mappings (KnownDef srcLine ident) = do
  m <- requireMapping mappings srcLine
  case lineAt bundleLines (mGenLine m) of
    Nothing ->
      assertFailure
        ( "mapping for Main.can:"
            ++ show srcLine
            ++ " points at generated line "
            ++ show (mGenLine m)
            ++ " which is out of range (bundle has "
            ++ show (length bundleLines)
            ++ " lines)"
        )
    Just lineText -> do
      let sliced = drop (mGenCol m) lineText
      assertBool
        ( "mapping for Main.can:"
            ++ show srcLine
            ++ " has generated column "
            ++ show (mGenCol m)
            ++ "; slicing generated line "
            ++ show (mGenLine m)
            ++ " at that column should start with "
            ++ show ident
            ++ ", but the slice is:\n    "
            ++ take 60 sliced
            ++ "\n(full line:\n    "
            ++ lineText
            ++ ")"
        )
        (ident `List.isPrefixOf` sliced)
      -- The source column must remain the def's .can start column (1-based 1,
      -- i.e. 0-based 0 on the wire), confirming Ann.Region start col still feeds
      -- _mSrcCol unchanged by the genCol work.
      assertBool
        ( "mapping for Main.can:"
            ++ show srcLine
            ++ " should keep source column 0 (the def's .can column 1), got "
            ++ show (mSrcCol m)
        )
        (mSrcCol m == 0)

-- | Assert the def's mapping column is non-zero.
assertDefColumnNonZero :: [Mapping] -> KnownDef -> IO ()
assertDefColumnNonZero mappings (KnownDef srcLine ident) = do
  m <- requireMapping mappings srcLine
  assertBool
    ( "mapping for Main.can:"
        ++ show srcLine
        ++ " (def "
        ++ ident
        ++ ") should have a non-zero generated column after CMP-7A, but got "
        ++ show (mGenCol m)
    )
    (mGenCol m > 0)

-- | Look up the mapping for a 1-based Main.can source line, failing if absent.
requireMapping :: [Mapping] -> Int -> IO Mapping
requireMapping mappings srcLine1Based =
  case List.find (\m -> mSrcModule m == "Main.can" && mSrcLine m == srcLine1Based - 1) mappings of
    Just m -> pure m
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
        >> pure (Mapping 0 0 "" 0 0)

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
    else compileSample >>= action

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
  Temp.withSystemTempDirectory "can-cmp7a" $ \tmp -> do
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

-- | The canopy.json for an application project (matches SourceMapLineBaseTest).
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
-- @;@ separates generated lines (line index = number of preceding @;@), @,@
-- separates segments, and each segment is Base64-VLQ deltas
-- [genCol, srcIndex, srcLine, srcCol(, name)]. genCol resets at each generated
-- line; the other fields carry across the whole stream as relative deltas.

-- | A decoded mapping retaining BOTH the generated column and the source column
-- (CMP-7A needs columns, unlike the line-only decoder in SourceMapLineBaseTest).
data Mapping = Mapping
  { mGenLine :: Int,
    mGenCol :: Int,
    mSrcModule :: String,
    mSrcLine :: Int,
    mSrcCol :: Int
  }
  deriving (Show)

-- | The fields of a source-map JSON document we care about.
data RawMap = RawMap [String] String

instance Aeson.FromJSON RawMap where
  parseJSON = Aeson.withObject "SourceMap" $ \o ->
    RawMap <$> o .: "sources" <*> o .: "mappings"

-- | Parse the .js.map JSON and decode its VLQ mappings.
decodeSourceMap :: String -> Either String [Mapping]
decodeSourceMap raw =
  case Aeson.eitherDecode (LBS8.pack raw) of
    Left err -> Left err
    Right (RawMap sources mappings) -> Right (decodeMappings sources mappings)

-- | Decode the @mappings@ string into 'Mapping's using running VLQ state.
decodeMappings :: [String] -> String -> [Mapping]
decodeMappings sources mappingsStr =
  concat (go 0 0 0 0 (splitOn ';' mappingsStr))
  where
    go _ _ _ _ [] = []
    go genLine srcIdx srcLine srcCol (lineStr : rest) =
      let (decoded, srcIdx', srcLine', srcCol') =
            decodeSegs genLine 0 srcIdx srcLine srcCol (filter (not . null) (splitOn ',' lineStr))
       in decoded : go (genLine + 1) srcIdx' srcLine' srcCol' rest
    decodeSegs _ _ srcIdx srcLine srcCol [] = ([], srcIdx, srcLine, srcCol)
    decodeSegs genLine genCol srcIdx srcLine srcCol (seg : segs) =
      case decodeVLQs seg of
        (gcD : srcIdxD : srcLineD : srcColD : _) ->
          let genCol' = genCol + gcD
              srcIdx' = srcIdx + srcIdxD
              srcLine' = srcLine + srcLineD
              srcCol' = srcCol + srcColD
              m = Mapping genLine genCol' (sourceAt sources srcIdx') srcLine' srcCol'
              (ms, fi, fl, fc) = decodeSegs genLine genCol' srcIdx' srcLine' srcCol' segs
           in (m : ms, fi, fl, fc)
        (gcD : _) ->
          -- genCol-only segment: advance the running column, emit no mapping.
          decodeSegs genLine (genCol + gcD) srcIdx srcLine srcCol segs
        _ ->
          decodeSegs genLine genCol srcIdx srcLine srcCol segs

-- | Split a string on a delimiter, keeping empty fields.
splitOn :: Char -> String -> [String]
splitOn delim = foldr step [[]]
  where
    step c acc@(cur : rest)
      | c == delim = [] : acc
      | otherwise = (c : cur) : rest
    step _ [] = [[]]

-- | The source module name at a (sanitized) source index.
sourceAt :: [String] -> Int -> String
sourceAt sources i
  | i >= 0 && i < length sources = sources !! i
  | otherwise = "<out-of-range>"

-- | Decode all Base64-VLQ values packed in a segment string.
decodeVLQs :: String -> [Int]
decodeVLQs [] = []
decodeVLQs s =
  let (val, rest) = decodeOneVLQ s in val : decodeVLQs rest

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

-- | Index of a character in the Base64 VLQ alphabet (0 if absent).
base64Index :: Char -> Int
base64Index c = Maybe.fromMaybe 0 (List.elemIndex c base64Alphabet)

base64Alphabet :: String
base64Alphabet =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
