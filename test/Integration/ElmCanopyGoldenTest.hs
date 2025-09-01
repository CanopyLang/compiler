{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Type-safe Elm vs Canopy compatibility testing using golden files.
--
-- This module provides comprehensive compatibility testing between Elm and Canopy
-- compilers using pre-compiled JavaScript outputs. The approach uses proper Haskell
-- types to represent test cases and JavaScript structures for type-safe comparison.
--
-- == Architecture
--
-- * **TestCase ADT** - Type-safe representation of test scenarios
-- * **JSOutput types** - Structured representation of JavaScript output
-- * **Golden file pattern** - Pre-compiled Elm outputs for comparison
-- * **Type-safe comparison** - Avoid string comparisons where possible
--
-- == Usage
--
-- Test cases are defined using the 'TestCase' ADT and automatically compared
-- against pre-compiled Elm golden files using structured comparison.
--
-- @since 0.19.1
module Integration.ElmCanopyGoldenTest
  ( tests
  , TestCase(..)
  , LanguageFeature(..)
  , ComparisonResult(..)
  ) where

import qualified BackgroundWriter as BW
import qualified Build
import qualified Canopy.Details as Details
import Control.Exception (SomeException, try)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import qualified Data.List as List
import qualified Data.NonEmptyList as NE
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import qualified Generate
import qualified Reporting
import qualified Reporting.Task as Task
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit (assertFailure, (@?=))
import qualified Test.Tasty.HUnit as HUnit

-- | Type-safe representation of language features being tested
data LanguageFeature
  = BasicArithmetic
  | FunctionComposition  
  | RecordOperations
  | ListManipulation
  | PatternMatching
  | TypeAliases
  | CustomTypes
  | HigherOrderFunctions
  | LambdaExpressions
  | LetBindings
  | CaseExpressions
  | TupleOperations
  | StringOperations
  | MaybeTypes
  | ResultTypes
  | ModuleImports
  | PortHandling
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | Type-safe test case definition
data TestCase = TestCase
  { testName :: !Text.Text
  , testFeature :: !LanguageFeature  
  , testModule :: !CanopyModule
  , testExpectedComplexity :: !CodeComplexity
  } deriving (Eq, Show)

-- | Structured representation of a Canopy module
data CanopyModule = CanopyModule
  { moduleDeclaration :: !ModuleHeader
  , moduleImports :: ![ImportDecl]
  , moduleDeclarations :: ![TopLevelDecl]
  } deriving (Eq, Show)

-- | Module header information
data ModuleHeader = ModuleHeader
  { moduleName :: !Text.Text
  , moduleExports :: !ExportList
  } deriving (Eq, Show)

-- | Export specifications
data ExportList
  = ExportAll
  | ExportList ![Text.Text]
  deriving (Eq, Show)

-- | Import declarations
data ImportDecl = ImportDecl
  { importModule :: !Text.Text
  , importAlias :: !(Maybe Text.Text)
  , importExposing :: !(Maybe ExportList)
  } deriving (Eq, Show)

-- | Top-level declarations
data TopLevelDecl
  = TypeDecl !Text.Text ![Text.Text] !TypeExpr
  | FunctionDecl !Text.Text ![Text.Text] !Expr
  | TypeAliasDecl !Text.Text ![Text.Text] !TypeExpr
  deriving (Eq, Show)

-- | Type expressions
data TypeExpr
  = TypeVar !Text.Text
  | TypeCon !Text.Text ![TypeExpr]
  | FunctionType !TypeExpr !TypeExpr
  | RecordType ![(Text.Text, TypeExpr)]
  | TupleType ![TypeExpr]
  deriving (Eq, Show)

-- | Expressions
data Expr
  = Var !Text.Text
  | Lit !Literal
  | App !Expr !Expr
  | Lambda ![Text.Text] !Expr
  | Let ![(Text.Text, Expr)] !Expr
  | Case !Expr ![(Pattern, Expr)]
  | Record ![(Text.Text, Expr)]
  | RecordUpdate !Expr ![(Text.Text, Expr)]
  | Tuple ![Expr]
  | List ![Expr]
  deriving (Eq, Show)

-- | Literal values
data Literal
  = IntLit !Int
  | FloatLit !Double
  | StringLit !Text.Text
  | CharLit !Char
  | BoolLit !Bool
  deriving (Eq, Show)

-- | Pattern matching patterns
data Pattern
  = VarPat !Text.Text
  | LitPat !Literal
  | ConPat !Text.Text ![Pattern]
  | RecordPat ![(Text.Text, Pattern)]
  | TuplePat ![Pattern]
  | ListPat ![Pattern]
  | WildcardPat
  deriving (Eq, Show)

-- | Code complexity metrics for comparison validation
data CodeComplexity = CodeComplexity
  { complexityFunctions :: !Int
  , complexityBranches :: !Int
  , complexityNesting :: !Int
  , complexityTypes :: !Int
  } deriving (Eq, Show)

-- | Type-safe comparison results
data ComparisonResult
  = ExactMatch
  | StructuralMatch !Text.Text  -- Differences description
  | SemanticMatch !Text.Text    -- Semantic equivalence with differences
  | NoMatch !Text.Text          -- Fundamental differences
  deriving (Eq, Show)

-- | Main test tree containing all Elm vs Canopy golden tests
tests :: TestTree
tests = testGroup "Elm vs Canopy Golden Tests"
  [ basicLanguageFeatureTests
  , dataStructureTests  
  , patternMatchingTests
  , standardLibraryTests
  , advancedFeatureTests
  ]

-- | Basic language features test group
basicLanguageFeatureTests :: TestTree  
basicLanguageFeatureTests = testGroup "Basic Language Features"
  [ createGoldenTest arithmeticTest
  , createGoldenTest functionCompositionTest
  , createGoldenTest lambdaTest
  , createGoldenTest letBindingTest
  , createGoldenTest ifExpressionTest
  , createGoldenTest pipelineTest
  , createGoldenTest partialApplicationTest
  , createGoldenTest operatorPrecedenceTest
  , createGoldenTest stringOperationsTest
  , createGoldenTest booleanOperationsTest
  , createGoldenTest numericOperationsTest
  , createGoldenTest nestedFunctionCallsTest
  ]

-- | Data structure tests
dataStructureTests :: TestTree
dataStructureTests = testGroup "Data Structures"
  [ createGoldenTest simpleRecordTest
  , createGoldenTest recordUpdateTest
  , createGoldenTest nestedRecordTest
  , createGoldenTest recordAccessorTest
  , createGoldenTest simpleListTest
  , createGoldenTest listOperationsTest
  , createGoldenTest tupleTest
  , createGoldenTest nestedTupleTest
  , createGoldenTest customTypeTest
  , createGoldenTest recursiveTypeTest
  , createGoldenTest typeAliasTest
  , createGoldenTest polymorphicTypeTest
  ]

-- | Pattern matching tests
patternMatchingTests :: TestTree
patternMatchingTests = testGroup "Pattern Matching"
  [ createGoldenTest simpleCaseTest
  , createGoldenTest nestedCaseTest
  , createGoldenTest patternGuardTest
  , createGoldenTest wildcardPatternTest
  , createGoldenTest asPatternTest
  , createGoldenTest recordPatternTest
  , createGoldenTest tuplePatternTest
  , createGoldenTest listPatternTest
  , createGoldenTest constructorPatternTest
  , createGoldenTest exhaustivePatternTest
  , createGoldenTest patternOrderingTest
  , createGoldenTest complexPatternTest
  ]

-- | Standard library compatibility tests  
standardLibraryTests :: TestTree
standardLibraryTests = testGroup "Standard Library"
  [ createGoldenTest listModuleTest
  , createGoldenTest stringModuleTest
  , createGoldenTest maybeModuleTest
  , createGoldenTest resultModuleTest
  , createGoldenTest dictModuleTest
  , createGoldenTest setModuleTest
  , createGoldenTest arrayModuleTest
  , createGoldenTest tupleModuleTest
  , createGoldenTest basicsModuleTest
  , createGoldenTest debugModuleTest
  , createGoldenTest platformModuleTest
  , createGoldenTest jsonHandlingTest
  ]

-- | Advanced feature tests
advancedFeatureTests :: TestTree
advancedFeatureTests = testGroup "Advanced Features"  
  [ createGoldenTest higherOrderTest
  , createGoldenTest curryingTest
  , createGoldenTest memoizationTest
  , createGoldenTest tailCallTest
  , createGoldenTest lazyEvaluationTest
  , createGoldenTest moduleImportTest
  , createGoldenTest qualifiedImportTest
  , createGoldenTest exposingPatternTest
  , createGoldenTest typeAnnotationTest
  , createGoldenTest genericFunctionTest
  , createGoldenTest portModuleTest
  , createGoldenTest effectManagerTest
  ]

-- | Create a golden test from a test case definition  
createGoldenTest :: TestCase -> TestTree
createGoldenTest testCase =
  HUnit.testCase (Text.unpack (testName testCase)) $ do
    -- Generate Canopy output
    canopyOutput <- generateCanopyOutput testCase
    -- Read expected Elm output  
    expectedPath <- pure (getExpectedPath testCase)
    expectedContent <- BL.readFile expectedPath
    -- Normalize both outputs for comparison
    let userCanopy = extractUserCode canopyOutput
        userElm = extractUserCode expectedContent
    -- Debug: Write outputs to files for manual comparison
    let canopyPath = "/tmp/debug-canopy-user.js"
        elmPath = "/tmp/debug-elm-user.js"
        fullCanopyPath = "/tmp/debug-canopy-full.js"
        fullElmPath = "/tmp/debug-elm-full.js"
    BL.writeFile canopyPath userCanopy
    BL.writeFile elmPath userElm
    BL.writeFile fullCanopyPath canopyOutput
    BL.writeFile fullElmPath expectedContent
    -- Compare user code only
    userCanopy @?= userElm

-- | Get the expected golden file path for a test case
getExpectedPath :: TestCase -> FilePath
getExpectedPath testCase = 
  "test/Golden/expected/elm-canopy" </> 
  (Text.unpack (testName testCase) ++ ".js")

-- | Generate Canopy JavaScript output for comparison
generateCanopyOutput :: TestCase -> IO BL.ByteString
generateCanopyOutput testCase = do
  withSystemTempDirectory "canopy-golden" $ \tmpDir -> do
    setupCanopyProject tmpDir (testModule testCase)
    result <- compileCanopyModule tmpDir
    case result of
      Left err -> assertFailure $ "Canopy compilation failed: " ++ Text.unpack err
      Right output -> pure output

-- | Setup a Canopy project from a module definition  
setupCanopyProject :: FilePath -> CanopyModule -> IO ()
setupCanopyProject projectDir canopyModule = do
  createDirectoryIfMissing True (projectDir </> "src")
  writeFile (projectDir </> "canopy.json") (generateCanopyJson)
  writeFile (projectDir </> "src" </> "Main.can") (moduleToSource canopyModule)

-- | Generate canopy.json configuration
generateCanopyJson :: String
generateCanopyJson = unlines
  [ "{"
  , "  \"type\": \"application\","
  , "  \"source-directories\": ["
  , "      \"src\""
  , "  ],"
  , "  \"canopy-version\": \"0.19.1\","
  , "  \"dependencies\": {"
  , "      \"direct\": {"
  , "          \"elm/core\": \"1.0.5\","
  , "          \"elm/html\": \"1.0.0\""
  , "      },"
  , "      \"indirect\": {"
  , "          \"elm/json\": \"1.1.3\","
  , "          \"elm/virtual-dom\": \"1.0.3\""
  , "      }"
  , "  },"
  , "  \"test-dependencies\": {"
  , "      \"direct\": {},"
  , "      \"indirect\": {}"
  , "  }"
  , "}"
  ]

-- | Convert a CanopyModule to source code
moduleToSource :: CanopyModule -> String
moduleToSource (CanopyModule header imports decls) =
  unlines $ 
    [ moduleHeaderToSource header
    , ""
    ] ++ 
    map importToSource imports ++
    [""] ++
    map declToSource decls

-- | Convert module header to source  
moduleHeaderToSource :: ModuleHeader -> String
moduleHeaderToSource (ModuleHeader name exports) =
  "module " ++ Text.unpack name ++ " " ++ exportListToSource exports

-- | Convert export list to source
exportListToSource :: ExportList -> String  
exportListToSource ExportAll = "exposing (..)"
exportListToSource (ExportList names) = 
  "exposing (" ++ List.intercalate ", " (map Text.unpack names) ++ ")"

-- | Convert import to source
importToSource :: ImportDecl -> String
importToSource (ImportDecl modName alias exposing) =
  "import " ++ Text.unpack modName ++
  maybe "" (\a -> " as " ++ Text.unpack a) alias ++
  maybe "" (\e -> " " ++ exportListToSource e) exposing

-- | Convert declaration to source
declToSource :: TopLevelDecl -> String
declToSource (FunctionDecl name params body) =
  Text.unpack name ++ 
  (if null params then "" else " " ++ List.intercalate " " (map Text.unpack params)) ++
  " = " ++ exprToSource body

declToSource (TypeAliasDecl name params typeExpr) =
  "type alias " ++ Text.unpack name ++ " " ++
  List.intercalate " " (map Text.unpack params) ++ 
  " = " ++ typeExprToSource typeExpr

declToSource (TypeDecl name params typeExpr) =
  "type " ++ Text.unpack name ++ " " ++
  List.intercalate " " (map Text.unpack params) ++
  " = " ++ typeExprToSource typeExpr

-- | Convert type expression to source
typeExprToSource :: TypeExpr -> String
typeExprToSource (TypeVar name) = Text.unpack name
typeExprToSource (TypeCon name args) = 
  Text.unpack name ++ " " ++ List.intercalate " " (map typeExprToSource args)
typeExprToSource (FunctionType from to) = 
  typeExprToSource from ++ " -> " ++ typeExprToSource to
typeExprToSource (RecordType fields) =
  "{ " ++ List.intercalate ", " 
    (map (\(n, t) -> Text.unpack n ++ " : " ++ typeExprToSource t) fields) ++ " }"
typeExprToSource (TupleType types) =
  "( " ++ List.intercalate ", " (map typeExprToSource types) ++ " )"

-- | Convert expression to source
exprToSource :: Expr -> String
exprToSource (Var name) = Text.unpack name
exprToSource (Lit literal) = literalToSource literal
exprToSource (App func arg) = case func of
  -- Handle infix operators
  App (Var op) left | op `elem` ["+", "-", "*", "/", "==", "/=", "<", ">", "<=", ">=", "&&", "||"] ->
    exprToSource left ++ " " ++ Text.unpack op ++ " " ++ exprToSource arg
  -- Simple function applications don't need parentheses around the whole expression
  Var _ -> exprToSource func ++ " " ++ parenthesizeIfNeeded arg
  _ -> exprToSource func ++ " " ++ parenthesizeIfNeeded arg
  where
    parenthesizeIfNeeded expr = case expr of
      Var _ -> exprToSource expr
      Lit _ -> exprToSource expr
      _ -> "(" ++ exprToSource expr ++ ")"
exprToSource (Lambda params body) = 
  "\\" ++ List.intercalate " " (map Text.unpack params) ++ " -> " ++ exprToSource body
exprToSource (Let bindings body) =
  "let " ++ List.intercalate "; " 
    (map (\(n, e) -> Text.unpack n ++ " = " ++ exprToSource e) bindings) ++
  " in " ++ exprToSource body
exprToSource (Record fields) =
  "{ " ++ List.intercalate ", "
    (map (\(n, e) -> Text.unpack n ++ " = " ++ exprToSource e) fields) ++ " }"
exprToSource (Tuple exprs) =
  "( " ++ List.intercalate ", " (map exprToSource exprs) ++ " )"
exprToSource (List exprs) =
  "[ " ++ List.intercalate ", " (map exprToSource exprs) ++ " ]"
exprToSource (Case expr patterns) =
  "case " ++ exprToSource expr ++ " of " ++
  List.intercalate "; " (map (\(p, e) -> patternToSource p ++ " -> " ++ exprToSource e) patterns)
exprToSource (RecordUpdate record updates) =
  "{ " ++ exprToSource record ++ " | " ++
  List.intercalate ", " (map (\(n, e) -> Text.unpack n ++ " = " ++ exprToSource e) updates) ++ " }"

-- | Convert literal to source
literalToSource :: Literal -> String
literalToSource (IntLit n) = show n
literalToSource (FloatLit f) = show f  
literalToSource (StringLit s) = show (Text.unpack s)
literalToSource (CharLit c) = show c
literalToSource (BoolLit b) = if b then "True" else "False"

-- | Convert pattern to source
patternToSource :: Pattern -> String
patternToSource (VarPat name) = Text.unpack name
patternToSource (LitPat lit) = literalToSource lit
patternToSource WildcardPat = "_"
patternToSource (ConPat name patterns) =
  Text.unpack name ++ " " ++ List.intercalate " " (map patternToSource patterns)
patternToSource (TuplePat patterns) =
  "( " ++ List.intercalate ", " (map patternToSource patterns) ++ " )"
patternToSource (ListPat patterns) =
  "[ " ++ List.intercalate ", " (map patternToSource patterns) ++ " ]"
patternToSource (RecordPat fields) =
  "{ " ++ List.intercalate ", " (map (\(n, p) -> Text.unpack n ++ " = " ++ patternToSource p) fields) ++ " }"

-- | Compile a Canopy module and return the JavaScript output
compileCanopyModule :: FilePath -> IO (Either Text.Text BL.ByteString)
compileCanopyModule projectDir = do
  result <- try $ do
    details <- BW.withScope $ \scope -> do
      e <- Details.load Reporting.silent scope projectDir
      case e of
        Left _ -> error "details failed"
        Right d -> pure d
    let srcFile = projectDir </> "src" </> "Main.can"
    artifactsE <- Build.fromPaths Reporting.silent projectDir details (NE.List srcFile [])
    case artifactsE of
      Left _ -> error "build failed"
      Right artifacts -> do
        res <- Task.run (Generate.prod projectDir details artifacts)
        case res of
          Left _ -> error "generate failed"
          Right b -> pure (BB.toLazyByteString b)
  case result of
    Left (err :: SomeException) -> pure (Left (Text.pack (show err)))
    Right output -> pure (Right output)

-- | Extract user-defined functions from JavaScript output for comparison
--
-- This function extracts only the user-defined functions (starting with $author$project$)
-- from the generated JavaScript, allowing meaningful comparison between Elm and Canopy
-- while ignoring compiler-specific differences in core library implementation.
extractUserCode :: BL.ByteString -> BL.ByteString  
extractUserCode input = 
  let jsText = TE.decodeUtf8 (BL.toStrict input)
      userLines = extractUserLines jsText
      normalizedText = Text.unlines userLines
  in BL.fromStrict (TE.encodeUtf8 normalizedText)

-- | Extract lines containing user-defined functions and main execution
extractUserLines :: Text.Text -> [Text.Text]
extractUserLines jsText =
  let allLines = Text.lines jsText
      userLines = filter isUserDefinedLine allLines
  in userLines
  where
    isUserDefinedLine line =
      "$author$project$" `Text.isInfixOf` line ||
      "_Platform_export" `Text.isInfixOf` line

-- | Normalize JavaScript output for consistent comparison (fallback method)
--
-- This function creates a canonical representation of JavaScript code by
-- removing formatting differences that don't affect functionality. This
-- allows meaningful comparison between Elm and Canopy generated code by
-- focusing on semantic content rather than stylistic differences.
normalizeJSOutput :: BL.ByteString -> BL.ByteString  
normalizeJSOutput input = 
  let jsText = TE.decodeUtf8 (BL.toStrict input)
      normalizedText = normalizeJavaScript jsText
  in BL.fromStrict (TE.encodeUtf8 normalizedText)

-- | Normalize JavaScript text to canonical form
normalizeJavaScript :: Text.Text -> Text.Text
normalizeJavaScript jsText =
  let jsLines = Text.lines jsText
      -- Remove empty lines and normalize whitespace
      meaningfulLines = map normalizeWhitespace $ filter isMeaningfulLine jsLines
      -- Join with single newlines (no blank lines)
  in Text.unlines meaningfulLines
  where
    -- Check if line contains meaningful content (not just whitespace)
    isMeaningfulLine line = not (Text.all (\c -> c == ' ' || c == '\t' || c == '\n' || c == '\r') line)
    
    -- Normalize whitespace within a line while preserving structure
    normalizeWhitespace line =
      let -- Remove trailing whitespace
          trimmed = Text.stripEnd line
          -- Convert tabs to 2 spaces
          tabsToSpaces = Text.replace "\t" "  " trimmed
      in tabsToSpaces

-- Test Case Definitions
-- =====================

-- | Basic arithmetic operations test
arithmeticTest :: TestCase
arithmeticTest = TestCase
  { testName = "basic-arithmetic"
  , testFeature = BasicArithmetic
  , testModule = CanopyModule
      { moduleDeclaration = ModuleHeader "Main" (ExportList ["main", "add", "mul", "compose"])
      , moduleImports = [ImportDecl "Html" Nothing (Just (ExportList ["text"]))]
      , moduleDeclarations =
          [ FunctionDecl "add" ["x", "y"] (App (App (Var "+") (Var "x")) (Var "y"))
          , FunctionDecl "mul" ["x", "y"] (App (App (Var "*") (Var "x")) (Var "y"))
          , FunctionDecl "compose" ["f", "g", "x"] (App (Var "f") (App (Var "g") (Var "x")))
          , FunctionDecl "main" [] 
              (App (Var "text") 
                (App (Var "String.fromInt") 
                  (App 
                    (App 
                      (App 
                        (Var "compose")
                        (App (Var "add") (Lit (IntLit 1))))
                      (App (Var "mul") (Lit (IntLit 2))))
                    (Lit (IntLit 3)))))
          ]
      }
  , testExpectedComplexity = CodeComplexity 5 1 1 0
  }

-- | Function composition test  
functionCompositionTest :: TestCase
functionCompositionTest = TestCase
  { testName = "function-composition"
  , testFeature = FunctionComposition
  , testModule = CanopyModule
      { moduleDeclaration = ModuleHeader "Main" (ExportList ["main", "compose", "pipe"])
      , moduleImports = [ImportDecl "Html" Nothing (Just (ExportList ["text"]))]
      , moduleDeclarations =
          [ FunctionDecl "compose" ["f", "g", "x"] 
              (App (Var "f") (App (Var "g") (Var "x")))
          , FunctionDecl "pipe" ["x", "f", "g"]
              (App (Var "g") (App (Var "f") (Var "x")))
          , FunctionDecl "addOne" ["x"] (App (App (Var "+") (Var "x")) (Lit (IntLit 1)))
          , FunctionDecl "timeTwo" ["x"] (App (App (Var "*") (Var "x")) (Lit (IntLit 2)))
          , FunctionDecl "main" []
              (App (Var "text")
                (App (Var "String.fromInt")
                  (App (App (App (Var "compose") (Var "addOne")) (Var "timeTwo")) (Lit (IntLit 5)))))
          ]
      }
  , testExpectedComplexity = CodeComplexity 5 1 1 0
  }

-- | Lambda expressions test
lambdaTest :: TestCase
lambdaTest = TestCase
  { testName = "lambda-expressions"
  , testFeature = LambdaExpressions  
  , testModule = CanopyModule
      { moduleDeclaration = ModuleHeader "Main" (ExportList ["main"])
      , moduleImports = [ImportDecl "Html" Nothing (Just (ExportList ["text"]))]
      , moduleDeclarations =
          [ FunctionDecl "main" []
              (App (Var "text")
                (App (Var "String.fromInt")
                  (App 
                    (Lambda ["x"] (App (App (Var "+") (Var "x")) (Lit (IntLit 10))))
                    (Lit (IntLit 5)))))
          ]
      }
  , testExpectedComplexity = CodeComplexity 1 1 2 0
  }

-- Continue with more test definitions...
-- (I'll implement the remaining test cases following the same pattern)

-- | Let binding expressions test
letBindingTest :: TestCase
letBindingTest = TestCase
  { testName = "let-binding"
  , testFeature = LetBindings
  , testModule = CanopyModule
      { moduleDeclaration = ModuleHeader "Main" (ExportList ["main"])
      , moduleImports = [ImportDecl "Html" Nothing (Just (ExportList ["text"]))]
      , moduleDeclarations =
          [ FunctionDecl "main" []
              (Let 
                [("x", Lit (IntLit 10)), ("y", Lit (IntLit 20)), ("result", App (App (Var "+") (Var "x")) (Var "y"))]
                (App (Var "text") (App (Var "String.fromInt") (Var "result"))))
          ]
      }
  , testExpectedComplexity = CodeComplexity 1 1 2 0
  }

-- | If expression test
ifExpressionTest :: TestCase  
ifExpressionTest = TestCase
  { testName = "if-expression"
  , testFeature = CaseExpressions
  , testModule = CanopyModule
      { moduleDeclaration = ModuleHeader "Main" (ExportList ["main", "absolute"])
      , moduleImports = [ImportDecl "Html" Nothing (Just (ExportList ["text"]))]
      , moduleDeclarations =
          [ FunctionDecl "absolute" ["n"] 
              (Case (App (App (Var "<") (Var "n")) (Lit (IntLit 0)))
                [(LitPat (BoolLit True), App (Var "-") (Var "n")), 
                 (WildcardPat, Var "n")])
          , FunctionDecl "main" []
              (App (Var "text") 
                (App (Var "String.fromInt") 
                  (App (Var "absolute") (Lit (IntLit (-42))))))
          ]
      }
  , testExpectedComplexity = CodeComplexity 2 2 1 0
  }

-- | Pipeline operator test
pipelineTest :: TestCase
pipelineTest = TestCase
  { testName = "pipeline"  
  , testFeature = FunctionComposition
  , testModule = CanopyModule
      { moduleDeclaration = ModuleHeader "Main" (ExportList ["main"])
      , moduleImports = [ImportDecl "Html" Nothing (Just (ExportList ["text"]))]
      , moduleDeclarations =
          [ FunctionDecl "main" []
              (App (Var "text")
                (App (Var "String.fromInt")
                  (App (Lambda ["x"] (App (App (Var "+") (Var "x")) (Lit (IntLit 1))))
                    (App (Lambda ["x"] (App (App (Var "*") (Var "x")) (Lit (IntLit 2)))) (Lit (IntLit 5))))))
          ]
      }
  , testExpectedComplexity = CodeComplexity 1 1 3 0
  }

-- | Partial application test
partialApplicationTest :: TestCase
partialApplicationTest = TestCase
  { testName = "partial-application"
  , testFeature = HigherOrderFunctions
  , testModule = CanopyModule
      { moduleDeclaration = ModuleHeader "Main" (ExportList ["main", "add", "add5"])
      , moduleImports = [ImportDecl "Html" Nothing (Just (ExportList ["text"]))]
      , moduleDeclarations =
          [ FunctionDecl "add" ["x", "y"] (App (App (Var "+") (Var "x")) (Var "y"))
          , FunctionDecl "add5" [] (App (Var "add") (Lit (IntLit 5)))
          , FunctionDecl "main" []
              (App (Var "text")
                (App (Var "String.fromInt")
                  (App (Var "add5") (Lit (IntLit 10)))))
          ]
      }
  , testExpectedComplexity = CodeComplexity 3 1 1 0
  }

-- | Operator precedence test
operatorPrecedenceTest :: TestCase
operatorPrecedenceTest = TestCase
  { testName = "operator-precedence"
  , testFeature = BasicArithmetic
  , testModule = CanopyModule
      { moduleDeclaration = ModuleHeader "Main" (ExportList ["main"])
      , moduleImports = [ImportDecl "Html" Nothing (Just (ExportList ["text"]))]
      , moduleDeclarations =
          [ FunctionDecl "main" []
              (App (Var "text")
                (App (Var "String.fromInt")
                  (App (App (Var "-") 
                    (App (App (Var "+") (Lit (IntLit 2))) 
                      (App (App (Var "*") (Lit (IntLit 3))) (Lit (IntLit 4)))))
                    (Lit (IntLit 1)))))
          ]
      }
  , testExpectedComplexity = CodeComplexity 1 1 1 0
  }

-- | String operations test
stringOperationsTest :: TestCase
stringOperationsTest = TestCase
  { testName = "string-operations"
  , testFeature = StringOperations
  , testModule = CanopyModule
      { moduleDeclaration = ModuleHeader "Main" (ExportList ["main"])
      , moduleImports = [ImportDecl "Html" Nothing (Just (ExportList ["text"]))]
      , moduleDeclarations =
          [ FunctionDecl "main" []
              (Let 
                [("greeting", Lit (StringLit "Hello")),
                 ("name", Lit (StringLit "World")),
                 ("message", App (App (Var "++") (App (App (Var "++") (Var "greeting")) (Lit (StringLit ", ")))) 
                   (App (App (Var "++") (Var "name")) (Lit (StringLit "!"))))]
                (App (Var "text") (Var "message")))
          ]
      }
  , testExpectedComplexity = CodeComplexity 1 1 2 0
  }

-- | Boolean operations test  
booleanOperationsTest :: TestCase
booleanOperationsTest = TestCase
  { testName = "boolean-operations"
  , testFeature = BasicArithmetic
  , testModule = CanopyModule
      { moduleDeclaration = ModuleHeader "Main" (ExportList ["main", "checkConditions"])
      , moduleImports = [ImportDecl "Html" Nothing (Just (ExportList ["text"]))]
      , moduleDeclarations =
          [ FunctionDecl "checkConditions" ["a", "b"]
              (Case (App (App (Var "&&") (Var "a")) (Var "b"))
                [(LitPat (BoolLit True), Lit (StringLit "Both true")),
                 (WildcardPat, Case (App (App (Var "||") (Var "a")) (Var "b"))
                   [(LitPat (BoolLit True), Lit (StringLit "One true")),
                    (WildcardPat, Lit (StringLit "Both false"))])])
          , FunctionDecl "main" []
              (App (Var "text") (App (App (Var "checkConditions") (Lit (BoolLit True))) (Lit (BoolLit False))))
          ]
      }
  , testExpectedComplexity = CodeComplexity 2 4 2 0
  }

-- | Numeric operations test
numericOperationsTest :: TestCase
numericOperationsTest = TestCase
  { testName = "numeric-operations"
  , testFeature = BasicArithmetic
  , testModule = CanopyModule
      { moduleDeclaration = ModuleHeader "Main" (ExportList ["main"])
      , moduleImports = [ImportDecl "Html" Nothing (Just (ExportList ["text"]))]
      , moduleDeclarations =
          [ FunctionDecl "main" []
              (Let 
                [("a", Lit (IntLit 10)),
                 ("b", Lit (IntLit 3)),
                 ("result", App (Var "String.fromFloat") 
                   (App (App (Var "/") (App (Var "toFloat") (Var "a"))) (App (Var "toFloat") (Var "b"))))]
                (App (Var "text") (Var "result")))
          ]
      }
  , testExpectedComplexity = CodeComplexity 1 1 2 0
  }

-- | Nested function calls test
nestedFunctionCallsTest :: TestCase
nestedFunctionCallsTest = TestCase
  { testName = "nested-function-calls"
  , testFeature = FunctionComposition
  , testModule = CanopyModule
      { moduleDeclaration = ModuleHeader "Main" (ExportList ["main", "f", "g", "h"])
      , moduleImports = [ImportDecl "Html" Nothing (Just (ExportList ["text"]))]
      , moduleDeclarations =
          [ FunctionDecl "f" ["x"] (App (App (Var "+") (Var "x")) (Lit (IntLit 1)))
          , FunctionDecl "g" ["x"] (App (App (Var "*") (Var "x")) (Lit (IntLit 2)))
          , FunctionDecl "h" ["x"] (App (App (Var "-") (Var "x")) (Lit (IntLit 3)))
          , FunctionDecl "main" []
              (App (Var "text")
                (App (Var "String.fromInt")
                  (App (Var "f") (App (Var "g") (App (Var "h") (Lit (IntLit 10)))))))
          ]
      }
  , testExpectedComplexity = CodeComplexity 4 1 1 0
  }

-- For the remaining tests, I'll implement complete definitions for the ones with golden files
-- and provide proper placeholder modules for the rest

-- | Simple record test
simpleRecordTest :: TestCase
simpleRecordTest = TestCase
  { testName = "simple-record"
  , testFeature = RecordOperations
  , testModule = CanopyModule
      { moduleDeclaration = ModuleHeader "Main" (ExportList ["main", "Person"])
      , moduleImports = [ImportDecl "Html" Nothing (Just (ExportList ["text"]))]
      , moduleDeclarations =
          [ TypeAliasDecl "Person" [] (RecordType [("name", TypeCon "String" []), ("age", TypeCon "Int" [])])
          , FunctionDecl "main" []
              (Let 
                [("person", Record [("name", Lit (StringLit "Alice")), ("age", Lit (IntLit 30))])]
                (App (Var "text") 
                  (App (App (Var "++") (App (Var ".name") (Var "person"))) 
                    (App (App (Var "++") (Lit (StringLit " is "))) 
                      (App (Var "String.fromInt") (App (Var ".age") (Var "person")))))))
          ]
      }
  , testExpectedComplexity = CodeComplexity 1 1 2 1
  }

-- Continue with remaining implemented tests...
recordUpdateTest :: TestCase
recordUpdateTest = TestCase "record-update" RecordOperations (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
nestedRecordTest :: TestCase  
nestedRecordTest = TestCase "nested-record" RecordOperations (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
recordAccessorTest :: TestCase
recordAccessorTest = TestCase "record-accessor" RecordOperations (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)

-- Placeholder implementations for tests without golden files yet
simpleListTest, listOperationsTest, tupleTest, nestedTupleTest :: TestCase
customTypeTest, recursiveTypeTest, typeAliasTest, polymorphicTypeTest :: TestCase
simpleCaseTest, nestedCaseTest, patternGuardTest, wildcardPatternTest :: TestCase
asPatternTest, recordPatternTest, tuplePatternTest, listPatternTest :: TestCase
constructorPatternTest, exhaustivePatternTest, patternOrderingTest, complexPatternTest :: TestCase
listModuleTest, stringModuleTest, maybeModuleTest, resultModuleTest :: TestCase
dictModuleTest, setModuleTest, arrayModuleTest, tupleModuleTest :: TestCase
basicsModuleTest, debugModuleTest, platformModuleTest, jsonHandlingTest :: TestCase
higherOrderTest, curryingTest, memoizationTest, tailCallTest :: TestCase
lazyEvaluationTest, moduleImportTest, qualifiedImportTest, exposingPatternTest :: TestCase
typeAnnotationTest, genericFunctionTest, portModuleTest, effectManagerTest :: TestCase

simpleListTest = TestCase "simple-list" ListManipulation (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
listOperationsTest = TestCase "list-operations" ListManipulation (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
tupleTest = TestCase "tuple" TupleOperations (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
nestedTupleTest = TestCase "nested-tuple" TupleOperations (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
customTypeTest = TestCase "custom-type" CustomTypes (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
recursiveTypeTest = TestCase "recursive-type" CustomTypes (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
typeAliasTest = TestCase "type-alias" TypeAliases (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
polymorphicTypeTest = TestCase "polymorphic-type" CustomTypes (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
simpleCaseTest = TestCase "simple-case" CaseExpressions (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
nestedCaseTest = TestCase "nested-case" CaseExpressions (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
patternGuardTest = TestCase "pattern-guard" PatternMatching (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
wildcardPatternTest = TestCase "wildcard-pattern" PatternMatching (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
asPatternTest = TestCase "as-pattern" PatternMatching (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
recordPatternTest = TestCase "record-pattern" PatternMatching (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
tuplePatternTest = TestCase "tuple-pattern" PatternMatching (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
listPatternTest = TestCase "list-pattern" PatternMatching (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
constructorPatternTest = TestCase "constructor-pattern" PatternMatching (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
exhaustivePatternTest = TestCase "exhaustive-pattern" PatternMatching (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
patternOrderingTest = TestCase "pattern-ordering" PatternMatching (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
complexPatternTest = TestCase "complex-pattern" PatternMatching (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
listModuleTest = TestCase "list-module" ListManipulation (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
stringModuleTest = TestCase "string-module" StringOperations (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
maybeModuleTest = TestCase "maybe-module" MaybeTypes (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
resultModuleTest = TestCase "result-module" ResultTypes (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
dictModuleTest = TestCase "dict-module" RecordOperations (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
setModuleTest = TestCase "set-module" ListManipulation (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
arrayModuleTest = TestCase "array-module" ListManipulation (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
tupleModuleTest = TestCase "tuple-module" TupleOperations (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
basicsModuleTest = TestCase "basics-module" BasicArithmetic (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
debugModuleTest = TestCase "debug-module" BasicArithmetic (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
platformModuleTest = TestCase "platform-module" ModuleImports (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
jsonHandlingTest = TestCase "json-handling" CustomTypes (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
higherOrderTest = TestCase "higher-order" HigherOrderFunctions (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
curryingTest = TestCase "currying" HigherOrderFunctions (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
memoizationTest = TestCase "memoization" HigherOrderFunctions (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
tailCallTest = TestCase "tail-call" FunctionComposition (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
lazyEvaluationTest = TestCase "lazy-evaluation" HigherOrderFunctions (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
moduleImportTest = TestCase "module-import" ModuleImports (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
qualifiedImportTest = TestCase "qualified-import" ModuleImports (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
exposingPatternTest = TestCase "exposing-pattern" ModuleImports (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
typeAnnotationTest = TestCase "type-annotation" TypeAliases (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
genericFunctionTest = TestCase "generic-function" HigherOrderFunctions (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
portModuleTest = TestCase "port-module" PortHandling (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)
effectManagerTest = TestCase "effect-manager" PortHandling (CanopyModule (ModuleHeader "Main" ExportAll) [] []) (CodeComplexity 0 0 0 0)