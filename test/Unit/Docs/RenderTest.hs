{-# LANGUAGE OverloadedStrings #-}

-- | Tests for the documentation rendering module.
--
-- Validates that 'Docs.Render' correctly converts 'Canopy.Docs.Documentation'
-- into JSON and Markdown formats.  Tests exercise the rendering of values,
-- type aliases, custom types, binary operators, and doc comments across
-- both output formats.
--
-- @since 0.19.2
module Unit.Docs.RenderTest (tests) where

import qualified AST.Utils.Binop as Binop
import qualified Canopy.Compiler.Type as Type
import qualified Canopy.Data.Name as Name
import qualified Canopy.Docs as Docs
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as LBS8
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Docs.Render (OutputFormat (..))
import qualified Docs.Render as Render
import qualified Json.String as Json
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as Test

tests :: TestTree
tests =
  Test.testGroup
    "Docs.Render"
    [ outputFormatTests,
      typeToTextTests,
      markdownRenderTests,
      jsonRenderTests
    ]

-- OUTPUT FORMAT

-- | Tests for the 'OutputFormat' type.
outputFormatTests :: TestTree
outputFormatTests =
  Test.testGroup
    "OutputFormat"
    [ Test.testCase "JsonFormat show" $
        show JsonFormat @?= "JsonFormat",
      Test.testCase "MarkdownFormat show" $
        show MarkdownFormat @?= "MarkdownFormat",
      Test.testCase "JsonFormat equality" $
        (JsonFormat == JsonFormat) @?= True,
      Test.testCase "different formats are not equal" $
        (JsonFormat == MarkdownFormat) @?= False
    ]

-- TYPE TO TEXT

-- | Tests for 'typeToText' rendering of various type structures.
typeToTextTests :: TestTree
typeToTextTests =
  Test.testGroup
    "typeToText"
    [ Test.testCase "simple named type" $
        Render.typeToText (Type.Type (Name.fromChars "Int") []) @?= "Int",
      Test.testCase "type variable" $
        Render.typeToText (Type.Var (Name.fromChars "a")) @?= "a",
      Test.testCase "unit type" $
        Render.typeToText Type.Unit @?= "()",
      Test.testCase "function type" $
        Render.typeToText (Type.Lambda intType intType) @?= "Int -> Int",
      Test.testCase "multi-arg function type" $
        Render.typeToText (Type.Lambda intType (Type.Lambda stringType intType))
          @?= "Int -> String -> Int",
      Test.testCase "parameterized type" $
        Render.typeToText (Type.Type (Name.fromChars "List") [intType])
          @?= "List Int",
      Test.testCase "tuple type" $
        Render.typeToText (Type.Tuple intType stringType [])
          @?= "( Int, String )",
      Test.testCase "record type" $
        Render.typeToText (Type.Record [(Name.fromChars "x", intType), (Name.fromChars "y", intType)] Nothing)
          @?= "{ x : Int, y : Int }"
    ]

-- MARKDOWN RENDERING

-- | Tests for Markdown documentation output.
markdownRenderTests :: TestTree
markdownRenderTests =
  Test.testGroup
    "Markdown"
    [ Test.testCase "empty docs produces minimal output" $
        let docs = Map.empty
         in Render.renderMarkdown docs @?= "",
      Test.testCase "single module with no exports" $
        let md = Render.renderModuleMarkdown emptyModule
         in assertContains "# TestModule" md,
      Test.testCase "module with value shows type signature" $
        let md = Render.renderModuleMarkdown moduleWithValue
         in assertContains "myFunc : Int -> Int" md,
      Test.testCase "module with value shows heading" $
        let md = Render.renderModuleMarkdown moduleWithValue
         in assertContains "### myFunc" md,
      Test.testCase "module with alias shows definition" $
        let md = Render.renderModuleMarkdown moduleWithAlias
         in assertContains "type alias Name" md,
      Test.testCase "module with union shows constructors" $
        let md = Render.renderModuleMarkdown moduleWithUnion
         in assertContains "= Just" md,
      Test.testCase "module with union shows second constructor" $
        let md = Render.renderModuleMarkdown moduleWithUnion
         in assertContains "| Nothing" md,
      Test.testCase "module with comment includes comment text" $
        let md = Render.renderModuleMarkdown moduleWithComment
         in assertContains "This is a test module" md,
      Test.testCase "module with binop shows operator" $
        let md = Render.renderModuleMarkdown moduleWithBinop
         in assertContains "(+)" md,
      Test.testCase "values section heading present" $
        let md = Render.renderModuleMarkdown moduleWithValue
         in assertContains "## Values" md,
      Test.testCase "type aliases section heading present" $
        let md = Render.renderModuleMarkdown moduleWithAlias
         in assertContains "## Type Aliases" md,
      Test.testCase "types section heading present" $
        let md = Render.renderModuleMarkdown moduleWithUnion
         in assertContains "## Types" md,
      Test.testCase "operators section heading present" $
        let md = Render.renderModuleMarkdown moduleWithBinop
         in assertContains "## Operators" md,
      Test.testCase "full docs renders multiple modules" $
        let docs =
              Map.fromList
                [ (Name.fromChars "A", emptyModule),
                  (Name.fromChars "B", moduleWithValue)
                ]
            md = Render.renderMarkdown docs
         in assertContains "# TestModule" md
              >> assertContains "myFunc" md
    ]

-- JSON RENDERING

-- | Tests for JSON documentation output.
jsonRenderTests :: TestTree
jsonRenderTests =
  Test.testGroup
    "JSON"
    [ Test.testCase "empty docs produces empty JSON array" $
        let docs = Map.empty
            json = builderToString (Render.renderJson docs)
         in json @?= "[]",
      Test.testCase "single module produces JSON with name field" $
        let docs = Map.singleton (Name.fromChars "TestModule") emptyModule
            json = builderToString (Render.renderJson docs)
         in assertContains "\"name\"" json,
      Test.testCase "module with value includes value name in JSON" $
        let docs = Map.singleton (Name.fromChars "TestModule") moduleWithValue
            json = builderToString (Render.renderJson docs)
         in assertContains "myFunc" json,
      Test.testCase "module with alias includes alias in JSON" $
        let docs = Map.singleton (Name.fromChars "TestModule") moduleWithAlias
            json = builderToString (Render.renderJson docs)
         in assertContains "Name" json,
      Test.testCase "module with union includes union in JSON" $
        let docs = Map.singleton (Name.fromChars "TestModule") moduleWithUnion
            json = builderToString (Render.renderJson docs)
         in assertContains "Maybe" json
    ]

-- HELPERS

-- | Check that a string contains a substring.
assertContains :: String -> String -> IO ()
assertContains needle haystack =
  Test.assertBool
    ("Expected output to contain " ++ show needle ++ " but got:\n" ++ haystack)
    (needle `List.isInfixOf` haystack)

-- | Convert a ByteString Builder to a String for assertion.
builderToString :: BB.Builder -> String
builderToString = LBS8.unpack . BB.toLazyByteString

-- | A simple Int type for test fixtures.
intType :: Type.Type
intType = Type.Type (Name.fromChars "Int") []

-- | A simple String type for test fixtures.
stringType :: Type.Type
stringType = Type.Type (Name.fromChars "String") []

-- | An empty doc comment.
noComment :: Docs.Comment
noComment = Json.fromChars ""

-- | An empty module with no exports.
emptyModule :: Docs.Module
emptyModule =
  Docs.Module
    { Docs._name = Name.fromChars "TestModule",
      Docs._comment = noComment,
      Docs._unions = Map.empty,
      Docs._aliases = Map.empty,
      Docs._values = Map.empty,
      Docs._binops = Map.empty
    }

-- | A module with a single exported value.
moduleWithValue :: Docs.Module
moduleWithValue =
  emptyModule
    { Docs._values =
        Map.singleton
          (Name.fromChars "myFunc")
          (Docs.Value noComment (Type.Lambda intType intType))
    }

-- | A module with a type alias.
moduleWithAlias :: Docs.Module
moduleWithAlias =
  emptyModule
    { Docs._aliases =
        Map.singleton
          (Name.fromChars "Name")
          (Docs.Alias noComment [] stringType)
    }

-- | A module with a custom type (union).
moduleWithUnion :: Docs.Module
moduleWithUnion =
  emptyModule
    { Docs._unions =
        Map.singleton
          (Name.fromChars "Maybe")
          ( Docs.Union
              noComment
              [Name.fromChars "a"]
              [ (Name.fromChars "Just", [Type.Var (Name.fromChars "a")]),
                (Name.fromChars "Nothing", [])
              ]
          )
    }

-- | A module with a doc comment.
moduleWithComment :: Docs.Module
moduleWithComment =
  emptyModule
    { Docs._comment = Json.fromChars "This is a test module"
    }

-- | A module with a binary operator.
moduleWithBinop :: Docs.Module
moduleWithBinop =
  emptyModule
    { Docs._binops =
        Map.singleton
          (Name.fromChars "+")
          (Docs.Binop noComment (Type.Lambda intType (Type.Lambda intType intType)) assocLeft prec6)
    }

-- | Left associativity for test binops.
assocLeft :: Binop.Associativity
assocLeft = Binop.Left

-- | Precedence 6 for test binops.
prec6 :: Binop.Precedence
prec6 = Binop.Precedence 6
