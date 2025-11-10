module IdentityPolymorphismArgument exposing (..)

-- Testing identity as argument with different instantiations

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


-- Key: viewPage expects (pageMsg -> mainMsg)
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
        helper toMsg page =
            viewPage toMsg page
    in
    case model of
        AnalyticsNew ->
            -- First branch: PageMsg << AnalyticsNewMsg : AnalyticsNewMsg -> MainMsg
            helper (PageMsg << AnalyticsNewMsg) analyticsNewView

        Analytics ->
            -- Second branch: identity : a -> a
            -- Should unify as: AnalyticsMsg -> AnalyticsMsg
            -- But error shows it's typed as: AnalyticsNewMsg -> AnalyticsNewMsg
            helper identity analyticsView
