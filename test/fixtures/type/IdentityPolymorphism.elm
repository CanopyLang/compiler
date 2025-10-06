module IdentityPolymorphism exposing (..)

-- Minimal reproduction of identity polymorphism bug
-- where identity gets polluted by a concrete type from a previous case branch

type Page msg
    = Page String msg


type MainMsg
    = SubMsg1 SubMsg1
    | SubMsg2 SubMsg2


type SubMsg1
    = Sub1A


type SubMsg2
    = Sub2A


type Model
    = Model1 String
    | Model2 String


viewPage : (pageMsg -> mainMsg) -> Page pageMsg -> Page mainMsg
viewPage toMsg (Page title msg) =
    Page title (toMsg msg)


view : Model -> Page MainMsg
view model =
    let
        helper toMsg page =
            viewPage toMsg page
    in
    case model of
        Model1 str ->
            -- First branch: concrete instantiation
            helper (SubMsg1) (Page "1" Sub1A)

        Model2 str ->
            -- Second branch: polymorphic identity
            -- This should work but fails if identity gets polluted
            helper identity (Page "2" Sub1A)
