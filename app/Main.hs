{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Main entry point for the Canopy CLI application.
--
-- This module provides the main entry point for the Canopy command-line
-- interface. It orchestrates the CLI application by configuring commands,
-- setting up help text, and delegating to the Terminal framework for
-- argument parsing and command dispatch.
--
-- == Architecture
--
-- The CLI follows a modular architecture:
--
-- * 'CLI.Commands' - Command definitions and configurations
-- * 'CLI.Documentation' - Help text and formatting utilities
-- * 'CLI.Parsers' - Reusable argument and flag parsers
-- * 'CLI.Types' - Core type definitions and re-exports
--
-- == Available Commands
--
-- The CLI provides these commands:
--
-- * @init@ - Initialize new Canopy projects
-- * @new@ - Create a new project in a fresh directory
-- * @repl@ - Interactive programming session
-- * @reactor@ - Development server with hot reload
-- * @make@ - Compile Canopy code to JavaScript or HTML
-- * @docs@ - Generate project documentation
-- * @test-ffi@ - Test and validate FFI functions
-- * @install@ - Install packages from repositories
-- * @publish@ - Publish packages to repositories
-- * @bump@ - Automatic version number management
-- * @diff@ - API change detection and analysis
--
-- == Usage Examples
--
-- @
-- canopy init                    -- Start a new project
-- canopy repl                    -- Open interactive session
-- canopy make src\/Main.can      -- Compile a single file
-- canopy install author\/package -- Install a package
-- @
--
-- @since 0.19.1
module Main
  ( -- * Application Entry Point
    main,
  ) where

import CLI.Commands
  ( createAuditCommand,
    createBenchCommand,
    createBumpCommand,
    createCheckCommand,
    createDiffCommand,
    createDocsCommand,
    createFFITestCommand,
    createFmtCommand,
    createInitCommand,
    createInstallCommand,
    createKitBuildCommand,
    createKitDevCommand,
    createKitNewCommand,
    createLinkCommand,
    createLintCommand,
    createMakeCommand,
    createMigrateCommand,
    createNewCommand,
    createPublishCommand,
    createReactorCommand,
    createReplCommand,
    createSelfUpdateCommand,
    createSetupCommand,
    createTestCommand,
    createUnlinkCommand,
    createUpgradeCommand,
    createVendorCommand,
    createWebIDLCommand,
  )
import CLI.Documentation (createIntroduction, createOutro)
import qualified Terminal

-- | Main application entry point.
--
-- Initializes and runs the Canopy CLI application with all available
-- commands. Sets up the Terminal framework with introduction text,
-- outro message, and the complete command list.
--
-- The application uses the Terminal framework to handle:
--
-- * Command-line argument parsing
-- * Help text generation and display
-- * Error handling and user feedback
-- * Command dispatch and execution
--
-- @since 0.19.1
main :: IO ()
main =
  Terminal.app
    createIntroduction
    createOutro
    createAllCommands

-- | Create the complete list of available CLI commands.
--
-- Assembles all commands in a logical order, grouping related
-- functionality together. The order affects help display and
-- command discovery.
--
-- Command organization:
--
-- * Interactive commands (repl, init, reactor)
-- * Build commands (make, check)
-- * Developer tools (fmt, lint, test, docs, audit, upgrade, bench)
-- * FFI testing (test-ffi)
-- * Package management (install, bump, diff, publish)
-- * Code generation (webidl)
--
-- @since 0.19.1
createAllCommands :: [Terminal.Command]
createAllCommands =
  [ createReplCommand,
    createInitCommand,
    createNewCommand,
    createSetupCommand,
    createReactorCommand,
    createMakeCommand,
    createCheckCommand,
    createFmtCommand,
    createLintCommand,
    createTestCommand,
    createDocsCommand,
    createAuditCommand,
    createUpgradeCommand,
    createBenchCommand,
    createMigrateCommand,
    createFFITestCommand,
    createInstallCommand,
    createBumpCommand,
    createDiffCommand,
    createPublishCommand,
    createLinkCommand,
    createUnlinkCommand,
    createVendorCommand,
    createWebIDLCommand,
    createSelfUpdateCommand,
    createKitNewCommand,
    createKitDevCommand,
    createKitBuildCommand
  ]