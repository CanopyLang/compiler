{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Property tests for Terminal.Chomp module.
--
-- Tests algebraic properties, laws, and invariants of the Terminal.Chomp
-- framework using QuickCheck property-based testing. Validates that the
-- parsing system maintains consistency across different input patterns
-- and satisfies fundamental computational laws.
--
-- @since 0.19.1
module Property.Terminal.ChompProps (tests) where

import Control.Lens ((^.), (&), (.~))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.QuickCheck
  ( testProperty,
    (==>),
    Arbitrary (..),
    Gen,
    choose,
    elements,
    listOf,
    suchThat
  )
import Terminal.Chomp.Types
  ( Chunk (..),
    Suggest (..),
    SuggestTarget (..),
    Value (..),
    ValueType (..),
    chunkContent,
    chunkIndex,
    createChunk,
    createSuggest,
    extractValue,
    suggestTarget
  )

-- | Custom generators for testing
newtype ValidIndex = ValidIndex Int deriving (Show, Eq)
newtype ValidContent = ValidContent String deriving (Show, Eq)
newtype SafeString = SafeString String deriving (Show, Eq)

instance Arbitrary ValidIndex where
  arbitrary = ValidIndex <$> choose (1, 1000)

instance Arbitrary ValidContent where
  arbitrary = ValidContent <$> listOf (elements (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ "._-"))

instance Arbitrary SafeString where
  arbitrary = SafeString <$> listOf (elements ['a'..'z']) `suchThat` (\s -> length s <= 50)

tests :: TestTree
tests = testGroup "Terminal.Chomp Properties"
  [ testChunkProperties
  , testSuggestionProperties
  , testValueProperties
  , testCompositionProperties
  , testInvariantProperties
  ]

-- | Test chunk-related properties
testChunkProperties :: TestTree
testChunkProperties = testGroup "Chunk Properties"
  [ testProperty "chunk creation preserves index" $ \(ValidIndex idx) (ValidContent content) ->
      let chunk = createChunk idx content
      in (chunk ^. chunkIndex) == idx
  , testProperty "chunk creation preserves content" $ \(ValidIndex idx) (ValidContent content) ->
      let chunk = createChunk idx content
      in (chunk ^. chunkContent) == content
  , testProperty "chunk equality is reflexive" $ \(ValidIndex idx) (ValidContent content) ->
      let chunk = createChunk idx content
      in chunk == chunk
  , testProperty "chunk equality respects components" $ \(ValidIndex idx1) (ValidIndex idx2) (ValidContent content) ->
      idx1 /= idx2 ==>
      let chunk1 = createChunk idx1 content
          chunk2 = createChunk idx2 content
      in chunk1 /= chunk2
  , testProperty "chunk lens access is consistent" $ \(ValidIndex idx) (ValidContent content) ->
      let chunk = createChunk idx content
      in (chunk ^. chunkIndex, chunk ^. chunkContent) == (idx, content)
  ]

-- | Test suggestion system properties
testSuggestionProperties :: TestTree
testSuggestionProperties = testGroup "Suggestion Properties"
  [ testProperty "createSuggest with positive index creates SuggestAt" $ \idx ->
      idx > 0 ==>
      case createSuggest idx of
        SuggestAt target -> (target ^. suggestTarget) == idx
        _ -> False
  , testProperty "createSuggest with non-positive index creates NoSuggestion" $ \idx ->
      idx <= 0 ==>
      createSuggest idx == NoSuggestion
  , testProperty "suggestion target lens is consistent" $ \idx ->
      idx > 0 ==>
      case createSuggest idx of
        SuggestAt target -> (target ^. suggestTarget) == idx
        _ -> False
  , testProperty "suggestion equality is reflexive" $ \idx ->
      let suggest = createSuggest idx
      in suggest == suggest
  , testProperty "different suggest targets are not equal" $ \idx1 idx2 ->
      idx1 > 0 && idx2 > 0 && idx1 /= idx2 ==>
      createSuggest idx1 /= createSuggest idx2
  ]

-- | Test value extraction properties
testValueProperties :: TestTree
testValueProperties = testGroup "Value Properties"
  [ testProperty "extractValue from NoValue is Nothing" $ \() ->
      extractValue NoValue == Nothing
  , testProperty "extractValue from DefiniteValue preserves content" $ \(ValidContent content) ->
      let valueType = ValueType { _valueIndex = 1, _valueContent = content }
          value = DefiniteValue valueType
      in extractValue value == Just content
  , testProperty "extractValue from PossibleValue preserves chunk content" $ \(ValidIndex idx) (ValidContent content) ->
      let chunk = createChunk idx content
          value = PossibleValue chunk
      in extractValue value == Just content
  , testProperty "extractValue is deterministic" $ \(ValidContent content) ->
      let valueType = ValueType { _valueIndex = 1, _valueContent = content }
          value = DefiniteValue valueType
          result1 = extractValue value
          result2 = extractValue value
      in result1 == result2
  ]

-- | Test composition and interaction properties
testCompositionProperties :: TestTree
testCompositionProperties = testGroup "Composition Properties"
  [ testProperty "chunk creation and extraction roundtrip" $ \(ValidIndex idx) (ValidContent content) ->
      let chunk = createChunk idx content
          extractedIdx = chunk ^. chunkIndex
          extractedContent = chunk ^. chunkContent
      in (extractedIdx, extractedContent) == (idx, content)
  , testProperty "suggestion creation is idempotent for valid indices" $ \idx ->
      idx > 0 ==>
      let suggest1 = createSuggest idx
          suggest2 = createSuggest idx
      in suggest1 == suggest2
  , testProperty "value extraction composition" $ \(ValidIndex idx) (ValidContent content) ->
      let chunk = createChunk idx content
          value = PossibleValue chunk
          extracted = extractValue value
          original = chunk ^. chunkContent
      in extracted == Just original
  ]

-- | Test fundamental invariants
testInvariantProperties :: TestTree
testInvariantProperties = testGroup "Invariant Properties"
  [ testProperty "chunk index is always positive after creation" $ \(ValidIndex idx) (ValidContent content) ->
      let chunk = createChunk idx content
      in (chunk ^. chunkIndex) > 0
  , testProperty "chunk content is preserved exactly" $ \(ValidIndex idx) (ValidContent content) ->
      let chunk = createChunk idx content
      in (chunk ^. chunkContent) == content
  , testProperty "suggestion target is consistent with input" $ \idx ->
      idx > 0 ==>
      case createSuggest idx of
        SuggestAt target -> (target ^. suggestTarget) == idx
        NoSuggestion -> False
        _ -> True  -- SuggestIO case
  , testProperty "value extraction respects Maybe semantics" $ \(ValidContent content) ->
      let valueType = ValueType { _valueIndex = 1, _valueContent = content }
          definiteValue = DefiniteValue valueType
          noValue = NoValue
      in case (extractValue definiteValue, extractValue noValue) of
           (Just _, Nothing) -> True
           _ -> False
  , testProperty "lens laws: get what you set" $ \(ValidIndex newIdx) (ValidContent content) ->
      let chunk = createChunk 1 content
          updated = chunk & chunkIndex .~ newIdx
      in (updated ^. chunkIndex) == newIdx
  ]

-- Helper types and functions for testing
-- Using actual types from Terminal.Chomp.Types

