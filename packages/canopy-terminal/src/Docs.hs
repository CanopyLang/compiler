{-# LANGUAGE OverloadedStrings #-}

-- | Documentation generation command for Canopy projects.
--
-- Implements the @canopy docs@ command, which extracts type-level
-- documentation from compiled build artifacts and renders it in the
-- requested output format (JSON or Markdown).
--
-- == Usage
--
-- @
-- canopy docs                     -- generate JSON docs to stdout
-- canopy docs --output docs.json  -- write JSON docs to a file
-- canopy docs --format markdown   -- generate Markdown docs to stdout
-- @
--
-- == Architecture
--
-- The docs command reuses the same compilation infrastructure as @make@.
-- It loads project details, compiles all exposed modules (for packages)
-- or specified source files (for applications), then extracts
-- documentation from the resulting 'Build.Artifacts'.
--
-- Documentation extraction is performed by 'Build.Docs.docsFromArtifacts',
-- which reads type information from compiled interfaces.  The rendering
-- step converts the internal 'Canopy.Docs.Documentation' representation
-- into the requested output format.
--
-- @since 0.19.2
module Docs
  ( -- * Main Interface
    run,

    -- * Types
    Flags (..),

    -- * Parsers
    formatParser,
    outputParser,
  )
where

import qualified BackgroundWriter as BW
import qualified Build
import qualified Build.Docs as BuildDocs
import qualified Canopy.Details as Details
import qualified Canopy.Docs as Docs
import qualified Canopy.ModuleName as ModuleName
import qualified Compiler
import Canopy.Data.NonEmptyList (List)
import qualified Canopy.Data.NonEmptyList as NE
import qualified Data.ByteString.Builder as BB
import Docs.Render (OutputFormat (..))
import qualified Docs.Render as Render
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified Stuff
import Terminal (Parser (..))
import qualified System.IO as IO

-- | Command-line flags for the docs command.
--
-- Controls the output format and destination for generated documentation.
data Flags = Flags
  { -- | Output format; defaults to JSON when 'Nothing'
    _docsFormat :: !(Maybe OutputFormat),
    -- | Output file path; 'Nothing' means write to stdout
    _docsOutput :: !(Maybe FilePath)
  }
  deriving (Eq, Show)

-- | Task type alias for docs command errors.
type DocsTask a = Task.Task Exit.Docs a

-- | Main entry point for the docs command.
--
-- Compiles the project and extracts documentation from the resulting
-- build artifacts, then renders it in the requested format.
--
-- When no paths are specified, generates documentation for all exposed
-- modules (package projects) or fails with an error (application
-- projects must specify files).
--
-- @since 0.19.2
run :: [FilePath] -> Flags -> IO ()
run paths flags = do
  maybeRoot <- Stuff.findRoot
  Reporting.attemptWithStyle Reporting.terminal Exit.docsToReport $
    case maybeRoot of
      Just root -> executeDocs root paths flags
      Nothing -> pure (Left Exit.DocsNoOutline)

-- | Execute the full docs pipeline from a known project root.
executeDocs :: FilePath -> [FilePath] -> Flags -> IO (Either Exit.Docs ())
executeDocs root paths flags =
  BW.withScope $ \scope ->
    Stuff.withRootLock root . Task.run $
      coordinateDocs root paths flags scope

-- | Coordinate the docs task inside the 'DocsTask' monad.
coordinateDocs ::
  FilePath ->
  [FilePath] ->
  Flags ->
  BW.Scope ->
  DocsTask ()
coordinateDocs root paths flags scope = do
  details <- loadDetailsForDocs scope root
  let srcDirs = extractSrcDirs details
  artifacts <- compileForDocs root srcDirs details paths
  let docs = BuildDocs.docsFromArtifacts artifacts
  let format = maybe JsonFormat id (_docsFormat flags)
  Task.io (emitDocs format (_docsOutput flags) docs)

-- | Load project details, mapping failures to 'Exit.DocsBadDetails'.
loadDetailsForDocs ::
  BW.Scope ->
  FilePath ->
  DocsTask Details.Details
loadDetailsForDocs scope root = do
  result <- Task.io (Details.load Reporting.silent scope root)
  either (Task.throw . Exit.DocsBadDetails) pure result

-- | Compile the project to produce artifacts for documentation.
compileForDocs ::
  FilePath ->
  [Compiler.SrcDir] ->
  Details.Details ->
  [FilePath] ->
  DocsTask Build.Artifacts
compileForDocs root srcDirs details [] =
  compileExposedModules root srcDirs details
compileForDocs root srcDirs details (p : ps) =
  compileFilePaths root srcDirs details (NE.List p ps)

-- | Compile all exposed modules for a package project.
compileExposedModules ::
  FilePath ->
  [Compiler.SrcDir] ->
  Details.Details ->
  DocsTask Build.Artifacts
compileExposedModules root srcDirs details = do
  exposed <- resolveExposedModules details
  let pkg = resolvePkgName details
  result <- Task.io (Compiler.compileFromExposed pkg False (Compiler.ProjectRoot root) srcDirs exposed)
  either (Task.throw . Exit.DocsCannotBuild) pure result

-- | Compile specific file paths for documentation.
compileFilePaths ::
  FilePath ->
  [Compiler.SrcDir] ->
  Details.Details ->
  List FilePath ->
  DocsTask Build.Artifacts
compileFilePaths root srcDirs details paths = do
  let pkg = resolvePkgName details
      isApp = detailsIsApp details
  result <- Task.io (Compiler.compileFromPaths pkg isApp (Compiler.ProjectRoot root) srcDirs (NE.toList paths))
  either (Task.throw . Exit.DocsCannotBuild) pure result

-- | Extract exposed modules from project details.
resolveExposedModules :: Details.Details -> DocsTask (List ModuleName.Raw)
resolveExposedModules (Details.Details _ validOutline _ _ _ _) =
  case validOutline of
    Details.ValidApp _ ->
      Task.throw Exit.DocsAppNeedsFileNames
    Details.ValidPkg _ [] _ ->
      Task.throw Exit.DocsPkgNeedsExposing
    Details.ValidPkg _ (m : ms) _ ->
      pure (NE.List m ms)

-- | Extract source directories from project details.
extractSrcDirs :: Details.Details -> [Compiler.SrcDir]
extractSrcDirs (Details.Details _ _ _ _ srcDirs _) =
  map Compiler.RelativeSrcDir srcDirs

-- | Extract the package name from project details.
resolvePkgName :: Details.Details -> Details.PkgName
resolvePkgName (Details.Details _ validOutline _ _ _ _) =
  case validOutline of
    Details.ValidPkg pkgName _ _ -> pkgName
    Details.ValidApp _ -> Details.dummyPkgName

-- | Determine whether project details describe an application.
detailsIsApp :: Details.Details -> Bool
detailsIsApp (Details.Details _ validOutline _ _ _ _) =
  case validOutline of
    Details.ValidApp _ -> True
    Details.ValidPkg _ _ _ -> False

-- | Write documentation output to the specified destination.
emitDocs :: OutputFormat -> Maybe FilePath -> Docs.Documentation -> IO ()
emitDocs format Nothing docs =
  emitToStdout format docs
emitDocs format (Just path) docs =
  emitToFile format path docs

-- | Write documentation to stdout.
emitToStdout :: OutputFormat -> Docs.Documentation -> IO ()
emitToStdout JsonFormat docs =
  BB.hPutBuilder IO.stdout (Render.renderJson docs)
emitToStdout MarkdownFormat docs =
  IO.putStr (Render.renderMarkdown docs)

-- | Write documentation to a file.
emitToFile :: OutputFormat -> FilePath -> Docs.Documentation -> IO ()
emitToFile JsonFormat path docs =
  IO.withFile path IO.WriteMode $ \h ->
    BB.hPutBuilder h (Render.renderJson docs)
emitToFile MarkdownFormat path docs =
  writeFile path (Render.renderMarkdown docs)

-- | Parser for the @--format@ flag.
--
-- Accepts @"json"@ or @"markdown"@ as valid values.
--
-- @since 0.19.2
formatParser :: Parser OutputFormat
formatParser =
  Parser
    { _singular = "output format",
      _plural = "output formats",
      _parser = parseFormat,
      _suggest = \_ -> pure ["json", "markdown"],
      _examples = \_ -> pure ["json", "markdown"]
    }

-- | Parse an output format from the command-line string.
parseFormat :: String -> Maybe OutputFormat
parseFormat "json" = Just JsonFormat
parseFormat "markdown" = Just MarkdownFormat
parseFormat "md" = Just MarkdownFormat
parseFormat _ = Nothing

-- | Parser for the @--output@ flag.
--
-- Accepts any file path as the documentation output target.
--
-- @since 0.19.2
outputParser :: Parser FilePath
outputParser =
  Parser
    { _singular = "output file",
      _plural = "output files",
      _parser = parseOutputPath,
      _suggest = \_ -> pure [],
      _examples = \_ -> pure ["docs.json", "docs.md"]
    }

-- | Parse an output file path.
parseOutputPath :: String -> Maybe FilePath
parseOutputPath "" = Nothing
parseOutputPath path = Just path
