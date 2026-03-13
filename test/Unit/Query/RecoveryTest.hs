{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Tests for 'Query.Recovery' partial compilation infrastructure.
--
-- @since 0.20.1
module Unit.Query.RecoveryTest (tests) where

import qualified Query.Recovery as Recovery
import Query.Recovery (PartialResult)
import qualified Test.Tasty as Test
import qualified Test.Tasty.HUnit as Test

tests :: Test.TestTree
tests =
  Test.testGroup
    "Query.Recovery Tests"
    [ fromEitherTests,
      completenessTests,
      recoverMapTests,
      recoverFoldTests
    ]

fromEitherTests :: Test.TestTree
fromEitherTests =
  Test.testGroup
    "fromEither"
    [ Test.testCase "Right produces complete result" $ do
        let pr = Recovery.fromEither (0 :: Int) "parse" "test.can" (Right 42)
        Recovery.partialResult pr Test.@?= 42
        Recovery.isComplete pr Test.@?= True
        Recovery.partialErrors pr Test.@?= [],
      Test.testCase "Left produces partial result with error" $ do
        let pr = Recovery.fromEither (0 :: Int) "parse" "test.can" (Left "syntax error")
        Recovery.partialResult pr Test.@?= 0
        Recovery.hasErrors pr Test.@?= True
        length (Recovery.partialErrors pr) Test.@?= 1
    ]

completenessTests :: Test.TestTree
completenessTests =
  Test.testGroup
    "isComplete / hasErrors"
    [ Test.testCase "complete result has no errors" $ do
        let pr = Recovery.fromEither () "phase" "f.can" (Right ())
        Recovery.isComplete pr Test.@?= True
        Recovery.hasErrors pr Test.@?= False,
      Test.testCase "partial result has errors" $ do
        let pr = Recovery.fromEither () "phase" "f.can" (Left "err")
        Recovery.isComplete pr Test.@?= False
        Recovery.hasErrors pr Test.@?= True
    ]

recoverMapTests :: Test.TestTree
recoverMapTests =
  Test.testGroup
    "recoverMap"
    [ Test.testCase "all succeed produces complete result" $ do
        let pr = Recovery.recoverMap (\x -> Right (x * 2)) [1 :: Int, 2, 3]
        Recovery.partialResult pr Test.@?= [2, 4, 6]
        Recovery.isComplete pr Test.@?= True,
      Test.testCase "some fail produces partial result" $ do
        let process x
              | x > 2 = Left (Recovery.RecoveryError "check" "f.can" "too big")
              | otherwise = Right (x * 10)
            pr = Recovery.recoverMap process [1 :: Int, 2, 3, 4]
        Recovery.partialResult pr Test.@?= [10, 20]
        length (Recovery.partialErrors pr) Test.@?= 2,
      Test.testCase "all fail produces empty result with errors" $ do
        let process _ = Left (Recovery.RecoveryError "p" "f" "fail")
            pr = Recovery.recoverMap process [1 :: Int, 2, 3]
        Recovery.partialResult pr Test.@?= ([] :: [Int])
        length (Recovery.partialErrors pr) Test.@?= 3
    ]

recoverFoldTests :: Test.TestTree
recoverFoldTests =
  Test.testGroup
    "recoverFold"
    [ Test.testCase "accumulates successfully" $ do
        let pr = Recovery.recoverFold (\acc x -> Right (acc + x)) (0 :: Int) [1, 2, 3]
        Recovery.partialResult pr Test.@?= 6
        Recovery.isComplete pr Test.@?= True,
      Test.testCase "recovers from failures mid-fold" $ do
        let step acc x
              | x > 10 = Left (Recovery.RecoveryError "fold" "f" "overflow")
              | otherwise = Right (acc + x)
            pr = Recovery.recoverFold step (0 :: Int) [1, 2, 100, 3]
        Recovery.partialResult pr Test.@?= 6
        length (Recovery.partialErrors pr) Test.@?= 1
    ]
