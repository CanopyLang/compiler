module IdentityPolymorphismDebugging exposing (..)

-- Extreme simplification to test the core issue

type Msg1 = M1
type Msg2 = M2

type alias Func a b = a -> b

wrapFunc : Func a b -> Func a b
wrapFunc f = f

case1 : Func Msg1 Msg2
case1 =
    wrapFunc (\m -> M2)

case2 : Func Msg2 Msg2
case2 =
    wrapFunc identity
