module TestPointfreeLet exposing (..)

-- Point-free style with let binding
mapPointfree : (a -> b) -> List a -> List b
mapPointfree =
    let
        helper f list =
            case list of
                [] -> []
                y :: ys -> f y :: helper f ys
    in
    helper

-- Should work: type variables flow through point-free definition
test : List Int
test =
    mapPointfree identity [1, 2, 3]

identity : a -> a
identity x = x
