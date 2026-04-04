-- | Unit.Parse.LimitsEnforcementTest — Tests for parser recursion and repetition limits.
--
-- Verifies that the limits declared in 'Parse.Limits' are actually enforced
-- by the expression parser.  Each test constructs input that either just
-- stays within the limit (success path) or just exceeds it (error path).
--
-- The limit values are inlined here because 'Parse.Limits' is an
-- internal (other-modules) module of canopy-core and cannot be imported
-- by the test suite.  The values match the module exactly:
-- 'maxFieldAccessDepth' = 100, 'maxCaseBranches' = 500, 'maxFunctionArgs' = 50.
--
-- Only limits whose enforcement is visible in the 'SyntaxError.Expr' error
-- type are tested here.  'maxExpressionDepth' and 'maxLetBindings' have no
-- dedicated error constructor yet and are therefore omitted.
--
-- @since 0.19.2
module Unit.Parse.LimitsEnforcementTest (tests) where

import qualified AST.Source as Src
import qualified Data.ByteString.Char8 as C8
import qualified Data.List as List
import qualified Parse.Expression as Expr
import qualified Parse.Primitives as Parse
import qualified Reporting.Error.Syntax as SyntaxError
import Test.Tasty
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

-- LIMIT CONSTANTS
--
-- Mirror the values from Parse.Limits (which is not exposed by canopy-core).

-- | Mirror of 'Parse.Limits.maxFieldAccessDepth'.
maxFieldAccessDepth :: Int
maxFieldAccessDepth = 100

-- | Mirror of 'Parse.Limits.maxCaseBranches'.
maxCaseBranches :: Int
maxCaseBranches = 500

-- | Mirror of 'Parse.Limits.maxFunctionArgs'.
maxFunctionArgs :: Int
maxFunctionArgs = 50

-- HELPERS

-- | Parse a complete expression from a string.
parseExpr :: String -> Either SyntaxError.Expr Src.Expr
parseExpr s = fst <$> Parse.fromByteString Expr.expression SyntaxError.Start (C8.pack s)

-- | Build a field-access chain of the given depth starting from "a".
--
-- @fieldChain 3@ produces @"a.f1.f2.f3"@, the root plus @depth@ accesses.
fieldChain :: Int -> String
fieldChain depth = List.intercalate "." ("a" : map fieldName [1 .. depth])
  where
    fieldName n = "f" <> show n

-- | Build a lambda with the given number of single-character arguments.
--
-- Argument names cycle through a-z, then add a numeric suffix for counts
-- greater than 26.
lambdaWithArgs :: Int -> String
lambdaWithArgs n = "\\" <> unwords (argNames n) <> " -> x"
  where
    argNames count = map toArg [0 .. count - 1]
    toArg i
      | i < 26    = [(['a' .. 'z'] !! i)]
      | otherwise = [(['a' .. 'z'] !! (i `mod` 26))] <> show (i `div` 26)

-- | Build a case expression with the given number of branches.
--
-- Each branch matches a distinct integer literal and returns it.
caseWithBranches :: Int -> String
caseWithBranches n =
  "case x of\n" <> concatMap branch [0 .. n - 1]
  where
    branch i = "  " <> show i <> " ->\n    " <> show i <> "\n"

-- TESTS

-- | All limits-enforcement tests.
tests :: TestTree
tests =
  testGroup
    "Parse.Limits enforcement"
    [ testFieldAccessDepth,
      testCaseBranches,
      testFunctionArgs
    ]

-- FIELD ACCESS DEPTH

testFieldAccessDepth :: TestTree
testFieldAccessDepth =
  testGroup
    "field access depth"
    [ testCase "depth exactly at limit succeeds" $
        assertBool "should succeed at limit" (isRight (parseExpr (fieldChain maxFieldAccessDepth))),
      testCase "depth one over limit fails with TooDeepFieldAccess" $
        case parseExpr (fieldChain (maxFieldAccessDepth + 1)) of
          Left (SyntaxError.TooDeepFieldAccess limit _ _) ->
            limit @?= maxFieldAccessDepth
          Left other ->
            assertFailure ("expected TooDeepFieldAccess, got: " <> show other)
          Right _ ->
            assertFailure "expected parse error for depth exceeding limit",
      testCase "TooDeepFieldAccess carries correct limit value" $
        case parseExpr (fieldChain (maxFieldAccessDepth + 5)) of
          Left (SyntaxError.TooDeepFieldAccess limit _ _) ->
            limit @?= maxFieldAccessDepth
          _ ->
            assertFailure "expected TooDeepFieldAccess with limit"
    ]

-- CASE BRANCHES

testCaseBranches :: TestTree
testCaseBranches =
  testGroup
    "case branch count"
    [ testCase "exactly at limit succeeds" $
        assertBool "should succeed at limit" (isRight (parseExpr (caseWithBranches maxCaseBranches))),
      testCase "one over limit fails with CaseTooManyBranches" $
        case parseExpr (caseWithBranches (maxCaseBranches + 1)) of
          Left (SyntaxError.Case (SyntaxError.CaseTooManyBranches limit _ _) _ _) ->
            limit @?= maxCaseBranches
          Left other ->
            assertFailure ("expected CaseTooManyBranches, got: " <> show other)
          Right _ ->
            assertFailure "expected parse error for too many branches",
      testCase "CaseTooManyBranches carries correct limit value" $
        case parseExpr (caseWithBranches (maxCaseBranches + 10)) of
          Left (SyntaxError.Case (SyntaxError.CaseTooManyBranches limit _ _) _ _) ->
            limit @?= maxCaseBranches
          _ ->
            assertFailure "expected CaseTooManyBranches with correct limit"
    ]

-- FUNCTION ARGS

testFunctionArgs :: TestTree
testFunctionArgs =
  testGroup
    "lambda argument count"
    [ testCase "exactly at limit succeeds" $
        assertBool "should succeed at limit" (isRight (parseExpr (lambdaWithArgs maxFunctionArgs))),
      testCase "one under limit succeeds" $
        assertBool "should succeed under limit" (isRight (parseExpr (lambdaWithArgs (maxFunctionArgs - 1))))
    ]

-- UTILITIES

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight (Left _)  = False
