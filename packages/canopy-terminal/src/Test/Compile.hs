{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Test compilation pipeline for the @canopy test@ command.
--
-- Compiles test @.can@ files to JavaScript, ensuring that test-dependency
-- packages have their @artifacts.dat@ built first. This is critical for
-- correct type-based dispatch (e.g. @BrowserTestMain@ detection requires
-- the @Test@ module to be canonicalised under @Pkg.test@, not @Pkg.dummyName@).
--
-- @since 0.19.1
module Test.Compile
  ( compileTestFiles,
    artifactsToJavaScript,
    artifactsToJavaScriptCov,
    collectMains,
    detectStaleFFI,
  )
where

import qualified AST.Optimized as Opt
import qualified Build.Artifacts as Build
import qualified Canopy.Constraint as Constraint
import qualified Canopy.Data.NonEmptyList as NE
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Compiler
import Control.Lens ((^.))
import qualified Exit as BuildExit
import qualified Reporting.Doc as Doc
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import qualified Canopy.Data.Name as Name
import qualified Generate.JavaScript as JS
import qualified Generate.JavaScript.Coverage as Coverage
import qualified Generate.JavaScript.FFI as FFI
import qualified Generate.Mode as Mode
import qualified PackageCache
import Reporting.Doc.ColorQQ (c)
import qualified Stuff
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified Terminal.Print as Print

-- | Compile test files to a JavaScript string and main type info.
--
-- Before compiling user test files, ensures that all test-dependency
-- packages have @artifacts.dat@. Packages with source but no artifacts
-- (e.g. locally symlinked @canopy\/test@ during development) are compiled
-- just-in-time so they receive their correct package identity in the
-- optimizer.
--
-- When @coverage@ is 'True', also returns the 'Coverage.CoverageMap'
-- for combining with runtime hit data after tests.
--
-- @since 0.19.1
compileTestFiles ::
  FilePath ->
  [FilePath] ->
  Bool ->
  IO (Maybe (Text.Text, Map.Map ModuleName.Canonical Opt.Main, Maybe Coverage.CoverageMap, [(String, FilePath)], Pkg.Name))
compileTestFiles root testFiles coverage = do
  ensureTestDepArtifacts root
  pkg <- resolvePackageName root
  let srcDirs =
        [ Compiler.RelativeSrcDir "src",
          Compiler.RelativeSrcDir "tests",
          Compiler.RelativeSrcDir "test",
          Compiler.RelativeSrcDir "test-app"
        ]
  result <- Compiler.compileFromPathsWithTestDeps True pkg False (Compiler.ProjectRoot root) srcDirs testFiles
  case result of
    Left err -> do
      Print.printErrLn [c|{red|Compilation failed.}|]
      Print.printErrLn (Doc.fromChars "")
      Print.printErrLn (BuildExit.toDoc err)
      pure Nothing
    Right artifacts ->
      if coverage
        then do
          let (js, mains, covMap) = artifactsToJavaScriptCov artifacts
              stale = detectStaleFFI (artifacts ^. Build.artifactsFFIInfo) (artifacts ^. Build.artifactsGlobalGraph)
          pure (Just (js, mains, covMap, stale, pkg))
        else pure (Just (artifactsToJavaScript artifacts, collectMains artifacts, Nothing, [], pkg))

-- | Resolve the package name from the project outline.
--
-- For packages, returns the package name from canopy.json. For applications
-- and workspaces (or when the outline can't be read), falls back to
-- 'Pkg.dummyName'.
--
-- @since 0.19.2
resolvePackageName :: FilePath -> IO Pkg.Name
resolvePackageName root = do
  eitherOutline <- Outline.read root
  pure (either (const Pkg.dummyName) extractPkgName eitherOutline)
  where
    extractPkgName (Outline.Pkg o) = Outline._pkgName o
    extractPkgName _ = Pkg.dummyName

-- | Ensure all dependency packages (regular + test) have compiled artifacts.
--
-- Reads the project outline, collects all dependencies (both regular and
-- test), resolves transitive dependencies, topologically sorts them, and
-- compiles any that lack @artifacts.dat@.
--
-- @since 0.19.1
ensureTestDepArtifacts :: FilePath -> IO ()
ensureTestDepArtifacts root = do
  eitherOutline <- Outline.read root
  case eitherOutline of
    Left _ -> pure ()
    Right outline -> do
      cacheDir <- Stuff.getPackageCache
      graph <- resolveTransitiveDeps cacheDir (Outline.allDeps outline) Map.empty
      let sorted = topologicalSort graph
      mapM_ (ensureOneTestDep cacheDir) sorted

-- | Dependency graph: maps each package to its version and direct dep names.
type DepGraph = Map.Map Pkg.Name (Version.Version, [Pkg.Name])

-- | Resolve transitive dependencies by reading each dep's outline from cache.
resolveTransitiveDeps ::
  FilePath ->
  [(Pkg.Name, Version.Version)] ->
  DepGraph ->
  IO DepGraph
resolveTransitiveDeps _ [] seen = pure seen
resolveTransitiveDeps cacheDir ((name, ver) : rest) seen
  | Map.member name seen = resolveTransitiveDeps cacheDir rest seen
  | otherwise = do
      subDeps <- readSubDeps cacheDir name ver
      let seen' = Map.insert name (ver, map fst subDeps) seen
      resolveTransitiveDeps cacheDir (subDeps ++ rest) seen'

-- | Read a package's dependencies from its cached outline.
readSubDeps :: FilePath -> Pkg.Name -> Version.Version -> IO [(Pkg.Name, Version.Version)]
readSubDeps cacheDir pkgName version = do
  let pkgDir = testDepDir cacheDir pkgName version
  eitherOutline <- Outline.read pkgDir
  pure (either (const []) extractPkgDeps eitherOutline)

-- | Extract regular dependencies from a package outline.
extractPkgDeps :: Outline.Outline -> [(Pkg.Name, Version.Version)]
extractPkgDeps (Outline.Pkg o) =
  Map.toList (Map.map Constraint.lowerBound (Outline._pkgDeps o))
extractPkgDeps _ = []

-- | Topologically sort packages so dependencies compile before dependents.
--
-- Uses iterative removal of nodes with no remaining in-graph dependencies.
-- Packages whose deps are all outside the graph (or already emitted) go first.
topologicalSort :: DepGraph -> [(Pkg.Name, Version.Version)]
topologicalSort graph = go graph []
  where
    go remaining acc
      | Map.null remaining = reverse acc
      | Map.null ready = reverse acc ++ Map.toList (Map.map fst remaining)
      | otherwise = go remaining' (Map.toList (Map.map fst ready) ++ acc)
      where
        readyNames = Map.keysSet (Map.filter (\(_, deps) -> all (`Map.notMember` remaining) deps) remaining)
        ready = Map.restrictKeys remaining readyNames
        remaining' = Map.withoutKeys remaining readyNames

-- | Compile a single test-dependency package if it lacks artifacts.
ensureOneTestDep :: FilePath -> (Pkg.Name, Version.Version) -> IO ()
ensureOneTestDep cacheDir (pkgName, version) = do
  let pkgDir = testDepDir cacheDir pkgName version
      artifactsPath = pkgDir </> "artifacts.dat"
  hasArtifacts <- Dir.doesFileExist artifactsPath
  if hasArtifacts
    then pure ()
    else compileTestDepFromSource pkgName version pkgDir

-- | Compile a test-dependency package from source and write artifacts.
compileTestDepFromSource :: Pkg.Name -> Version.Version -> FilePath -> IO ()
compileTestDepFromSource pkgName version pkgDir = do
  let srcPath = pkgDir </> "src"
  hasSrc <- Dir.doesDirectoryExist srcPath
  if not hasSrc
    then pure ()
    else do
      eitherOutline <- Outline.read pkgDir
      either (const (pure ())) (compileTestDepOutline pkgName version pkgDir srcPath) eitherOutline

-- | Compile a test-dependency package given its parsed outline.
compileTestDepOutline :: Pkg.Name -> Version.Version -> FilePath -> FilePath -> Outline.Outline -> IO ()
compileTestDepOutline _ _ _ _ (Outline.App _) = pure ()
compileTestDepOutline _ _ _ _ (Outline.Workspace _) = pure ()
compileTestDepOutline pkgName version pkgDir srcPath (Outline.Pkg pkgOutline) =
  case flattenExposedToNonEmpty (Outline._pkgExposed pkgOutline) of
    Nothing -> pure ()
    Just exposedModules -> do
      compileResult <-
        Dir.withCurrentDirectory
          pkgDir
          (Compiler.compileFromExposed pkgName False (Compiler.ProjectRoot pkgDir) [Compiler.AbsoluteSrcDir srcPath] exposedModules)
      either reportTestDepError (writeTestDepArtifacts pkgName version) compileResult
  where
    reportTestDepError err = do
      Print.printErrLn [c|{yellow|Warning:} Could not compile test dependency:|]
      Print.printErrLn (Doc.fromChars "")
      Print.printErrLn (BuildExit.toDoc err)

-- | Write compiled artifacts for a test-dependency package.
writeTestDepArtifacts :: Pkg.Name -> Version.Version -> Compiler.Artifacts -> IO ()
writeTestDepArtifacts (Pkg.Name author project) version artifacts =
  PackageCache.writePackageArtifacts
    (Utf8.toChars author)
    (Utf8.toChars project)
    (Version.toChars version)
    interfaces
    globalGraph
    ffiInfo
  where
    interfaces = buildArtifactsToInterfaces artifacts
    globalGraph = artifacts ^. Build.artifactsGlobalGraph
    ffiInfo = artifacts ^. Build.artifactsFFIInfo

-- | Convert compiled artifacts to package interface map.
buildArtifactsToInterfaces :: Compiler.Artifacts -> PackageCache.PackageInterfaces
buildArtifactsToInterfaces artifacts =
  Map.fromList
    [ (name, Interface.Public iface)
      | Build.Fresh name iface _ <- Build._artifactsModules artifacts
    ]

-- | Flatten exposed modules to a non-empty list.
flattenExposedToNonEmpty :: Outline.Exposed -> Maybe (NE.List ModuleName.Raw)
flattenExposedToNonEmpty exposed =
  case Outline.flattenExposed exposed of
    [] -> Nothing
    (x : xs) -> Just (NE.List x xs)

-- | Build the package directory path inside the cache.
testDepDir :: FilePath -> Pkg.Name -> Version.Version -> FilePath
testDepDir cacheDir (Pkg.Name author project) version =
  cacheDir </> Utf8.toChars author </> Utf8.toChars project </> Version.toChars version

-- | Generate JavaScript text from compiled artifacts.
--
-- Converts the Builder output directly to Text via UTF-8 decoding,
-- avoiding the intermediate @[Char]@ allocation.
--
-- @since 0.19.2
artifactsToJavaScript :: Compiler.Artifacts -> Text.Text
artifactsToJavaScript artifacts =
  postProcessJavaScript rawText
  where
    globalGraph = artifacts ^. Build.artifactsGlobalGraph
    ffiInfo = artifacts ^. Build.artifactsFFIInfo
    mains = collectMains artifacts
    (builder, _sourceMap, _coverageMap) = JS.generate (Mode.Dev Nothing False True False Set.empty False) globalGraph mains ffiInfo
    rawText = TextEnc.decodeUtf8 (LBS.toStrict (Builder.toLazyByteString builder))

-- | Generate JavaScript text with coverage instrumentation.
--
-- Like 'artifactsToJavaScript' but enables coverage mode in the code
-- generator, injecting @__cov(N)@ calls at function entries and branch
-- sites. Returns the JS text, the main map, and the 'CoverageMap' needed
-- to interpret the runtime hit data.
--
-- @since 0.19.2
artifactsToJavaScriptCov ::
  Compiler.Artifacts ->
  (Text.Text, Map.Map ModuleName.Canonical Opt.Main, Maybe Coverage.CoverageMap)
artifactsToJavaScriptCov artifacts =
  (postProcessJavaScript rawText, mains, covMap)
  where
    globalGraph = artifacts ^. Build.artifactsGlobalGraph
    ffiInfo = artifacts ^. Build.artifactsFFIInfo
    mains = collectMains artifacts
    (builder, _sourceMap, covMap) = JS.generate (Mode.Dev Nothing False True False Set.empty True) globalGraph mains ffiInfo
    rawText = TextEnc.decodeUtf8 (LBS.toStrict (Builder.toLazyByteString builder))

-- | Post-process JavaScript to fix rendering quirks and resolve kernel
-- debug\/prod markers for dev mode.
--
-- Fixes:
--   * @else if@ rendered as @elseif@ by @language-javascript@
--   * @\/\*\*__PROD\/...\/\/\*\/@ blocks removed (dev mode)
--   * @\/\*\*__DEBUG\/...\/\/\*\/@ blocks unwrapped to their content
--   * @__DEBUG@ and @__PROD@ function name suffixes resolved
--
-- @since 0.19.2
postProcessJavaScript :: Text.Text -> Text.Text
postProcessJavaScript =
  Text.replace "elseif" "else if"
    . resolveKernelProdBlocks
    . resolveKernelDebugBlocks
    . resolveKernelFunctionSuffixes

-- | Remove @\/\*\*__PROD\/...\/\/\*\/@ comment blocks (dev mode discards prod code).
--
-- @since 0.19.2
resolveKernelProdBlocks :: Text.Text -> Text.Text
resolveKernelProdBlocks txt =
  maybe txt (uncurry replaceProdBlock) (findProdBlock txt)

-- | Find and remove one @\/\*\*__PROD\/...\/\/\*\/@ block, then recurse.
findProdBlock :: Text.Text -> Maybe (Text.Text, Text.Text)
findProdBlock txt =
  case Text.breakOn "/**__PROD/" txt of
    (_, rest) | Text.null rest -> Nothing
    (before, rest) ->
      case Text.breakOn "//*/" (Text.drop 10 rest) of
        (_, closing) | Text.null closing -> Nothing
        (_, closing) -> Just (before, Text.drop 4 closing)

-- | Replace one prod block and recurse for any remaining.
replaceProdBlock :: Text.Text -> Text.Text -> Text.Text
replaceProdBlock before after =
  resolveKernelProdBlocks (before <> after)

-- | Unwrap @\/\*\*__DEBUG\/...\/\/\*\/@ comment blocks (dev mode keeps debug code).
--
-- @since 0.19.2
resolveKernelDebugBlocks :: Text.Text -> Text.Text
resolveKernelDebugBlocks txt =
  maybe txt (uncurry replaceDebugBlock) (findDebugBlock txt)

-- | Find one @\/\*\*__DEBUG\/...\/\/\*\/@ block and extract its content.
findDebugBlock :: Text.Text -> Maybe ((Text.Text, Text.Text), Text.Text)
findDebugBlock txt =
  case Text.breakOn "/**__DEBUG/" txt of
    (_, rest) | Text.null rest -> Nothing
    (before, rest) ->
      case Text.breakOn "//*/" (Text.drop 11 rest) of
        (_, closing) | Text.null closing -> Nothing
        (content, closing) -> Just ((before, content), Text.drop 4 closing)

-- | Replace one debug block with its content and recurse.
replaceDebugBlock :: (Text.Text, Text.Text) -> Text.Text -> Text.Text
replaceDebugBlock (before, content) after =
  resolveKernelDebugBlocks (before <> content <> after)

-- | Resolve @__DEBUG@ and @__PROD@ function name suffixes for dev mode.
--
-- In dev mode: @foo__DEBUG@ becomes @foo@, @foo__PROD@ lines are removed.
--
-- @since 0.19.2
resolveKernelFunctionSuffixes :: Text.Text -> Text.Text
resolveKernelFunctionSuffixes txt =
  Text.unlines (concatMap resolveLine (Text.lines txt))
  where
    resolveLine line
      | Text.isInfixOf "__PROD" line && not (Text.isInfixOf "/**" line) = []
      | otherwise = [Text.replace "__DEBUG" "" line]

-- | Collect main entries from all roots of the artifacts.
collectMains :: Compiler.Artifacts -> Map.Map ModuleName.Canonical Opt.Main
collectMains artifacts =
  Map.fromList (Maybe.mapMaybe (extractMain pkg) roots)
  where
    roots = NE.toList (artifacts ^. Build.artifactsRoots)
    pkg = artifacts ^. Build.artifactsName

-- | Extract a (CanonicalName, Main) pair from a root.
extractMain :: Pkg.Name -> Build.Root -> Maybe (ModuleName.Canonical, Opt.Main)
extractMain pkg root =
  case root of
    Build.Inside _ -> Nothing
    Build.Outside name _ (Opt.LocalGraph maybeMain _ _ _) ->
      fmap (\m -> (ModuleName.Canonical pkg name, m)) maybeMain

-- | Detect FFI functions that are defined but never referenced in the
-- compiled code.
--
-- Compares function names extracted from @\@canopy-type@ annotations in
-- FFI JavaScript files against the set of globals in the dependency graph.
-- Any annotated function whose name does not appear as a global is
-- reported as stale.
--
-- @since 0.19.2
detectStaleFFI :: Map.Map String FFI.FFIInfo -> Opt.GlobalGraph -> [(String, FilePath)]
detectStaleFFI ffiInfos (Opt.GlobalGraph nodes _ _) =
  concatMap checkFile (Map.toList ffiInfos)
  where
    usedNames = Set.fromList (map globalName (Map.keys nodes))
    globalName (Opt.Global _ n) = Name.toChars n

    checkFile (path, info) =
      let functions = FFI.extractCanopyTypeFunctions (Text.lines (FFI._ffiContent info))
          stale = filter (\(name, _) -> not (Set.member (Text.unpack name) usedNames)) functions
       in map (\(name, _) -> (Text.unpack name, path)) stale
