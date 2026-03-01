{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Local Canopy package compilation during setup.
--
-- Scans @~\/.canopy\/packages\/canopy\/@ for packages with source
-- directories but missing @artifacts.dat@, compiles them, and writes
-- the resulting artifacts.
--
-- @since 0.19.1
module Setup.LocalCompilation
  ( -- * Compilation
    compileLocalPackages,
  )
where

import qualified Build.Artifacts as Build
import qualified Canopy.Data.NonEmptyList as NE
import qualified Canopy.Data.Utf8 as Utf8
import qualified Canopy.Interface as Interface
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Compiler
import qualified Data.Map.Strict as Map
import qualified PackageCache
import Reporting.Doc.ColorQQ (c)
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified Terminal.Print as Print
import qualified Text.PrettyPrint.ANSI.Leijen as PP

-- | Compile all local Canopy packages that have source but no artifacts.
--
-- Scans @~/.canopy/packages/canopy/@ for packages with source directories
-- but missing artifacts.dat, compiles them, and writes the artifacts.
compileLocalPackages :: Bool -> IO [Bool]
compileLocalPackages verbose = do
  homeDir <- Dir.getHomeDirectory
  let canopyPkgDir = homeDir </> ".canopy" </> "packages" </> "canopy"
  exists <- Dir.doesDirectoryExist canopyPkgDir
  if not exists
    then pure []
    else do
      packages <- Dir.listDirectory canopyPkgDir
      results <- mapM (compileLocalPackage verbose canopyPkgDir) packages
      pure (concat results)

-- | Compile a single local Canopy package if needed.
compileLocalPackage :: Bool -> FilePath -> String -> IO [Bool]
compileLocalPackage verbose canopyPkgDir packageName = do
  let pkgDir = canopyPkgDir </> packageName
  versionDirs <- tryListDirectory pkgDir
  mapM (compilePackageVersion verbose packageName pkgDir) versionDirs

-- | Try to list a directory, returning empty list on failure.
tryListDirectory :: FilePath -> IO [FilePath]
tryListDirectory dir = do
  isDir <- Dir.doesDirectoryExist dir
  if isDir
    then Dir.listDirectory dir
    else pure []

-- | Compile a specific version of a package if it has source but no artifacts.
compilePackageVersion :: Bool -> String -> FilePath -> String -> IO Bool
compilePackageVersion verbose packageName pkgDir versionStr = do
  let versionDir = pkgDir </> versionStr
      artifactsPath = versionDir </> "artifacts.dat"
      canopyJsonPath = versionDir </> "canopy.json"
      srcDir = versionDir </> "src"
      label = "canopy/" <> packageName <> " " <> versionStr
  artifactsExist <- Dir.doesFileExist artifactsPath
  if artifactsExist
    then do
      Print.println [c|  #{label}: {green|ready}|]
      pure True
    else do
      canopyJsonExists <- Dir.doesFileExist canopyJsonPath
      srcExists <- Dir.doesDirectoryExist srcDir
      if canopyJsonExists && srcExists
        then compileAndReport verbose label packageName versionStr versionDir
        else do
          Print.println [c|  #{label}: {red|no source found}|]
          pure False

-- | Attempt compilation and report the result.
compileAndReport :: Bool -> String -> String -> String -> FilePath -> IO Bool
compileAndReport verbose label packageName versionStr versionDir = do
  Print.println [c|  #{label}: {yellow|compiling from source...}|]
  result <- compilePackageFromSource "canopy" packageName versionStr versionDir
  case result of
    Right () -> do
      Print.println [c|  #{label}: {green|compiled}|]
      pure True
    Left err -> do
      Print.println [c|  #{label}: {red|compilation failed}|]
      verboseLog verbose [c|    Error: #{err}|]
      pure False

-- | Compile a package from source and write its artifacts.
compilePackageFromSource :: String -> String -> String -> FilePath -> IO (Either String ())
compilePackageFromSource author packageName versionStr pkgDir = do
  eitherOutline <- Outline.read pkgDir
  case eitherOutline of
    Left err -> pure (Left err)
    Right outline ->
      compileFromOutline author packageName versionStr pkgDir outline

-- | Compile from a parsed package outline.
compileFromOutline :: String -> String -> String -> FilePath -> Outline.Outline -> IO (Either String ())
compileFromOutline _ _ _ _ (Outline.App _) = pure (Left "Expected package outline, found application outline")
compileFromOutline _ _ _ _ (Outline.Workspace _) = pure (Left "Expected package outline, found workspace outline")
compileFromOutline author packageName versionStr pkgDir (Outline.Pkg pkgOutline) =
  case exposedToNonEmpty (Outline._pkgExposed pkgOutline) of
    Nothing -> pure (Left "No exposed modules found in canopy.json")
    Just exposedModules -> do
      let pkg = mkPkg author packageName
          srcDir = pkgDir </> "src"
      compileResult <- Dir.withCurrentDirectory pkgDir
        (Compiler.compileFromExposed pkg False (Compiler.ProjectRoot pkgDir) [Compiler.AbsoluteSrcDir srcDir] exposedModules)
      case compileResult of
        Left err -> pure (Left (show err))
        Right artifacts -> do
          let interfaces = buildArtifactsToInterfaces artifacts
              globalGraph = Build._artifactsGlobalGraph artifacts
              ffiInfo = Build._artifactsFFIInfo artifacts
          PackageCache.writePackageArtifacts author packageName versionStr interfaces globalGraph ffiInfo
          pure (Right ())

-- | Convert Build.Artifacts to PackageInterfaces.
buildArtifactsToInterfaces :: Build.Artifacts -> PackageCache.PackageInterfaces
buildArtifactsToInterfaces artifacts =
  Map.fromList
    [ (name, Interface.Public iface)
    | Build.Fresh name iface _ <- Build._artifactsModules artifacts
    ]

-- | Convert Exposed to NonEmpty list of module names.
exposedToNonEmpty :: Outline.Exposed -> Maybe (NE.List ModuleName.Raw)
exposedToNonEmpty exposed =
  case Outline.flattenExposed exposed of
    [] -> Nothing
    (x:xs) -> Just (NE.List x xs)

-- | Construct a package name from author and project strings.
mkPkg :: String -> String -> Pkg.Name
mkPkg author project =
  Pkg.Name (Utf8.fromChars author) (Utf8.fromChars project)

-- | Print a 'PP.Doc' message when verbose mode is enabled.
verboseLog :: Bool -> PP.Doc -> IO ()
verboseLog verbose doc =
  if verbose
    then Print.println doc
    else pure ()
