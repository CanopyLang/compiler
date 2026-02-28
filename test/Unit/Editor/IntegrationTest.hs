{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Editor.Integration module.
--
-- Tests LSP configuration, file associations, and editor
-- information consistency.
--
-- @since 0.19.2
module Unit.Editor.IntegrationTest (tests) where

import qualified Data.List as List
import qualified Data.Text as Text
import qualified Editor.Integration as Editor
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Editor.Integration Tests"
    [ testLspConfig,
      testFileAssociations,
      testSupportedEditors
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- LSP configuration
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testLspConfig :: TestTree
testLspConfig =
  testGroup
    "LSP configuration"
    [ testCase "default command is canopy-lsp --stdio" $
        Editor._lspCommand Editor.defaultLspConfig @?= ["canopy-lsp", "--stdio"],
      testCase "default file types include .can" $
        assertBool
          ".can in file types"
          (".can" `elem` Editor._lspFileTypes Editor.defaultLspConfig),
      testCase "default file types include .canopy" $
        assertBool
          ".canopy in file types"
          (".canopy" `elem` Editor._lspFileTypes Editor.defaultLspConfig),
      testCase "root markers include canopy.json" $
        assertBool
          "canopy.json in root markers"
          ("canopy.json" `elem` Editor._lspRootMarkers Editor.defaultLspConfig),
      testCase "root markers include elm.json" $
        assertBool
          "elm.json in root markers"
          ("elm.json" `elem` Editor._lspRootMarkers Editor.defaultLspConfig),
      testCase "language id is canopy" $
        Editor._lspLanguageId Editor.defaultLspConfig @?= "canopy"
    ]

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- File associations
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testFileAssociations :: TestTree
testFileAssociations =
  testGroup
    "File associations"
    [ testCase "canopy file extensions list has two entries" $
        length Editor.canopyFileExtensions @?= 2,
      testCase "first extension is .can" $
        listToMaybe Editor.canopyFileExtensions @?= Just ".can",
      testCase "canopy language id is lowercase" $
        Editor.canopyLanguageId @?= "canopy"
    ]
  where
    listToMaybe [] = Nothing
    listToMaybe (x : _) = Just x

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Supported editors
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

testSupportedEditors :: TestTree
testSupportedEditors =
  testGroup
    "Supported editors"
    [ testCase "at least 4 editors supported" $
        assertBool
          "at least 4 editors"
          (length Editor.supportedEditors >= 4),
      testCase "VS Code is in supported editors" $
        assertBool
          "VS Code listed"
          (any isVSCode Editor.supportedEditors),
      testCase "Neovim is in supported editors" $
        assertBool
          "Neovim listed"
          (any isNeovim Editor.supportedEditors),
      testCase "all editors have non-empty names" $
        assertBool
          "all names non-empty"
          (all (not . Text.null . Editor._editorName) Editor.supportedEditors),
      testCase "all editors have install hints" $
        assertBool
          "all hints non-empty"
          (all (not . Text.null . Editor._editorInstallHint) Editor.supportedEditors),
      testCase "VS Code mechanism is Extension" $
        assertEditorMechanism "VS Code" "Extension",
      testCase "Neovim mechanism is nvim-lspconfig" $
        assertEditorMechanism "Neovim" "nvim-lspconfig"
    ]

-- | Check if an editor info is for VS Code.
isVSCode :: Editor.EditorInfo -> Bool
isVSCode info = Editor._editorName info == "VS Code"

-- | Check if an editor info is for Neovim.
isNeovim :: Editor.EditorInfo -> Bool
isNeovim info = Editor._editorName info == "Neovim"

-- | Assert that a named editor has the expected mechanism.
assertEditorMechanism :: Text.Text -> Text.Text -> Assertion
assertEditorMechanism editorName expectedMechanism =
  maybe
    (assertFailure ("Editor not found: " ++ Text.unpack editorName))
    (\info -> Editor._editorMechanism info @?= expectedMechanism)
    (List.find (\i -> Editor._editorName i == editorName) Editor.supportedEditors)
