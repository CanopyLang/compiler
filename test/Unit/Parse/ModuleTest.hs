module Unit.Parse.ModuleTest (tests) where

import qualified AST.Source as Src
import qualified Canopy.Package as Pkg
import qualified Data.ByteString.Char8 as C8
import qualified Canopy.Data.Name as Name
import qualified Parse.Module as ParseModule
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Syntax as SyntaxError
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Parse.Module"
    [ testSimpleModule,
      testImportsAndExports,
      testPortsDisallowedInPackage,
      testExplicitExposing,
      testOperatorExposing,
      testPortModuleApplication,
      testEffectModuleKernel,
      testEffectModuleDisallowedInApp,
      testAliasGenerics,
      testComparableBound,
      testAppendableBound,
      testNumberBound,
      testCompappendBound,
      testNoBoundIsNothing
    ]

parseModule :: ParseModule.ProjectType -> String -> Either SyntaxError.Error Src.Module
parseModule pt s = ParseModule.fromByteString pt (C8.pack s)

simpleModuleSrc :: String
simpleModuleSrc =
  unlines
    [ "module Utils exposing (..)",
      "",
      "import List as L exposing (map)",
      "",
      "x = 1",
      "y n = n",
      "",
      "type alias Pair = ( Int, Int )",
      "type Maybe a = Just a | Nothing"
    ]

testSimpleModule :: TestTree
testSimpleModule = testCase "parse simple module structure" $ case parseModule ParseModule.Application simpleModuleSrc of
  Right modul -> do
    Src.getName modul @?= Name.fromChars "Utils"
    case Src._effects modul of
      Src.NoEffects -> return ()
      _ -> assertFailure "expected NoEffects"
    -- default imports are added automatically; ensure our explicit import exists
    assertBool "List import present" $
      any (\(Src.Import (Ann.At _ name) _ _ _) -> name == Name.list) (Src._imports modul)
    length (Src._values modul) @?= 2
    length (Src._aliases modul) @?= 1
    length (Src._unions modul) @?= 1
  other -> assertFailure ("unexpected: " <> show other)

testImportsAndExports :: TestTree
testImportsAndExports = testCase "imports and exports parsed" $ case parseModule ParseModule.Application simpleModuleSrc of
  Right m -> do
    let isListImport = \case
          Src.Import (Ann.At _ name) (Just alias) _ _ -> name == Name.list || alias == Name.fromChars "L"
          _ -> False
    assertBool "has List import with alias" (any isListImport (Src._imports m))
    case Src._exports m of
      Ann.At _ Src.Open -> return ()
      _ -> assertFailure "expected Open exports"
  _ -> assertFailure "parse failed"

testPortsDisallowedInPackage :: TestTree
testPortsDisallowedInPackage = testCase "ports disallowed in package" $ do
  let src =
        unlines
          [ "module Utils exposing (..)",
            "port p : Int"
          ]
  case parseModule (ParseModule.Package Pkg.core) src of
    Left (SyntaxError.NoPortsInPackage (Ann.At _ _)) -> return ()
    other -> assertFailure ("expected NoPortsInPackage, got: " <> show other)

testExplicitExposing :: TestTree
testExplicitExposing = testCase "explicit exposing list with values and types" $ do
  let src =
        unlines
          [ "module M exposing (x, Pair(..))",
            "x = 1",
            "type Pair a = Pair a"
          ]
  case parseModule ParseModule.Application src of
    Right m -> case Src._exports m of
      Ann.At _ (Src.Explicit items) -> length items @?= 2
      _ -> assertFailure "expected explicit exports"
    other -> assertFailure ("unexpected: " <> show other)

testOperatorExposing :: TestTree
testOperatorExposing = testCase "explicit operator exposing" $ do
  let src =
        unlines
          [ "module M exposing ((:+), x)",
            "x = 1"
          ]
  case parseModule ParseModule.Application src of
    Right m -> case Src._exports m of
      Ann.At _ (Src.Explicit items) -> do
        let hasOp =
              any
                ( \case
                    Src.Operator _ _ -> True
                    _ -> False
                )
                items
        assertBool "operator exposed" hasOp
      _ -> assertFailure "expected explicit exports"
    other -> assertFailure ("unexpected: " <> show other)

testPortModuleApplication :: TestTree
testPortModuleApplication = testCase "port module with ports under Application" $ do
  let src =
        unlines
          [ "port module Ports exposing (..)",
            "",
            "port p : Int"
          ]
  case parseModule ParseModule.Application src of
    Right m -> case Src._effects m of
      Src.Ports ports -> length ports @?= 1
      _ -> assertFailure "expected Ports effects"
    other -> assertFailure ("unexpected: " <> show other)

testEffectModuleKernel :: TestTree
testEffectModuleKernel = testCase "effect module allowed only for kernel packages" $ do
  let src =
        unlines
          [ "effect module Eff where { command = Cmd, subscription = Sub } exposing (..)",
            "",
            "f = 1"
          ]
  case parseModule (ParseModule.Package Pkg.kernel) src of
    Right m -> case Src._effects m of
      Src.Manager _ _ -> return ()
      _ -> assertFailure "expected Manager effects"
    other -> assertFailure ("unexpected: " <> show other)

