module TestLetType exposing (..)

-- Minimal reproduction of Domains bug
mapWithLet : (a -> b) -> List a -> List b
mapWithLet f xs =
    let
        helper list =
            case list of
                [] -> []
                y :: ys -> f y :: helper ys
    in
    helper xs

-- Should work: type variable 'a' flows into let binding
test : List Int
test =
    mapWithLet identity [1, 2, 3]

identity : a -> a
identity x = x
