{-# LANGUAGE OverloadedStrings #-}

-- | Detect third-party packages using legacy kernel code.
--
-- Scans project dependencies to find packages that contain JavaScript files
-- in @src\/Elm\/Kernel\/@ directories. These packages use the legacy kernel
-- mechanism instead of the Canopy FFI system, which bypasses type safety
-- guarantees at the JavaScript boundary.
--
-- Trusted packages (authored by @canopy@, @elm@, @canopy-explorations@,
-- @elm-explorations@) are excluded from this check since they are part of
-- the core platform and their kernel code is maintained by the compiler team.
--
-- @since 0.19.2
module Make.KernelCheck
  ( -- * Detection
    detectKernelPackages,

    -- * Warning
    emitKernelWarning,
  )
where

import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Data.List as List
import qualified Canopy.Data.Utf8 as Utf8
import qualified System.Directory as Dir
import System.FilePath ((</>))
import qualified System.IO as IO

-- | Detect third-party packages that contain kernel code.
--
-- Reads the project outline to discover all dependencies, then checks each
-- non-trusted package for the presence of @src\/Elm\/Kernel\/@ JavaScript
-- files. Returns the list of package names (as display strings) that use
-- kernel code.
--
-- Trusted authors are excluded because their kernel usage is expected and
-- maintained by the Canopy platform team.
--
-- @since 0.19.2
detectKernelPackages :: FilePath -> IO [String]
detectKernelPackages root = do
  eitherOutline <- Outline.read root
  let deps = either (const []) Outline.allDeps eitherOutline
      thirdPartyDeps = filter (not . isTrustedDep . fst) deps
  filterKernelDeps thirdPartyDeps

-- | Check whether a package is from a trusted author.
--
-- Packages authored by @canopy@, @elm@, @canopy-explorations@, or
-- @elm-explorations@ are trusted and allowed to use kernel code.
isTrustedDep :: Pkg.Name -> Bool
isTrustedDep pkg =
  let author = Pkg._author pkg
   in author == Pkg.canopy
        || author == Pkg.elm
        || author == Pkg.canopyExplorations
        || author == Pkg.elmExplorations

-- | Filter dependencies to those containing kernel JavaScript files.
filterKernelDeps :: [(Pkg.Name, Version.Version)] -> IO [String]
filterKernelDeps deps = do
  results <- mapM checkPackageForKernel deps
  pure (concat results)

-- | Check a single package for kernel code presence.
--
-- Searches both @~\/.canopy\/packages\/@ and @~\/.elm\/0.19.1\/packages\/@
-- for the package directory, then checks for @src\/Elm\/Kernel\/@ containing
-- @.js@ files.
checkPackageForKernel :: (Pkg.Name, Version.Version) -> IO [String]
checkPackageForKernel (pkg, version) = do
  homeDir <- Dir.getHomeDirectory
  let author = Utf8.toChars (Pkg._author pkg)
      project = Utf8.toChars (Pkg._project pkg)
      ver = Version.toChars version
      candidates =
        [ homeDir </> ".canopy" </> "packages" </> author </> project </> ver,
          homeDir </> ".elm" </> "0.19.1" </> "packages" </> author </> project </> ver
        ]
  hasKernel <- anyDirectoryHasKernel candidates
  pure [Pkg.toChars pkg <> " " <> ver | hasKernel]

-- | Check if any of the candidate directories contain kernel JavaScript.
anyDirectoryHasKernel :: [FilePath] -> IO Bool
anyDirectoryHasKernel [] = pure False
anyDirectoryHasKernel (dir : rest) = do
  found <- directoryHasKernelJs dir
  if found then pure True else anyDirectoryHasKernel rest

-- | Check whether a package directory contains kernel JavaScript files.
--
-- Looks for @.js@ files (excluding @.server.js@) in the
-- @src\/Elm\/Kernel\/@ subdirectory.
directoryHasKernelJs :: FilePath -> IO Bool
directoryHasKernelJs pkgDir = do
  let kernelDir = pkgDir </> "src" </> "Elm" </> "Kernel"
  exists <- Dir.doesDirectoryExist kernelDir
  if exists
    then do
      files <- Dir.listDirectory kernelDir
      pure (any isKernelJsFile files)
    else pure False

-- | Check if a filename is a kernel JavaScript file.
isKernelJsFile :: FilePath -> Bool
isKernelJsFile f =
  List.isSuffixOf ".js" f
    && not (List.isSuffixOf ".server.js" f)

-- | Emit a prominent warning about kernel code usage to stderr.
--
-- Prints a highly visible warning banner that lists all third-party packages
-- using legacy kernel code. The warning recommends migrating to the Canopy
-- FFI system for type safety at the JavaScript boundary.
--
-- @since 0.19.2
emitKernelWarning :: [String] -> IO ()
emitKernelWarning pkgs = do
  IO.hPutStrLn IO.stderr ""
  IO.hPutStrLn IO.stderr "╔══════════════════════════════════════════════════════════════════════╗"
  IO.hPutStrLn IO.stderr "║  WARNING: LEGACY KERNEL CODE DETECTED                              ║"
  IO.hPutStrLn IO.stderr "╠══════════════════════════════════════════════════════════════════════╣"
  IO.hPutStrLn IO.stderr "║                                                                    ║"
  IO.hPutStrLn IO.stderr "║  The following packages use legacy kernel code instead of the       ║"
  IO.hPutStrLn IO.stderr "║  Canopy FFI system. Kernel code bypasses type safety at the         ║"
  IO.hPutStrLn IO.stderr "║  JavaScript boundary and is NOT recommended for production use.     ║"
  IO.hPutStrLn IO.stderr "║                                                                    ║"
  mapM_ emitPackageLine pkgs
  IO.hPutStrLn IO.stderr "║                                                                    ║"
  IO.hPutStrLn IO.stderr "║  Migrate these packages to the Canopy FFI system for type-safe     ║"
  IO.hPutStrLn IO.stderr "║  JavaScript interop. See: https://canopy-lang.org/guide/ffi        ║"
  IO.hPutStrLn IO.stderr "║                                                                    ║"
  IO.hPutStrLn IO.stderr "╚══════════════════════════════════════════════════════════════════════╝"
  IO.hPutStrLn IO.stderr ""

-- | Emit a single package line inside the warning box.
emitPackageLine :: String -> IO ()
emitPackageLine pkg =
  IO.hPutStrLn IO.stderr ("║    - " <> pkg <> replicate padding ' ' <> "║")
  where
    contentLen = 6 + length pkg
    padding = max 1 (70 - contentLen)
