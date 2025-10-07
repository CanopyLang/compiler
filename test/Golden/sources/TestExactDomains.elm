module TestExactDomains exposing (..)

type List a = Nil | Cons a (List a)

-- Wrapper type (like Decoder)
type Wrapper a = Wrapper a

-- andThen for Wrapper
andThen : (a -> Wrapper b) -> Wrapper a -> Wrapper b
andThen f (Wrapper x) = f x

-- succeed for Wrapper
succeed : a -> Wrapper a
succeed x = Wrapper x

-- Exact pattern from Domains.elm
process : Wrapper a -> Wrapper (List a)
process =
    let
        decode x =
            case x of
                Nil -> succeed Nil
                Cons y ys -> succeed (Cons y ys)
    in
    andThen decode

-- Use it
test : Wrapper (List Int)
test =
    process (Wrapper Nil)
