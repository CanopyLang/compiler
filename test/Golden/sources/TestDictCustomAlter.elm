module TestDictCustomAlter exposing (alter, insert, get, Dict)

import Dict

-- Exact reproduction of the Dict.Custom module structure

type Dict comparable k v
    = Dict (k -> comparable) (comparable -> k) (Dict.Dict comparable v)

-- The alter function that should fail type checking with the bug
alter : k -> (Maybe v -> v) -> Dict comparable k v -> Dict comparable k v
alter k f dict =
    insert k (f (get k dict)) dict

-- Helper functions using standard Dict
insert : k -> v -> Dict comparable k v -> Dict comparable k v
insert k v (Dict f g dict) =
    Dict f g (Dict.insert (f k) v dict)

get : k -> Dict comparable k v -> Maybe v
get k (Dict f _ dict) =
    Dict.get (f k) dict
