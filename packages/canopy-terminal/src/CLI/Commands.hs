{-# LANGUAGE OverloadedStrings #-}

-- | CLI command definitions and configurations.
--
-- This module re-exports all command constructors from their
-- respective sub-modules.  Each command is self-contained with
-- metadata, argument parsers, flag configurations, and help text.
--
-- == Sub-modules
--
-- * "CLI.Commands.Project" - init, new, setup
-- * "CLI.Commands.Build" - make, check, reactor
-- * "CLI.Commands.Dev" - repl, fmt, lint, test, docs, audit, upgrade, migrate, bench
-- * "CLI.Commands.Package" - install, publish, bump, diff
-- * "CLI.Commands.Tools" - test-ffi, webidl, self-update
--
-- @since 0.19.1
module CLI.Commands
  ( -- * Project Commands
    createInitCommand,
    createNewCommand,
    createSetupCommand,

    -- * Build Commands
    createMakeCommand,
    createCheckCommand,
    createReactorCommand,

    -- * Developer Tools
    createReplCommand,
    createFmtCommand,
    createLintCommand,
    createTestCommand,
    createDocsCommand,
    createAuditCommand,
    createUpgradeCommand,
    createMigrateCommand,
    createBenchCommand,

    -- * Package Commands
    createInstallCommand,
    createPublishCommand,
    createBumpCommand,
    createDiffCommand,

    -- * Tool Commands
    createFFITestCommand,
    createWebIDLCommand,
    createSelfUpdateCommand,
  )
where

import CLI.Commands.Build
  ( createCheckCommand,
    createMakeCommand,
    createReactorCommand,
  )
import CLI.Commands.Dev
  ( createAuditCommand,
    createBenchCommand,
    createDocsCommand,
    createFmtCommand,
    createLintCommand,
    createMigrateCommand,
    createReplCommand,
    createTestCommand,
    createUpgradeCommand,
  )
import CLI.Commands.Package
  ( createBumpCommand,
    createDiffCommand,
    createInstallCommand,
    createPublishCommand,
  )
import CLI.Commands.Project
  ( createInitCommand,
    createNewCommand,
    createSetupCommand,
  )
import CLI.Commands.Tools
  ( createFFITestCommand,
    createSelfUpdateCommand,
    createWebIDLCommand,
  )
