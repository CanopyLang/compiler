{-# LANGUAGE OverloadedStrings #-}

module Canopy.Constraint
  ( Constraint,
    exactly,
    anything,
    fromRange,
    lowerBound,
    toChars,
    fromChars,
    satisfies,
    check,
    intersect,
    goodCanopy,
    defaultCanopy,
    untilNextMajor,
    untilNextMinor,
    expand,
    --
    Error (..),
    decoder,
    encode,
  )
where

import qualified Canopy.Version as Version
import Control.Monad (liftM4)
import Data.Binary (Binary, get, getWord8, put, putWord8)
import qualified Data.ByteString.Char8 as C8
import qualified Json.Decode as Decode
import qualified Json.Encode as Encode
import Parse.Primitives (Col, Row)
import qualified Parse.Primitives as Parse

-- CONSTRAINTS

data Constraint
  = Range Version.Version Op Op Version.Version
  deriving (Eq, Show)

data Op
  = Less
  | LessOrEqual
  deriving (Eq, Show)

-- COMMON CONSTRAINTS

-- | Extract the lower bound version from a constraint.
--
-- For a constraint like @1.0.0 <= v < 2.0.0@, returns @1.0.0@.
lowerBound :: Constraint -> Version.Version
lowerBound (Range lower _ _ _) = lower

exactly :: Version.Version -> Constraint
exactly version =
  Range version LessOrEqual LessOrEqual version

anything :: Constraint
anything =
  Range Version.one LessOrEqual LessOrEqual Version.max

-- | Build a constraint from lower\/upper bounds and their operators.
--
-- The boolean arguments indicate whether the operator is @<=@ ('True')
-- or @<@ ('False').
--
-- @since 0.19.2
fromRange :: Version.Version -> Bool -> Bool -> Version.Version -> Constraint
fromRange lower lowerLe upperLe upper =
  Range lower (boolToOp lowerLe) (boolToOp upperLe) upper
  where
    boolToOp True = LessOrEqual
    boolToOp False = Less

-- | Parse a constraint from its textual representation.
--
-- Accepts both range format (@"1.0.0 <= v < 2.0.0"@) and
-- bare version strings (@"1.0.0"@, treated as exact constraint).
-- Returns 'Nothing' on invalid input.
--
-- @since 0.19.2
fromChars :: String -> Maybe Constraint
fromChars s =
  either (const Nothing) Just (Parse.fromByteString parser BadFormat (C8.pack s))

-- TO CHARS

toChars :: Constraint -> String
toChars constraint =
  case constraint of
    Range lower lowerOp upperOp upper ->
      Version.toChars lower <> (opToChars lowerOp <> ("v" <> (opToChars upperOp <> Version.toChars upper)))

opToChars :: Op -> String
opToChars op =
  case op of
    Less -> " < "
    LessOrEqual -> " <= "

-- IS SATISFIED

satisfies :: Constraint -> Version.Version -> Bool
satisfies constraint version =
  case constraint of
    Range lower lowerOp upperOp upper ->
      isLess lowerOp lower version
        && isLess upperOp version upper

isLess :: (Ord a) => Op -> (a -> a -> Bool)
isLess op =
  case op of
    Less ->
      (<)
    LessOrEqual ->
      (<=)

check :: Constraint -> Version.Version -> Ordering
check constraint version =
  case constraint of
    Range lower lowerOp upperOp upper ->
      if not (isLess lowerOp lower version)
        then LT
        else
          if not (isLess upperOp version upper)
            then GT
            else EQ

-- INTERSECT

intersect :: Constraint -> Constraint -> Maybe Constraint
intersect (Range lo lop hop hi) (Range lo_ lop_ hop_ hi_) =
  let (newLo, newLop) =
        case compare lo lo_ of
          LT -> (lo_, lop_)
          EQ -> (lo, if Less `elem` [lop, lop_] then Less else LessOrEqual)
          GT -> (lo, lop)

      (newHi, newHop) =
        case compare hi hi_ of
          LT -> (hi, hop)
          EQ -> (hi, if Less `elem` [hop, hop_] then Less else LessOrEqual)
          GT -> (hi_, hop_)
   in if newLo <= newHi
        then Just (Range newLo newLop newHop newHi)
        else Nothing

-- CANOPY CONSTRAINT

goodCanopy :: Constraint -> Bool
goodCanopy constraint =
  satisfies constraint Version.compiler

defaultCanopy :: Constraint
defaultCanopy =
  if Version._major Version.compiler > 0
    then untilNextMajor Version.compiler
    else untilNextMinor Version.compiler

-- CREATE CONSTRAINTS

untilNextMajor :: Version.Version -> Constraint
untilNextMajor version =
  Range version LessOrEqual Less (Version.bumpMajor version)

untilNextMinor :: Version.Version -> Constraint
untilNextMinor version =
  Range version LessOrEqual Less (Version.bumpMinor version)

expand :: Constraint -> Version.Version -> Constraint
expand constraint@(Range lower lowerOp upperOp upper) version
  | version < lower =
    Range version LessOrEqual upperOp upper
  | version > upper =
    Range lower lowerOp Less (Version.bumpMajor version)
  | otherwise =
    constraint

-- JSON

encode :: Constraint -> Encode.Value
encode constraint =
  Encode.chars (toChars constraint)

decoder :: Decode.Decoder Error Constraint
decoder =
  Decode.customString parser BadFormat

-- BINARY

instance Binary Constraint where
  get = liftM4 Range get get get get
  put (Range a b c d) = put a >> put b >> put c >> put d

instance Binary Op where
  put op =
    case op of
      Less -> putWord8 0
      LessOrEqual -> putWord8 1

  get =
    do
      n <- getWord8
      case n of
        0 -> return Less
        1 -> return LessOrEqual
        _ -> fail "binary encoding of Op was corrupted"

-- PARSER

data Error
  = BadFormat Row Col
  | InvalidRange Version.Version Version.Version
  deriving (Show)

parser :: Parse.Parser Error Constraint
parser =
  do
    lower <- parseVersion
    Parse.word1 0x20 {- -} BadFormat
    loOp <- parseOp
    Parse.word1 0x20 {- -} BadFormat
    Parse.word1 0x76 {-v-} BadFormat
    Parse.word1 0x20 {- -} BadFormat
    hiOp <- parseOp
    Parse.word1 0x20 {- -} BadFormat
    higher <- parseVersion
    Parse.Parser $ \state@(Parse.State _ _ _ _ row col) _ eok _ eerr ->
      if lower < higher
        then eok (Range lower loOp hiOp higher) state
        else eerr row col (\_ _ -> InvalidRange lower higher)

parseVersion :: Parse.Parser Error Version.Version
parseVersion =
  Parse.specialize (\(r, c) _ _ -> BadFormat r c) Version.parser

parseOp :: Parse.Parser Error Op
parseOp =
  do
    Parse.word1 0x3C {-<-} BadFormat
    Parse.oneOfWithFallback
      [ do
          Parse.word1 0x3D {-=-} BadFormat
          return LessOrEqual
      ]
      Less
