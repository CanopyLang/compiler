module Test exposing (..)

import Json.Decode as Decode

type alias Zipper a = { current : a }

decodeZipper : Decode.Decoder a -> Decode.Decoder (Zipper a)
decodeZipper =
    let
        decode x =
            case x of
                [] ->
                    Decode.fail "empty"

                y :: ys ->
                    Decode.succeed { current = y }
    in
    Decode.andThen decode << Decode.list

test : Decode.Decoder (Zipper Int)
test =
    decodeZipper Decode.int
