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
-- * "CLI.Commands.Dev" - repl, fmt, lint, test, docs, audit, upgrade, bench, coverage
-- * "CLI.Commands.Package" - install, publish, bump, diff
-- * "CLI.Commands.Tools" - test-ffi, webidl, self-update
-- * "CLI.Commands.Link" - link, unlink
-- * "CLI.Commands.Kit" - kit-new, kit-dev, kit-build
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
    createBenchCommand,
    createCoverageCommand,

    -- * Package Commands
    createInstallCommand,
    createPublishCommand,
    createBumpCommand,
    createDiffCommand,
    createVendorCommand,

    -- * Link Commands
    createLinkCommand,
    createUnlinkCommand,

    -- * Tool Commands
    createFFITestCommand,
    createWebIDLCommand,
    createSelfUpdateCommand,

    -- * Migration Commands
    createMigrateCommand,

    -- * Conversion Commands
    createConvertCommand,

    -- * Kit Commands
    createKitNewCommand,
    createKitDevCommand,
    createKitBuildCommand,
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
    createCoverageCommand,
    createDocsCommand,
    createFmtCommand,
    createLintCommand,
    createReplCommand,
    createTestCommand,
    createUpgradeCommand,
  )
import CLI.Commands.Package
  ( createBumpCommand,
    createDiffCommand,
    createInstallCommand,
    createPublishCommand,
    createVendorCommand,
  )
import CLI.Commands.Project
  ( createInitCommand,
    createNewCommand,
    createSetupCommand,
  )
import CLI.Commands.Link
  ( createLinkCommand,
    createUnlinkCommand,
  )
import CLI.Commands.Convert
  ( createConvertCommand,
  )
import CLI.Commands.Kit
  ( createKitBuildCommand,
    createKitDevCommand,
    createKitNewCommand,
  )
import CLI.Commands.Migrate
  ( createMigrateCommand,
  )
import CLI.Commands.Tools
  ( createFFITestCommand,
    createSelfUpdateCommand,
    createWebIDLCommand,
  )
