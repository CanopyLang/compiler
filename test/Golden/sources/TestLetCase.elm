module TestLetCase exposing (..)

type Maybe a = Just a | Nothing

mapMaybe : (a -> b) -> Maybe a -> Maybe b
mapMaybe f =
    let
        helper x =
            case x of
                Just val ->
                    Just (f val)

                Nothing ->
                    Nothing
    in
    helper

test : Maybe Int
test =
    mapMaybe identity (Just 5)

identity : a -> a
identity x = x
