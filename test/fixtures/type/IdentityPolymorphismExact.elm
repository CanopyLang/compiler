module IdentityPolymorphismExact exposing (..)

-- Exact reproduction of the Main.elm identity polymorphism bug
-- where identity is used in one branch after << composition in another

type Page msg
    = Page String


type MainMsg
    = PageMsg PageMsg


type PageMsg
    = AnalyticsNewMsg AnalyticsNewMsg
    | AnalyticsMsg AnalyticsMsg


type AnalyticsNewMsg
    = NewMsg


type AnalyticsMsg
    = OldMsg


type Model
    = AnalyticsNew
    | Analytics


viewPage : (pageMsg -> mainMsg) -> Page pageMsg -> Page mainMsg
viewPage toMsg (Page title) =
    Page title


view : Model -> Page MainMsg
view model =
    let
        helper toMsg page =
            viewPage toMsg page
    in
    case model of
        AnalyticsNew ->
            -- First branch: composition with <<
            helper (PageMsg << AnalyticsNewMsg) (Page "new")

        Analytics ->
            -- Second branch: identity - should remain polymorphic
            -- but gets polluted with AnalyticsNewMsg from previous branch
            helper identity (Page "old")
