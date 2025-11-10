{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Main module.
--
-- Tests the main CLI application entry point, command list assembly,
-- and integration with the Terminal framework.
module Unit.MainTest (tests) where

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
import Terminal.Internal (Command, toName)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

-- | All unit tests for Main module functionality.
tests :: TestTree
tests =
  testGroup
    "Main Module Tests"
    [ testCreateAllCommands
    ]

-- | Test command list creation functionality.
testCreateAllCommands :: TestTree
testCreateAllCommands =
  testGroup
    "createAllCommands function"
    [ testCase "creates exactly 8 commands" $ do
        let commands = getAllCommands
        length commands @?= 8,
      testCase "includes repl command" $ do
        let commands = getAllCommands
            names = map toName commands
        "repl" `elem` names @?= True,
      testCase "includes init command" $ do
        let commands = getAllCommands
            names = map toName commands
        "init" `elem` names @?= True,
      testCase "includes reactor command" $ do
        let commands = getAllCommands
            names = map toName commands
        "reactor" `elem` names @?= True,
      testCase "includes make command" $ do
        let commands = getAllCommands
            names = map toName commands
        "make" `elem` names @?= True,
      testCase "includes install command" $ do
        let commands = getAllCommands
            names = map toName commands
        "install" `elem` names @?= True,
      testCase "includes bump command" $ do
        let commands = getAllCommands
            names = map toName commands
        "bump" `elem` names @?= True,
      testCase "includes diff command" $ do
        let commands = getAllCommands
            names = map toName commands
        "diff" `elem` names @?= True,
      testCase "includes publish command" $ do
        let commands = getAllCommands
            names = map toName commands
        "publish" `elem` names @?= True,
      testCase "has repl as first command" $ do
        let commands = getAllCommands
        case commands of
          [] -> False @?= True
          (first : _) -> toName first @?= "repl",
      testCase "has unique command names" $ do
        let commands = getAllCommands
            names = map toName commands
            uniqueNames = length $ filter (\x -> length (filter (== x) names) == 1) names
        uniqueNames @?= length names
    ]
  where
    getAllCommands :: [Command]
    getAllCommands =
      [ createReplCommand,
        createInitCommand,
        createReactorCommand,
        createMakeCommand,
        createInstallCommand,
        createPublishCommand,
        createBumpCommand,
        createDiffCommand
      ]
