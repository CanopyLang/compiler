module IdentityPolymorphismPipeline exposing (..)

-- Exact reproduction using <| pipeline operator

type Page msg
    = Page String (List msg)


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


-- viewPage expects (pageMsg -> mainMsg)
viewPage : (pageMsg -> mainMsg) -> Page pageMsg -> Page mainMsg
viewPage toMsg (Page title msgs) =
    Page title (List.map toMsg msgs)


analyticsNewView : Page AnalyticsNewMsg
analyticsNewView =
    Page "Analytics New" [ NewMsg ]


analyticsView : Page AnalyticsMsg
analyticsView =
    Page "Analytics" [ OldMsg ]


view : Model -> Page MainMsg
view model =
    let
        -- Note: no type annotation on helper - it's polymorphic
        helper toMsg page =
            viewPage toMsg page
    in
    case model of
        AnalyticsNew ->
            -- Using <| like in Main.elm
            helper (PageMsg << AnalyticsNewMsg) <|
                analyticsNewView

        Analytics ->
            -- This should work: identity : a -> a
            -- Should unify with AnalyticsMsg -> AnalyticsMsg for this branch
            helper identity <|
                analyticsView
