{-# LANGUAGE OverloadedStrings #-}

-- | Elm project file to Canopy project file conversion.
--
-- Transforms @elm.json@ into @canopy.json@ by applying field renames
-- (e.g. @elm-version@ to @canopy-version@) and package dependency
-- remapping (e.g. @elm\/core@ to @canopy\/core@).
--
-- The conversion operates at the byte level using search-and-replace,
-- which preserves the original JSON formatting and avoids the need
-- for a full JSON parse/reformat cycle.
--
-- @since 0.19.2
module Convert.ProjectFile
  ( -- * Conversion
    convertElmJson,
    convertElmJsonToFile,

    -- * Detection
    hasPortsOrKernel,
  )
where

import qualified Convert.PackageMap as PackageMap
import qualified Data.ByteString as BS
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import System.FilePath ((</>))
import qualified System.Directory as Dir
import qualified System.FilePath as FP

-- | Convert @elm.json@ content to @canopy.json@ format.
--
-- Applies all field renames and package dependency remappings from
-- 'PackageMap.elmToCanopyJsonReplacements'.
--
-- @since 0.19.2
convertElmJson :: BS.ByteString -> BS.ByteString
convertElmJson content =
  List.foldl' applyReplacement content PackageMap.elmToCanopyJsonReplacements

-- | Read @elm.json@ from the source directory, convert it, and write
-- @canopy.json@ to the output directory.
--
-- Returns the converted content as 'Text', or 'Nothing' if no @elm.json@
-- was found.
--
-- @since 0.19.2
convertElmJsonToFile :: FilePath -> FilePath -> IO (Maybe Text)
convertElmJsonToFile sourceDir outputDir = do
  let elmJsonPath = sourceDir </> "elm.json"
  exists <- Dir.doesFileExist elmJsonPath
  if not exists
    then pure Nothing
    else do
      content <- BS.readFile elmJsonPath
      let converted = convertElmJson content
      Dir.createDirectoryIfMissing True outputDir
      BS.writeFile (outputDir </> "canopy.json") converted
      pure (Just (either (const Text.empty) id (TE.decodeUtf8' converted)))

-- | Check whether an @elm.json@ file references ports or kernel JS.
--
-- Packages that use @effect-module@ or reference kernel JavaScript files
-- cannot be auto-converted and require manual porting.
--
-- Returns a description of the unsupported feature if found, or 'Nothing'
-- if the package is safe to auto-convert.
--
-- @since 0.19.2
hasPortsOrKernel :: FilePath -> IO (Maybe Text)
hasPortsOrKernel sourceDir = do
  elmFiles <- findSourceFiles sourceDir
  results <- mapM checkFile elmFiles
  pure (List.find (const True) (concat results))
  where
    checkFile path = do
      content <- BS.readFile path
      pure (either (const []) (detectUnsupported path) (TE.decodeUtf8' content))

-- | Detect unsupported features in a source file.
detectUnsupported :: FilePath -> Text -> [Text]
detectUnsupported path content =
  portCheck ++ kernelCheck
  where
    portCheck
      | Text.isInfixOf "effect module" content =
          ["Effect module in " <> Text.pack path]
      | otherwise = []
    kernelCheck
      | Text.isInfixOf "Elm.Kernel." content =
          ["Kernel reference in " <> Text.pack path]
      | otherwise = []

-- | Find all source files (both @.elm@ and @.can@) in the @src@ directory.
findSourceFiles :: FilePath -> IO [FilePath]
findSourceFiles root = do
  let srcDir = root </> "src"
  exists <- Dir.doesDirectoryExist srcDir
  if exists
    then walkForSources srcDir
    else pure []

-- | Recursively walk a directory collecting source files.
walkForSources :: FilePath -> IO [FilePath]
walkForSources dir = do
  entries <- Dir.listDirectory dir
  results <- mapM (processSourceEntry dir) entries
  pure (concat results)

-- | Process a single entry for source file discovery.
processSourceEntry :: FilePath -> FilePath -> IO [FilePath]
processSourceEntry parent entry = do
  let full = parent </> entry
  isDir <- Dir.doesDirectoryExist full
  if isDir
    then walkForSources full
    else pure (sourceFileFilter full)

-- | Filter to only @.elm@ and @.can@ source files.
sourceFileFilter :: FilePath -> [FilePath]
sourceFileFilter path
  | ext == ".elm" || ext == ".can" = [path]
  | otherwise = []
  where
    ext = FP.takeExtension path

-- | Apply a single strict 'BS.ByteString' search-and-replace.
applyReplacement :: BS.ByteString -> (BS.ByteString, BS.ByteString) -> BS.ByteString
applyReplacement content (needle, replacement) =
  replaceAll needle replacement content

-- | Replace every non-overlapping occurrence of @needle@ in @haystack@.
replaceAll :: BS.ByteString -> BS.ByteString -> BS.ByteString -> BS.ByteString
replaceAll needle replacement haystack =
  case BS.breakSubstring needle haystack of
    (before, after)
      | BS.null after -> haystack
      | otherwise ->
          before
            <> replacement
            <> replaceAll needle replacement (BS.drop (BS.length needle) after)
