{-# LANGUAGE OverloadedStrings #-}

-- | Output generation and target handling.
--
-- This module manages the generation of final build outputs, including
-- JavaScript files, HTML files, and null output for testing. It handles
-- output format selection, target validation, and file generation.
--
-- Key functions:
--   * 'generateOutput' - Generate output based on target type
--   * 'generateJavaScript' - Create JavaScript output
--   * 'generateHtml' - Create HTML output with wrapper
--   * 'selectOutputFormat' - Choose format based on main functions
--
-- The module follows CLAUDE.md guidelines with functions ≤15 lines,
-- comprehensive error handling, and lens-based record access.
--
-- @since 0.19.1
module Make.Output
  ( -- * Output Generation
    generateOutput,
    generateForTarget,
    selectOutputFormat,

    -- * Specific Generators
    generateJavaScript,
    generateSplitJavaScript,
    generateHtml,
    generateDevNull,

    -- * Format Selection
    chooseFormatFromMains,

    -- * Utilities
    fixEmbeddedJavaScript,
  )
where

import qualified Build
import qualified Canopy.ModuleName as ModuleName
import Control.Lens ((^.))
import Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as ByteString.Lazy
import Data.Function ((&))
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.NonEmptyList as NonEmptyList
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified FFI.Capability
import qualified FFI.CapabilityEnforcement as CapEnforce
import qualified FFI.Manifest as Manifest
import qualified FFI.Types
import qualified File
import qualified Foreign.FFI as FFI
import qualified Generate.Html as Html
import qualified Generate.JavaScript.CodeSplit.Types as Split
import qualified Generate.JavaScript.SourceMap as SourceMap
import Logging.Event (LogEvent (..))
import qualified Logging.Logger as Log
import Make.Builder (createBuilder, extractMainModules, hasExactlyOneMain)
import Make.Generation (writeOutputFile)
import qualified Make.Reproducible as Reproducible
import Make.Types
  ( BuildContext,
    Output (..),
    Task,
    bcDetails,
    bcStyle,
  )
import qualified Canopy.Details as Details
import qualified Canopy.Outline as Outline
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified System.Directory as Dir
import qualified System.FilePath as FilePath
import qualified System.IO as IO

-- | Generate output based on artifacts and optional target.
--
-- Determines the appropriate output format and generates the final
-- build result. If no target is specified, selects format based on
-- the number of main functions found.
--
-- @
-- generateOutput ctx artifacts Nothing      -- Auto-select format
-- generateOutput ctx artifacts (Just target) -- Use specific target
-- @
generateOutput ::
  BuildContext ->
  Build.Artifacts ->
  Maybe Output ->
  Bool ->
  Task ()
generateOutput ctx artifacts maybeTarget doVerify = do
  validateDeclaredCapabilities ctx artifacts
  case maybeTarget of
    Nothing -> selectOutputFormat ctx artifacts
    Just target -> generateForTarget ctx artifacts target doVerify

-- | Select output format based on main function analysis.
--
-- Automatically chooses the appropriate output format:
--   * No mains → No output (library)
--   * One main → HTML output for application
--   * Multiple mains → JavaScript output for multi-entry
chooseFormatFromMains :: BuildContext -> Build.Artifacts -> Task ()
chooseFormatFromMains ctx artifacts =
  case extractMainModules artifacts of
    [] -> generateNoOutput
    [mainName] -> generateSingleAppHtml ctx artifacts mainName
    mainNames -> generateMultiAppJs ctx artifacts mainNames

-- | Generate output for specific target format.
--
-- Creates output according to the specified target type. Validates
-- that the target is compatible with the compiled artifacts.
generateForTarget :: BuildContext -> Build.Artifacts -> Output -> Bool -> Task ()
generateForTarget _ _ DevNull _ = generateDevNull
generateForTarget ctx artifacts (JS target) doVerify =
  generateJavaScript ctx artifacts target doVerify
generateForTarget ctx artifacts (Html target) doVerify =
  generateHtml ctx artifacts target doVerify

-- | Generate JavaScript output to specified file.
--
-- Creates JavaScript output from artifacts, including source map in dev mode.
-- Prepends the capability registry when capabilities are declared in canopy.json.
-- Appends @\/\/# sourceMappingURL@ comment and writes @.js.map@ alongside.
generateJavaScript ::
  BuildContext ->
  Build.Artifacts ->
  FilePath ->
  Bool ->
  Task ()
generateJavaScript ctx artifacts target doVerify = do
  Task.io (IO.hPutStrLn IO.stderr ("Generating JavaScript to " <> target))
  Task.io (Log.logEvent (BuildStarted (Text.pack ("Generating JavaScript to: " <> target))))
  (builder, maybeSourceMap) <- createBuilder ctx artifacts
  verifyIfRequested ctx artifacts doVerify builder
  let caps = extractCapabilities ctx
      fullBuilder = CapEnforce.generateCapabilityRegistry caps <> builder
      rootNames = Build.getRootNames artifacts
      jsWithRef = appendSourceMapRef target fullBuilder maybeSourceMap
  Task.io (Reproducible.reportContentHash target (Reproducible.hashBuilder fullBuilder) doVerify)
  writeOutputFile (ctx ^. bcStyle) target jsWithRef rootNames
  Task.io (writeSourceMapFile target maybeSourceMap)
  Task.io (writeCapabilitiesManifest target artifacts)

-- | Generate code-split JavaScript output to a directory.
--
-- Writes each chunk as a separate file in the output directory,
-- plus a @manifest.json@ for server-side tooling. The entry chunk
-- is always @entry.js@; lazy and shared chunks have content-hashed
-- filenames for cache-busting.
--
-- @since 0.19.2
generateSplitJavaScript ::
  BuildContext ->
  Split.SplitOutput ->
  FilePath ->
  Task ()
generateSplitJavaScript _ctx splitOutput targetDir = do
  Task.io (IO.hPutStrLn IO.stderr ("Generating split JavaScript to " <> targetDir <> "/"))
  Task.io (Log.logEvent (BuildStarted (Text.pack ("Generating split JS to: " <> targetDir))))
  Task.io (Dir.createDirectoryIfMissing True targetDir)
  Task.io (writeChunks targetDir chunks)
  Task.io (writeManifest targetDir (splitOutput ^. Split.soManifest))
  Task.io (reportChunkSizes chunks)
  where
    chunks = splitOutput ^. Split.soChunks

-- | Write all chunk files to the output directory.
writeChunks :: FilePath -> [Split.ChunkOutput] -> IO ()
writeChunks dir = mapM_ (writeChunk dir)

-- | Write a single chunk file to the output directory.
writeChunk :: FilePath -> Split.ChunkOutput -> IO ()
writeChunk dir co = do
  let path = dir FilePath.</> Split._coFilename co
  File.writeBuilder path (Split._coBuilder co)
  Log.logEvent (BuildStarted (Text.pack ("  wrote chunk: " <> Split._coFilename co)))

-- | Write the JSON manifest file to the output directory.
writeManifest :: FilePath -> Builder -> IO ()
writeManifest dir manifest =
  File.writeBuilder (dir FilePath.</> "manifest.json") manifest

-- | Report chunk sizes to the build log.
--
-- Logs each chunk's filename and approximate byte size, plus the
-- total across all chunks. Provides visibility into the split output
-- so developers can assess whether lazy boundaries are effective.
--
-- @since 0.19.2
reportChunkSizes :: [Split.ChunkOutput] -> IO ()
reportChunkSizes chunks = do
  Log.logEvent (BuildStarted (Text.pack "Code splitting:"))
  mapM_ reportOneChunk chunks
  Log.logEvent (BuildStarted (Text.pack (totalLine chunks)))

-- | Report a single chunk's size.
reportOneChunk :: Split.ChunkOutput -> IO ()
reportOneChunk co =
  Log.logEvent (BuildStarted (Text.pack ("  " <> padFilename <> formatKB size)))
  where
    filename = Split._coFilename co
    size = chunkBuilderSize (Split._coBuilder co)
    padFilename = filename <> replicate (35 - length filename) ' '

-- | Compute the byte size of a builder.
chunkBuilderSize :: Builder -> Int
chunkBuilderSize =
  fromIntegral . ByteString.Lazy.length . Builder.toLazyByteString

-- | Format a byte count as a human-readable KB string.
formatKB :: Int -> String
formatKB bytes =
  show (fromIntegral bytes / (1024.0 :: Double) :: Double) <> " KB"

-- | Build the summary total line for chunk size reporting.
totalLine :: [Split.ChunkOutput] -> String
totalLine chunks =
  "  Total: " <> formatKB total <> " (" <> show (length chunks) <> " chunks)"
  where
    total = sum (map (chunkBuilderSize . Split._coBuilder) chunks)

-- | Generate HTML output to specified file.
--
-- Creates HTML output with embedded JavaScript. Requires exactly one
-- main function to serve as the application entry point.
generateHtml ::
  BuildContext ->
  Build.Artifacts ->
  FilePath ->
  Bool ->
  Task ()
generateHtml ctx artifacts target doVerify = do
  Task.io (IO.hPutStrLn IO.stderr ("Generating HTML to " <> target))
  Task.io (Log.logEvent (BuildStarted (Text.pack ("Generating HTML to: " <> target))))
  mainName <- hasExactlyOneMain artifacts
  (builder, _sourceMap) <- createBuilder ctx artifacts
  verifyIfRequested ctx artifacts doVerify builder
  let caps = extractCapabilities ctx
      fullBuilder = CapEnforce.generateCapabilityRegistry caps <> builder
      fixedBuilder = fixEmbeddedJavaScript fullBuilder
      htmlBuilder = Html.sandwich mainName fixedBuilder
  Task.io (Reproducible.reportContentHash target (Reproducible.hashBuilder htmlBuilder) doVerify)
  writeOutputFile (ctx ^. bcStyle) target htmlBuilder (NonEmptyList.List mainName [])

-- | Generate null output (no files created).
--
-- Used for testing and benchmarking builds without creating output files.
-- Simply logs the action and returns without generating anything.
generateDevNull :: Task ()
generateDevNull =
  Task.io (Log.logEvent (BuildStarted (Text.pack "Output target is /dev/null - generating nothing")))

-- | Generate no output for library builds.
--
-- Used when no main functions are found, indicating a library build
-- that doesn't produce executable output.
generateNoOutput :: Task ()
generateNoOutput =
  Task.io (Log.logEvent (BuildStarted (Text.pack "No main functions found - generating nothing")))

-- | Generate HTML for single-application build.
--
-- Creates index.html with the single main function as entry point.
-- Used for simple applications with one executable module.
generateSingleAppHtml ::
  BuildContext ->
  Build.Artifacts ->
  ModuleName.Raw ->
  Task ()
generateSingleAppHtml ctx artifacts mainName = do
  Task.io (Log.logEvent (BuildStarted (Text.pack ("Found single main function - generating HTML: " <> Name.toChars mainName))))
  (builder, _sourceMap) <- createBuilder ctx artifacts
  let caps = extractCapabilities ctx
      fullBuilder = CapEnforce.generateCapabilityRegistry caps <> builder
      fixedBuilder = fixEmbeddedJavaScript fullBuilder
      htmlBuilder = Html.sandwich mainName fixedBuilder
      target = "index.html"
  writeOutputFile (ctx ^. bcStyle) target htmlBuilder (NonEmptyList.List mainName [])

-- | Generate JavaScript for multi-application build.
--
-- Creates canopy.js with multiple entry points. Used for complex
-- applications with multiple executable modules.
generateMultiAppJs ::
  BuildContext ->
  Build.Artifacts ->
  [ModuleName.Raw] ->
  Task ()
generateMultiAppJs ctx artifacts mainNames =
  case mainNames of
    [] -> generateNoOutput
    name : rest -> do
      let nameStrs = fmap Name.toChars mainNames
      Task.io (Log.logEvent (BuildStarted (Text.pack ("Found multiple main functions - generating JS: " <> show nameStrs))))
      (builder, maybeSourceMap) <- createBuilder ctx artifacts
      let caps = extractCapabilities ctx
          fullBuilder = CapEnforce.generateCapabilityRegistry caps <> builder
          target = "canopy.js"
          jsWithRef = appendSourceMapRef target fullBuilder maybeSourceMap
      writeOutputFile (ctx ^. bcStyle) target jsWithRef (NonEmptyList.List name rest)
      Task.io (writeSourceMapFile target maybeSourceMap)


-- | Select output format automatically based on artifacts.
--
-- Alias for 'chooseFormatFromMains' to maintain consistent naming
-- across the module interface.
selectOutputFormat :: BuildContext -> Build.Artifacts -> Task ()
selectOutputFormat = chooseFormatFromMains

-- | Fix JavaScript spacing issues in embedded JavaScript.
--
-- Applies the same spacing fixes used for standalone JavaScript files
-- to JavaScript code that will be embedded in HTML files.
fixEmbeddedJavaScript :: Builder -> Builder
fixEmbeddedJavaScript builder =
  let content = builderToText builder
      fixedContent = fixJavaScriptSpacing content
  in Builder.stringUtf8 (Text.unpack fixedContent)

-- | Convert Builder to Text for post-processing.
--
-- Efficiently converts a Builder to Text using the underlying ByteString.
builderToText :: Builder -> Text.Text
builderToText = Text.decodeUtf8 . ByteString.toStrict . Builder.toLazyByteString

-- | Fix JavaScript spacing issues.
--
-- Applies regex-based fixes for spacing problems in generated JavaScript.
-- These issues typically arise from optimization passes that concat strings
-- without preserving proper keyword spacing.
fixJavaScriptSpacing :: Text.Text -> Text.Text
fixJavaScriptSpacing content =
  content
    & Text.replace "elseif" "else if"
    & Text.replace "elsereturn" "else return"
    & Text.replace "elsethrow" "else throw"
    & Text.replace "elsevar" "else var"
    & Text.replace "elsefor" "else for"
    & Text.replace "elsewhile" "else while"

-- | Append sourceMappingURL comment to JS output when a source map exists.
--
-- Adds the standard @\/\/# sourceMappingURL=filename.js.map@ comment
-- that browsers use to locate the source map file.
appendSourceMapRef :: FilePath -> Builder -> Maybe SourceMap.SourceMap -> Builder
appendSourceMapRef _target builder Nothing = builder
appendSourceMapRef target builder (Just _) =
  builder <> Builder.stringUtf8 ("\n//# sourceMappingURL=" <> mapFilename <> "\n")
  where
    mapFilename = FilePath.takeFileName target <> ".map"

-- | Write source map JSON file alongside the JavaScript output.
--
-- Creates a @.js.map@ file containing Source Map V3 JSON when the
-- compiler produces source map data (dev mode only).
writeSourceMapFile :: FilePath -> Maybe SourceMap.SourceMap -> IO ()
writeSourceMapFile _target Nothing = pure ()
writeSourceMapFile target (Just sm) =
  File.writeBuilder mapPath (SourceMap.toBuilder sm)
  where
    mapPath = target <> ".map"

-- | Write capabilities manifest alongside the JavaScript output.
--
-- Scans FFI info from build artifacts for @capability annotations
-- and writes a @capabilities.json@ file in the same directory as the
-- JavaScript output. The manifest is only written when FFI content
-- contains capability annotations.
--
-- @since 0.19.1
writeCapabilitiesManifest :: FilePath -> Build.Artifacts -> IO ()
writeCapabilitiesManifest target artifacts = do
  let ffiInfoMap = artifacts ^. Build.artifactsFFIInfo
  moduleFunctions <- parseFFICapabilities ffiInfoMap
  let manifest = Manifest.collectCapabilities moduleFunctions
  if hasCapabilities manifest
    then Manifest.writeManifest manifestPath manifest
    else pure ()
  where
    manifestPath = FilePath.replaceExtension target ".capabilities.json"

-- | Check whether a manifest contains any capabilities.
hasCapabilities :: Manifest.CapabilityManifest -> Bool
hasCapabilities m =
  Manifest._manifestUserActivation m
    || not (null (Manifest._manifestModules m))

-- | Parse FFI content for capability annotations.
--
-- Files that fail to parse are included with an empty function list
-- since capability checking is advisory — a parse error in JSDoc
-- should not block compilation.
parseFFICapabilities :: Map.Map String a -> IO [(Text.Text, [FFI.JSDocFunction])]
parseFFICapabilities ffiInfoMap =
  traverse parseOne (Map.keys ffiInfoMap)
  where
    parseOne path = do
      result <- FFI.parseJSDocFromFile path
      pure (Text.pack path, either (const []) id result)

-- | Validate FFI capability requirements against canopy.json declarations.
--
-- Parses FFI files for @capability annotations, then checks:
--   1. All required capabilities are declared in canopy.json (error if not)
--   2. All declared capabilities are actually used (warning if not)
--
-- Skips validation entirely when no capabilities are declared and no
-- FFI files require any, which is the common case.
--
-- @since 0.20.0
validateDeclaredCapabilities :: BuildContext -> Build.Artifacts -> Task ()
validateDeclaredCapabilities ctx artifacts = do
  let declared = extractCapabilities ctx
      ffiInfoMap = artifacts ^. Build.artifactsFFIInfo
  moduleFunctions <- Task.io (parseFFICapabilities ffiInfoMap)
  let requirements = collectRequirements moduleFunctions
  validateRequired declared requirements
  warnUnused declared requirements

-- | Collect (function name, file path, required capabilities) triples
-- from parsed FFI functions.
--
-- Extracts the capability names from each function's parsed
-- 'CapabilityConstraint' annotation.
collectRequirements :: [(Text.Text, [FFI.JSDocFunction])] -> [(Text.Text, Text.Text, Set Text.Text)]
collectRequirements = concatMap collectFromFile

-- | Collect capability requirements from a single FFI file's functions.
collectFromFile :: (Text.Text, [FFI.JSDocFunction]) -> [(Text.Text, Text.Text, Set Text.Text)]
collectFromFile (filePath, funcs) =
  concatMap (collectFromFunction filePath) funcs

-- | Collect capability requirements from a single FFI function.
collectFromFunction :: Text.Text -> FFI.JSDocFunction -> [(Text.Text, Text.Text, Set Text.Text)]
collectFromFunction filePath func =
  case FFI.jsDocFuncCapabilities func of
    Nothing -> []
    Just constraint ->
      let caps = constraintToNames constraint
          funcName = FFI.unJsFunctionName (FFI.jsDocFuncName func)
       in [(funcName, filePath, caps) | not (Set.null caps)]

-- | Extract capability name strings from a 'CapabilityConstraint'.
constraintToNames :: FFI.Capability.CapabilityConstraint -> Set Text.Text
constraintToNames FFI.Capability.UserActivationRequired =
  Set.singleton "user-activation"
constraintToNames (FFI.Capability.PermissionRequired perm) =
  Set.singleton (FFI.Types.unPermissionName perm)
constraintToNames (FFI.Capability.InitializationRequired resource) =
  Set.singleton (FFI.Types.unResourceName resource)
constraintToNames (FFI.Capability.AvailabilityRequired name) =
  Set.singleton name
constraintToNames (FFI.Capability.MultipleConstraints constraints) =
  Set.unions (map constraintToNames constraints)

-- | Throw a compile error if any required capabilities are missing.
validateRequired :: Set Text.Text -> [(Text.Text, Text.Text, Set Text.Text)] -> Task ()
validateRequired declared requirements =
  case CapEnforce.validateCapabilities declared requirements of
    [] -> pure ()
    errors -> Task.throw (Exit.MakeCapabilityError errors)

-- | Log warnings for capabilities declared but not required by any FFI function.
warnUnused :: Set Text.Text -> [(Text.Text, Text.Text, Set Text.Text)] -> Task ()
warnUnused declared requirements =
  let unused = CapEnforce.findUnusedCapabilities declared requirements
   in Task.io (logUnusedCapabilities unused)

-- | Log a warning for each unused capability.
logUnusedCapabilities :: Set Text.Text -> IO ()
logUnusedCapabilities caps =
  mapM_ logOne (Set.toList caps)
  where
    logOne cap =
      IO.hPutStrLn IO.stderr
        ( "Warning: Capability "
            <> show (Text.unpack cap)
            <> " is declared in canopy.json but no FFI function requires it."
        )

-- | Extract declared capabilities from the build context.
--
-- Looks up the @capabilities@ field from the @canopy.json@ configuration
-- stored in the build context. Returns an empty set for package projects
-- since capabilities are only meaningful for applications.
--
-- @since 0.20.0
extractCapabilities :: BuildContext -> Set Text.Text
extractCapabilities ctx =
  capabilitiesFromOutline (ctx ^. bcDetails . Details.detailsOutline)

-- | Extract capabilities from a validated project outline.
--
-- Applications may declare capabilities in @canopy.json@; packages
-- and workspaces always have an empty capability set.
capabilitiesFromOutline :: Details.ValidOutline -> Set Text.Text
capabilitiesFromOutline (Details.ValidApp app) = Outline._appCapabilities app
capabilitiesFromOutline (Details.ValidPkg _ _ _) = Set.empty

-- | Verify build reproducibility if the flag is set.
--
-- Runs code generation a second time from the same artifacts and
-- compares the output byte-for-byte with the first build. Throws
-- 'Exit.MakeReproducibilityFailure' if the outputs differ.
--
-- @since 0.19.2
verifyIfRequested ::
  BuildContext ->
  Build.Artifacts ->
  Bool ->
  Builder.Builder ->
  Task ()
verifyIfRequested _ _ False _ = pure ()
verifyIfRequested ctx artifacts True firstBuilder = do
  Task.io (Log.logEvent (BuildStarted "Running second build for reproducibility verification"))
  (secondBuilder, _) <- createBuilder ctx artifacts
  result <- Task.io (Reproducible.verifyBuilderReproducibility firstBuilder secondBuilder)
  maybe (pure ()) (Task.throw . Exit.MakeReproducibilityFailure) result
