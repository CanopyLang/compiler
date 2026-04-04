{-# LANGUAGE OverloadedStrings #-}

-- | Unit.Generate.JavaScript.ExpressionCaseTest - Tests for case code generation
--
-- This module provides unit tests for the pure functions exported by
-- "Generate.JavaScript.Expression.Case". The focus is on functions that can
-- be exercised with lightweight fixtures.
--
-- == Test Coverage
--
-- * pathToJsExpr: Empty path produces Ref; Index path produces Access;
--   Unbox path behaves differently in Dev vs Prod mode
-- * generateCaseValue: Int, Str, Chr tests produce correct JS.Expr
-- * generateCaseValue: IsCtor in Dev mode produces JS.String;
--   in Prod mode produces JS.Int
--
-- @since 0.19.1
module Unit.Generate.JavaScript.ExpressionCaseTest
  ( tests
  ) where

import Test.Tasty
import Test.Tasty.HUnit
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified AST.Canonical as Can
import qualified Canopy.Data.Index as Index
import qualified Canopy.Data.Name as Name
import qualified Canopy.Data.Utf8 as Utf8
import Canopy.String (String)
import qualified Canopy.String as CString
import qualified Canopy.ModuleName as ModuleName
import qualified AST.Optimized as Opt
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.JavaScript.Expression as Gen
import qualified Generate.JavaScript.Expression.Case as Case
import qualified Generate.JavaScript.Name as JsName
import qualified Generate.JavaScript.StringPool as StringPool
import qualified Generate.Mode as Mode
import qualified Optimize.DecisionTree as DT
import Prelude hiding (String)

-- | Root test tree for Generate.JavaScript.Expression.Case.
tests :: TestTree
tests = testGroup "Generate.JavaScript.Expression.Case Tests"
  [ pathToJsExprTests
  , generateCaseValueTests
  ]

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

-- | Development mode with all flags off.
devMode :: Mode.Mode
devMode = Mode.Dev Nothing False False False Set.empty False

-- | The expression generator extracted from 'Gen'.
genExpr :: Mode.Mode -> Opt.Expr -> JS.Expr
genExpr mode expr = Gen.codeToExpr (Gen.generate mode expr)

-- | A simple root variable name.
rootName :: Name.Name
rootName = Name.fromChars "expr"

-- ---------------------------------------------------------------------------
-- pathToJsExpr
-- ---------------------------------------------------------------------------

-- | Tests for 'Case.pathToJsExpr'.
--
-- The root path (DT.Empty) should yield a JS.Ref for the root variable.
-- A DT.Index path should yield a JS.Access into the sub-path result.
-- A DT.Unbox in Dev mode should yield a JS.Access at index 0 of the sub-path.
pathToJsExprTests :: TestTree
pathToJsExprTests = testGroup "pathToJsExpr"
  [ testCase "Empty path produces JS.Ref to root" $
      let result = Case.pathToJsExpr genExpr devMode rootName DT.Empty
      in case result of
           JS.Ref _ -> pure ()
           other -> assertFailure ("Expected JS.Ref for Empty path, got: " ++ show other)

  , testCase "Index first on Empty produces JS.Access" $
      let result = Case.pathToJsExpr genExpr devMode rootName (DT.Index Index.first DT.Empty)
      in case result of
           JS.Access _ _ -> pure ()
           other -> assertFailure ("Expected JS.Access for Index path, got: " ++ show other)

  , testCase "Index second on Empty produces JS.Access" $
      let result = Case.pathToJsExpr genExpr devMode rootName (DT.Index Index.second DT.Empty)
      in case result of
           JS.Access _ _ -> pure ()
           other -> assertFailure ("Expected JS.Access for Index second, got: " ++ show other)

  , testCase "Index first accessed field matches index 0 name" $
      let result = Case.pathToJsExpr genExpr devMode rootName (DT.Index Index.first DT.Empty)
      in case result of
           JS.Access _ fieldName ->
             show fieldName @?= show (JsName.fromIndex Index.first)
           other -> assertFailure ("Expected JS.Access, got: " ++ show other)

  , testCase "Unbox in Dev mode produces JS.Access at index first" $
      let result = Case.pathToJsExpr genExpr devMode rootName (DT.Unbox DT.Empty)
      in case result of
           JS.Access _ fieldName ->
             show fieldName @?= show (JsName.fromIndex Index.first)
           other -> assertFailure ("Expected JS.Access(first) for Unbox in Dev, got: " ++ show other)

  , testCase "Unbox in Prod mode is identity (no extra Access)" $
      let prodMode = Mode.Prod Map.empty False False False emptyStringPool Set.empty Map.empty
          result = Case.pathToJsExpr genExpr prodMode rootName (DT.Unbox DT.Empty)
      in case result of
           JS.Ref _ -> pure ()
           other -> assertFailure ("Expected JS.Ref for Unbox in Prod, got: " ++ show other)

  , testCase "Nested Index produces nested JS.Access" $
      let path = DT.Index Index.first (DT.Index Index.second DT.Empty)
          result = Case.pathToJsExpr genExpr devMode rootName path
      in case result of
           JS.Access (JS.Access _ _) _ -> pure ()
           other -> assertFailure ("Expected nested JS.Access, got: " ++ show other)
  ]

-- | Minimal production mode with empty string pool.
emptyStringPool :: StringPool.StringPool
emptyStringPool = StringPool.emptyPool

-- ---------------------------------------------------------------------------
-- generateCaseValue
-- ---------------------------------------------------------------------------

-- | Tests for 'Case.generateCaseValue'.
--
-- generateCaseValue converts a DT.Test into a JS.Expr for use as a case arm
-- value in a switch statement.
generateCaseValueTests :: TestTree
generateCaseValueTests = testGroup "generateCaseValue"
  [ testCase "IsInt produces JS.Int with correct value" $
      let result = Case.generateCaseValue devMode (DT.IsInt 42)
      in show result @?= show (JS.Int 42)

  , testCase "IsInt zero produces JS.Int 0" $
      let result = Case.generateCaseValue devMode (DT.IsInt 0)
      in show result @?= show (JS.Int 0)

  , testCase "IsStr produces JS.String" $
      let result = Case.generateCaseValue devMode (DT.IsStr (Utf8.fromChars "hello" :: CString.String))
      in case result of
           JS.String _ -> pure ()
           other -> assertFailure ("Expected JS.String, got: " ++ show other)

  , testCase "IsStr value is encoded as expected" $
      let target = Utf8.fromChars "hello" :: CString.String
          result = Case.generateCaseValue devMode (DT.IsStr target)
      in show result @?= show (JS.String (Utf8.toBuilder target))

  , testCase "IsChr produces JS.String in any mode" $
      let result = Case.generateCaseValue devMode (DT.IsChr (Utf8.fromChars "a" :: CString.String))
      in case result of
           JS.String _ -> pure ()
           other -> assertFailure ("Expected JS.String for IsChr, got: " ++ show other)

  , testCase "IsCtor in Dev mode produces JS.String with constructor name" $
      let home = ModuleName.basics
          ctorName = Name.fromChars "Just"
          result = Case.generateCaseValue devMode
                     (DT.IsCtor home ctorName Index.first 1 Can.Normal)
      in show result @?= show (JS.String (Name.toBuilder ctorName))

  , testCase "IsCtor in Prod mode produces JS.Int with machine index" $
      let prodMode = Mode.Prod Map.empty False False False emptyStringPool Set.empty Map.empty
          home = ModuleName.basics
          ctorName = Name.fromChars "Just"
          result = Case.generateCaseValue prodMode
                     (DT.IsCtor home ctorName Index.first 1 Can.Normal)
      in show result @?= show (JS.Int (Index.toMachine Index.first))
  ]
