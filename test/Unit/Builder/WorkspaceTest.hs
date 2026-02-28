{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Builder.Workspace module.
--
-- Tests workspace discovery, package resolution, and validation
-- for monorepo/workspace support.
--
-- @since 0.19.2
module Unit.Builder.WorkspaceTest (tests) where

import qualified Builder.Workspace as Workspace
import qualified Canopy.Outline as Outline
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as Version
import qualified Data.ByteString.Lazy.Char8 as LBS8
import qualified Data.Map.Strict as Map
import System.FilePath ((</>))
import qualified System.Directory as Dir
import qualified System.IO.Temp as Temp
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Builder.Workspace Tests"
    [ testWorkspaceOutlineTypes,
      testWorkspaceDiscovery,
      testWorkspaceResolution,
      testWorkspaceValidation
    ]

testWorkspaceOutlineTypes :: TestTree
testWorkspaceOutlineTypes =
  testGroup
    "WorkspaceOutline types"
    [ testCase "roundtrip workspace outline through write/read" $
        Temp.withSystemTempDirectory "ws-rt" $ \tmpDir -> do
          let ws =
                Outline.WorkspaceOutline
                  { Outline._wsPackages = ["packages/core", "packages/ui"],
                    Outline._wsSharedDeps = Map.empty,
                    Outline._wsCanopy = Version.compiler
                  }
          Outline.write tmpDir (Outline.Workspace ws)
          result <- Outline.read tmpDir
          case result of
            Right (Outline.Workspace decoded) -> do
              Outline._wsPackages decoded @?= ["packages/core", "packages/ui"]
              Outline._wsCanopy decoded @?= Version.compiler
            Right _ -> assertFailure "Expected Workspace outline"
            Left err -> assertFailure ("Read failed: " ++ err),
      testCase "workspace with shared deps roundtrips" $
        Temp.withSystemTempDirectory "ws-deps-rt" $ \tmpDir -> do
          let coreName = Pkg.core
              ws =
                Outline.WorkspaceOutline
                  { Outline._wsPackages = ["app"],
                    Outline._wsSharedDeps = Map.singleton coreName Version.one,
                    Outline._wsCanopy = Version.compiler
                  }
          Outline.write tmpDir (Outline.Workspace ws)
          result <- Outline.read tmpDir
          case result of
            Right (Outline.Workspace decoded) ->
              Map.size (Outline._wsSharedDeps decoded) @?= 1
            Right _ -> assertFailure "Expected Workspace outline"
            Left err -> assertFailure ("Read failed: " ++ err),
      testCase "isWorkspace returns True for workspace" $ do
        let ws =
              Outline.Workspace
                (Outline.WorkspaceOutline [] Map.empty Version.compiler)
        Outline.isWorkspace ws @?= True,
      testCase "isWorkspace returns False for App" $ do
        let app =
              Outline.App
                ( Outline.AppOutline
                    Version.compiler
                    []
                    Map.empty
                    Map.empty
                    Map.empty
                    Map.empty
                    Map.empty
                )
        Outline.isWorkspace app @?= False,
      testCase "allDeps returns shared deps for workspace" $ do
        let coreName = Pkg.core
            ws =
              Outline.Workspace
                ( Outline.WorkspaceOutline
                    ["pkg"]
                    (Map.singleton coreName Version.one)
                    Version.compiler
                )
        Outline.allDeps ws @?= [(coreName, Version.one)]
    ]

testWorkspaceDiscovery :: TestTree
testWorkspaceDiscovery =
  testGroup
    "Workspace discovery"
    [ testCase "findWorkspaceRoot finds workspace in parent directory" $
        Temp.withSystemTempDirectory "ws-test" $ \tmpDir -> do
          let pkgDir = tmpDir </> "packages" </> "core"
          Dir.createDirectoryIfMissing True pkgDir
          writeWorkspaceOutline tmpDir ["packages/core"]
          writeAppOutline pkgDir Version.compiler
          result <- Workspace.findWorkspaceRoot pkgDir
          case result of
            Just (foundRoot, ws) -> do
              foundRoot @?= tmpDir
              Outline._wsPackages ws @?= ["packages/core"]
            Nothing -> assertFailure "Expected to find workspace root",
      testCase "findWorkspaceRoot returns Nothing when no workspace exists" $
        Temp.withSystemTempDirectory "no-ws-test" $ \tmpDir -> do
          let subDir = tmpDir </> "sub"
          Dir.createDirectoryIfMissing True subDir
          writeAppOutline subDir Version.compiler
          result <- Workspace.findWorkspaceRoot subDir
          case result of
            Nothing -> pure ()
            Just _ -> assertFailure "Expected Nothing from findWorkspaceRoot"
    ]

testWorkspaceResolution :: TestTree
testWorkspaceResolution =
  testGroup
    "Workspace package resolution"
    [ testCase "resolveWorkspacePackages finds member packages" $
        Temp.withSystemTempDirectory "ws-resolve" $ \tmpDir -> do
          let pkgDir = tmpDir </> "packages" </> "core"
          Dir.createDirectoryIfMissing True pkgDir
          writeAppOutline pkgDir Version.compiler
          let ws =
                Outline.WorkspaceOutline
                  { Outline._wsPackages = ["packages/core"],
                    Outline._wsSharedDeps = Map.empty,
                    Outline._wsCanopy = Version.compiler
                  }
          result <- Workspace.resolveWorkspacePackages tmpDir ws
          case result of
            Right packages -> length packages @?= 1
            Left err -> assertFailure ("Resolution failed: " ++ show err),
      testCase "resolveWorkspacePackages fails on missing member" $
        Temp.withSystemTempDirectory "ws-missing" $ \tmpDir -> do
          let ws =
                Outline.WorkspaceOutline
                  { Outline._wsPackages = ["nonexistent"],
                    Outline._wsSharedDeps = Map.empty,
                    Outline._wsCanopy = Version.compiler
                  }
          result <- Workspace.resolveWorkspacePackages tmpDir ws
          case result of
            Left (Workspace.MemberNotFound _) -> pure ()
            Left err -> assertFailure ("Expected MemberNotFound, got: " ++ show err)
            Right _ -> assertFailure "Expected failure for missing member"
    ]

testWorkspaceValidation :: TestTree
testWorkspaceValidation =
  testGroup
    "Workspace validation"
    [ testCase "validateWorkspace succeeds for valid workspace" $
        Temp.withSystemTempDirectory "ws-valid" $ \tmpDir -> do
          let pkgDir = tmpDir </> "packages" </> "core"
          Dir.createDirectoryIfMissing True pkgDir
          writeAppOutline pkgDir Version.compiler
          let ws =
                Outline.WorkspaceOutline
                  { Outline._wsPackages = ["packages/core"],
                    Outline._wsSharedDeps = Map.empty,
                    Outline._wsCanopy = Version.compiler
                  }
          result <- Workspace.validateWorkspace tmpDir ws
          result @?= Right (),
      testCase "validateWorkspace rejects nested workspaces" $
        Temp.withSystemTempDirectory "ws-nested" $ \tmpDir -> do
          let nestedDir = tmpDir </> "nested"
          Dir.createDirectoryIfMissing True nestedDir
          writeWorkspaceOutline nestedDir ["sub"]
          let ws =
                Outline.WorkspaceOutline
                  { Outline._wsPackages = ["nested"],
                    Outline._wsSharedDeps = Map.empty,
                    Outline._wsCanopy = Version.compiler
                  }
          result <- Workspace.validateWorkspace tmpDir ws
          case result of
            Left (Workspace.MemberInvalidOutline _ _) -> pure ()
            Left err -> assertFailure ("Expected MemberInvalidOutline, got: " ++ show err)
            Right () -> assertFailure "Expected validation failure for nested workspace",
      testCase "validateWorkspace detects version conflicts" $
        Temp.withSystemTempDirectory "ws-conflict" $ \tmpDir -> do
          let pkgDir = tmpDir </> "pkg"
          Dir.createDirectoryIfMissing True pkgDir
          writeAppOutline pkgDir (Version.Version 1 0 0)
          let ws =
                Outline.WorkspaceOutline
                  { Outline._wsPackages = ["pkg"],
                    Outline._wsSharedDeps = Map.empty,
                    Outline._wsCanopy = Version.compiler
                  }
          result <- Workspace.validateWorkspace tmpDir ws
          case result of
            Left (Workspace.MemberVersionConflict _ _ _) -> pure ()
            Left err -> assertFailure ("Expected MemberVersionConflict, got: " ++ show err)
            Right () -> assertFailure "Expected validation failure for version conflict"
    ]

-- | Write a workspace canopy.json to a directory.
writeWorkspaceOutline :: FilePath -> [String] -> IO ()
writeWorkspaceOutline dir packages =
  Outline.write dir (Outline.Workspace ws)
  where
    ws =
      Outline.WorkspaceOutline
        packages
        Map.empty
        Version.compiler

-- | Write a minimal application canopy.json to a directory.
--
-- Writes raw JSON in the elm-compatible format that 'Outline.read' expects,
-- because 'Outline.write' uses a different serialization format than
-- what 'Outline.read' parses.
writeAppOutline :: FilePath -> Version.Version -> IO ()
writeAppOutline dir ver =
  LBS8.writeFile (dir </> "canopy.json") jsonBytes
  where
    verStr = Version.toChars ver
    jsonBytes =
      LBS8.pack $
        "{\"type\":\"application\""
          ++ ",\"source-directories\":[\"src\"]"
          ++ ",\"canopy-version\":\"" ++ verStr ++ "\""
          ++ ",\"dependencies\":{\"direct\":{},\"indirect\":{}}"
          ++ ",\"test-dependencies\":{\"direct\":{},\"indirect\":{}}"
          ++ "}"
