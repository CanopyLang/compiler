{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for Deps.Registry private registry support.
--
-- Tests registry URL resolution, authentication token resolution,
-- and the fallback chain from environment variables to custom
-- repository configuration to the default public registry.
--
-- @since 0.19.2
module Unit.Deps.RegistryTest (tests) where

import qualified Canopy.CustomRepositoryData as CustomRepo
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Deps.Registry as Registry
import qualified System.Environment as Env
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Deps.Registry Tests"
    [ testRegistryUrlResolution,
      testRegistryTokenResolution,
      testAuthHeader,
      testRegistryDataTypes
    ]

testRegistryUrlResolution :: TestTree
testRegistryUrlResolution =
  testGroup
    "registry URL resolution"
    [ testCase "empty custom repos uses default URL" $ do
        unsetRegistryEnv
        url <- Registry.resolveRegistryUrl Map.empty
        url @?= "https://package.elm-lang.org/all-packages",
      testCase "custom repo URL is used when set" $ do
        unsetRegistryEnv
        let customUrl = "https://packages.mycompany.com/all-packages"
            repos = Map.singleton "mycompany" (mkCustomRepo "mycompany" customUrl Nothing)
        url <- Registry.resolveRegistryUrl repos
        url @?= customUrl,
      testCase "env var overrides custom repos" $ do
        unsetRegistryEnv
        let envUrl = "https://env-registry.example.com/all-packages"
        Env.setEnv "CANOPY_REGISTRY_URL" envUrl
        let repos = Map.singleton "mycompany" (mkCustomRepo "mycompany" "https://other.com" Nothing)
        url <- Registry.resolveRegistryUrl repos
        Env.unsetEnv "CANOPY_REGISTRY_URL"
        url @?= envUrl
    ]

testRegistryTokenResolution :: TestTree
testRegistryTokenResolution =
  testGroup
    "registry token resolution"
    [ testCase "empty custom repos returns Nothing" $ do
        unsetRegistryEnv
        token <- Registry.resolveRegistryToken Map.empty
        token @?= Nothing,
      testCase "custom repo token is used when set" $ do
        unsetRegistryEnv
        let repos = Map.singleton "mycompany" (mkCustomRepo "mycompany" "https://example.com" (Just "secret-token"))
        token <- Registry.resolveRegistryToken repos
        token @?= Just "secret-token",
      testCase "custom repo without token returns Nothing" $ do
        unsetRegistryEnv
        let repos = Map.singleton "mycompany" (mkCustomRepo "mycompany" "https://example.com" Nothing)
        token <- Registry.resolveRegistryToken repos
        token @?= Nothing,
      testCase "env var overrides custom repo token" $ do
        unsetRegistryEnv
        Env.setEnv "CANOPY_REGISTRY_TOKEN" "env-token"
        let repos = Map.singleton "mycompany" (mkCustomRepo "mycompany" "https://example.com" (Just "repo-token"))
        token <- Registry.resolveRegistryToken repos
        Env.unsetEnv "CANOPY_REGISTRY_TOKEN"
        token @?= Just "env-token"
    ]

testAuthHeader :: TestTree
testAuthHeader =
  testGroup
    "auth header creation"
    [ testCase "createAuthHeader produces Bearer token header" $ do
        let header = Registry.createAuthHeader "my-token"
        snd header @?= "Bearer my-token"
    ]

testRegistryDataTypes :: TestTree
testRegistryDataTypes =
  testGroup
    "registry data types"
    [ testCase "empty registry has zero packages" $ do
        let reg = Registry.Registry 0 Map.empty
        case reg of
          Registry.Registry count _ -> count @?= 0,
      testCase "mergeRegistries is identity" $ do
        let reg = Registry.Registry 3 Map.empty
        Registry.mergeRegistries reg @?= reg,
      testCase "cache TTL is 1 hour" $
        Registry.registryCacheTTL @?= 3600
    ]

-- | Create a custom repository data entry for testing.
mkCustomRepo :: CustomRepo.RepositoryLocalName -> String -> Maybe String -> CustomRepo.CustomSingleRepositoryData
mkCustomRepo name url maybeToken =
  CustomRepo.DefaultPackageServerRepoData
    { CustomRepo._defaultPackageServerRepoLocalName = name,
      CustomRepo._defaultPackageServerRepoUrl = Text.pack url,
      CustomRepo._defaultPackageServerRepoAuthToken = fmap Text.pack maybeToken
    }

-- | Clean up environment variables after tests.
unsetRegistryEnv :: IO ()
unsetRegistryEnv = do
  Env.unsetEnv "CANOPY_REGISTRY_URL"
  Env.unsetEnv "CANOPY_REGISTRY_TOKEN"
