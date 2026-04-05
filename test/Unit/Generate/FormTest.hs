{-# LANGUAGE OverloadedStrings #-}

-- | Tests for 'Generate.Form'.
--
-- Verifies schema-driven form code generation from Canopy record type aliases.
-- The tests focus on the pure helper functions that do not require IO.
--
-- == Test Coverage
--
-- * 'fieldNameToLabel' — camelCase to "Title Case" conversion
-- * 'mapFieldType' — field name and type heuristics for constructor selection
-- * 'generateFormDefinition' — Nothing for non-record aliases, Just for records
-- * 'generateFormModule' — module header and imports are present in output
--
-- @since 0.20.1
module Unit.Generate.FormTest (tests) where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.Text as Text
import qualified Generate.Form as Form
import Test.Tasty
import Test.Tasty.HUnit

-- | Root test tree.
tests :: TestTree
tests =
  testGroup
    "Generate.Form"
    [ fieldNameToLabelTests,
      mapFieldTypeTests,
      generateFormDefinitionTests,
      generateFormModuleTests
    ]

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

renderBuilder :: BB.Builder -> String
renderBuilder = BL8.unpack . BB.toLazyByteString

-- | A simple type alias wrapping a record.
recordAlias :: Map.Map Name.Name Can.FieldType -> Can.Alias
recordAlias fields =
  Can.Alias [] [] (Can.TRecord fields Nothing) Nothing []

-- | A non-record alias (wraps an Int type).
nonRecordAlias :: Can.Alias
nonRecordAlias = Can.Alias [] [] intType Nothing []

intType :: Can.Type
intType = Can.TType ModuleName.basics (Name.fromChars "Int") []

stringType :: Can.Type
stringType = Can.TType ModuleName.string (Name.fromChars "String") []

boolType :: Can.Type
boolType = Can.TType ModuleName.basics (Name.fromChars "Bool") []

floatType :: Can.Type
floatType = Can.TType ModuleName.basics (Name.fromChars "Float") []

maybeStringType :: Can.Type
maybeStringType = Can.TType ModuleName.maybe (Name.fromChars "Maybe") [stringType]

-- | Build a field map with a single field.
singleField :: Name.Name -> Can.Type -> Map.Map Name.Name Can.FieldType
singleField name tipe = Map.singleton name (Can.FieldType 0 tipe)

-- ---------------------------------------------------------------------------
-- fieldNameToLabel tests
-- ---------------------------------------------------------------------------

fieldNameToLabelTests :: TestTree
fieldNameToLabelTests =
  testGroup
    "fieldNameToLabel"
    [ testCase "single lowercase word is capitalised" $
        Form.fieldNameToLabel (Name.fromChars "email") @?= Text.pack "Email",

      testCase "camelCase splits on uppercase letters" $
        Form.fieldNameToLabel (Name.fromChars "firstName") @?= Text.pack "First name",

      testCase "camelCase with three words" $
        Form.fieldNameToLabel (Name.fromChars "rememberMe") @?= Text.pack "Remember me",

      testCase "single character is capitalised" $
        Form.fieldNameToLabel (Name.fromChars "x") @?= Text.pack "X",

      testCase "already capitalised word keeps first capital" $
        Form.fieldNameToLabel (Name.fromChars "password") @?= Text.pack "Password"
    ]

-- ---------------------------------------------------------------------------
-- mapFieldType tests
-- ---------------------------------------------------------------------------

mapFieldTypeTests :: TestTree
mapFieldTypeTests =
  testGroup
    "mapFieldType"
    [ testCase "String field maps to textField" $
        Form._fmConstructor (Form.mapFieldType (Name.fromChars "bio") stringType)
          @?= Text.pack "Field.textField",

      testCase "Int field maps to numberField" $
        Form._fmConstructor (Form.mapFieldType (Name.fromChars "age") intType)
          @?= Text.pack "Field.numberField",

      testCase "Float field maps to numberField" $
        Form._fmConstructor (Form.mapFieldType (Name.fromChars "score") floatType)
          @?= Text.pack "Field.numberField",

      testCase "Bool field maps to checkboxField" $
        Form._fmConstructor (Form.mapFieldType (Name.fromChars "active") boolType)
          @?= Text.pack "Field.checkboxField",

      testCase "field named email maps to emailField regardless of type" $
        Form._fmConstructor (Form.mapFieldType (Name.fromChars "email") stringType)
          @?= Text.pack "Field.emailField",

      testCase "field named password maps to passwordField" $
        Form._fmConstructor (Form.mapFieldType (Name.fromChars "password") stringType)
          @?= Text.pack "Field.passwordField",

      testCase "field named url maps to urlField" $
        Form._fmConstructor (Form.mapFieldType (Name.fromChars "url") stringType)
          @?= Text.pack "Field.urlField",

      testCase "Maybe String field is marked optional" $
        Form._fmIsOptional (Form.mapFieldType (Name.fromChars "bio") maybeStringType)
          @?= True,

      testCase "String field is not optional" $
        Form._fmIsOptional (Form.mapFieldType (Name.fromChars "bio") stringType)
          @?= False,

      testCase "field id matches field name" $
        Form._fmFieldId (Form.mapFieldType (Name.fromChars "username") stringType)
          @?= Text.pack "username"
    ]

-- ---------------------------------------------------------------------------
-- generateFormDefinition tests
-- ---------------------------------------------------------------------------

generateFormDefinitionTests :: TestTree
generateFormDefinitionTests =
  testGroup
    "generateFormDefinition"
    [ testCase "non-record alias returns Nothing" $
        Maybe.isNothing
          (Form.generateFormDefinition (Name.fromChars "MyInt") nonRecordAlias)
          @?= True,

      testCase "record alias returns Just a non-empty builder" $
        let alias = recordAlias (singleField (Name.fromChars "name") stringType)
            result = Form.generateFormDefinition (Name.fromChars "UserForm") alias
         in Maybe.isJust result @?= True,

      testCase "generated output contains Form.succeed" $
        let alias = recordAlias (singleField (Name.fromChars "name") stringType)
         in case Form.generateFormDefinition (Name.fromChars "User") alias of
              Nothing -> assertFailure "Expected Just builder"
              Just b -> assertBool "missing Form.succeed" ("Form.succeed" `isSubstring` renderBuilder b),

      testCase "generated output contains Form.append" $
        let alias = recordAlias (singleField (Name.fromChars "name") stringType)
         in case Form.generateFormDefinition (Name.fromChars "User") alias of
              Nothing -> assertFailure "Expected Just builder"
              Just b -> assertBool "missing Form.append" ("|> Form.append" `isSubstring` renderBuilder b)
    ]

-- ---------------------------------------------------------------------------
-- generateFormModule tests
-- ---------------------------------------------------------------------------

generateFormModuleTests :: TestTree
generateFormModuleTests =
  testGroup
    "generateFormModule"
    [ testCase "output starts with module header" $
        let out = renderBuilder (Form.generateFormModule (Text.pack "Gen.Forms") [])
         in assertBool "missing module line" ("module Gen.Forms" `isSubstring` out),

      testCase "output contains Form import" $
        let out = renderBuilder (Form.generateFormModule (Text.pack "Gen.Forms") [])
         in assertBool "missing Form import" ("import Form" `isSubstring` out),

      testCase "output contains Field import" $
        let out = renderBuilder (Form.generateFormModule (Text.pack "Gen.Forms") [])
         in assertBool "missing Field import" ("import Form.Field" `isSubstring` out),

      testCase "non-record aliases are silently skipped" $
        let aliases = [(Name.fromChars "MyInt", nonRecordAlias)]
            out = renderBuilder (Form.generateFormModule (Text.pack "M") aliases)
         in assertBool "should not contain Form.succeed" (not ("Form.succeed" `isSubstring` out))
    ]

-- ---------------------------------------------------------------------------
-- Substring helper
-- ---------------------------------------------------------------------------

isSubstring :: String -> String -> Bool
isSubstring needle haystack =
  any (needle `isPrefix`) (tails haystack)

isPrefix :: String -> String -> Bool
isPrefix [] _ = True
isPrefix _ [] = False
isPrefix (x : xs) (y : ys) = x == y && isPrefix xs ys

tails :: [a] -> [[a]]
tails [] = [[]]
tails xs@(_ : rest) = xs : tails rest
