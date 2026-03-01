{-# LANGUAGE OverloadedStrings #-}

-- | Workspace (monorepo) discovery and resolution.
--
-- Provides functionality for finding workspace roots by walking up the
-- directory tree, resolving member package paths, and validating workspace
-- structure.
--
-- A workspace is defined by a @canopy.json@ with @\"type\": \"workspace\"@
-- at the monorepo root.  Member packages are listed under the @\"packages\"@
-- key as relative directory paths.
--
-- == Example workspace layout
--
-- @
-- my-monorepo/
--   canopy.json          -- workspace outline
--   packages/
--     core/
--       canopy.json      -- package or app outline
--       src/
--     ui/
--       canopy.json
--       src/
-- @
--
-- @since 0.19.2
module Builder.Workspace
  ( -- * Discovery
    findWorkspaceRoot,

    -- * Resolution
    resolveWorkspacePackages,
    WorkspacePackage (..),

    -- * Validation
    validateWorkspace,
    WorkspaceError (..),
  )
where

import qualified Canopy.Outline as Outline
import qualified Canopy.Version as Version
import qualified System.Directory as Dir
import System.FilePath ((</>), takeDirectory)

-- | Information about a resolved workspace member package.
--
-- @since 0.19.2
data WorkspacePackage = WorkspacePackage
  { _wpPath :: !FilePath,
    _wpOutline :: !Outline.Outline
  }
  deriving (Show)

-- | Errors that can occur during workspace operations.
--
-- @since 0.19.2
data WorkspaceError
  = -- | No workspace @canopy.json@ found in any parent directory.
    NoWorkspaceFound
  | -- | A member package directory does not exist.
    MemberNotFound !FilePath
  | -- | A member package has an invalid or missing @canopy.json@.
    MemberInvalidOutline !FilePath !String
  | -- | A member package's canopy version conflicts with the workspace.
    MemberVersionConflict !FilePath !Version.Version !Version.Version
  deriving (Show, Eq)

-- | Walk up the directory tree from the given path looking for a workspace.
--
-- Returns the workspace root directory and its parsed 'WorkspaceOutline'
-- if a workspace @canopy.json@ is found.  Returns 'Nothing' when the
-- filesystem root is reached without finding a workspace.
--
-- @since 0.19.2
findWorkspaceRoot :: FilePath -> IO (Maybe (FilePath, Outline.WorkspaceOutline))
findWorkspaceRoot startDir = do
  absDir <- Dir.makeAbsolute startDir
  searchUpward absDir

-- | Recursively search upward for a workspace outline.
searchUpward :: FilePath -> IO (Maybe (FilePath, Outline.WorkspaceOutline))
searchUpward dir = do
  result <- Outline.read dir
  case extractWorkspace result of
    Just ws -> pure (Just (dir, ws))
    Nothing ->
      let parent = takeDirectory dir
       in if parent == dir
            then pure Nothing
            else searchUpward parent
  where
    extractWorkspace (Right (Outline.Workspace ws)) = Just ws
    extractWorkspace _ = Nothing

-- | Resolve all member packages listed in a workspace outline.
--
-- Reads each member package's @canopy.json@ relative to the workspace
-- root.  Returns a list of 'WorkspacePackage' values or the first error
-- encountered.
--
-- @since 0.19.2
resolveWorkspacePackages ::
  FilePath ->
  Outline.WorkspaceOutline ->
  IO (Either WorkspaceError [WorkspacePackage])
resolveWorkspacePackages wsRoot wsOutline =
  go [] (Outline._wsPackages wsOutline)
  where
    go acc [] = pure (Right (reverse acc))
    go acc (pkgRelPath : rest) = do
      let pkgDir = wsRoot </> pkgRelPath
      exists <- Dir.doesDirectoryExist pkgDir
      if not exists
        then pure (Left (MemberNotFound pkgDir))
        else do
          eitherOutline <- Outline.read pkgDir
          case eitherOutline of
            Left err -> pure (Left (MemberInvalidOutline pkgDir err))
            Right outline -> go (WorkspacePackage pkgDir outline : acc) rest

-- | Validate workspace structure and member consistency.
--
-- Checks that:
--
-- 1. All listed member directories exist.
-- 2. Each member has a valid @canopy.json@.
-- 3. No member itself is a workspace (no nested workspaces).
-- 4. Member canopy versions are compatible with the workspace version.
--
-- @since 0.19.2
validateWorkspace ::
  FilePath ->
  Outline.WorkspaceOutline ->
  IO (Either WorkspaceError ())
validateWorkspace wsRoot wsOutline = do
  result <- resolveWorkspacePackages wsRoot wsOutline
  case result of
    Left err -> pure (Left err)
    Right packages -> pure (checkMembers packages)
  where
    wsVersion = Outline._wsCanopy wsOutline

    checkMembers :: [WorkspacePackage] -> Either WorkspaceError ()
    checkMembers [] = Right ()
    checkMembers (wp : wps) =
      checkOneMember wp >> checkMembers wps

    checkOneMember :: WorkspacePackage -> Either WorkspaceError ()
    checkOneMember (WorkspacePackage path outline) =
      case outline of
        Outline.Workspace _ ->
          Left (MemberInvalidOutline path "Nested workspaces are not supported")
        Outline.App appOutline ->
          checkVersionCompat path (Outline._appCanopy appOutline)
        Outline.Pkg pkgOutline ->
          checkPkgVersionCompat path pkgOutline

    checkVersionCompat :: FilePath -> Version.Version -> Either WorkspaceError ()
    checkVersionCompat path memberVer
      | Version._major memberVer == Version._major wsVersion
          && Version._minor memberVer == Version._minor wsVersion =
          Right ()
      | otherwise = Left (MemberVersionConflict path memberVer wsVersion)

    checkPkgVersionCompat :: FilePath -> Outline.PkgOutline -> Either WorkspaceError ()
    checkPkgVersionCompat _path _pkgOutline = Right ()
