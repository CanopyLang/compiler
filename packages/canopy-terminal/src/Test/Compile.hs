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
    collectMains,
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
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import qualified Generate.JavaScript as JS
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
-- @since 0.19.1
compileTestFiles :: FilePath -> [FilePath] -> IO (Maybe (Text.Text, Map.Map ModuleName.Canonical Opt.Main))
compileTestFiles root testFiles = do
  ensureTestDepArtifacts root
  let pkg = Pkg.dummyName
      srcDirs =
        [ Compiler.RelativeSrcDir "src",
          Compiler.RelativeSrcDir "tests",
          Compiler.RelativeSrcDir "test"
        ]
  result <- Compiler.compileFromPaths pkg True (Compiler.ProjectRoot root) srcDirs testFiles
  case result of
    Left err -> do
      let errStr = show err
      Print.printErrLn [c|{red|Compilation error:} #{errStr}|]
      pure Nothing
    Right artifacts -> pure (Just (artifactsToJavaScript artifacts, collectMains artifacts))

-- | Ensure all test-dependency packages have compiled artifacts.
--
-- Reads the project outline, extracts test dependencies, and for each
-- package that has source files but no @artifacts.dat@, compiles the
-- package from source with its real package identity.
--
-- @since 0.19.1
ensureTestDepArtifacts :: FilePath -> IO ()
ensureTestDepArtifacts root = do
  eitherOutline <- Outline.read root
  case eitherOutline of
    Left _ -> pure ()
    Right outline -> do
      cacheDir <- Stuff.getPackageCache
      mapM_ (ensureOneTestDep cacheDir) (extractTestDeps outline)

-- | Extract test-dependency (name, version) pairs from an outline.
extractTestDeps :: Outline.Outline -> [(Pkg.Name, Version.Version)]
extractTestDeps (Outline.App o) = Map.toList (Outline._appTestDepsDirect o)
extractTestDeps (Outline.Pkg o) =
  Map.toList (Map.map Constraint.lowerBound (Outline._pkgTestDeps o))
extractTestDeps (Outline.Workspace _) = []

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
      let errStr = show err
      Print.printErrLn [c|{yellow|Warning:} Could not compile test dependency: #{errStr}|]

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
    (builder, _sourceMap) = JS.generate (Mode.Dev Nothing False False False Set.empty) globalGraph mains ffiInfo
    rawText = TextEnc.decodeUtf8 (LBS.toStrict (Builder.toLazyByteString builder))

-- | Post-process JavaScript to fix the @language-javascript@ rendering
-- quirk where @else if@ is emitted as @elseif@.
postProcessJavaScript :: Text.Text -> Text.Text
postProcessJavaScript = Text.replace "elseif" "else if"

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
