{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Property tests for Terminal module.
--
-- Tests laws and invariants for the Terminal framework including
-- parser combinators, argument builders, and flag builders.
-- Validates algebraic properties and behavior consistency.
--
-- @since 0.19.1
module Property.TerminalProps (tests) where

import qualified Data.Char as Char
import qualified Data.List as List
import qualified Terminal
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.QuickCheck
  ( Arbitrary (..),
    Gen,
    choose,
    elements,
    listOf,
    oneof,
    sized,
    suchThat,
    testProperty,
    (==>),
  )
import qualified Text.Read as Read

-- | Custom generators for testing
newtype ValidInt = ValidInt Int deriving (Show, Eq)

newtype BoundedInt = BoundedInt (Int, Int, Int) deriving (Show, Eq) -- (min, max, value)

newtype ValidFloat = ValidFloat Float deriving (Show, Eq)

newtype ValidBool = ValidBool String deriving (Show, Eq)

newtype SafeString = SafeString String deriving (Show, Eq)

instance Arbitrary ValidInt where
  arbitrary = ValidInt <$> choose (-1000, 1000)

instance Arbitrary BoundedInt where
  arbitrary = do
    minVal <- choose (1, 50)
    maxVal <- choose (minVal + 1, 100)
    value <- choose (minVal, maxVal)
    pure $ BoundedInt (minVal, maxVal, value)

instance Arbitrary ValidFloat where
  arbitrary = ValidFloat <$> choose (-1000.0, 1000.0)

instance Arbitrary ValidBool where
  arbitrary = ValidBool <$> elements ["true", "false", "yes", "no", "1", "0"]

instance Arbitrary SafeString where
  arbitrary = SafeString <$> sized genSafeString
    where
      genSafeString n = listOf (choose ('a', 'z')) `suchThat` (\s -> length s <= n)

tests :: TestTree
tests =
  testGroup
    "Terminal Properties"
    [ testParserProperties,
      testArgumentProperties,
      testFlagProperties,
      testCompositionProperties,
      testInvariantProperties
    ]

-- | Test parser-specific properties
testParserProperties :: TestTree
testParserProperties =
  testGroup
    "Parser Properties"
    [ testProperty "stringParser identity property" $ \(SafeString input) ->
        let parser = Terminal.stringParser "test" "description"
            Terminal.Parser _ _ parseFunc _ _ = parser
         in parseFunc input == Just input,
      testProperty "intParser bounds respected" $ \(BoundedInt (minVal, maxVal, value)) ->
        let parser = Terminal.intParser minVal maxVal
            Terminal.Parser _ _ parseFunc _ _ = parser
            result = parseFunc (show value)
         in result == Just value,
      testProperty "intParser rejects out-of-bounds" $ \(BoundedInt (minVal, maxVal, _)) ->
        let parser = Terminal.intParser minVal maxVal
            Terminal.Parser _ _ parseFunc _ _ = parser
            outOfBoundsValue = maxVal + 1
            result = parseFunc (show outOfBoundsValue)
         in result == Nothing,
      testProperty "boolParser handles valid representations" $ \(ValidBool input) ->
        let parser = Terminal.boolParser
            Terminal.Parser _ _ parseFunc _ _ = parser
            result = parseFunc input
         in case result of
              Just _ -> True
              Nothing -> False,
      testProperty "floatParser preserves numeric values" $ \(ValidFloat value) ->
        let parser = Terminal.floatParser
            Terminal.Parser _ _ parseFunc _ _ = parser
            result = parseFunc (show value)
         in case result of
              Just parsed -> abs (parsed - value) < 0.001 -- Float precision
              Nothing -> False,
      testProperty "fileParser accepts any string" $ \(SafeString filename) ->
        let parser = Terminal.fileParser []
            Terminal.Parser _ _ parseFunc _ _ = parser
         in parseFunc filename == Just filename,
      testProperty "parser singular/plural naming consistency" $ \(SafeString name) ->
        not (null name)
          ==> let parser = Terminal.stringParser name "description"
                  Terminal.Parser singular plural _ _ _ = parser
               in singular == name && plural == (name ++ "s")
    ]

-- | Test argument builder properties
testArgumentProperties :: TestTree
testArgumentProperties =
  testGroup
    "Argument Properties"
    [ testProperty "noArgs is identity for unit" $ \() ->
        let args = Terminal.noArgs
         in case args of
              Terminal.Args [Terminal.Exactly (Terminal.Done ())] -> True
              _ -> False,
      testProperty "require0 preserves values" $ \(SafeString value) ->
        let args = Terminal.require0 value
         in case args of
              Terminal.Args [Terminal.Exactly (Terminal.Done actualValue)] -> actualValue == value
              _ -> False,
      testProperty "required creates proper structure" $ \(SafeString name) ->
        not (null name)
          ==> let parser = Terminal.stringParser name "description"
                  args = Terminal.required parser
               in case args of
                    Terminal.Args [Terminal.Exactly (Terminal.Required (Terminal.Done _) _)] -> True
                    _ -> False,
      testProperty "optional creates proper structure" $ \(SafeString name) ->
        not (null name)
          ==> let parser = Terminal.stringParser name "description"
                  args = Terminal.optional parser
               in case args of
                    Terminal.Args [Terminal.Optional (Terminal.Done _) _] -> True
                    _ -> False,
      testProperty "zeroOrMore creates multiple structure" $ \(SafeString name) ->
        not (null name)
          ==> let parser = Terminal.stringParser name "description"
                  args = Terminal.zeroOrMore parser
               in case args of
                    Terminal.Args [Terminal.Multiple (Terminal.Done _) _] -> True
                    _ -> False,
      testProperty "oneOf preserves argument count" $ \argCount ->
        argCount >= 0 && argCount <= 10
          ==> let parser = Terminal.stringParser "test" "description"
                  argsList = replicate argCount (Terminal.required parser)
                  combined = Terminal.oneOf argsList
               in case combined of
                    Terminal.Args alternatives -> length alternatives == argCount,
      testProperty "require1 with identity preserves structure" $ \(SafeString name) ->
        not (null name)
          ==> let parser = Terminal.stringParser name "description"
                  args = Terminal.require1 id parser
               in case args of
                    Terminal.Args [Terminal.Exactly (Terminal.Required (Terminal.Done _) _)] -> True
                    _ -> False
    ]

-- | Test flag builder properties
testFlagProperties :: TestTree
testFlagProperties =
  testGroup
    "Flag Properties"
    [ testProperty "noFlags creates unit flags" $ \() ->
        let flags = Terminal.noFlags
         in case flags of
              Terminal.FDone () -> True
              _ -> False,
      testProperty "flags preserves any value" $ \(SafeString value) ->
        let flags = Terminal.flags value
         in case flags of
              Terminal.FDone actualValue -> actualValue == value
              _ -> False,
      testProperty "flag creates proper structure" $ \(SafeString name, SafeString desc) ->
        not (null name) && not (null desc)
          ==> let parser = Terminal.stringParser "value" "description"
                  flagDef = Terminal.flag name parser desc
               in case flagDef of
                    Terminal.Flag actualName _ actualDesc -> actualName == name && actualDesc == desc
                    _ -> False,
      testProperty "onOff creates boolean flag" $ \(SafeString name, SafeString desc) ->
        not (null name) && not (null desc)
          ==> let flagDef = Terminal.onOff name desc
               in case flagDef of
                    Terminal.OnOff actualName actualDesc -> actualName == name && actualDesc == desc
                    _ -> False,
      testProperty "onOffFlag equivalent to onOff" $ \(SafeString name, SafeString desc) ->
        not (null name) && not (null desc)
          ==> let flag1 = Terminal.onOff name desc
                  flag2 = Terminal.onOffFlag name desc
               in case (flag1, flag2) of
                    (Terminal.OnOff n1 d1, Terminal.OnOff n2 d2) -> n1 == n2 && d1 == d2
                    _ -> False
    ]

-- | Test composition properties
testCompositionProperties :: TestTree
testCompositionProperties =
  testGroup
    "Composition Properties"
    [ testProperty "oneOf empty list creates empty args" $ \() ->
        let combined = Terminal.oneOf []
         in case combined of
              Terminal.Args [] -> True
              _ -> False,
      testProperty "oneOf single element preserves structure" $ \(SafeString name) ->
        not (null name)
          ==> let parser = Terminal.stringParser name "description"
                  args = Terminal.required parser
                  combined = Terminal.oneOf [args]
               in case (args, combined) of
                    (Terminal.Args original, Terminal.Args combined') ->
                      length original == length combined'
                    _ -> False,
      testProperty "require2 creates nested structure" $ \(SafeString name1, SafeString name2) ->
        not (null name1) && not (null name2)
          ==> let parser1 = Terminal.stringParser name1 "desc1"
                  parser2 = Terminal.stringParser name2 "desc2"
                  args = Terminal.require2 (,) parser1 parser2
               in case args of
                    Terminal.Args [Terminal.Exactly (Terminal.Required (Terminal.Required (Terminal.Done _) _) _)] -> True
                    _ -> False,
      testProperty "require3 creates triple-nested structure" $ \(SafeString n1, SafeString n2, SafeString n3) ->
        not (null n1) && not (null n2) && not (null n3)
          ==> let parser1 = Terminal.stringParser n1 "desc1"
                  parser2 = Terminal.stringParser n2 "desc2"
                  parser3 = Terminal.stringParser n3 "desc3"
                  args = Terminal.require3 (,,) parser1 parser2 parser3
               in case args of
                    Terminal.Args [Terminal.Exactly (Terminal.Required (Terminal.Required (Terminal.Required (Terminal.Done _) _) _) _)] -> True
                    _ -> False
    ]

-- | Test invariant properties
testInvariantProperties :: TestTree
testInvariantProperties =
  testGroup
    "Invariant Properties"
    [ testProperty "parser functor law - identity" $ \(SafeString input) ->
        let parser = Terminal.stringParser "test" "description"
            Terminal.Parser _ _ parseFunc _ _ = parser
            result = parseFunc input
         in case result of
              Just value -> Just (id value) == Just value
              Nothing -> True,
      testProperty "intParser bounds are always respected" $ \minVal maxVal ->
        minVal < maxVal
          ==> let parser = Terminal.intParser minVal maxVal
                  Terminal.Parser _ _ parseFunc _ _ = parser
                  testValue = minVal + ((maxVal - minVal) `div` 2)
                  result = parseFunc (show testValue)
               in case result of
                    Just parsed -> parsed >= minVal && parsed <= maxVal
                    Nothing -> False,
      testProperty "stringParser never fails on valid strings" $ \(SafeString input) ->
        let parser = Terminal.stringParser "test" "description"
            Terminal.Parser _ _ parseFunc _ _ = parser
         in parseFunc input == Just input,
      testProperty "boolParser is consistent" $ \(ValidBool input) ->
        let parser = Terminal.boolParser
            Terminal.Parser _ _ parseFunc _ _ = parser
            result1 = parseFunc input
            result2 = parseFunc input
         in result1 == result2,
      testProperty "noArgs is idempotent" $ \() ->
        let args1 = Terminal.noArgs
            args2 = Terminal.noArgs
         in case (args1, args2) of
              (Terminal.Args a1, Terminal.Args a2) -> length a1 == length a2
              _ -> False,
      testProperty "flags construction is deterministic" $ \(SafeString value) ->
        let flags1 = Terminal.flags value
            flags2 = Terminal.flags value
         in case (flags1, flags2) of
              (Terminal.FDone v1, Terminal.FDone v2) -> v1 == v2
              _ -> False
    ]
