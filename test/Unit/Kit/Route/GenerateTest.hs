{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Kit route code generation.
--
-- Tests that the Routes.can module generator produces correct output
-- for various route configurations: static, dynamic, catch-all, and
-- mixed route manifests.
--
-- @since 0.20.1
module Unit.Kit.Route.GenerateTest
  ( tests
  ) where

import qualified Data.Text as Text
import Kit.Route.Types
  ( RouteEntry (..)
  , RouteManifest (..)
  , RoutePattern (..)
  , RouteSegment (..)
  , PageKind (..)
  )
import qualified Kit.Route.Generate as Generate
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.HUnit ((@?=))
import qualified Test.Tasty.HUnit as HUnit

tests :: TestTree
tests =
  Test.testGroup "Kit.Route.Generate"
    [ generatesModuleHeader
    , generatesStaticRouteParser
    , generatesDynamicRouteParser
    , generatesLazyImports
    , generatesEmptyManifest
    , generatesMultipleRoutes
    ]


-- | Generated module starts with correct header.
generatesModuleHeader :: TestTree
generatesModuleHeader =
  HUnit.testCase "generated module has correct header" $ do
    let output = Generate.generateRoutesModule singleRouteManifest
        firstLine = head (Text.lines output)
    firstLine @?= "module Routes exposing (Route(..), href, parser)"

-- | Static route produces a literal parser segment.
generatesStaticRouteParser :: TestTree
generatesStaticRouteParser =
  HUnit.testCase "static route produces literal segment" $ do
    let output = Generate.generateRoutesModule singleRouteManifest
        outputLines = Text.lines output
        parserArm = outputLines !! parserArmIndex outputLines
    parserArm @?= "        [ \"about\" ] -> Just About"

-- | Dynamic route produces a parser with variable capture.
generatesDynamicRouteParser :: TestTree
generatesDynamicRouteParser =
  HUnit.testCase "dynamic route produces variable capture" $ do
    let output = Generate.generateRoutesModule dynamicRouteManifest
        outputLines = Text.lines output
        parserArm = outputLines !! parserArmIndex outputLines
    parserArm @?= "        [ \"users\", id ] -> Just UsersId id"

-- | Lazy imports are generated for each route module.
generatesLazyImports :: TestTree
generatesLazyImports =
  HUnit.testCase "generates lazy imports for route modules" $ do
    let output = Generate.generateRoutesModule twoRouteManifest
        outputLines = Text.lines output
        importLines = filter isLazyImport outputLines
    importLines @?= ["lazy import Routes.About", "lazy import Routes.Contact"]

-- | Empty manifest produces a module with no routes.
generatesEmptyManifest :: TestTree
generatesEmptyManifest =
  HUnit.testCase "empty manifest produces valid module" $ do
    let output = Generate.generateRoutesModule emptyManifest
        outputLines = Text.lines output
        firstLine = head outputLines
        lastLine = last outputLines
    firstLine @?= "module Routes exposing (Route(..), href, parser)"
    lastLine @?= "        _ -> Nothing"

-- | Multiple routes produce entries for each.
generatesMultipleRoutes :: TestTree
generatesMultipleRoutes =
  HUnit.testCase "multiple routes produce multiple entries" $ do
    let output = Generate.generateRoutesModule twoRouteManifest
        outputLines = Text.lines output
        typeLines = takeTypeLines outputLines
    typeLines @?= ["type Route", "    = About", "    | Contact"]


-- HELPERS


-- | Find the index of the first parser case arm (line after "case segments of").
parserArmIndex :: [Text.Text] -> Int
parserArmIndex ls =
  maybe 0 (+ 1) (findIndex' "    case segments of" ls)

-- | Find the index of a line matching the given text.
findIndex' :: Text.Text -> [Text.Text] -> Maybe Int
findIndex' target ls =
  go 0 ls
  where
    go _ [] = Nothing
    go i (x:xs)
      | x == target = Just i
      | otherwise = go (i + 1) xs

-- | Check whether a line is a lazy import declaration.
isLazyImport :: Text.Text -> Bool
isLazyImport l = Text.take 11 l == "lazy import"

-- | Extract the type declaration lines from the output.
takeTypeLines :: [Text.Text] -> [Text.Text]
takeTypeLines ls =
  takeWhile isTypeLine (dropWhile (/= "type Route") ls)
  where
    isTypeLine l =
      l == "type Route" || Text.take 6 l == "    = " || Text.take 6 l == "    | "


-- TEST DATA


emptyManifest :: RouteManifest
emptyManifest = RouteManifest [] [] []

singleRouteManifest :: RouteManifest
singleRouteManifest = RouteManifest
  { _rmRoutes =
      [ RouteEntry
          { _rePattern = RoutePattern [StaticSegment "about"] "src/routes/about/page.can"
          , _rePageKind = StaticPage
          , _reSourceFile = "src/routes/about/page.can"
          , _reModuleName = "Routes.About"
          }
      ]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

dynamicRouteManifest :: RouteManifest
dynamicRouteManifest = RouteManifest
  { _rmRoutes =
      [ RouteEntry
          { _rePattern = RoutePattern
              [StaticSegment "users", DynamicSegment "id"]
              "src/routes/users/[id]/page.can"
          , _rePageKind = DynamicPage
          , _reSourceFile = "src/routes/users/[id]/page.can"
          , _reModuleName = "Routes.Users.Param_Id"
          }
      ]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }

twoRouteManifest :: RouteManifest
twoRouteManifest = RouteManifest
  { _rmRoutes =
      [ RouteEntry
          { _rePattern = RoutePattern [StaticSegment "about"] "src/routes/about/page.can"
          , _rePageKind = StaticPage
          , _reSourceFile = "src/routes/about/page.can"
          , _reModuleName = "Routes.About"
          }
      , RouteEntry
          { _rePattern = RoutePattern [StaticSegment "contact"] "src/routes/contact/page.can"
          , _rePageKind = StaticPage
          , _reSourceFile = "src/routes/contact/page.can"
          , _reModuleName = "Routes.Contact"
          }
      ]
  , _rmLayouts = []
  , _rmErrorBoundaries = []
  }
