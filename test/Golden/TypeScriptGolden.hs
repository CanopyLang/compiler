{-# LANGUAGE OverloadedStrings #-}

-- | Golden tests for TypeScript .d.ts output.
--
-- Verifies that 'renderDecls' produces correct .d.ts file content
-- for various declaration types.
--
-- @since 0.20.0
module Golden.TypeScriptGolden (tests) where

import qualified Canopy.Data.Name as Name
import Canopy.Data.Name (Name)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as BL
import Generate.TypeScript.Render (renderDecls)
import Generate.TypeScript.Types (DtsDecl (..), TsType (..))
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)

tests :: TestTree
tests =
  testGroup
    "TypeScript .d.ts Golden"
    [ goldenVsString
        "simple value exports"
        "test/Golden/expected/TypeScript/SimpleValues.d.ts"
        (pure (renderToLBS simpleValueDecls)),
      goldenVsString
        "union types"
        "test/Golden/expected/TypeScript/UnionTypes.d.ts"
        (pure (renderToLBS unionTypeDecls)),
      goldenVsString
        "record aliases"
        "test/Golden/expected/TypeScript/RecordAliases.d.ts"
        (pure (renderToLBS recordAliasDecls)),
      goldenVsString
        "generic types"
        "test/Golden/expected/TypeScript/GenericTypes.d.ts"
        (pure (renderToLBS genericTypeDecls)),
      goldenVsString
        "opaque types"
        "test/Golden/expected/TypeScript/OpaqueTypes.d.ts"
        (pure (renderToLBS opaqueTypeDecls)),
      goldenVsString
        "well-known type conversions"
        "test/Golden/expected/TypeScript/WellKnownTypes.d.ts"
        (pure (renderToLBS wellKnownTypeDecls))
    ]


renderToLBS :: [DtsDecl] -> BL.ByteString
renderToLBS = BB.toLazyByteString . renderDecls


n :: String -> Name
n = Name.fromChars


simpleValueDecls :: [DtsDecl]
simpleValueDecls =
  [ DtsValue (n "greet") (TsFunction [TsString] TsString),
    DtsValue (n "add") (TsFunction [TsNumber, TsNumber] TsNumber),
    DtsValue (n "isValid") (TsFunction [TsString] TsBoolean),
    DtsValue (n "unit") TsVoid
  ]


unionTypeDecls :: [DtsDecl]
unionTypeDecls =
  [ DtsUnionType
      (n "Color")
      []
      (TsUnion
        [ TsTaggedVariant (n "Red") [],
          TsTaggedVariant (n "Green") [],
          TsTaggedVariant (n "Blue") []
        ]),
    DtsUnionType
      (n "Shape")
      []
      (TsUnion
        [ TsTaggedVariant (n "Circle") [(n "a", TsNumber)],
          TsTaggedVariant (n "Rect") [(n "a", TsNumber), (n "b", TsNumber)]
        ])
  ]


recordAliasDecls :: [DtsDecl]
recordAliasDecls =
  [ DtsTypeAlias
      (n "Point")
      []
      (TsObject [(n "x", TsNumber), (n "y", TsNumber)]),
    DtsTypeAlias
      (n "Person")
      []
      (TsObject [(n "age", TsNumber), (n "name", TsString)])
  ]


genericTypeDecls :: [DtsDecl]
genericTypeDecls =
  [ DtsTypeAlias
      (n "Pair")
      [n "a"]
      (TsObject [(n "first", TsTypeVar (n "A")), (n "second", TsTypeVar (n "A"))]),
    DtsTypeAlias
      (n "Either")
      [n "e", n "a"]
      (TsUnion
        [ TsTaggedVariant (n "Left") [(n "a", TsTypeVar (n "E"))],
          TsTaggedVariant (n "Right") [(n "a", TsTypeVar (n "A"))]
        ])
  ]


opaqueTypeDecls :: [DtsDecl]
opaqueTypeDecls =
  [ DtsBrandedType (n "UserId") [],
    DtsBrandedType (n "SessionToken") []
  ]


wellKnownTypeDecls :: [DtsDecl]
wellKnownTypeDecls =
  [ DtsValue
      (n "names")
      (TsReadonlyArray TsString),
    DtsValue
      (n "lookup")
      (TsFunction
        [TsString]
        (TsUnion
          [ TsTaggedVariant (n "Just") [(n "a", TsNumber)],
            TsTaggedVariant (n "Nothing") []
          ])),
    DtsValue
      (n "parse")
      (TsFunction
        [TsString]
        (TsUnion
          [ TsTaggedVariant (n "Ok") [(n "a", TsNumber)],
            TsTaggedVariant (n "Err") [(n "a", TsString)]
          ]))
  ]