testEffectModuleDisallowedInApp :: TestTree
testEffectModuleDisallowedInApp = testCase "effect module disallowed outside kernel packages" $ do
  let src =
        unlines
          [ "effect module Eff where { command = Cmd, subscription = Sub } exposing (..)",
            "",
            "f = 1"
          ]
  case parseModule ParseModule.Application src of
    Left (SyntaxError.NoEffectsOutsideKernel _) -> return ()
    other -> assertFailure ("expected NoEffectsOutsideKernel, got: " <> show other)

testAliasGenerics :: TestTree
testAliasGenerics = testCase "type alias generics referenced in field types" $ do
  let src =
        unlines
          [ "module A exposing (..)",
            "",
            "type alias Box a = { value : a }"
          ]
  case parseModule ParseModule.Application src of
    Right m -> case Src._aliases m of
      [Ann.At _ (Src.Alias (Ann.At _ name) typeVars tipe _)] -> do
        name @?= Name.fromChars "Box"
        -- ensure one type var named 'a'
        case typeVars of
          [Ann.At _ tv] -> tv @?= Name.fromChars "a"
          _ -> assertFailure "expected single type variable 'a'"
        -- ensure record field refers to TVar 'a'
        case tipe of
          Ann.At _ (Src.TRecord [(Ann.At _ field, Ann.At _ (Src.TVar v))] Nothing) -> do
            field @?= Name.fromChars "value"
            v @?= Name.fromChars "a"
          other -> assertFailure ("unexpected alias body: " <> show other)
      _ -> assertFailure "expected exactly one alias"
    other -> assertFailure ("unexpected: " <> show other)

-- | Parse a type alias with @comparable =>@ bound and verify the bound is present.
testComparableBound :: TestTree
testComparableBound = testCase "comparable bound on type alias" $ do
  let src =
        unlines
          [ "module M exposing (..)",
            "",
            "type alias UserId = comparable => String"
          ]
  case parseModule ParseModule.Application src of
    Right m -> case Src._aliases m of
      [Ann.At _ (Src.Alias (Ann.At _ name) _ _ maybeBound)] -> do
        name @?= Name.fromChars "UserId"
        maybeBound @?= Just Src.ComparableBound
      _ -> assertFailure "expected exactly one alias"
    other -> assertFailure ("unexpected: " <> show other)

-- | Parse a type alias with @appendable =>@ bound and verify the bound is present.
testAppendableBound :: TestTree
testAppendableBound = testCase "appendable bound on type alias" $ do
  let src =
        unlines
          [ "module M exposing (..)",
            "",
            "type alias Tag = appendable => String"
          ]
  case parseModule ParseModule.Application src of
    Right m -> case Src._aliases m of
      [Ann.At _ (Src.Alias (Ann.At _ name) _ _ maybeBound)] -> do
        name @?= Name.fromChars "Tag"
        maybeBound @?= Just Src.AppendableBound
      _ -> assertFailure "expected exactly one alias"
    other -> assertFailure ("unexpected: " <> show other)

-- | Parse a type alias with @number =>@ bound and verify the bound is present.
testNumberBound :: TestTree
testNumberBound = testCase "number bound on type alias" $ do
  let src =
        unlines
          [ "module M exposing (..)",
            "",
            "type alias Score = number => Int"
          ]
  case parseModule ParseModule.Application src of
    Right m -> case Src._aliases m of
      [Ann.At _ (Src.Alias (Ann.At _ name) _ _ maybeBound)] -> do
        name @?= Name.fromChars "Score"
        maybeBound @?= Just Src.NumberBound
      _ -> assertFailure "expected exactly one alias"
    other -> assertFailure ("unexpected: " <> show other)

-- | Parse a type alias with @compappend =>@ bound and verify the bound is present.
testCompappendBound :: TestTree
testCompappendBound = testCase "compappend bound on type alias" $ do
  let src =
        unlines
          [ "module M exposing (..)",
            "",
            "type alias Key = compappend => String"
          ]
  case parseModule ParseModule.Application src of
    Right m -> case Src._aliases m of
      [Ann.At _ (Src.Alias (Ann.At _ name) _ _ maybeBound)] -> do
        name @?= Name.fromChars "Key"
        maybeBound @?= Just Src.CompAppendBound
      _ -> assertFailure "expected exactly one alias"
    other -> assertFailure ("unexpected: " <> show other)

-- | Parse a type alias without a bound and verify the bound field is 'Nothing'.
testNoBoundIsNothing :: TestTree
testNoBoundIsNothing = testCase "alias without bound has Nothing" $ do
  let src =
        unlines
          [ "module M exposing (..)",
            "",
            "type alias Pair = ( Int, Int )"
          ]
  case parseModule ParseModule.Application src of
    Right m -> case Src._aliases m of
      [Ann.At _ (Src.Alias (Ann.At _ name) _ _ maybeBound)] -> do
        name @?= Name.fromChars "Pair"
        maybeBound @?= Nothing
      _ -> assertFailure "expected exactly one alias"
    other -> assertFailure ("unexpected: " <> show other)
