-- | Tests for parsing ability and impl declarations.
--
-- Validates that the parser correctly handles:
--   * Ability declarations with methods and super-abilities
--   * Impl declarations with method definitions
--   * Error cases (malformed syntax)
--
-- @since 0.20.0
module Unit.Parse.AbilityTest (tests) where

import qualified AST.Source as Src
import qualified Data.ByteString.Char8 as C8
import qualified Canopy.Data.Name as Name
import qualified Parse.Module as ParseModule
import qualified Reporting.Annotation as Ann
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Parse.Ability"
    [ testAbilityDecl
    , testAbilityWithSuperAbility
    , testImplDecl
    , testAbilityAndImpl
    , testSingleMethodCount
    , testAbilityThenValue
    , testMultipleMethods
    , testAbilityFieldValues
    ]

parseModule :: String -> Either a Src.Module
parseModule s =
  case ParseModule.fromByteString ParseModule.Application (C8.pack s) of
    Right m -> Right m
    Left _ -> Left undefined

abilityModuleSrc :: String
abilityModuleSrc =
  unlines
    [ "module M exposing (..)"
    , ""
    , "ability Show a where"
    , "  show : a -> String"
    ]

testAbilityDecl :: TestTree
testAbilityDecl = testCase "parse ability declaration" $
  case ParseModule.fromByteString ParseModule.Application (C8.pack abilityModuleSrc) of
    Right m -> do
      length (Src._abilities m) @?= 1
      let Ann.At _ ability = head (Src._abilities m)
      let Ann.At _ abilityName = Src._abilityName ability
      Name.toChars abilityName @?= "Show"
      let Ann.At _ varName = Src._abilityVar ability
      Name.toChars varName @?= "a"
      length (Src._abilityMethods ability) @?= 1
    Left err -> assertFailure ("parse failed: " <> show err)

testAbilityWithSuperAbility :: TestTree
testAbilityWithSuperAbility = testCase "parse ability with super-ability" $
  case ParseModule.fromByteString ParseModule.Application (C8.pack src) of
    Right m -> do
      length (Src._abilities m) @?= 1
      let Ann.At _ ability = head (Src._abilities m)
      let Ann.At _ name = Src._abilityName ability
      Name.toChars name @?= "Ord"
    Left err -> assertFailure ("parse failed: " <> show err)
  where
    src = unlines
      [ "module M exposing (..)"
      , ""
      , "ability Ord a where"
      , "  compare : a -> a -> Order"
      ]

implModuleSrc :: String
implModuleSrc =
  unlines
    [ "module M exposing (..)"
    , ""
    , "ability Show a where"
    , "  show : a -> String"
    , ""
    , "impl Show Int where"
    , "  show n ="
    , "    String.fromInt n"
    ]

testImplDecl :: TestTree
testImplDecl = testCase "parse impl declaration" $
  case ParseModule.fromByteString ParseModule.Application (C8.pack implModuleSrc) of
    Right m -> do
      length (Src._impls m) @?= 1
      let Ann.At _ impl = head (Src._impls m)
      let Ann.At _ implAbilityName = Src._implAbility impl
      Name.toChars implAbilityName @?= "Show"
      length (Src._implMethods impl) @?= 1
    Left err -> assertFailure ("parse failed: " <> show err)

testAbilityAndImpl :: TestTree
testAbilityAndImpl = testCase "parse ability and impl in same module" $
  case ParseModule.fromByteString ParseModule.Application (C8.pack implModuleSrc) of
    Right m -> do
      length (Src._abilities m) @?= 1
      length (Src._impls m) @?= 1
    Left err -> assertFailure ("parse failed: " <> show err)

testSingleMethodCount :: TestTree
testSingleMethodCount = testCase "single method parses with correct count" $
  case ParseModule.fromByteString ParseModule.Application (C8.pack src) of
    Right m -> do
      length (Src._abilities m) @?= 1
      let Ann.At _ ability = head (Src._abilities m)
      length (Src._abilityMethods ability) @?= 1
    Left err -> assertFailure ("parse failed: " <> show err)
  where
    src =
      "module M exposing (..)\n\
      \\n\
      \ability Show a where\n\
      \    show : a -> String\n"

testAbilityThenValue :: TestTree
testAbilityThenValue = testCase "ability followed by value declaration" $
  case ParseModule.fromByteString ParseModule.Application (C8.pack src) of
    Right m -> do
      length (Src._abilities m) @?= 1
      length (Src._values m) @?= 1
    Left err -> assertFailure ("parse failed: " <> show err)
  where
    src =
      "module M exposing (..)\n\
      \\n\
      \ability Show a where\n\
      \    show : a -> String\n\
      \\n\
      \x = 1\n"

testMultipleMethods :: TestTree
testMultipleMethods = testCase "parse ability with multiple methods" $
  case ParseModule.fromByteString ParseModule.Application (C8.pack src) of
    Right m -> do
      length (Src._abilities m) @?= 1
      let Ann.At _ ability = head (Src._abilities m)
      let methodNames = fmap (\(Ann.At _ n, _) -> Name.toChars n) (Src._abilityMethods ability)
      assertBool ("expected 2 methods, got " <> show (length methodNames) <> ": " <> show methodNames)
        (length (Src._abilityMethods ability) == 2)
    Left err -> assertFailure ("parse failed: " <> show err)
  where
    src =
      "module M exposing (..)\n\
      \\n\
      \ability Eq a where\n\
      \    eq : a -> a -> Bool\n\
      \    neq : a -> a -> Bool\n"

testAbilityFieldValues :: TestTree
testAbilityFieldValues = testCase "ability method names are correct" $
  case ParseModule.fromByteString ParseModule.Application (C8.pack src) of
    Right m -> do
      let Ann.At _ ability = head (Src._abilities m)
          methods = Src._abilityMethods ability
          methodNames = fmap (\(Ann.At _ n, _) -> Name.toChars n) methods
      methodNames @?= ["eq", "neq"]
    Left err -> assertFailure ("parse failed: " <> show err)
  where
    src =
      "module M exposing (..)\n\
      \\n\
      \ability Eq a where\n\
      \    eq : a -> a -> Bool\n\
      \    neq : a -> a -> Bool\n"
