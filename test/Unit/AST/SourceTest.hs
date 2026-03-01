module Unit.AST.SourceTest (tests) where

import qualified AST.Source as Src
import qualified AST.Utils.Binop as Binop
import qualified Canopy.Data.Name as Name
import qualified Reporting.Annotation as Ann
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
  let m = emptyModule {Src._name = Just (Ann.At Ann.one modName)}
  Src.getName m @?= modName

testGetImportName :: TestTree
testGetImportName = testCase "getImportName extracts base name" $ do
  let imp = Src.Import (Ann.At Ann.one (Name.fromChars "Html")) Nothing Src.Open False
  Src.getImportName imp @?= Name.fromChars "Html"

testExprConstructors :: TestTree
testExprConstructors =
  testGroup
    "expression constructors"
    [ testCase "list, tuple, and record" $ do
        let x = Ann.At Ann.one (Src.Var Src.LowVar (Name.fromChars "x"))
        let y = Ann.At Ann.one (Src.Int 42)
        let lst = Ann.At Ann.one (Src.List [x, y])
        case Ann.toValue lst of
          Src.List [_, _] -> return ()
          _ -> assertFailure "expected two-element list"
        let tup = Ann.At Ann.one (Src.Tuple x y [])
        case Ann.toValue tup of
          Src.Tuple _ _ [] -> return ()
          _ -> assertFailure "expected 2-tuple"
        let rec = Ann.At Ann.one (Src.Record [(Ann.At Ann.one (Name.fromChars "a"), y)])
        case Ann.toValue rec of
          Src.Record [(Ann.At _ field, _)] -> field @?= Name.fromChars "a"
          _ -> assertFailure "expected single-field record",
      testCase "let and lambda" $ do
        let n = Name.fromChars "n"
        let pat = Ann.At Ann.one (Src.PVar n)
        let body = Ann.At Ann.one (Src.Int 0)
        let lam = Ann.At Ann.one (Src.Lambda [pat] body)
        case Ann.toValue lam of
          Src.Lambda [Ann.At _ (Src.PVar n')] (Ann.At _ (Src.Int 0)) -> n' @?= n
          _ -> assertFailure "unexpected lambda shape"
        let def = Ann.At Ann.one (Src.Define (Ann.At Ann.one n) [pat] body Nothing)
        let let_ = Ann.At Ann.one (Src.Let [def] body)
        case Ann.toValue let_ of
          Src.Let [Ann.At _ (Src.Define {})] (Ann.At _ (Src.Int 0)) -> return ()
          _ -> assertFailure "unexpected let shape"
    ]

testPatternConstructors :: TestTree
testPatternConstructors =
  testGroup
    "pattern constructors"
    [ testCase "records, tuples, lists, cons" $ do
        let a = Ann.At Ann.one (Name.fromChars "a")
        let pRec = Ann.At Ann.one (Src.PRecord [a])
        case Ann.toValue pRec of
          Src.PRecord [Ann.At _ name] -> name @?= Name.fromChars "a"
          _ -> assertFailure "expected record pattern"
        let pUnit = Ann.At Ann.one Src.PUnit
        let pTup = Ann.At Ann.one (Src.PTuple pUnit pUnit [])
        case Ann.toValue pTup of
          Src.PTuple _ _ [] -> return ()
          _ -> assertFailure "expected 2-tuple pattern"
        let pList = Ann.At Ann.one (Src.PList [pUnit, pUnit])
        case Ann.toValue pList of
          Src.PList [_, _] -> return ()
          _ -> assertFailure "expected list pattern"
        let pCons = Ann.At Ann.one (Src.PCons pUnit pUnit)
        case Ann.toValue pCons of
          Src.PCons _ _ -> return ()
          _ -> assertFailure "expected cons pattern"
    ]

testTypeConstructors :: TestTree
testTypeConstructors =
  testGroup
    "type constructors"
    [ testCase "lambda, type, record, tuple" $ do
        let tVar = Ann.At Ann.one (Src.TVar (Name.fromChars "a"))
        let tLam = Ann.At Ann.one (Src.TLambda tVar tVar)
        case Ann.toValue tLam of
          Src.TLambda _ _ -> return ()
          _ -> assertFailure "expected TLambda"
        let tType = Ann.At Ann.one (Src.TType Ann.one (Name.list) [tVar])
        case Ann.toValue tType of
          Src.TType _ _ [Ann.At _ (Src.TVar _)] -> return ()
          _ -> assertFailure "expected TType with one parameter"
        let tRec = Ann.At Ann.one (Src.TRecord [(Ann.At Ann.one (Name.fromChars "x"), tVar)] Nothing)
        case Ann.toValue tRec of
          Src.TRecord [(Ann.At _ field, _)] Nothing -> field @?= Name.fromChars "x"
          _ -> assertFailure "expected TRecord with one field"
        let tTup = Ann.At Ann.one (Src.TTuple tVar tVar [])
        case Ann.toValue tTup of
          Src.TTuple _ _ [] -> return ()
          _ -> assertFailure "expected TTuple"
    ]

testModuleConstruction :: TestTree
testModuleConstruction = testCase "module with values, unions, aliases, infix, effects" $ do
  let exportAll = Ann.At Ann.one Src.Open
  let docs = Src.NoDocs Ann.one
  let imports = [Src.Import (Ann.At Ann.one (Name.fromChars "List")) (Just (Name.fromChars "L")) Src.Open False]
  let val = Ann.At Ann.one (Src.Value (Ann.At Ann.one (Name.fromChars "x")) [] (Ann.At Ann.one (Src.Int 1)) Nothing)
  let union = Ann.At Ann.one (Src.Union (Ann.At Ann.one (Name.fromChars "U")) [] [(Ann.At Ann.one (Name.fromChars "C"), [])])
  let alias = Ann.At Ann.one (Src.Alias (Ann.At Ann.one (Name.fromChars "Alias")) [] (Ann.At Ann.one (Src.TUnit)))
  let _binop = Ann.At Ann.one (Src.Infix (Name.fromChars "+") Binop.Left (Binop.Precedence 5) (Name.fromChars "add"))
  let m = Src.Module Nothing exportAll docs imports [] [val] [union] [alias] [_binop] Src.NoEffects []
  -- Validate import alias and effects
  case imports of
    [Src.Import _ (Just aliasName) _ _] -> aliasName @?= Name.fromChars "L"
    _ -> assertFailure "expected one import with alias"
  case Src._effects m of
    Src.NoEffects -> return ()
    _ -> assertFailure "expected NoEffects"

-- Helpers

emptyModule :: Src.Module
emptyModule =
  Src.Module
    { Src._name = Nothing,
      Src._exports = Ann.At Ann.one Src.Open,
      Src._docs = Src.NoDocs Ann.one,
      Src._imports = [],
      Src._foreignImports = [],
      Src._values = [],
      Src._unions = [],
      Src._aliases = [],
      Src._binops = [],
      Src._effects = Src.NoEffects,
      Src._comments = []
    }
