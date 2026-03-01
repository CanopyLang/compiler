{-# LANGUAGE OverloadedStrings #-}

-- | Parse benchmarks for the Canopy compiler.
--
-- Measures parsing throughput for modules of varying sizes and
-- complexity. Uses real Canopy source syntax to produce meaningful
-- performance numbers.
--
-- @since 0.19.1
module Bench.Parse (benchmarks) where

import qualified AST.Source as Src
import Criterion.Main (Benchmark)
import qualified Criterion.Main as Criterion
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Parse.Module as Parse
import qualified Reporting.Error.Syntax.Types as SyntaxError

-- | All parse benchmarks.
benchmarks :: Benchmark
benchmarks =
  Criterion.bgroup
    "Parse"
    [ Criterion.bench "small module (10 lines)" (Criterion.whnf parseApp smallModule),
      Criterion.bench "medium module (50 lines)" (Criterion.whnf parseApp mediumModule),
      Criterion.bench "large module (200 lines)" (Criterion.whnf parseApp largeModule),
      Criterion.bench "xlarge module (500 lines)" (Criterion.whnf parseApp xlargeModule),
      Criterion.bench "xxlarge module (1000 lines)" (Criterion.whnf parseApp xxlargeModule),
      Criterion.bench "expression-heavy" (Criterion.whnf parseApp exprHeavyModule),
      Criterion.bench "type-heavy" (Criterion.whnf parseApp typeHeavyModule),
      Criterion.bench "pattern-heavy" (Criterion.whnf parseApp patternHeavyModule)
    ]

-- | Parse as an Application project type.
parseApp :: BS.ByteString -> Either SyntaxError.Error Src.Module
parseApp = Parse.fromByteString Parse.Application

-- | Small module with minimal declarations.
smallModule :: BS.ByteString
smallModule =
  BSC.pack
    (unlines
      [ "module Main exposing (main)"
      , ""
      , "import Html"
      , ""
      , ""
      , "main ="
      , "  Html.text \"Hello, World!\""
      , ""
      , ""
      , "greeting : String"
      , "greeting ="
      , "  \"Hello\""
      ])

-- | Medium module with several functions and type annotations.
mediumModule :: BS.ByteString
mediumModule =
  BSC.pack
    (unlines
      ([ "module Counter exposing (Model, Msg, init, update, view)"
       , ""
       , "import Html"
       , "import Html.Events"
       , "import Html.Attributes"
       , ""
       , ""
       , "type alias Model ="
       , "  { count : Int"
       , "  , step : Int"
       , "  , history : List Int"
       , "  }"
       , ""
       , ""
       , "type Msg"
       , "  = Increment"
       , "  | Decrement"
       , "  | Reset"
       , "  | SetStep Int"
       , ""
       , ""
       , "init : Model"
       , "init ="
       , "  { count = 0"
       , "  , step = 1"
       , "  , history = []"
       , "  }"
       ] ++ generateUpdateFunctions ++ generateViewFunctions))

-- | Large module with many declarations.
largeModule :: BS.ByteString
largeModule =
  BSC.pack
    (unlines
      ([ "module App exposing (..)"
       , ""
       , "import Html"
       , "import Html.Events"
       , "import Html.Attributes"
       , "import Json.Decode"
       , "import Json.Encode"
       , "import Http"
       , "import Task"
       , "import Time"
       , ""
       ] ++ generateManyFunctions 40))

-- | Extra large module (~500 lines) with many functions and types.
xlargeModule :: BS.ByteString
xlargeModule =
  BSC.pack
    (unlines
      ([ "module XLarge exposing (..)"
       , ""
       , "import Html"
       , "import Html.Events"
       , "import Html.Attributes"
       , "import Json.Decode"
       , "import Json.Encode"
       , "import Http"
       , "import Task"
       , "import Time"
       , ""
       ] ++ generateManyFunctions 60
         ++ generateTypeDeclarations 20
         ++ generatePatternFunctions 10))

-- | Very large module (~1000 lines) for stress testing.
xxlargeModule :: BS.ByteString
xxlargeModule =
  BSC.pack
    (unlines
      ([ "module XXLarge exposing (..)"
       , ""
       , "import Html"
       , "import Html.Events"
       , "import Html.Attributes"
       , "import Json.Decode"
       , "import Json.Encode"
       , "import Http"
       , "import Task"
       , "import Time"
       , ""
       ] ++ generateManyFunctions 120
         ++ generateTypeDeclarations 40
         ++ generatePatternFunctions 20))

-- | Module with deeply nested expressions.
exprHeavyModule :: BS.ByteString
exprHeavyModule =
  BSC.pack
    (unlines
      ([ "module Expr exposing (..)"
       , ""
       , "import Html"
       , ""
       ] ++ generateExprFunctions 20))

-- | Module with many type annotations and aliases.
typeHeavyModule :: BS.ByteString
typeHeavyModule =
  BSC.pack
    (unlines
      ([ "module Types exposing (..)"
       , ""
       ] ++ generateTypeDeclarations 30))

-- | Module with extensive pattern matching.
patternHeavyModule :: BS.ByteString
patternHeavyModule =
  BSC.pack
    (unlines
      ([ "module Patterns exposing (..)"
       , ""
       ] ++ generatePatternFunctions 15))

-- Generators for synthetic module content

generateUpdateFunctions :: [String]
generateUpdateFunctions =
  [ ""
  , ""
  , "update : Msg -> Model -> Model"
  , "update msg model ="
  , "  case msg of"
  , "    Increment ->"
  , "      { model | count = model.count + model.step, history = model.count :: model.history }"
  , ""
  , "    Decrement ->"
  , "      { model | count = model.count - model.step, history = model.count :: model.history }"
  , ""
  , "    Reset ->"
  , "      { model | count = 0, history = [] }"
  , ""
  , "    SetStep n ->"
  , "      { model | step = n }"
  ]

generateViewFunctions :: [String]
generateViewFunctions =
  [ ""
  , ""
  , "view : Model -> Html.Html Msg"
  , "view model ="
  , "  Html.div []"
  , "    [ Html.h1 [] [ Html.text (String.fromInt model.count) ]"
  , "    , Html.button [ Html.Events.onClick Increment ] [ Html.text \"+\" ]"
  , "    , Html.button [ Html.Events.onClick Decrement ] [ Html.text \"-\" ]"
  , "    , Html.button [ Html.Events.onClick Reset ] [ Html.text \"Reset\" ]"
  , "    ]"
  ]

generateManyFunctions :: Int -> [String]
generateManyFunctions n =
  concatMap generateOneFunction [1 .. n]

generateOneFunction :: Int -> [String]
generateOneFunction i =
  [ ""
  , ""
  , "helper" ++ show i ++ " : Int -> Int -> Int"
  , "helper" ++ show i ++ " x y ="
  , "  let"
  , "    a = x + y"
  , "    b = x * y"
  , "  in"
  , "  a + b + " ++ show i
  ]

generateExprFunctions :: Int -> [String]
generateExprFunctions n =
  concatMap generateExprFunction [1 .. n]

generateExprFunction :: Int -> [String]
generateExprFunction i =
  [ ""
  , ""
  , "compute" ++ show i ++ " : Int -> Int -> Int -> Int"
  , "compute" ++ show i ++ " a b c ="
  , "  let"
  , "    x = a + b * c"
  , "    y = (a - b) * (b + c)"
  , "    z = if x > y then x * 2 else y * 3"
  , "  in"
  , "  x + y + z + " ++ show i
  ]

generateTypeDeclarations :: Int -> [String]
generateTypeDeclarations n =
  concatMap generateTypeDecl [1 .. n]

generateTypeDecl :: Int -> [String]
generateTypeDecl i =
  [ ""
  , ""
  , "type alias Record" ++ show i ++ " ="
  , "  { field1 : Int"
  , "  , field2 : String"
  , "  , field3 : List Int"
  , "  , field4 : Maybe String"
  , "  }"
  ]

generatePatternFunctions :: Int -> [String]
generatePatternFunctions n =
  concatMap generatePatternFunction [1 .. n]

generatePatternFunction :: Int -> [String]
generatePatternFunction i =
  [ ""
  , ""
  , "type Shape" ++ show i
  , "  = Circle" ++ show i ++ " Float"
  , "  | Square" ++ show i ++ " Float"
  , "  | Triangle" ++ show i ++ " Float Float Float"
  , ""
  , ""
  , "area" ++ show i ++ " : Shape" ++ show i ++ " -> Float"
  , "area" ++ show i ++ " shape ="
  , "  case shape of"
  , "    Circle" ++ show i ++ " r ->"
  , "      3.14159 * r * r"
  , ""
  , "    Square" ++ show i ++ " s ->"
  , "      s * s"
  , ""
  , "    Triangle" ++ show i ++ " a b c ->"
  , "      let"
  , "        p = (a + b + c) / 2"
  , "      in"
  , "      p * (p - a) * (p - b) * (p - c)"
  ]
