module TestComposeLet exposing (..)

type Maybe a = Just a | Nothing

-- Helper function (like Decode.andThen)
andThen : (a -> Maybe b) -> Maybe a -> Maybe b
andThen f m =
    case m of
        Just x -> f x
        Nothing -> Nothing

-- Helper function (like Decode.list)
wrapList : a -> Maybe a
wrapList x = Just x

-- Pattern matching Domains: point-free with let, composition, andThen
processWithLet : (a -> b) -> a -> Maybe b
processWithLet =
    let
        process x =
            case x of
                val -> Just val
    in
    \f -> andThen process << wrapList << f

-- Should work
test : Maybe Int
test =
    processWithLet identity 5

identity : a -> a
identity x = x
