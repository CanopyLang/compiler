{-# LANGUAGE StandaloneDeriving #-}

module Reporting.Annotation
  ( Located (..),
    Position (..),
    Region (..),
    traverse,
    toValue,
    merge,
    at,
    toRegion,
    mergeRegions,
    zero,
    one,
  )
where

import Control.Monad (liftM2)
import Data.Binary (Binary, get, put)
import Data.Word (Word32)
import Prelude hiding (traverse)

-- LOCATED

data Located a
  = At Region a -- PERF see if unpacking region is helpful

deriving instance Show a => Show (Located a)

instance Functor Located where
  fmap f (At region a) =
    At region (f a)

traverse :: (Functor f) => (a -> f b) -> Located a -> f (Located b)
traverse func (At region value) =
  At region <$> func value

toValue :: Located a -> a
toValue (At _ value) =
  value

merge :: Located a -> Located b -> value -> Located value
merge (At r1 _) (At r2 _) = At (mergeRegions r1 r2)

-- POSITION

data Position
  = Position
      {-# UNPACK #-} !Word32
      {-# UNPACK #-} !Word32
  deriving (Eq, Show)

at :: Position -> Position -> a -> Located a
at start end = At (Region start end)

-- REGION

data Region = Region Position Position
  deriving (Eq, Show)

toRegion :: Located a -> Region
toRegion (At region _) =
  region

mergeRegions :: Region -> Region -> Region
mergeRegions (Region start _) (Region _ end) =
  Region start end

zero :: Region
zero =
  Region (Position 0 0) (Position 0 0)

one :: Region
one =
  Region (Position 1 1) (Position 1 1)

instance Binary Region where
  put (Region a b) = put a >> put b
  get = liftM2 Region get get

instance Binary Position where
  put (Position a b) = put a >> put b
  get = liftM2 Position get get
