{-# LANGUAGE OverloadedStrings #-}

-- | Structured error types and reporting for Terminal operations.
--
-- Every error displayed to the user flows through this module. Each error
-- follows a consistent three-part structure:
--
-- 1. A colored title bar (@Doc.dullred "-- ERROR TITLE"@)
-- 2. A reflowed explanation of what went wrong
-- 3. A concrete fix suggestion highlighted in green
--
-- This ensures all CLI error messages are visually consistent with the
-- compiler's own error output (inherited from Elm).
--
-- Implementation is split across sub-modules under @Reporting.Exit.*@.
-- This module re-exports everything for backward compatibility.
--
-- @since 0.19.1
module Reporting.Exit
  ( -- * Report Type
    Report,
    toStderr,
    toStdout,

    -- * Make Errors
    Make
      ( MakeNoOutline,
        MakeBadDetails,
        MakeBuildError,
        MakeBadGenerate,
        MakeAppNeedsFileNames,
        MakePkgNeedsExposing,
        MakeNoMain,
        MakeMultipleFilesIntoHtml,
        MakeCannotBuild,
        MakeCannotOptimizeAndDebug,
        MakeReproducibilityFailure
      ),
    makeToReport,

    -- * Check Errors
    Check
      ( CheckNoOutline,
        CheckBadDetails,
        CheckCannotBuild,
        CheckAppNeedsFileNames,
        CheckPkgNeedsExposing
      ),
    checkToReport,

    -- * REPL Errors
    Repl
      ( ReplBadDetails,
        ReplBadGenerate,
        ReplCannotBuild
      ),
    replToReport,

    -- * Install Errors
    Install (..),
    installToReport,

    -- * Publish Errors
    Publish (..),
    publishToReport,
    newPackageOverview,

    -- * Diff Errors
    Diff (..),
    diffToReport,

    -- * Bump Errors
    Bump (..),
    bumpToReport,

    -- * Init Errors
    Init (..),
    initToReport,

    -- * New (project scaffolding) Errors
    New (..),
    newToReport,

    -- * Docs Errors
    Docs
      ( DocsNoOutline,
        DocsBadDetails,
        DocsCannotBuild,
        DocsAppNeedsFileNames,
        DocsPkgNeedsExposing,
        DocsCannotWrite
      ),
    docsToReport,

    -- * Setup Errors
    Setup (..),
    setupToReport,

    -- * Other Error Types
    RegistryProblem (..),
    Solver (..),
    Reactor (..),
    reactorToReport,
  )
where

import Reporting.Exit.Bump (Bump (..), bumpToReport)
import Reporting.Exit.Check (Check (..), checkToReport)
import Reporting.Exit.Diff (Diff (..), diffToReport)
import Reporting.Exit.Docs (Docs (..), docsToReport)
import Reporting.Exit.Help (Report, toStderr, toStdout)
import Reporting.Exit.Init (Init (..), initToReport)
import Reporting.Exit.Install (Install (..), installToReport)
import Reporting.Exit.Make (Make (..), makeToReport)
import Reporting.Exit.New (New (..), newToReport)
import Reporting.Exit.Publish (Publish (..), newPackageOverview, publishToReport)
import Reporting.Exit.Repl (Repl (..), replToReport)
import Reporting.Exit.Setup
  ( Reactor (..),
    RegistryProblem (..),
    Setup (..),
    Solver (..),
    reactorToReport,
    setupToReport,
  )
