module TestTypeVarIdentity exposing (..)

-- Test case for type variable identity bug
-- The bug: When a function calls another function with the same type variable names,
-- the instantiated type variables should unify with the caller's type variables.

-- Helper function with polymorphic type variables
identity : a -> a
identity x = x

-- This should work: using 'a' as both parameter name and instantiated type var
useIdentity : a -> a
useIdentity x =
    identity x

-- More complex: custom type with type variables
type Box a b
    = Box a b

-- Helper that creates a box
makeBox : a -> b -> Box a b
makeBox x y =
    Box x y

-- This should work: passing parameters to a function with same type var names
wrapInBox : a -> b -> Box a b
wrapInBox x y =
    makeBox x y

-- Even more complex: same names, nested types
type Container comparable k v
    = Container (k -> comparable) (k -> v)

makeContainer : (k -> comparable) -> (k -> v) -> Container comparable k v
makeContainer f g =
    Container f g

useContainer : (k -> comparable) -> (k -> v) -> Container comparable k v
useContainer f g =
    makeContainer f g

-- The actual Dict.Custom pattern
type Dict comparable k v
    = Dict (k -> comparable) (comparable -> k) (List (comparable, v))

insert : k -> v -> Dict comparable k v -> Dict comparable k v
insert key val (Dict f g list) =
    Dict f g ((f key, val) :: list)

get : k -> Dict comparable k v -> Maybe v
get key (Dict f g list) =
    case list of
        [] -> Nothing
        (k, v) :: rest -> Just v

-- This is the exact pattern from Dict.Custom.alter that supposedly fails
alter : k -> (Maybe v -> v) -> Dict comparable k v -> Dict comparable k v
alter k f dict =
    insert k (f (get k dict)) dict
