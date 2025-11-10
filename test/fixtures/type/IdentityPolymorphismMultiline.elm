module IdentityPolymorphismMultiline exposing (..)

-- Test with exact Main.elm structure including multi-line <|

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


type Domains
    = Domains


type TimeZone
    = TimeZone


type Model
    = AnalyticsNew AnalyticsNewState
    | Analytics AnalyticsState


type AnalyticsNewState
    = AnalyticsNewState


type AnalyticsState
    = AnalyticsState


viewPage : (pageMsg -> mainMsg) -> Page pageMsg -> Page mainMsg
viewPage toMsg page =
    { title = page.title
    , body = List.map toMsg page.body
    }


analyticsNewView : Domains -> TimeZone -> AnalyticsNewState -> Page AnalyticsNewMsg
analyticsNewView domains timeZone state =
    { title = "Analytics New"
    , body = [ NewMsg ]
    }


analyticsView : AnalyticsState -> Page msg
analyticsView state =
    { title = "Analytics"
    , body = []
    }


view : Domains -> TimeZone -> Model -> Page MainMsg
view domains timeZone model =
    let
        helper toMsg page =
            viewPage toMsg page
    in
    case model of
        AnalyticsNew analyticsNew ->
            helper (PageMsg << AnalyticsNewMsg) <|
                analyticsNewView domains timeZone analyticsNew

        Analytics analytics ->
            helper identity <|
                analyticsView analytics
