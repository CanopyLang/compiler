module Canopy.Magnitude
  ( Magnitude (..),
    toChars,
  )
where

-- MAGNITUDE

data Magnitude
  = PATCH
  | MINOR
  | MAJOR
  deriving (Eq, Ord, Show)

toChars :: Magnitude -> String
toChars magnitude =
  case magnitude of
    PATCH -> "PATCH"
    MINOR -> "MINOR"
    MAJOR -> "MAJOR"
