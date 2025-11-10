{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Property tests for Develop module system.
--
-- Tests invariants, laws, and roundtrip properties for the development
-- server types and operations. Uses QuickCheck to verify behavioral
-- properties following CLAUDE.md property testing patterns.
--
-- @since 0.19.1
module Property.DevelopProps (tests) where

import Control.Lens ((&), (.~), (^.))
import Data.List (isInfixOf)
import qualified Develop.Environment as Environment
import Develop.Types
  ( FileServeMode (..),
    Flags (..),
    ServerConfig (..),
    flagsPort,
    scPort,
    scRoot,
    scVerbose,
  )
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.QuickCheck (testProperty, (==>))
import qualified Test.Tasty.QuickCheck as QC

-- | Main property test suite for Develop module system.
tests :: TestTree
tests =
  Test.testGroup
    "Develop Properties"
    [ flagsProperties,
      serverConfigProperties,
      environmentProperties,
      lensLawProperties
    ]

-- | Properties for Flags data type.
flagsProperties :: TestTree
flagsProperties =
  Test.testGroup
    "Flags Properties"
    [ testProperty "flags lens roundtrip property" $ \maybePort ->
        let flags = Flags maybePort
            retrieved = flags ^. flagsPort
         in retrieved == maybePort,
      testProperty "flags lens update preserves structure" $ \maybePort1 maybePort2 ->
        let flags = Flags maybePort1
            updated = flags & flagsPort .~ maybePort2
         in updated ^. flagsPort == maybePort2,
      testProperty "flags equality works for same port values" $ \maybePort ->
        let flags1 = Flags maybePort
            flags2 = Flags maybePort
         in flags1 == flags2,
      testProperty "flags equality is symmetric" $ \maybePort ->
        let flags1 = Flags maybePort
            flags2 = Flags maybePort
         in (flags1 == flags2) == (flags2 == flags1),
      testProperty "flags show contains port information" $ \maybePort ->
        let flags = Flags maybePort
            shown = show flags
         in case maybePort of
              Nothing -> "Nothing" `isInfixOf` shown
              Just port -> show port `isInfixOf` shown
    ]

-- | Properties for ServerConfig data type.
serverConfigProperties :: TestTree
serverConfigProperties =
  Test.testGroup
    "ServerConfig Properties"
    [ testProperty "server config lens roundtrip for port" $ \port verbose root ->
        let config = ServerConfig port verbose root
            retrieved = config ^. scPort
         in retrieved == port,
      testProperty "server config lens roundtrip for verbose" $ \port verbose root ->
        let config = ServerConfig port verbose root
            retrieved = config ^. scVerbose
         in retrieved == verbose,
      testProperty "server config lens roundtrip for root" $ \port verbose root ->
        let config = ServerConfig port verbose root
            retrieved = config ^. scRoot
         in retrieved == root,
      testProperty "server config lens updates are independent" $ \port1 verbose1 root1 port2 ->
        let config = ServerConfig port1 verbose1 root1
            updated = config & scPort .~ port2
         in (updated ^. scPort == port2)
              && (updated ^. scVerbose == verbose1)
              && (updated ^. scRoot == root1),
      testProperty "server config show contains port information" $ \port verbose root ->
        let config = ServerConfig port verbose root
            shown = show config
         in show port `isInfixOf` shown && show verbose `isInfixOf` shown
    ]

-- | Properties for Environment functions.
environmentProperties :: TestTree
environmentProperties =
  Test.testGroup
    "Environment Properties"
    [ testProperty "resolve port returns 8000 for Nothing" $
        Environment.resolvePort (Flags Nothing) == 8000,
      testProperty "resolve port preserves valid Just values" $ \port ->
        port > 0 && port <= 65535
          ==> Environment.resolvePort (Flags (Just port)) == port,
      testProperty "resolve port always returns positive value" $ \maybePort ->
        let validatedPort = case maybePort of
              Just p | p > 0 && p <= 65535 -> Just p
              _ -> Nothing
            port = Environment.resolvePort (Flags validatedPort)
         in port > 0,
      testProperty "resolve port returns values in valid range" $ \maybePort ->
        let validatedPort = case maybePort of
              Just p | p > 0 && p <= 65535 -> Just p
              _ -> Nothing
            port = Environment.resolvePort (Flags validatedPort)
         in port >= 1 && port <= 65535
    ]

-- | Properties testing lens laws.
lensLawProperties :: TestTree
lensLawProperties =
  Test.testGroup
    "Lens Law Properties"
    [ testProperty "flags port lens get-put law" $ \maybePort ->
        let flags = Flags maybePort
            retrieved = flags ^. flagsPort
            restored = flags & flagsPort .~ retrieved
         in restored == flags,
      testProperty "flags port lens put-get law" $ \maybePort newPort ->
        let flags = Flags maybePort
            updated = flags & flagsPort .~ newPort
            retrieved = updated ^. flagsPort
         in retrieved == newPort,
      testProperty "server config port lens get-put law" $ \port verbose root ->
        let config = ServerConfig port verbose root
            retrieved = config ^. scPort
            restored = config & scPort .~ retrieved
         in restored == config,
      testProperty "server config port lens put-get law" $ \port verbose root newPort ->
        let config = ServerConfig port verbose root
            updated = config & scPort .~ newPort
            retrieved = updated ^. scPort
         in retrieved == newPort,
      testProperty "server config verbose lens get-put law" $ \port verbose root ->
        let config = ServerConfig port verbose root
            retrieved = config ^. scVerbose
            restored = config & scVerbose .~ retrieved
         in restored == config,
      testProperty "server config root lens get-put law" $ \port verbose root ->
        let config = ServerConfig port verbose root
            retrieved = config ^. scRoot
            restored = config & scRoot .~ retrieved
         in restored == config
    ]

-- | QuickCheck instance for generating valid port numbers.
instance QC.Arbitrary Flags where
  arbitrary = do
    maybePort <-
      QC.frequency
        [ (1, pure Nothing),
          (3, Just <$> QC.choose (1, 65535))
        ]
    pure (Flags maybePort)

-- | QuickCheck instance for generating ServerConfig values.
instance QC.Arbitrary ServerConfig where
  arbitrary = do
    port <- QC.choose (1, 65535)
    verbose <- QC.arbitrary
    maybeRoot <-
      QC.frequency
        [ (1, pure Nothing),
          (2, Just <$> QC.elements ["/project", "/root", "/home/user/project", "/var/www"])
        ]
    pure (ServerConfig port verbose maybeRoot)

-- | QuickCheck instance for generating FileServeMode values.
instance QC.Arbitrary FileServeMode where
  arbitrary =
    QC.oneof
      [ ServeRaw <$> arbitraryFilePath,
        ServeCode <$> arbitraryFilePath,
        ServeCanopy <$> arbitraryFilePath,
        ServeAsset <$> arbitraryContent <*> arbitraryMimeType
      ]
    where
      arbitraryFilePath =
        QC.elements
          [ "/path/to/file.txt",
            "/src/Main.hs",
            "/project/Main.can",
            "/assets/style.css",
            "/images/logo.png"
          ]
      arbitraryContent =
        QC.elements
          [ "file content",
            "body { margin: 0; }",
            "console.log('test');",
            "binary data"
          ]
      arbitraryMimeType =
        QC.elements
          [ "text/plain",
            "text/html",
            "text/css",
            "application/javascript",
            "image/png",
            "application/json"
          ]
