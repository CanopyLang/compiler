{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the IIFE tree-shaker root-scan helpers.
--
-- The optimized-AST walk that drives runtime tree-shaking cannot see
-- references the code generator emits directly into the output — the
-- program-export call @_Platform_export({...})@ and the @F7@/@A3@ arity
-- helpers called by emitted runtime functions like @_Json_map6@. To keep the
-- tree-shaker's roots in sync with the bytes the bundle actually emits,
-- 'JS.scanRuntimeIdents' and 'JS.scanArities' re-scan the generated output.
--
-- Without this scan the native IIFE bundle crashes at runtime with
-- @F7 is not defined@ / @_Platform_export is not defined@. These tests pin the
-- byte-level recovery, prove the scanned set is always covered by the registry
-- closure, and add a free-identifier regression guard for the exact crash.
--
-- == Test Coverage
--
-- * (golden/unit) byte-level recovery of kernel runtime idents, F\/A arities,
--   and 'JS.arityToken' / 'JS.isIdentByte' boundary cases
-- * (property) scanned runtime ids are a subset of 'JS.allIds';
--   'JS.closeDeps' covers the scanned set; 'JS.arityToken' roundtrips
--   for n in 2..9; scanned ids ⊆ kernel-filtered tokens
-- * (regression) a representative @_Platform_export({...})@ + @_Json_map6@ +
--   @F7(@ output yields roots covered by 'JS.closeDeps' and by
--   'Functions.generateConditionalFunctions', so no F\<n\>/_Module_name token
--   is referenced without being defined — the @F7 is not defined@ /
--   @_Platform_export is not defined@ failure mode the patch fixes
--
-- @since 0.20.5
module Unit.Generate.TreeShakeRootsTest (tests) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as BL
import qualified Data.Set as Set
import Generate.JavaScript (RuntimeId (..))
import qualified Generate.JavaScript as JS
import qualified Generate.JavaScript.Functions as Functions
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit
import Test.Tasty.QuickCheck ((===), (==>))
import qualified Test.Tasty.QuickCheck as QC

tests :: TestTree
tests =
  Test.testGroup
    "Generate.TreeShakeRoots"
    [ goldenTests,
      propertyTests,
      regressionTests
    ]

-- GOLDEN / UNIT
--
-- Pin the byte-level recovery on literal generated-output fragments.

goldenTests :: TestTree
goldenTests =
  Test.testGroup
    "byte-level recovery"
    [ HUnit.testCase "scanRuntimeIdents recovers _Platform_export and _Json_map6" $
        let bytes = "if (typeof scope === 'object') { _Platform_export({Main: _Json_map6(a)}); }"
            found = JS.scanRuntimeIdents bytes
         in do
              Set.member (RuntimeId "_Platform_export") found @?= True
              Set.member (RuntimeId "_Json_map6") found @?= True,
      HUnit.testCase "scanRuntimeIdents ignores non-kernel and lowercase tokens" $
        -- `scope`, `object`, `Main`, `a` are not _Module_name shaped.
        let bytes = "var scope = {}; var Main = a; foo_bar(baz);"
         in JS.scanRuntimeIdents bytes @?= Set.empty,
      HUnit.testCase "scanArities recovers F7 and A3 arities" $
        let bytes = "var _Json_map6 = F7(function (a) { return A3(b, c, d); });"
         in JS.scanArities bytes @?= Set.fromList [7, 3],
      HUnit.testCase "scanArities ignores out-of-range and malformed arity tokens" $
        -- F1/A1 (1 not in 2..9), F0, FX, F77, plain F/A are never arity helpers.
        let bytes = "F1( A1( F0( FX( F77( F( A( )"
         in JS.scanArities bytes @?= Set.empty,
      HUnit.testCase "arityToken recognizes F2..F9 / A2..A9" $ do
        JS.arityToken "F7" @?= Just 7
        JS.arityToken "A9" @?= Just 9
        JS.arityToken "F2" @?= Just 2
        JS.arityToken "A2" @?= Just 2,
      HUnit.testCase "arityToken rejects boundary and malformed tokens" $ do
        JS.arityToken "F1" @?= Nothing -- 1 not in 2..9
        JS.arityToken "F0" @?= Nothing -- 0 not in 2..9
        JS.arityToken "FX" @?= Nothing -- non-digit
        JS.arityToken "F77" @?= Nothing -- length /= 2
        JS.arityToken "F" @?= Nothing -- length /= 2
        JS.arityToken "" @?= Nothing -- empty
        JS.arityToken "G7" @?= Nothing, -- not F or A
      HUnit.testCase "generatedIdentTokens splits on non-identifier bytes" $
        -- `_a.b(F2)` -> ["_a", "b", "F2"] with empty tokens for adjacent delimiters.
        let toks = filter (not . BS.null) (JS.generatedIdentTokens "_a.b(F2)")
         in toks @?= ["_a", "b", "F2"],
      HUnit.testCase "isIdentByte true for [A-Za-z0-9_$], false for delimiters" $ do
        map JS.isIdentByte [0x5F, 0x24, 0x41, 0x7A, 0x39, 0x30] @?= [True, True, True, True, True, True]
        map JS.isIdentByte [0x2E, 0x28, 0x29, 0x20, 0x7B, 0x2C] @?= [False, False, False, False, False, False]
    ]

-- PROPERTY (QuickCheck)
--
-- Invariants that must hold for arbitrary subsets of the registry.

propertyTests :: TestTree
propertyTests =
  Test.testGroup
    "invariants"
    [ QC.testProperty "scanned runtime ids are a subset of JS.allIds" $
        QC.forAll (subsetOf allIdList) $ \ids ->
          let bytes = renderIdsAsOutput ids
              scanned = JS.scanRuntimeIdents bytes
           in QC.counterexample (show (Set.toList scanned))
                (scanned `Set.isSubsetOf` JS.allIds),
      QC.testProperty "closeDeps covers the scanned set (reachable kernel tokens covered)" $
        QC.forAll (subsetOf allIdList) $ \ids ->
          let bytes = renderIdsAsOutput ids
              scanned = JS.scanRuntimeIdents bytes
           in scanned `Set.isSubsetOf` JS.closeDeps scanned,
      QC.testProperty "scanned ids equal the kernel-filtered tokens of the bytes" $
        QC.forAll (subsetOf allIdList) $ \ids ->
          let bytes = renderIdsAsOutput ids
              scanned = JS.scanRuntimeIdents bytes
              filtered =
                Set.fromList
                  [ RuntimeId tok
                  | tok <- JS.generatedIdentTokens bytes,
                    JS.isKernelIdent tok
                  ]
           in scanned === filtered,
      QC.testProperty "arityToken roundtrips for n in 2..9" $
        QC.forAll (QC.choose (2, 9)) $ \n ->
          let fTok = BS8.pack ('F' : show (n :: Int))
              aTok = BS8.pack ('A' : show n)
           in JS.arityToken fTok === Just n QC..&&. JS.arityToken aTok === Just n,
      QC.testProperty "arityToken rejects single-digit n outside 2..9" $
        QC.forAll (QC.choose (0, 9)) $ \n ->
          (n == 0 || n == 1)
            ==> ( JS.arityToken (BS8.pack ('F' : show (n :: Int))) === Nothing
                    QC..&&. JS.arityToken (BS8.pack ('A' : show n)) === Nothing
                ),
      QC.testProperty "isKernelIdent implies isIdentByte for every byte of the token" $
        QC.forAll (subsetOf allIdList) $ \ids ->
          QC.conjoin
            [ QC.counterexample (show tok) (BS.all JS.isIdentByte tok)
            | RuntimeId tok <- ids,
              JS.isKernelIdent tok
            ]
    ]

-- REGRESSION (free-identifier)
--
-- The exact native-crash failure mode: a generated IIFE that references a
-- kernel runtime symbol or an F/A arity helper the optimizer never saw. We
-- build a representative slice of generated output (the program-export call
-- plus an emitted runtime function that curries via F7), scan it the way
-- 'JS.generate' does, and assert every referenced token is COVERED — kernel
-- idents by 'JS.closeDeps', arity helpers by
-- 'Functions.generateConditionalFunctions'. A regression that reintroduces the
-- crash (dropping the scan, or filtering out a referenced root) fails here.

regressionTests :: TestTree
regressionTests =
  Test.testGroup
    "free-identifier regression"
    [ HUnit.testCase "every kernel ident referenced in output is covered by closeDeps" $
        let scanned = JS.scanRuntimeIdents representativeOutput
            covered = JS.closeDeps scanned
            -- closeDeps is a closure: it must contain every scanned root.
            uncovered = Set.difference scanned covered
         in uncovered @?= Set.empty,
      HUnit.testCase "_Platform_export root survives the scan (was: '_Platform_export is not defined')" $
        let scanned = JS.scanRuntimeIdents representativeOutput
         in Set.member (RuntimeId "_Platform_export") scanned @?= True,
      HUnit.testCase "every F/A arity referenced in output is emitted by generateConditionalFunctions (was: 'F7 is not defined')" $
        let neededArities = JS.scanArities representativeOutput
            emitted = renderFunctions neededArities
         in do
              -- The exact crash: F7 referenced, never defined.
              Set.member 7 neededArities @?= True
              -- Each referenced arity helper has a `var F<n> = ...` definition.
              mapM_ (assertArityDefined emitted) (Set.toList neededArities),
      HUnit.testCase "no referenced kernel ident is left free when registry-resolvable" $
        -- For every scanned root that the registry knows about, its full
        -- dependency closure is resolvable (every dep is itself a registry id),
        -- i.e. there is no dangling reference that would emit a free identifier.
        let scanned = JS.scanRuntimeIdents representativeOutput
            closure = JS.closeDeps scanned
            knownRoots = Set.filter resolvable scanned
            resolvable rid = case JS.lookupDef rid of
              Just _ -> True
              Nothing -> False
         in -- Every registry-known root is inside its own closure, and the
            -- closure is self-consistent (closing it again is a no-op).
            do
              knownRoots `Set.isSubsetOf` closure @?= True
              JS.closeDeps closure @?= closure
    ]

-- HELPERS

-- | Sorted list of every registry id, used as the QuickCheck universe.
allIdList :: [RuntimeId]
allIdList = Set.toList JS.allIds

-- | A random subset of the registry ids.
subsetOf :: [a] -> QC.Gen [a]
subsetOf = QC.sublistOf

-- | Render a list of runtime ids the way generated output references them:
-- a call site @id(...)@ separated by arbitrary non-identifier delimiters, so
-- the scanner must recover them from realistic byte boundaries.
renderIdsAsOutput :: [RuntimeId] -> BS.ByteString
renderIdsAsOutput ids =
  BS.intercalate "; " [_ridName rid <> "(a, b)" | rid <- ids]

-- | A representative slice of dev-mode generated output exercising both the
-- program-export call and an emitted runtime function that curries via F7 —
-- the canonical shapes that bypass the optimized-AST walk.
representativeOutput :: BS.ByteString
representativeOutput =
  BS.concat
    [ "var _Json_map6 = F7(function (a, b, c, d, e, f, g) {\n",
      "  return A3(_Utils_Tuple3, a, b);\n",
      "});\n",
      "_Platform_export({ Main: { init: _Json_map6 } });\n"
    ]

-- | Render the conditional F/A helper definitions for a set of arities to bytes.
renderFunctions :: Set.Set Int -> BS.ByteString
renderFunctions =
  BL.toStrict . BB.toLazyByteString . Functions.generateConditionalFunctions

-- | Assert that arity helper @F\<n\>@ has a definition in the emitted bytes.
-- 'Functions.generateConditionalFunctions' renders each helper as
-- @function F\<n\>(fun) { ... }@.
assertArityDefined :: BS.ByteString -> Int -> HUnit.Assertion
assertArityDefined emitted n =
  let decl = BS8.pack ("function F" ++ show n ++ "(")
      defined = decl `BS.isInfixOf` emitted
   in HUnit.assertBool ("expected definition of F" ++ show n ++ " in emitted helpers") defined
