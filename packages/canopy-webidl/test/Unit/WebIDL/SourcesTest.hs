{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Tests for WebIDL Sources module.
--
-- Validates the API groups, spec metadata, and lookup functions.
--
-- @since 0.20.0
module Unit.WebIDL.SourcesTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit

import qualified Data.Map.Strict as Map
import qualified Data.Text as Text

import WebIDL.Sources
  ( Source(..)
  , SourceType(..)
  , SpecGroup(..)
  , SpecInfo(..)
  , mozillaSource
  , webrefSource
  , apiGroups
  , defaultGroups
  , getGroup
  , allSpecs
  , lookupSpec
  , specsForGroup
  , urlForSpec
  )
import WebIDL.Types
  ( mkSpecName
  , mkGroupName
  , specNameToText
  , groupNameToText
  , packageNameToText
  , moduleNameToText
  , specUrlToText
  , webIdlPathToText
  )


tests :: TestTree
tests = testGroup "WebIDL.Sources"
  [ sourceTests
  , apiGroupTests
  , specLookupTests
  , urlConstructionTests
  ]


sourceTests :: TestTree
sourceTests = testGroup "Source Definitions"
  [ testCase "mozillaSource has correct name" $
      specNameToText (sourceName mozillaSource) @?= "Mozilla Gecko"

  , testCase "mozillaSource has GitHubRepo type" $
      case sourceType mozillaSource of
        GitHubRepo {} -> pure ()
        _ -> assertFailure "Expected GitHubRepo source type"

  , testCase "webrefSource has correct name" $
      specNameToText (sourceName webrefSource) @?= "W3C Webref"

  , testCase "webrefSource has WebRefNpm type" $
      case sourceType webrefSource of
        WebRefNpm -> pure ()
        _ -> assertFailure "Expected WebRefNpm source type"

  , testCase "webrefSource baseUrl contains jsdelivr" $
      assertBool "baseUrl should contain jsdelivr"
        (Text.isInfixOf "jsdelivr" (specUrlToText (sourceBaseUrl webrefSource)))
  ]


apiGroupTests :: TestTree
apiGroupTests = testGroup "API Groups"
  [ testCase "apiGroups contains dom group" $
      assertBool "dom group should exist"
        (Map.member (mkGroupName "dom") apiGroups)

  , testCase "apiGroups contains fetch group" $
      assertBool "fetch group should exist"
        (Map.member (mkGroupName "fetch") apiGroups)

  , testCase "apiGroups contains audio group" $
      assertBool "audio group should exist"
        (Map.member (mkGroupName "audio") apiGroups)

  , testCase "defaultGroups contains dom" $
      assertBool "defaultGroups should contain dom"
        (mkGroupName "dom" `elem` defaultGroups)

  , testCase "defaultGroups contains fetch" $
      assertBool "defaultGroups should contain fetch"
        (mkGroupName "fetch" `elem` defaultGroups)

  , testCase "getGroup returns dom group" $
      case getGroup (mkGroupName "dom") of
        Just group -> do
          groupNameToText (groupName group) @?= "dom"
          packageNameToText (groupPackage group) @?= "canopy/web-dom"
          moduleNameToText (groupModulePrefix group) @?= "Dom"
        Nothing -> assertFailure "Expected dom group to exist"

  , testCase "getGroup returns Nothing for unknown" $
      case getGroup (mkGroupName "unknown-group") of
        Nothing -> pure ()
        Just _ -> assertFailure "Expected Nothing for unknown group"

  , testCase "dom group has multiple specs" $
      case getGroup (mkGroupName "dom") of
        Just group -> assertBool "dom should have multiple specs"
          (length (groupSpecs group) > 1)
        Nothing -> assertFailure "Expected dom group"

  , testCase "fetch group has correct specs" $
      case getGroup (mkGroupName "fetch") of
        Just group -> do
          assertBool "should contain fetch spec"
            (mkSpecName "fetch" `elem` groupSpecs group)
          assertBool "should contain streams spec"
            (mkSpecName "streams" `elem` groupSpecs group)
        Nothing -> assertFailure "Expected fetch group"
  ]


specLookupTests :: TestTree
specLookupTests = testGroup "Spec Lookup"
  [ testCase "allSpecs contains dom spec" $
      assertBool "dom spec should exist"
        (Map.member (mkSpecName "dom") allSpecs)

  , testCase "allSpecs contains fetch spec" $
      assertBool "fetch spec should exist"
        (Map.member (mkSpecName "fetch") allSpecs)

  , testCase "lookupSpec finds dom" $
      case lookupSpec (mkSpecName "dom") of
        Just spec -> do
          specNameToText (specName spec) @?= "dom"
          specTitle spec @?= "DOM Standard"
          specUrlToText (specUrl spec) @?= "https://dom.spec.whatwg.org/"
          webIdlPathToText (specWebIdlPath spec) @?= "dom.webidl"
        Nothing -> assertFailure "Expected dom spec"

  , testCase "lookupSpec finds webaudio" $
      case lookupSpec (mkSpecName "webaudio") of
        Just spec -> do
          specTitle spec @?= "Web Audio API"
          webIdlPathToText (specWebIdlPath spec) @?= "webaudio.webidl"
        Nothing -> assertFailure "Expected webaudio spec"

  , testCase "lookupSpec returns Nothing for unknown" $
      case lookupSpec (mkSpecName "unknown-spec") of
        Nothing -> pure ()
        Just _ -> assertFailure "Expected Nothing for unknown spec"

  , testCase "specsForGroup returns specs" $
      case getGroup (mkGroupName "dom") of
        Just group -> do
          let specs = specsForGroup group
          assertBool "should return at least one spec" (not (null specs))
        Nothing -> assertFailure "Expected dom group"

  , testCase "specsForGroup returns correct number" $
      case getGroup (mkGroupName "audio") of
        Just group -> do
          let specs = specsForGroup group
          length specs @?= 1
        Nothing -> assertFailure "Expected audio group"
  ]


urlConstructionTests :: TestTree
urlConstructionTests = testGroup "URL Construction"
  [ testCase "urlForSpec constructs correct URL" $
      case lookupSpec (mkSpecName "dom") of
        Just spec -> do
          let url = urlForSpec webrefSource spec
          let urlText = specUrlToText url
          assertBool "URL should contain base" $
            Text.isInfixOf "jsdelivr" urlText
          assertBool "URL should contain path" $
            Text.isInfixOf "dom.webidl" urlText
        Nothing -> assertFailure "Expected dom spec"
  ]
