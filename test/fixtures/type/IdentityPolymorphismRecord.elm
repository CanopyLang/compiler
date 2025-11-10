module IdentityPolymorphismRecord exposing (..)

-- Test with record type like actual Main.elm's {title, body}

type alias Page msg =
    { title : String
    , body : List msg
    }


type MainMsg
    = PageMsg PageMsg


type PageMsg
    = AnalyticsNewMsg AnalyticsNewMsg


type AnalyticsNewMsg
    = NewMsg


type Model
    = AnalyticsNew
    | Analytics


viewPage : (pageMsg -> mainMsg) -> Page pageMsg -> Page mainMsg
viewPage toMsg page =
    { title = page.title
    , body = List.map toMsg page.body
    }


analyticsNewView : Page AnalyticsNewMsg
analyticsNewView =
    { title = "Analytics New"
    , body = [ NewMsg ]
    }


analyticsView : Page msg
analyticsView =
    { title = "Analytics"
    , body = []
    }


view : Model -> Page MainMsg
view model =
    let
        helper toMsg page =
            viewPage toMsg page
    in
    case model of
        AnalyticsNew ->
            helper (PageMsg << AnalyticsNewMsg) <|
                analyticsNewView

        Analytics ->
            helper identity <|
                analyticsView
