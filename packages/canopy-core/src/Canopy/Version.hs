{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE UnboxedTuples #-}

module Canopy.Version
  ( Version (..),
    one,
    max,
    compiler,
    bumpPatch,
    bumpMinor,
    bumpMajor,
    toChars,
    --
    decoder,
    encode,
    --
    parser,
  )
where

import Control.Monad (liftM3)
import qualified Data.Aeson as Aeson
import Data.Binary (Binary, get, getWord8, put, putWord8)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import qualified Data.Version as Version
import Data.Word (Word16, Word8)
import Foreign.Ptr (Ptr, minusPtr, plusPtr)
import qualified Json.Decode as Decode
import qualified Reporting.InternalError as InternalError
import qualified Json.Encode as Encode
import Parse.Primitives (Col, Row)
import qualified Parse.Primitives as Parse
import qualified Paths_canopy_core as Paths_canopy
import Prelude hiding (max)

-- VERSION

data Version = Version
  { _major :: {-# UNPACK #-} !Word16,
    _minor :: {-# UNPACK #-} !Word16,
    _patch :: {-# UNPACK #-} !Word16
  }
  deriving (Eq, Ord, Show)

one :: Version
one =
  Version 1 0 0

max :: Version
max =
  Version maxBound 0 0

compiler :: Version
compiler =
  case fmap fromIntegral (Version.versionBranch Paths_canopy.version) of
    major : minor : patch : _ ->
      Version major minor patch
    [major, minor] ->
      Version major minor 0
    [major] ->
      Version major 0 0
    [] ->
      InternalError.report
        "Canopy.Version.compiler"
        "could not detect version of canopy-compiler you are using"
        "The Paths_canopy_core package should always provide a version string. An empty version branch list indicates a broken or malformed package installation."

-- BUMP

bumpPatch :: Version -> Version
bumpPatch (Version major minor patch) =
  Version major minor (patch + 1)

bumpMinor :: Version -> Version
bumpMinor (Version major minor _patch) =
  Version major (minor + 1) 0

bumpMajor :: Version -> Version
bumpMajor (Version major _minor _patch) =
  Version (major + 1) 0 0

-- TO CHARS

toChars :: Version -> String
toChars (Version major minor patch) =
  show major <> ('.' : (show minor <> ('.' : show patch)))

-- JSON

decoder :: Decode.Decoder (Row, Col) Version
decoder =
  Decode.customString parser (,)

encode :: Version -> Encode.Value
encode version =
  Encode.chars (toChars version)

-- BINARY

instance Binary Version where
  get =
    do
      word <- getWord8
      if word == 255
        then liftM3 Version get get get
        else do
          minor <- getWord8
          Version (fromIntegral word) (fromIntegral minor) . fromIntegral <$> getWord8

  put (Version major minor patch) =
    if major < 255 && minor < 256 && patch < 256
      then do
        putWord8 (fromIntegral major)
        putWord8 (fromIntegral minor)
        putWord8 (fromIntegral patch)
      else do
        putWord8 255
        put major
        put minor
        put patch

-- AESON JSON INSTANCES

instance Aeson.ToJSON Version where
  toJSON version = Aeson.String (Text.pack (toChars version))

instance Aeson.FromJSON Version where
  parseJSON = Aeson.withText "Version" $ \txt ->
    case Parse.fromByteString parser (,) (TextEnc.encodeUtf8 txt) of
      Right version -> pure version
      Left _ -> fail ("Invalid version: " ++ Text.unpack txt)

-- PARSER

parser :: Parse.Parser (Row, Col) Version
parser =
  do
    major <- numberParser
    Parse.word1 0x2E {-.-} (,)
    minor <- numberParser
    Parse.word1 0x2E {-.-} (,)
    Version major minor <$> numberParser

numberParser :: Parse.Parser (Row, Col) Word16
numberParser =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ eerr ->
    if pos >= end
      then eerr row col (,)
      else
        let !word = Parse.unsafeIndex pos
         in if word == 0x30 {-0-}
              then
                let !newState = Parse.State src (plusPtr pos 1) end indent row (col + 1)
                 in cok 0 newState
              else
                if isDigit word
                  then
                    let (# total, newPos #) = chompWord16 (plusPtr pos 1) end (fromIntegral (word - 0x30))
                        !newState = Parse.State src newPos end indent row (col + fromIntegral (minusPtr newPos pos))
                     in cok total newState
                  else eerr row col (,)

chompWord16 :: Ptr Word8 -> Ptr Word8 -> Word16 -> (# Word16, Ptr Word8 #)
chompWord16 pos end total =
  if pos >= end
    then (# total, pos #)
    else
      let !word = Parse.unsafeIndex pos
       in if isDigit word
            then chompWord16 (plusPtr pos 1) end (10 * total + fromIntegral (word - 0x30))
            else (# total, pos #)

isDigit :: Word8 -> Bool
isDigit word =
  0x30 {-0-} <= word && word <= 0x39 {-9-}
