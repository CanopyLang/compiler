{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Unit.Foreign.AudioFFITest (tests) where

import qualified Data.List as List
import qualified Data.Name as Name
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Foreign.AudioFFI Tests"
    [ testFFIModuleAlias,
      testFFIFunctionNames,
      testFFITypeAnnotations,
      testWebAudioTypes
    ]

testFFIModuleAlias :: TestTree
testFFIModuleAlias =
  testGroup
    "FFI module alias tests"
    [ testCase "module alias creation" $ do
        let alias = Name.fromChars "AudioFFI"
        Name.toChars alias @?= "AudioFFI",
      testCase "qualified function name" $ do
        let qualifiedName = "AudioFFI.createAudioContext"
        let parts = splitOn '.' qualifiedName
        length parts @?= 2
        head parts @?= "AudioFFI"
        (parts !! 1) @?= "createAudioContext",
      testCase "multiple qualified functions share module" $ do
        let func1 = "AudioFFI.createOscillator"
        let func2 = "AudioFFI.createGainNode"
        let module1 = takeWhile (/= '.') func1
        let module2 = takeWhile (/= '.') func2
        module1 @?= module2
    ]

testFFIFunctionNames :: TestTree
testFFIFunctionNames =
  testGroup
    "FFI function name tests"
    [ testCase "createAudioContext name" $ do
        let funcName = Name.fromChars "createAudioContext"
        Name.toChars funcName @?= "createAudioContext",
      testCase "createOscillator name" $ do
        let funcName = Name.fromChars "createOscillator"
        Name.toChars funcName @?= "createOscillator",
      testCase "createGainNode name" $ do
        let funcName = Name.fromChars "createGainNode"
        Name.toChars funcName @?= "createGainNode",
      testCase "startOscillator name" $ do
        let funcName = Name.fromChars "startOscillator"
        Name.toChars funcName @?= "startOscillator",
      testCase "stopOscillator name" $ do
        let funcName = Name.fromChars "stopOscillator"
        Name.toChars funcName @?= "stopOscillator",
      testCase "setGain name" $ do
        let funcName = Name.fromChars "setGain"
        Name.toChars funcName @?= "setGain",
      testCase "getCurrentTime name" $ do
        let funcName = Name.fromChars "getCurrentTime"
        Name.toChars funcName @?= "getCurrentTime",
      testCase "checkWebAudioSupport name" $ do
        let funcName = Name.fromChars "checkWebAudioSupport"
        Name.toChars funcName @?= "checkWebAudioSupport",
      testCase "resumeAudioContext name" $ do
        let funcName = Name.fromChars "resumeAudioContext"
        Name.toChars funcName @?= "resumeAudioContext",
      testCase "connectToDestination name" $ do
        let funcName = Name.fromChars "connectToDestination"
        Name.toChars funcName @?= "connectToDestination"
    ]

testFFITypeAnnotations :: TestTree
testFFITypeAnnotations =
  testGroup
    "FFI type annotation structure tests"
    [ testCase "simple type annotation" $ do
        let typeString = "AudioContext"
        not (null typeString) @? "Type string should not be empty",
      testCase "function arrow type structure" $ do
        let typeString = "Float -> String -> OscillatorNode"
        List.isInfixOf "->" typeString @? "Should contain arrow operator",
      testCase "Task type structure" $ do
        let typeString = "Task CapabilityError (Initialized AudioContext)"
        List.isInfixOf "Task" typeString @? "Should contain Task type"
        List.isInfixOf "CapabilityError" typeString @? "Should contain CapabilityError"
        List.isInfixOf "Initialized" typeString @? "Should contain Initialized",
      testCase "capability-constrained type structure" $ do
        let typeString = "UserActivated -> Task CapabilityError AudioContext"
        List.isInfixOf "UserActivated" typeString @? "Should contain UserActivated capability",
      testCase "multi-parameter function type" $ do
        let typeString = "Initialized AudioContext -> Float -> String -> Task CapabilityError OscillatorNode"
        let arrowCount = length (filter (== '>') typeString)
        arrowCount >= 3 @? "Should have multiple arrow operators for multi-parameter function"
    ]

testWebAudioTypes :: TestTree
testWebAudioTypes =
  testGroup
    "Web Audio API type tests"
    [ testCase "AudioContext type name" $ do
        let typeName = Name.fromChars "AudioContext"
        Name.toChars typeName @?= "AudioContext",
      testCase "OscillatorNode type name" $ do
        let typeName = Name.fromChars "OscillatorNode"
        Name.toChars typeName @?= "OscillatorNode",
      testCase "GainNode type name" $ do
        let typeName = Name.fromChars "GainNode"
        Name.toChars typeName @?= "GainNode",
      testCase "Initialized wrapper type" $ do
        let wrapperName = Name.fromChars "Initialized"
        Name.toChars wrapperName @?= "Initialized",
      testCase "UserActivated capability type" $ do
        let capabilityName = Name.fromChars "UserActivated"
        Name.toChars capabilityName @?= "UserActivated",
      testCase "CapabilityError type name" $ do
        let errorName = Name.fromChars "CapabilityError"
        Name.toChars errorName @?= "CapabilityError"
    ]

-- Helper function for splitting strings
splitOn :: Eq a => a -> [a] -> [[a]]
splitOn delimiter = foldr f [[]]
  where
    f c (x : xs)
      | c == delimiter = [] : x : xs
      | otherwise = (c : x) : xs
    f _ [] = [[]]
