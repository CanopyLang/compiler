module Unit.AST.SourceTest (tests) where

import qualified AST.Source as Src
import qualified AST.Utils.Binop as Binop
import qualified Data.Name as Name
import qualified Reporting.Annotation as A
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "AST.Source Tests"
    [ testGetNameDefault,
      testGetNameExplicit,
      testGetImportName,
      testExprConstructors,
      testPatternConstructors,
      testTypeConstructors,
      testModuleConstruction
    ]

testGetNameDefault :: TestTree
testGetNameDefault = testCase "getName defaults to Main" $ do
  let m = emptyModule {Src._name = Nothing}
  Src.getName m @?= Name._Main

testGetNameExplicit :: TestTree
testGetNameExplicit = testCase "getName returns explicit module name" $ do
  let modName = Name.fromChars "My.Module"
  let m = emptyModule {Src._name = Just (A.At A.one modName)}
  Src.getName m @?= modName

testGetImportName :: TestTree
testGetImportName = testCase "getImportName extracts base name" $ do
  let imp = Src.Import (A.At A.one (Name.fromChars "Html")) Nothing Src.Open
  Src.getImportName imp @?= Name.fromChars "Html"

testExprConstructors :: TestTree
testExprConstructors =
  testGroup
    "expression constructors"
    [ testCase "list, tuple, and record" $ do
        let x = A.At A.one (Src.Var Src.LowVar (Name.fromChars "x"))
        let y = A.At A.one (Src.Int 42)
        let lst = A.At A.one (Src.List [x, y])
        case A.toValue lst of
          Src.List [_, _] -> return ()
          _ -> assertFailure "expected two-element list"
        let tup = A.At A.one (Src.Tuple x y [])
        case A.toValue tup of
          Src.Tuple _ _ [] -> return ()
          _ -> assertFailure "expected 2-tuple"
        let rec = A.At A.one (Src.Record [(A.At A.one (Name.fromChars "a"), y)])
        case A.toValue rec of
          Src.Record [(A.At _ field, _)] -> field @?= Name.fromChars "a"
          _ -> assertFailure "expected single-field record",
      testCase "let and lambda" $ do
        let n = Name.fromChars "n"
        let pat = A.At A.one (Src.PVar n)
        let body = A.At A.one (Src.Int 0)
        let lam = A.At A.one (Src.Lambda [pat] body)
        case A.toValue lam of
          Src.Lambda [A.At _ (Src.PVar n')] (A.At _ (Src.Int 0)) -> n' @?= n
          _ -> assertFailure "unexpected lambda shape"
        let def = A.At A.one (Src.Define (A.At A.one n) [pat] body Nothing)
        let let_ = A.At A.one (Src.Let [def] body)
        case A.toValue let_ of
          Src.Let [A.At _ (Src.Define _ _ _ _)] (A.At _ (Src.Int 0)) -> return ()
          _ -> assertFailure "unexpected let shape"
    ]

testPatternConstructors :: TestTree
testPatternConstructors =
  testGroup
    "pattern constructors"
    [ testCase "records, tuples, lists, cons" $ do
        let a = A.At A.one (Name.fromChars "a")
        let pRec = A.At A.one (Src.PRecord [a])
        case A.toValue pRec of
          Src.PRecord [A.At _ name] -> name @?= Name.fromChars "a"
          _ -> assertFailure "expected record pattern"
        let pUnit = A.At A.one Src.PUnit
        let pTup = A.At A.one (Src.PTuple pUnit pUnit [])
        case A.toValue pTup of
          Src.PTuple _ _ [] -> return ()
          _ -> assertFailure "expected 2-tuple pattern"
        let pList = A.At A.one (Src.PList [pUnit, pUnit])
        case A.toValue pList of
          Src.PList [_, _] -> return ()
          _ -> assertFailure "expected list pattern"
        let pCons = A.At A.one (Src.PCons pUnit pUnit)
        case A.toValue pCons of
          Src.PCons _ _ -> return ()
          _ -> assertFailure "expected cons pattern"
    ]

testTypeConstructors :: TestTree
testTypeConstructors =
  testGroup
    "type constructors"
    [ testCase "lambda, type, record, tuple" $ do
        let tVar = A.At A.one (Src.TVar (Name.fromChars "a"))
        let tLam = A.At A.one (Src.TLambda tVar tVar)
        case A.toValue tLam of
          Src.TLambda _ _ -> return ()
          _ -> assertFailure "expected TLambda"
        let tType = A.At A.one (Src.TType A.one (Name.list) [tVar])
        case A.toValue tType of
          Src.TType _ _ [A.At _ (Src.TVar _)] -> return ()
          _ -> assertFailure "expected TType with one parameter"
        let tRec = A.At A.one (Src.TRecord [(A.At A.one (Name.fromChars "x"), tVar)] Nothing)
        case A.toValue tRec of
          Src.TRecord [(A.At _ field, _)] Nothing -> field @?= Name.fromChars "x"
          _ -> assertFailure "expected TRecord with one field"
        let tTup = A.At A.one (Src.TTuple tVar tVar [])
        case A.toValue tTup of
          Src.TTuple _ _ [] -> return ()
          _ -> assertFailure "expected TTuple"
    ]

testModuleConstruction :: TestTree
testModuleConstruction = testCase "module with values, unions, aliases, infix, effects" $ do
  let exportAll = A.At A.one Src.Open
  let docs = Src.NoDocs A.one
  let imports = [Src.Import (A.At A.one (Name.fromChars "List")) (Just (Name.fromChars "L")) Src.Open]
  let val = A.At A.one (Src.Value (A.At A.one (Name.fromChars "x")) [] (A.At A.one (Src.Int 1)) Nothing)
  let union = A.At A.one (Src.Union (A.At A.one (Name.fromChars "U")) [] [(A.At A.one (Name.fromChars "C"), [])])
  let alias = A.At A.one (Src.Alias (A.At A.one (Name.fromChars "Alias")) [] (A.At A.one (Src.TUnit)))
  let _binop = A.At A.one (Src.Infix (Name.fromChars "+") Binop.Left (Binop.Precedence 5) (Name.fromChars "add"))
  let m = Src.Module Nothing exportAll docs imports [val] [union] [alias] [_binop] Src.NoEffects
  -- Validate import alias and effects
  case imports of
    [Src.Import _ (Just aliasName) _] -> aliasName @?= Name.fromChars "L"
    _ -> assertFailure "expected one import with alias"
  case Src._effects m of
    Src.NoEffects -> return ()
    _ -> assertFailure "expected NoEffects"

-- Helpers

emptyModule :: Src.Module
emptyModule =
  Src.Module
    { Src._name = Nothing,
      Src._exports = A.At A.one Src.Open,
      Src._docs = Src.NoDocs A.one,
      Src._imports = [],
      Src._values = [],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects
    }
