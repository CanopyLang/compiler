{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for FFI.Capability constraint types.
--
-- Verifies constructors, equality, show output, and nesting of
-- 'CapabilityConstraint', 'CapabilityError', and 'Capability' types
-- used during FFI JSDoc parsing.
--
-- @since 0.20.1
module Unit.FFI.CapabilityTest
  ( tests
  ) where

import FFI.Capability
  ( Capability (..)
  , CapabilityConstraint (..)
  , CapabilityError (..)
  )
import FFI.Types (PermissionName (..), ResourceName (..))
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit


tests :: TestTree
tests =
  Test.testGroup "FFI.Capability"
    [ constraintUserActivationShowTest
    , constraintPermissionShowTest
    , constraintInitializationShowTest
    , constraintAvailabilityShowTest
    , constraintMultipleShowTest
    , constraintEqualityTest
    , constraintInequalityTest
    , errorUserActivationShowTest
    , errorPermissionShowTest
    , errorInitializationShowTest
    , errorFeatureNotAvailableShowTest
    , errorEqualityTest
    , errorInequalityTest
    , capabilityUserActivationShowTest
    , capabilityPermissionShowTest
    , capabilityInitializationShowTest
    , capabilityAvailabilityShowTest
    , capabilityEqualityTest
    , capabilityInequalityTest
    , multipleConstraintsNestingTest
    ]

constraintUserActivationShowTest :: TestTree
constraintUserActivationShowTest =
  HUnit.testCase "show UserActivationRequired" $
    show UserActivationRequired @?= "UserActivationRequired"

constraintPermissionShowTest :: TestTree
constraintPermissionShowTest =
  HUnit.testCase "show PermissionRequired" $
    show (PermissionRequired (PermissionName "microphone"))
      @?= "PermissionRequired (PermissionName {unPermissionName = \"microphone\"})"

constraintInitializationShowTest :: TestTree
constraintInitializationShowTest =
  HUnit.testCase "show InitializationRequired" $
    show (InitializationRequired (ResourceName "AudioContext"))
      @?= "InitializationRequired (ResourceName {unResourceName = \"AudioContext\"})"

constraintAvailabilityShowTest :: TestTree
constraintAvailabilityShowTest =
  HUnit.testCase "show AvailabilityRequired" $
    show (AvailabilityRequired "WebGL")
      @?= "AvailabilityRequired \"WebGL\""

constraintMultipleShowTest :: TestTree
constraintMultipleShowTest =
  HUnit.testCase "show MultipleConstraints" $
    show (MultipleConstraints [UserActivationRequired])
      @?= "MultipleConstraints [UserActivationRequired]"

constraintEqualityTest :: TestTree
constraintEqualityTest =
  HUnit.testCase "same constraints are equal" $
    (UserActivationRequired == UserActivationRequired) @?= True

constraintInequalityTest :: TestTree
constraintInequalityTest =
  HUnit.testCase "different constraints are not equal" $
    (UserActivationRequired == AvailabilityRequired "WebGL") @?= False

errorUserActivationShowTest :: TestTree
errorUserActivationShowTest =
  HUnit.testCase "show UserActivationRequiredError" $
    show (UserActivationRequiredError "click required")
      @?= "UserActivationRequiredError \"click required\""

errorPermissionShowTest :: TestTree
errorPermissionShowTest =
  HUnit.testCase "show PermissionRequiredError" $
    show (PermissionRequiredError (PermissionName "geolocation"))
      @?= "PermissionRequiredError (PermissionName {unPermissionName = \"geolocation\"})"

errorInitializationShowTest :: TestTree
errorInitializationShowTest =
  HUnit.testCase "show InitializationRequiredError" $
    show (InitializationRequiredError (ResourceName "WebGLRenderingContext"))
      @?= "InitializationRequiredError (ResourceName {unResourceName = \"WebGLRenderingContext\"})"

errorFeatureNotAvailableShowTest :: TestTree
errorFeatureNotAvailableShowTest =
  HUnit.testCase "show FeatureNotAvailableError" $
    show (FeatureNotAvailableError "SharedArrayBuffer")
      @?= "FeatureNotAvailableError \"SharedArrayBuffer\""

errorEqualityTest :: TestTree
errorEqualityTest =
  HUnit.testCase "same errors are equal" $
    (FeatureNotAvailableError "X" == FeatureNotAvailableError "X") @?= True

errorInequalityTest :: TestTree
errorInequalityTest =
  HUnit.testCase "different errors are not equal" $
    (FeatureNotAvailableError "X" == FeatureNotAvailableError "Y") @?= False

capabilityUserActivationShowTest :: TestTree
capabilityUserActivationShowTest =
  HUnit.testCase "show UserActivationCapability" $
    show UserActivationCapability @?= "UserActivationCapability"

capabilityPermissionShowTest :: TestTree
capabilityPermissionShowTest =
  HUnit.testCase "show PermissionCapability" $
    show (PermissionCapability (PermissionName "camera"))
      @?= "PermissionCapability (PermissionName {unPermissionName = \"camera\"})"

capabilityInitializationShowTest :: TestTree
capabilityInitializationShowTest =
  HUnit.testCase "show InitializationCapability" $
    show (InitializationCapability (ResourceName "AudioContext"))
      @?= "InitializationCapability (ResourceName {unResourceName = \"AudioContext\"})"

capabilityAvailabilityShowTest :: TestTree
capabilityAvailabilityShowTest =
  HUnit.testCase "show AvailabilityCapability" $
    show (AvailabilityCapability "WebRTC")
      @?= "AvailabilityCapability \"WebRTC\""

capabilityEqualityTest :: TestTree
capabilityEqualityTest =
  HUnit.testCase "same capabilities are equal" $
    (UserActivationCapability == UserActivationCapability) @?= True

capabilityInequalityTest :: TestTree
capabilityInequalityTest =
  HUnit.testCase "different capabilities are not equal" $
    (UserActivationCapability == AvailabilityCapability "X") @?= False

multipleConstraintsNestingTest :: TestTree
multipleConstraintsNestingTest =
  HUnit.testCase "MultipleConstraints contains nested constraints" $
    nested @?= MultipleConstraints
      [ UserActivationRequired
      , PermissionRequired (PermissionName "microphone")
      ]
  where
    nested = MultipleConstraints
      [ UserActivationRequired
      , PermissionRequired (PermissionName "microphone")
      ]
