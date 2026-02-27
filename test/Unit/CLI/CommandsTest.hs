{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for CLI.Commands module.
--
-- Tests command creation functions, verifying correct command structure,
-- metadata, and configuration for all CLI commands.
module Unit.CLI.CommandsTest (tests) where

import CLI.Commands
  ( createBumpCommand,
    createDiffCommand,
    createInitCommand,
    createInstallCommand,
    createMakeCommand,
    createPublishCommand,
    createReactorCommand,
    createReplCommand,
  )
import qualified Terminal
import Terminal.Internal (toName)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

-- | All unit tests for CLI command creation functionality.
tests :: TestTree
tests =
  testGroup
    "CLI Commands Tests"
    [ testInitCommand,
      testReplCommand,
      testReactorCommand,
      testMakeCommand,
      testInstallCommand,
      testPublishCommand,
      testBumpCommand,
      testDiffCommand
    ]

-- | Test init command creation.
testInitCommand :: TestTree
testInitCommand =
  testGroup
    "createInitCommand function"
    [ testCase "command has correct name" $ do
        let cmd = createInitCommand
        toName cmd @?= "init",
      testCase "command has summary" $ do
        let cmd = createInitCommand
            Terminal.Command _ summary _ _ _ _ _ = cmd
        case summary of
          Terminal.Common s -> length s > 0 @?= True
          _ -> False @?= True
    ]

-- | Test REPL command creation.
testReplCommand :: TestTree
testReplCommand =
  testGroup
    "createReplCommand function"
    [ testCase "command has correct name" $ do
        let cmd = createReplCommand
        toName cmd @?= "repl",
      testCase "command has summary" $ do
        let cmd = createReplCommand
            Terminal.Command _ summary _ _ _ _ _ = cmd
        case summary of
          Terminal.Common s -> length s > 0 @?= True
          _ -> False @?= True
    ]

-- | Test reactor command creation.
testReactorCommand :: TestTree
testReactorCommand =
  testGroup
    "createReactorCommand function"
    [ testCase "command has correct name" $ do
        let cmd = createReactorCommand
        toName cmd @?= "reactor",
      testCase "command has summary" $ do
        let cmd = createReactorCommand
            Terminal.Command _ summary _ _ _ _ _ = cmd
        case summary of
          Terminal.Common s -> length s > 0 @?= True
          _ -> False @?= True
    ]

-- | Test make command creation.
testMakeCommand :: TestTree
testMakeCommand =
  testGroup
    "createMakeCommand function"
    [ testCase "command has correct name" $ do
        let cmd = createMakeCommand
        toName cmd @?= "make",
      testCase "command is marked as uncommon" $ do
        let cmd = createMakeCommand
            Terminal.Command _ summary _ _ _ _ _ = cmd
        case summary of
          Terminal.Uncommon -> True @?= True
          _ -> False @?= True
    ]

-- | Test install command creation.
testInstallCommand :: TestTree
testInstallCommand =
  testGroup
    "createInstallCommand function"
    [ testCase "command has correct name" $ do
        let cmd = createInstallCommand
        toName cmd @?= "install",
      testCase "command is marked as uncommon" $ do
        let cmd = createInstallCommand
            Terminal.Command _ summary _ _ _ _ _ = cmd
        case summary of
          Terminal.Uncommon -> True @?= True
          _ -> False @?= True
    ]

-- | Test publish command creation.
testPublishCommand :: TestTree
testPublishCommand =
  testGroup
    "createPublishCommand function"
    [ testCase "command has correct name" $ do
        let cmd = createPublishCommand
        toName cmd @?= "publish",
      testCase "command is marked as uncommon" $ do
        let cmd = createPublishCommand
            Terminal.Command _ summary _ _ _ _ _ = cmd
        case summary of
          Terminal.Uncommon -> True @?= True
          _ -> False @?= True
    ]

-- | Test bump command creation.
testBumpCommand :: TestTree
testBumpCommand =
  testGroup
    "createBumpCommand function"
    [ testCase "command has correct name" $ do
        let cmd = createBumpCommand
        toName cmd @?= "bump",
      testCase "command is marked as uncommon" $ do
        let cmd = createBumpCommand
            Terminal.Command _ summary _ _ _ _ _ = cmd
        case summary of
          Terminal.Uncommon -> True @?= True
          _ -> False @?= True
    ]

-- | Test diff command creation.
testDiffCommand :: TestTree
testDiffCommand =
  testGroup
    "createDiffCommand function"
    [ testCase "command has correct name" $ do
        let cmd = createDiffCommand
        toName cmd @?= "diff",
      testCase "command is marked as uncommon" $ do
        let cmd = createDiffCommand
            Terminal.Command _ summary _ _ _ _ _ = cmd
        case summary of
          Terminal.Uncommon -> True @?= True
          _ -> False @?= True
    ]
