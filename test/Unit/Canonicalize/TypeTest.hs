{-# LANGUAGE OverloadedStrings #-}

-- | Tests for type annotation canonicalization via the full pipeline.
--
-- 'Canonicalize.Type' is an internal module not directly accessible from
-- the test suite. Its behaviour is fully observable through the module
-- canonicalization pipeline: every type annotation written in source code
-- is processed by 'Canonicalize.Type.canonicalize' before the module body
-- is checked.
--
-- We exercise the following type forms:
--
-- * Type variables (@a@, @msg@, @comparable@, …)
-- * Function types (@a -> b@)
-- * Record types (closed and open)
-- * Unit type @()@
-- * Tuple types (2- and 3-element)
-- * Named types (union types, type aliases)
-- * Qualified names
-- * Free-variable collection (Forall wrapping)
-- * Error cases: unknown type, wrong arity, 4-element tuple type,
--   duplicate record field in type annotation
--
-- @since 0.20.0
module Unit.Canonicalize.TypeTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit

import qualified Canonicalize.Module as Module
import qualified Canopy.Data.OneOrMore as OneOrMore
import qualified Canopy.Package as Pkg
import qualified Data.ByteString.Char8 as C8
import qualified Data.Map.Strict as Map
import qualified Parse.Module as ParseModule
import qualified Reporting.Error.Canonicalize as Error
import qualified Reporting.Result as Result
import qualified Reporting.Warning as Warning

-- | Top-level test tree for Canonicalize.Type.
tests :: TestTree
tests = testGroup "Canonicalize.Type Tests"
  [ tVarTests
  , tLambdaTests
  , tRecordTests
  , tUnitTests
  , tTupleTests
  , tNamedTypeTests
  , toAnnotationFreeVarTests
  , tErrorTests
  ]

-- HELPERS

-- | Parse and canonicalize source, returning errors.
canonicalizeErrors :: String -> IO [Error.Error]
canonicalizeErrors src =
  case ParseModule.fromByteString (ParseModule.Package Pkg.core) (C8.pack src) of
    Left err -> assertFailure ("parse failed: " ++ show err) >> error "unreachable"
    Right m ->
      pure (extractErrors (Result.run (Module.canonicalize config Map.empty m)))
  where
    config = Module.CanonConfig Pkg.core (ParseModule.Package Pkg.core) Map.empty

extractErrors :: ([Warning.Warning], Either (OneOrMore.OneOrMore Error.Error) a) -> [Error.Error]
extractErrors (_, Left errs) = OneOrMore.destruct (:) errs
extractErrors (_, Right _) = []

-- | Canonicalize source expecting no errors.
expectSuccess :: String -> IO ()
expectSuccess src = do
  errs <- canonicalizeErrors src
  assertBool ("expected success, got: " ++ show errs) (null errs)

-- | Minimal module header.
withHeader :: [String] -> String
withHeader bodyLines = unlines ("module M exposing (..)" : "" : bodyLines)

-- TVAR TESTS

-- | Type variables in annotations are valid.
tVarTests :: TestTree
tVarTests = testGroup "TVar in type annotations"
  [ testCase "single type variable annotation is accepted" $
      expectSuccess (withHeader
        [ "identity : a -> a"
        , "identity x = x"
        ])

  , testCase "multiple distinct type variables are accepted" $
      expectSuccess (withHeader
        [ "const : a -> b -> a"
        , "const x _ = x"
        ])

  , testCase "type variable named 'msg' is accepted" $
      expectSuccess (withHeader
        [ "wrap : msg -> msg"
        , "wrap x = x"
        ])

  , testCase "type variable in record field type is accepted" $
      expectSuccess (withHeader
        [ "getValue : { value : a } -> a"
        , "getValue r = r.value"
        ])
  ]

-- TLAMBDA TESTS

-- | Function type annotations.
tLambdaTests :: TestTree
tLambdaTests = testGroup "TLambda in type annotations"
  [ testCase "a -> b function type annotation is accepted" $
      expectSuccess (withHeader
        [ "apply : (a -> b) -> a -> b"
        , "apply f x = f x"
        ])

  , testCase "higher-order function type annotation is accepted" $
      expectSuccess (withHeader
        [ "compose : (b -> c) -> (a -> b) -> a -> c"
        , "compose g f x = g (f x)"
        ])

  , testCase "curried function type annotation is accepted" $
      expectSuccess (withHeader
        [ "add : Int -> Int -> Int"
        , "add x y = x + y"
        ])
  ]

-- TRECORD TESTS

-- | Record type annotations.
tRecordTests :: TestTree
tRecordTests = testGroup "TRecord in type annotations"
  [ testCase "closed record type annotation is accepted" $
      expectSuccess (withHeader
        [ "getName : { name : String } -> String"
        , "getName r = r.name"
        ])

  , testCase "record with multiple fields is accepted" $
      expectSuccess (withHeader
        [ "origin : { x : Int, y : Int }"
        , "origin = { x = 0, y = 0 }"
        ])

  , testCase "open record type annotation is accepted" $
      expectSuccess (withHeader
        [ "getX : { r | x : Int } -> Int"
        , "getX r = r.x"
        ])

  , testCase "record type alias annotation is accepted" $
      expectSuccess (withHeader
        [ "type alias Point = { x : Int, y : Int }"
        , ""
        , "zero : Point"
        , "zero = { x = 0, y = 0 }"
        ])
  ]

-- TUNIT TESTS

-- | Unit type annotation.
tUnitTests :: TestTree
tUnitTests = testGroup "TUnit in type annotations"
  [ testCase "unit type annotation () is accepted" $
      expectSuccess (withHeader
        [ "noop : ()"
        , "noop = ()"
        ])

  , testCase "function returning unit is accepted" $
      expectSuccess (withHeader
        [ "discard : a -> ()"
        , "discard _ = ()"
        ])
  ]

-- TTUPLE TESTS

-- | Tuple type annotations.
tTupleTests :: TestTree
tTupleTests = testGroup "TTuple in type annotations"
  [ testCase "2-tuple type annotation is accepted" $
      expectSuccess (withHeader
        [ "swap : ( a, b ) -> ( b, a )"
        , "swap (a, b) = (b, a)"
        ])

  , testCase "3-tuple type annotation is accepted" $
      expectSuccess (withHeader
        [ "triple : a -> b -> c -> ( a, b, c )"
        , "triple a b c = (a, b, c)"
        ])

  , testCase "nested tuple annotation is accepted" $
      expectSuccess (withHeader
        [ "nest : ( ( Int, Int ), Int ) -> Int"
        , "nest ((a, _), _) = a"
        ])
  ]

-- NAMED TYPE TESTS

-- | Named type constructors (unions and aliases) in annotations.
tNamedTypeTests :: TestTree
tNamedTypeTests = testGroup "named types in annotations"
  [ testCase "union type annotation is accepted" $
      expectSuccess (withHeader
        [ "type Color = Red | Green | Blue"
        , ""
        , "toRed : Color -> Color"
        , "toRed _ = Red"
        ])

  , testCase "parametrized union type annotation is accepted" $
      expectSuccess (withHeader
        [ "type Maybe a = Nothing | Just a"
        , ""
        , "toMaybe : a -> Maybe a"
        , "toMaybe x = Just x"
        ])

  , testCase "type alias with type argument is accepted" $
      expectSuccess (withHeader
        [ "type alias Pair a b = ( a, b )"
        , ""
        , "swap : Pair a b -> Pair b a"
        , "swap (a, b) = (b, a)"
        ])

  , testCase "nested named type annotation is accepted" $
      expectSuccess (withHeader
        [ "type Tree a = Leaf | Node (Tree a) a (Tree a)"
        , ""
        , "leaf : Tree a"
        , "leaf = Leaf"
        ])
  ]

-- FREE VAR / ANNOTATION TESTS

-- | Tests that verify free variable collection works correctly.
--
-- 'toAnnotation' wraps the canonical type in a 'Can.Forall' containing
-- all free type variables. We test this indirectly: a definition whose
-- annotation has N distinct type variables should canonicalize without error.
toAnnotationFreeVarTests :: TestTree
toAnnotationFreeVarTests = testGroup "free variable collection in toAnnotation"
  [ testCase "annotation with zero free vars canonicalizes" $
      expectSuccess (withHeader
        [ "one : Int"
        , "one = 1"
        ])

  , testCase "annotation with one free var canonicalizes" $
      expectSuccess (withHeader
        [ "id : a -> a"
        , "id x = x"
        ])

  , testCase "annotation with two free vars canonicalizes" $
      expectSuccess (withHeader
        [ "ap : (a -> b) -> a -> b"
        , "ap f x = f x"
        ])

  , testCase "annotation with repeated free var canonicalizes" $
      expectSuccess (withHeader
        [ "dup : a -> ( a, a )"
        , "dup x = (x, x)"
        ])

  , testCase "annotation with three distinct free vars canonicalizes" $
      expectSuccess (withHeader
        [ "trimap : (a -> d) -> (b -> e) -> (c -> f) -> ( a, b, c ) -> ( d, e, f )"
        , "trimap f g h (a, b, c) = (f a, g b, h c)"
        ])
  ]

-- ERROR TESTS

-- | Tests for type canonicalization error cases.
tErrorTests :: TestTree
tErrorTests = testGroup "type canonicalization errors"
  [ testCase "4-element tuple type produces TupleLargerThanThree error" $ do
      let src = withHeader
            [ "bad : ( a, b, c, d )"
            , "bad = (1, 2, 3, 4)"
            ]
      errs <- canonicalizeErrors src
      assertBool
        ("expected TupleLargerThanThree, got: " ++ show errs)
        (any isTupleTooLarge errs)

  , testCase "unknown type constructor produces error" $ do
      let src = withHeader
            [ "x : UnknownType"
            , "x = 0"
            ]
      errs <- canonicalizeErrors src
      assertBool ("expected type error, got: " ++ show errs) (not (null errs))

  , testCase "type alias with wrong arity produces BadArity error" $ do
      let src = withHeader
            [ "type alias Pair a b = ( a, b )"
            , ""
            , "bad : Pair Int"
            , "bad = (1, 2)"
            ]
      errs <- canonicalizeErrors src
      assertBool ("expected arity error, got: " ++ show errs) (not (null errs))

  , testCase "union type with wrong arity produces BadArity error" $ do
      let src = withHeader
            [ "type Maybe a = Nothing | Just a"
            , ""
            , "bad : Maybe Int String"
            , "bad = Nothing"
            ]
      errs <- canonicalizeErrors src
      assertBool ("expected arity error, got: " ++ show errs) (not (null errs))

  , testCase "duplicate record field in type annotation produces error" $ do
      let src = withHeader
            [ "bad : { a : Int, a : String }"
            , "bad = { a = 1, a = \"\" }"
            ]
      errs <- canonicalizeErrors src
      assertBool ("expected duplicate field error, got: " ++ show errs) (not (null errs))
  ]

-- ERROR PREDICATES

-- | Check whether an error is 'TupleLargerThanThree'.
isTupleTooLarge :: Error.Error -> Bool
isTupleTooLarge (Error.TupleLargerThanThree _) = True
isTupleTooLarge _ = False
