module TestPointFreePartial exposing (..)

-- Test point-free functions that return functions

-- Simple case: identity returning identity
identityReturnsIdentity : a -> (a -> a)
identityReturnsIdentity x =
    identity

identity : a -> a
identity y = y

-- Dict.Custom decoder pattern: 4 parameters but only 2 implemented
type Dict comparable k v
    = Dict (k -> comparable) (comparable -> k) (List v)

decoderVia :
    Dict comparable k v
    -> (String -> Result String k)
    -> (String -> Result String v)
    -> (String -> Result String (Dict comparable k v))
decoderVia dict decK decV =
    \input -> Ok dict

-- This mimics the Dict.Custom.decoder bug
-- Type signature says 4 parameters, but implementation only takes 2
decoder :
    (k -> comparable)
    -> (comparable -> k)
    -> (String -> Result String k)
    -> (String -> Result String v)
    -> (String -> Result String (Dict comparable k v))
decoder f g =
    decoderVia (Dict f g [])

-- Let's also test if this works in the context of alter
insert : k -> v -> Dict comparable k v -> Dict comparable k v
insert key val (Dict f g list) =
    Dict f g (val :: list)

get : k -> Dict comparable k v -> Maybe v
get key (Dict f g list) =
    case list of
        [] -> Nothing
        v :: rest -> Just v

alter : k -> (Maybe v -> v) -> Dict comparable k v -> Dict comparable k v
alter k f dict =
    insert k (f (get k dict)) dict
