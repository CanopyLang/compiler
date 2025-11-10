module TestComposition exposing (..)

type List a = Nil | Cons a (List a)

wrap : a -> List a
wrap x = Cons x Nil

processList : (a -> b) -> List a -> b
processList f =
    let
        process xs =
            case xs of
                Cons x rest ->
                    f x

                Nil ->
                    f (error "empty")
    in
    process << wrap

test : Int
test =
    processList identity 5

identity : a -> a
identity x = x

error : String -> a
error _ = error "unreachable"
