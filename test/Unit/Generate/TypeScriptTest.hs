{-# LANGUAGE OverloadedStrings #-}

module Unit.Generate.TypeScriptTest (tests) where

import qualified AST.Canonical as Can
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Generate.TypeScript.Convert (convertType)
import Generate.TypeScript.Render (renderDecl, renderType)
import Generate.TypeScript.Types (DtsDecl (..), TsType (..))
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Generate.TypeScript"
    [ testConvertPrimitives,
      testConvertFunctions,
      testConvertRecords,
      testConvertMaybe,
      testConvertResult,
      testConvertList,
      testConvertTuple,
      testConvertHoleyAlias,
      testConvertRecursiveAlias,
      testConvertExtensibleRecord,
      testRenderTypes,
      testRenderDecls,
      testRenderExtensibleRecord
    ]


testConvertPrimitives :: TestTree
testConvertPrimitives =
  testGroup
    "primitive type conversion"
    [ testCase "Int maps to TsNumber" $
        convertType Set.empty intType @?= TsNumber,
      testCase "Float maps to TsNumber" $
        convertType Set.empty floatType @?= TsNumber,
      testCase "Bool maps to TsBoolean" $
        convertType Set.empty boolType @?= TsBoolean,
      testCase "String maps to TsString" $
        convertType Set.empty stringType @?= TsString,
      testCase "Unit maps to TsVoid" $
        convertType Set.empty Can.TUnit @?= TsVoid,
      testCase "type variable maps to TsTypeVar" $
        convertType Set.empty (Can.TVar (Name.fromChars "a"))
          @?= TsTypeVar (Name.fromChars "A")
    ]


testConvertFunctions :: TestTree
testConvertFunctions =
  testGroup
    "function type conversion"
    [ testCase "single-arg function uncurries" $
        convertType Set.empty (Can.TLambda intType stringType)
          @?= TsFunction [TsNumber] TsString,
      testCase "multi-arg function uncurries" $
        convertType Set.empty (Can.TLambda intType (Can.TLambda boolType stringType))
          @?= TsFunction [TsNumber, TsBoolean] TsString
    ]


testConvertRecords :: TestTree
testConvertRecords =
  testGroup
    "record type conversion"
    [ testCase "record with fields" $
        convertType Set.empty (Can.TRecord fields Nothing)
          @?= TsObject
            [ (Name.fromChars "age", TsNumber),
              (Name.fromChars "name", TsString)
            ]
    ]
  where
    fields =
      Map.fromList
        [ (Name.fromChars "name", Can.FieldType 0 stringType),
          (Name.fromChars "age", Can.FieldType 1 intType)
        ]


testConvertMaybe :: TestTree
testConvertMaybe =
  testCase "Maybe a converts to discriminated union" $
    convertType Set.empty maybeIntType
      @?= TsUnion
        [ TsTaggedVariant (Name.fromChars "Just") [(Name.fromChars "a", TsNumber)],
          TsTaggedVariant (Name.fromChars "Nothing") []
        ]


testConvertResult :: TestTree
testConvertResult =
  testCase "Result e a converts to discriminated union" $
    convertType Set.empty resultType
      @?= TsUnion
        [ TsTaggedVariant (Name.fromChars "Ok") [(Name.fromChars "a", TsNumber)],
          TsTaggedVariant (Name.fromChars "Err") [(Name.fromChars "a", TsString)]
        ]


testConvertList :: TestTree
testConvertList =
  testCase "List a converts to ReadonlyArray" $
    convertType Set.empty listIntType @?= TsReadonlyArray TsNumber


testConvertTuple :: TestTree
testConvertTuple =
  testGroup
    "tuple type conversion"
    [ testCase "2-tuple converts to object with a,b fields" $
        convertType Set.empty (Can.TTuple intType stringType Nothing)
          @?= TsObject
            [ (Name.fromChars "a", TsNumber),
              (Name.fromChars "b", TsString)
            ],
      testCase "3-tuple converts to object with a,b,c fields" $
        convertType Set.empty (Can.TTuple intType stringType (Just boolType))
          @?= TsObject
            [ (Name.fromChars "a", TsNumber),
              (Name.fromChars "b", TsString),
              (Name.fromChars "c", TsBoolean)
            ]
    ]


testRenderTypes :: TestTree
testRenderTypes =
  testGroup
    "type rendering"
    [ testCase "string renders as string" $
        rendered TsString @?= "string",
      testCase "number renders as number" $
        rendered TsNumber @?= "number",
      testCase "boolean renders as boolean" $
        rendered TsBoolean @?= "boolean",
      testCase "void renders as void" $
        rendered TsVoid @?= "void",
      testCase "unknown renders as unknown" $
        rendered TsUnknown @?= "unknown",
      testCase "ReadonlyArray renders correctly" $
        rendered (TsReadonlyArray TsNumber) @?= "ReadonlyArray<number>",
      testCase "function renders with params" $
        rendered (TsFunction [TsNumber, TsString] TsBoolean)
          @?= "(p0: number, p1: string) => boolean",
      testCase "object renders with readonly fields" $
        rendered (TsObject [(Name.fromChars "x", TsNumber)])
          @?= "{ readonly x: number }",
      testCase "tagged variant renders with discriminant" $
        rendered (TsTaggedVariant (Name.fromChars "Just") [(Name.fromChars "a", TsNumber)])
          @?= "{ readonly $: 'Just'; readonly a: number }",
      testCase "union renders with pipe separator" $
        rendered (TsUnion [TsNumber, TsString])
          @?= "number | string"
    ]


testRenderDecls :: TestTree
testRenderDecls =
  testGroup
    "declaration rendering"
    [ testCase "value declaration" $
        renderedDecl (DtsValue (Name.fromChars "foo") TsNumber)
          @?= "export const foo: number;\n",
      testCase "type alias declaration" $
        renderedDecl (DtsTypeAlias (Name.fromChars "Foo") [Name.fromChars "a"] TsNumber)
          @?= "export type Foo<A> = number;\n",
      testCase "branded type declaration" $
        renderedDecl (DtsBrandedType (Name.fromChars "Id") [])
          @?= "export type Id = { readonly __brand: unique symbol };\n"
    ]


testConvertHoleyAlias :: TestTree
testConvertHoleyAlias =
  testCase "Holey alias resolves via dealias" $
    convertType Set.empty holeyAlias
      @?= TsObject [(Name.fromChars "x", TsNumber)]
  where
    holeyAlias =
      Can.TAlias
        ModuleName.basics
        (Name.fromChars "MyAlias")
        [(Name.fromChars "a", intType)]
        (Can.Holey (Can.TRecord (Map.singleton (Name.fromChars "x") (Can.FieldType 0 (Can.TVar (Name.fromChars "a")))) Nothing))


testConvertRecursiveAlias :: TestTree
testConvertRecursiveAlias =
  testCase "recursive alias produces TsNamed (no infinite loop)" $
    convertType Set.empty recursiveAlias
      @?= TsNamed (Name.fromChars "Tree") []
  where
    recursiveAlias =
      Can.TAlias
        ModuleName.basics
        (Name.fromChars "Tree")
        []
        (Can.Holey (Can.TAlias ModuleName.basics (Name.fromChars "Tree") [] (Can.Holey Can.TUnit)))


testConvertExtensibleRecord :: TestTree
testConvertExtensibleRecord =
  testCase "extensible record produces TsObjectWithIndex" $
    convertType Set.empty (Can.TRecord fields (Just (Name.fromChars "a")))
      @?= TsObjectWithIndex [(Name.fromChars "x", TsNumber)]
  where
    fields = Map.singleton (Name.fromChars "x") (Can.FieldType 0 intType)


testRenderExtensibleRecord :: TestTree
testRenderExtensibleRecord =
  testGroup
    "extensible record rendering"
    [ testCase "with fields" $
        rendered (TsObjectWithIndex [(Name.fromChars "x", TsNumber)])
          @?= "{ readonly x: number; [key: string]: unknown }",
      testCase "empty extensible record" $
        rendered (TsObjectWithIndex [])
          @?= "{ [key: string]: unknown }"
    ]


-- HELPERS


rendered :: TsType -> String
rendered = BL8.unpack . BB.toLazyByteString . renderType


renderedDecl :: DtsDecl -> String
renderedDecl = BL8.unpack . BB.toLazyByteString . renderDecl


intType :: Can.Type
intType = Can.TType ModuleName.basics (Name.fromChars "Int") []


floatType :: Can.Type
floatType = Can.TType ModuleName.basics (Name.fromChars "Float") []


boolType :: Can.Type
boolType = Can.TType ModuleName.basics (Name.fromChars "Bool") []


stringType :: Can.Type
stringType = Can.TType ModuleName.string (Name.fromChars "String") []


maybeIntType :: Can.Type
maybeIntType = Can.TType ModuleName.maybe (Name.fromChars "Maybe") [intType]


resultType :: Can.Type
resultType = Can.TType ModuleName.result (Name.fromChars "Result") [stringType, intType]


listIntType :: Can.Type
listIntType = Can.TType ModuleName.list (Name.fromChars "List") [intType]
