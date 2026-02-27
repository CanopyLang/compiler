{-# LANGUAGE OverloadedStrings #-}

-- | Tests for WebIDL type-safe identifiers.
--
-- Validates that all newtype wrappers provide proper type safety
-- and prevent mixing different identifier types.
--
-- @since 0.20.0
module Unit.WebIDL.TypesTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit

import WebIDL.Types
  ( mkSpecName
  , specNameToText
  , mkInterfaceName
  , interfaceNameToText
  , mkGroupName
  , groupNameToText
  , mkPackageName
  , packageNameToText
  , mkModuleName
  , moduleNameToText
  , mkSpecUrl
  , specUrlToText
  , mkWebIdlPath
  , webIdlPathToText
  , validateName
  , emptySpecSet
  , singletonSpec
  , insertSpec
  , memberSpec
  , specSetToList
  , emptyInterfaceSet
  , singletonInterface
  , insertInterface
  , memberInterface
  , interfaceSetToList
  )


tests :: TestTree
tests = testGroup "WebIDL.Types"
  [ specNameTests
  , interfaceNameTests
  , groupNameTests
  , packageNameTests
  , moduleNameTests
  , specUrlTests
  , webIdlPathTests
  , validatedNameTests
  , specSetTests
  , interfaceSetTests
  ]


specNameTests :: TestTree
specNameTests = testGroup "SpecName"
  [ testCase "mkSpecName creates from Text" $
      specNameToText (mkSpecName "dom") @?= "dom"

  , testCase "specNameToText roundtrip" $
      let original = "webaudio" :: Text
          name = mkSpecName original
      in specNameToText name @?= original

  , testCase "SpecName equality works" $
      mkSpecName "fetch" @?= mkSpecName "fetch"

  , testCase "different SpecNames are not equal" $
      assertBool "dom /= fetch" (mkSpecName "dom" /= mkSpecName "fetch")

  , testCase "IsString instance works" $
      specNameToText ("webgl" :: SpecName) @?= "webgl"
  ]


interfaceNameTests :: TestTree
interfaceNameTests = testGroup "InterfaceName"
  [ testCase "mkInterfaceName creates from Text" $
      interfaceNameToText (mkInterfaceName "Element") @?= "Element"

  , testCase "interfaceNameToText roundtrip" $
      let original = "Document" :: Text
          name = mkInterfaceName original
      in interfaceNameToText name @?= original

  , testCase "InterfaceName equality works" $
      mkInterfaceName "Node" @?= mkInterfaceName "Node"

  , testCase "different InterfaceNames are not equal" $
      assertBool "Element /= Document"
        (mkInterfaceName "Element" /= mkInterfaceName "Document")

  , testCase "IsString instance works" $
      interfaceNameToText ("AudioContext" :: InterfaceName) @?= "AudioContext"
  ]


groupNameTests :: TestTree
groupNameTests = testGroup "GroupName"
  [ testCase "mkGroupName creates from Text" $
      groupNameToText (mkGroupName "dom") @?= "dom"

  , testCase "groupNameToText roundtrip" $
      let original = "audio" :: Text
          name = mkGroupName original
      in groupNameToText name @?= original

  , testCase "GroupName equality works" $
      mkGroupName "fetch" @?= mkGroupName "fetch"

  , testCase "IsString instance works" $
      groupNameToText ("webgl" :: GroupName) @?= "webgl"
  ]


packageNameTests :: TestTree
packageNameTests = testGroup "PackageName"
  [ testCase "mkPackageName creates from Text" $
      packageNameToText (mkPackageName "canopy/web-dom") @?= "canopy/web-dom"

  , testCase "packageNameToText roundtrip" $
      let original = "canopy/web-audio" :: Text
          name = mkPackageName original
      in packageNameToText name @?= original

  , testCase "PackageName with slashes" $
      packageNameToText (mkPackageName "author/package") @?= "author/package"

  , testCase "IsString instance works" $
      packageNameToText ("canopy/core" :: PackageName) @?= "canopy/core"
  ]


moduleNameTests :: TestTree
moduleNameTests = testGroup "ModuleName"
  [ testCase "mkModuleName creates from Text" $
      moduleNameToText (mkModuleName "Dom.Element") @?= "Dom.Element"

  , testCase "moduleNameToText roundtrip" $
      let original = "Audio.Context" :: Text
          name = mkModuleName original
      in moduleNameToText name @?= original

  , testCase "ModuleName with dots" $
      moduleNameToText (mkModuleName "Web.Audio.Context") @?= "Web.Audio.Context"

  , testCase "IsString instance works" $
      moduleNameToText ("Platform.Cmd" :: ModuleName) @?= "Platform.Cmd"
  ]


specUrlTests :: TestTree
specUrlTests = testGroup "SpecUrl"
  [ testCase "mkSpecUrl creates from Text" $
      specUrlToText (mkSpecUrl "https://example.com/spec.webidl")
        @?= "https://example.com/spec.webidl"

  , testCase "specUrlToText roundtrip" $
      let original = "https://w3c.github.io/dom.idl" :: Text
          url = mkSpecUrl original
      in specUrlToText url @?= original

  , testCase "SpecUrl equality works" $
      mkSpecUrl "https://a.com" @?= mkSpecUrl "https://a.com"

  , testCase "IsString instance works" $
      specUrlToText ("https://test.com" :: SpecUrl) @?= "https://test.com"
  ]


webIdlPathTests :: TestTree
webIdlPathTests = testGroup "WebIdlPath"
  [ testCase "mkWebIdlPath creates from Text" $
      webIdlPathToText (mkWebIdlPath "/path/to/file.webidl")
        @?= "/path/to/file.webidl"

  , testCase "webIdlPathToText roundtrip" $
      let original = "bundled/dom.webidl" :: Text
          path = mkWebIdlPath original
      in webIdlPathToText path @?= original

  , testCase "WebIdlPath equality works" $
      mkWebIdlPath "a.webidl" @?= mkWebIdlPath "a.webidl"

  , testCase "IsString instance works" $
      webIdlPathToText ("test.webidl" :: WebIdlPath) @?= "test.webidl"
  ]


validatedNameTests :: TestTree
validatedNameTests = testGroup "ValidatedName"
  [ testCase "validateName accepts valid identifier" $
      case validateName "Element" of
        Just _ -> pure ()
        Nothing -> assertFailure "Expected valid name"

  , testCase "validateName accepts underscore prefix" $
      case validateName "_private" of
        Just _ -> pure ()
        Nothing -> assertFailure "Expected valid name with underscore"

  , testCase "validateName rejects empty string" $
      case validateName "" of
        Nothing -> pure ()
        Just _ -> assertFailure "Expected rejection of empty string"

  , testCase "validateName rejects lowercase start" $
      case validateName "element" of
        Nothing -> pure ()
        Just _ -> assertFailure "Expected rejection of lowercase start"

  , testCase "validateName rejects number start" $
      case validateName "1Element" of
        Nothing -> pure ()
        Just _ -> assertFailure "Expected rejection of number start"

  , testCase "validateName accepts alphanumeric" $
      case validateName "Element123" of
        Just _ -> pure ()
        Nothing -> assertFailure "Expected valid alphanumeric name"

  , testCase "validateName accepts underscores" $
      case validateName "My_Element_Name" of
        Just _ -> pure ()
        Nothing -> assertFailure "Expected valid name with underscores"
  ]


specSetTests :: TestTree
specSetTests = testGroup "SpecSet"
  [ testCase "emptySpecSet is empty" $
      specSetToList emptySpecSet @?= []

  , testCase "singletonSpec creates singleton set" $
      specSetToList (singletonSpec (mkSpecName "dom")) @?= [mkSpecName "dom"]

  , testCase "insertSpec adds to set" $
      let set = insertSpec (mkSpecName "fetch") (singletonSpec (mkSpecName "dom"))
      in length (specSetToList set) @?= 2

  , testCase "memberSpec finds element" $
      let set = singletonSpec (mkSpecName "dom")
      in assertBool "dom should be member" (memberSpec (mkSpecName "dom") set)

  , testCase "memberSpec returns False for non-member" $
      let set = singletonSpec (mkSpecName "dom")
      in assertBool "fetch should not be member"
           (not (memberSpec (mkSpecName "fetch") set))

  , testCase "insertSpec is idempotent for same element" $
      let set = insertSpec (mkSpecName "dom") (singletonSpec (mkSpecName "dom"))
      in length (specSetToList set) @?= 1
  ]


interfaceSetTests :: TestTree
interfaceSetTests = testGroup "InterfaceSet"
  [ testCase "emptyInterfaceSet is empty" $
      interfaceSetToList emptyInterfaceSet @?= []

  , testCase "singletonInterface creates singleton set" $
      interfaceSetToList (singletonInterface (mkInterfaceName "Element"))
        @?= [mkInterfaceName "Element"]

  , testCase "insertInterface adds to set" $
      let set = insertInterface (mkInterfaceName "Document")
                  (singletonInterface (mkInterfaceName "Element"))
      in length (interfaceSetToList set) @?= 2

  , testCase "memberInterface finds element" $
      let set = singletonInterface (mkInterfaceName "Element")
      in assertBool "Element should be member"
           (memberInterface (mkInterfaceName "Element") set)

  , testCase "memberInterface returns False for non-member" $
      let set = singletonInterface (mkInterfaceName "Element")
      in assertBool "Document should not be member"
           (not (memberInterface (mkInterfaceName "Document") set))

  , testCase "InterfaceSet Semigroup combines sets" $
      let set1 = singletonInterface (mkInterfaceName "Element")
          set2 = singletonInterface (mkInterfaceName "Document")
          combined = set1 <> set2
      in length (interfaceSetToList combined) @?= 2
  ]
