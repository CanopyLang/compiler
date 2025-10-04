{-# LANGUAGE OverloadedStrings #-}

module Develop.StaticFiles.Build
  ( readAsset,
    buildReactorFrontEnd,
  )
where

import qualified BackgroundWriter as BW
import qualified Build
import qualified Canopy.Details as Details
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Lazy as LBS
import qualified Data.NonEmptyList as NE
import qualified Generate
import qualified Reporting
import qualified Reporting.Exit as Exit
import qualified Reporting.Task as Task
import qualified System.Directory as Dir
import System.FilePath ((</>))

-- ASSETS

readAsset :: FilePath -> IO ByteString
readAsset path =
  BS.readFile ("reactor" </> "assets" </> path)

-- BUILD REACTOR CANOPY

buildReactorFrontEnd :: IO ByteString
buildReactorFrontEnd =
  BW.withScope $ \_ ->
    Dir.withCurrentDirectory "reactor" $
      do
        root <- Dir.getCurrentDirectory
        runTaskUnsafe $
          do
            details <- Task.io (Details.loadForReactorTH Reporting.silent root) >>= either (Task.throw . Exit.ReactorBadDetails) pure
            artifacts <- Task.io (Build.fromPaths Reporting.silent root details (NE.toList paths)) >>= either (Task.throw . Exit.ReactorBadBuild) pure
            javascript <- Task.mapError Exit.ReactorBadGenerate $ Generate.prod root details artifacts
            return (LBS.toStrict (B.toLazyByteString javascript))

paths :: NE.List FilePath
paths =
  NE.List
    ("src" </> "NotFound.canopy")
    [ "src" </> "Errors.canopy",
      "src" </> "Index.canopy"
    ]

runTaskUnsafe :: Task.Task Exit.Reactor a -> IO a
runTaskUnsafe task =
  do
    result <- Task.run task
    case result of
      Right a ->
        return a
      Left exit ->
        do
          Exit.toStderr (Exit.reactorToReport exit)
          error
            "\n--------------------------------------------------------\
            \\nError in Develop.StaticFiles.Build.buildReactorFrontEnd\
            \\nCompile with `canopy make` directly to figure it out faster\
            \\n--------------------------------------------------------\
            \\n"
