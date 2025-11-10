module TestDictBug exposing (..)

import Dict

-- Reproduction of the actual bug in Dict.Custom

type Dict comparable k v
    = Dict (k -> comparable) (comparable -> k) (Dict.Dict comparable v)

type alias Decoder a = String -> Result String a

-- This function has 4 parameters in its type signature
-- but only implements 2 - this is the USER BUG!
decoder :
    (k -> comparable)
    -> (comparable -> k)
    -> Decoder k
    -> Decoder v
    -> Decoder (Dict comparable k v)
decoder f g =
    decoderVia (Dict f g Dict.empty)

decoderVia :
    Dict comparable k v
    -> Decoder k
    -> Decoder v
    -> Decoder (Dict comparable k v)
decoderVia dict decK decV =
    \input -> Ok dict
